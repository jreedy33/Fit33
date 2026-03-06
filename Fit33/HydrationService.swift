import Foundation
import SwiftUI
import Combine
import CoreData

// MARK: - Water Intake Models

struct HydrationLog: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let amountMl: Int
    let drinkType: String  // Always "water"
    let loggedAt: Date
    let notes: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case amountMl = "amount_ml"
        case drinkType = "drink_type"
        case loggedAt = "logged_at"
        case notes
        case createdAt = "created_at"
    }
}

struct HydrationDailySummary: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: String
    let totalMl: Int
    let goalMl: Int
    let waterMl: Int
    let teaMl: Int
    let coffeeMl: Int
    let sportsDrinkMl: Int
    let otherMl: Int
    let entryCount: Int
    let firstDrinkTime: String?
    let lastDrinkTime: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case totalMl = "total_ml"
        case goalMl = "goal_ml"
        case waterMl = "water_ml"
        case teaMl = "tea_ml"
        case coffeeMl = "coffee_ml"
        case sportsDrinkMl = "sports_drink_ml"
        case otherMl = "other_ml"
        case entryCount = "entry_count"
        case firstDrinkTime = "first_drink_time"
        case lastDrinkTime = "last_drink_time"
    }
    
    var progress: Double {
        guard goalMl > 0 else { return 0 }
        return min(Double(totalMl) / Double(goalMl), 1.0)
    }
    
    var remaining: Int {
        max(0, goalMl - totalMl)
    }
    
    var goalMet: Bool {
        totalMl >= goalMl
    }
}

struct HydrationSettings: Codable {
    var id: UUID?
    let userId: UUID
    var dailyGoalMl: Int
    var reminderEnabled: Bool
    var reminderIntervalHours: Int
    var reminderStartTime: String
    var reminderEndTime: String
    var preferredCupSizeMl: Int
    var weightBasedGoal: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case dailyGoalMl = "daily_goal_ml"
        case reminderEnabled = "reminder_enabled"
        case reminderIntervalHours = "reminder_interval_hours"
        case reminderStartTime = "reminder_start_time"
        case reminderEndTime = "reminder_end_time"
        case preferredCupSizeMl = "preferred_cup_size_ml"
        case weightBasedGoal = "weight_based_goal"
    }
    
    static var `default`: HydrationSettings {
        HydrationSettings(
            id: nil,
            userId: UUID(),
            dailyGoalMl: 2500,
            reminderEnabled: true,
            reminderIntervalHours: 2,
            reminderStartTime: "08:00",
            reminderEndTime: "22:00",
            preferredCupSizeMl: 250,
            weightBasedGoal: true
        )
    }
}

struct HydrationStreaks: Codable {
    let id: UUID?
    let userId: UUID
    let currentStreak: Int
    let longestStreak: Int
    let totalDaysLogged: Int
    let totalDaysGoalMet: Int
    let totalLitersConsumed: Double
    let avgDailyIntakeMl: Int
    let bestDailyIntakeMl: Int
    let bestDailyDate: String?
    let lastGoalMetDate: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalDaysLogged = "total_days_logged"
        case totalDaysGoalMet = "total_days_goal_met"
        case totalLitersConsumed = "total_liters_consumed"
        case avgDailyIntakeMl = "avg_daily_intake_ml"
        case bestDailyIntakeMl = "best_daily_intake_ml"
        case bestDailyDate = "best_daily_date"
        case lastGoalMetDate = "last_goal_met_date"
    }
}

// MARK: - Water Intake Service

class HydrationService: ObservableObject {
    static let shared = HydrationService()
    
    @Published var todaySummary: HydrationDailySummary?
    @Published var todayLogs: [HydrationLog] = []
    @Published var settings: HydrationSettings = .default
    @Published var streaks: HydrationStreaks?
    @Published var weeklyData: [HydrationDailySummary] = []
    @Published var isLoading = false
    @Published var recommendedGoalMl: Int = 2500
    
    private let supabase = SupabaseManager.shared
    
    // Cached ISO8601 formatter (expensive to create)
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    @inline(__always) private func dateToISO(_ date: Date) -> String {
        iso8601.string(from: date)
    }
    
    private init() {
        Task {
            await loadTodayData()
            await calculateSmartGoal()
        }
    }
    
    // MARK: - Smart Goal Calculation
    
    /// Calculates recommended daily water intake based on user's weight and fitness goals
    /// Base formula: 35ml per kg of body weight
    /// Adjustments:
    /// - Weight Loss: +500ml (increased metabolism support)
    /// - Build Muscle: +750ml (muscle recovery and protein synthesis)
    /// - Improve Endurance: +500ml (hydration for cardio)
    /// - General Fitness: +250ml (moderate activity level)
    @MainActor
    func calculateSmartGoal() async {
        // Get user data from Core Data
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        
        do {
            let users = try viewContext.fetch(request)
            guard let user = users.first else {
                print("ℹ️ [Water] No user found, using default goal")
                recommendedGoalMl = 2500
                return
            }
            
            let weightKg = Int(user.weight)
            let fitnessGoal = user.fitnessGoal ?? "General Fitness"
            
            // Skip if no weight data
            guard weightKg > 0 else {
                print("ℹ️ [Water] No weight data, using default goal")
                recommendedGoalMl = 2500
                return
            }
            
            // Base calculation: 35ml per kg body weight
            var baseGoal = weightKg * 35
            
            // Adjust based on fitness goal
            switch fitnessGoal {
            case "Lose Weight", "Weight Loss":
                baseGoal += 500  // Extra water helps metabolism
            case "Build Muscle", "Gain Muscle":
                baseGoal += 750  // Muscle recovery needs more water
            case "Improve Endurance", "Endurance":
                baseGoal += 500  // Cardio requires more hydration
            case "General Fitness", "Stay Active":
                baseGoal += 250  // Moderate activity adjustment
            default:
                baseGoal += 250
            }
            
            // Round to nearest 100ml for cleaner numbers
            let roundedGoal = ((baseGoal + 50) / 100) * 100
            
            // Clamp between reasonable bounds (1500ml - 5000ml)
            recommendedGoalMl = min(max(roundedGoal, 1500), 5000)
            
            print("✅ [Water] Smart goal calculated: \(recommendedGoalMl)ml (weight: \(weightKg)kg, goal: \(fitnessGoal))")
            
            // Update settings if user hasn't customized their goal
            if settings.weightBasedGoal && settings.dailyGoalMl != recommendedGoalMl {
                var updatedSettings = settings
                updatedSettings.dailyGoalMl = recommendedGoalMl
                settings = updatedSettings
                
                // Sync to cloud if authenticated
                if supabase.isAuthenticated {
                    let _ = await updateSettings(updatedSettings)
                }
            }
            
        } catch {
            print("❌ [Water] Failed to fetch user data: \(error)")
            recommendedGoalMl = 2500
        }
    }
    
    // MARK: - Load Data
    
    @MainActor
    func loadTodayData() async {
        guard supabase.isAuthenticated, let userId = supabase.currentUser?.id else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Load today's summary
        await loadTodaySummary(userId: userId)
        
        // Load today's logs
        await loadTodayLogs(userId: userId)
        
        // Load settings
        await loadSettings(userId: userId)
        
        // Load streaks
        await loadStreaks(userId: userId)
        
        // Load weekly data for chart
        await loadWeeklyData(userId: userId)
    }
    
    private func loadTodaySummary(userId: UUID) async {
        let today = dateFormatter.string(from: Date())
        
        do {
            let summaries: [HydrationDailySummary] = try await supabase.supabaseClient
                .from("hydration_daily_summary")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("date", value: today)
                .execute()
                .value
            
            await MainActor.run {
                self.todaySummary = summaries.first
            }
        } catch {
            print("❌ [Water] Failed to load today's summary: \(error)")
        }
    }
    
    private func loadTodayLogs(userId: UUID) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        do {
            let logs: [HydrationLog] = try await supabase.supabaseClient
                .from("hydration_logs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("logged_at", value: dateToISO( startOfDay))
                .lt("logged_at", value: dateToISO( endOfDay))
                .order("logged_at", ascending: false)
                .execute()
                .value
            
            await MainActor.run {
                self.todayLogs = logs
            }
        } catch {
            print("❌ [Water] Failed to load today's logs: \(error)")
        }
    }
    
    private func loadSettings(userId: UUID) async {
        do {
            let settings: [HydrationSettings] = try await supabase.supabaseClient
                .from("hydration_settings")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            if let userSettings = settings.first {
                await MainActor.run {
                    self.settings = userSettings
                }
            } else {
                // Create default settings
                await createDefaultSettings(userId: userId)
            }
        } catch {
            print("❌ [Water] Failed to load settings: \(error)")
        }
    }
    
    private func loadStreaks(userId: UUID) async {
        do {
            let streaks: [HydrationStreaks] = try await supabase.supabaseClient
                .from("hydration_streaks")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            await MainActor.run {
                self.streaks = streaks.first
            }
        } catch {
            print("❌ [Water] Failed to load streaks: \(error)")
        }
    }
    
    private func loadWeeklyData(userId: UUID) async {
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        
        do {
            let summaries: [HydrationDailySummary] = try await supabase.supabaseClient
                .from("hydration_daily_summary")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date", value: dateFormatter.string(from: weekAgo))
                .order("date", ascending: true)
                .execute()
                .value
            
            await MainActor.run {
                self.weeklyData = summaries
            }
        } catch {
            print("❌ [Water] Failed to load weekly data: \(error)")
        }
    }
    
    // MARK: - Log Water
    
    @MainActor
    func logWater(amountMl: Int, notes: String? = nil) async -> Bool {
        // Get user ID from Supabase or local UserManager
        let userId: UUID
        if supabase.isAuthenticated, let supabaseUserId = supabase.currentUser?.id {
            userId = supabaseUserId
        } else if let localUser = UserManager.shared.currentUser, let localUserId = localUser.id {
            userId = localUserId
            print("⚠️ [Water] Using local user ID (not authenticated to cloud)")
        } else {
            print("❌ [Water] No user ID available")
            return false
        }
        
        // Always update local data FIRST for instant feedback
        await MainActor.run {
            todayLogs.append(HydrationLog(
                id: UUID(),
                userId: userId,
                amountMl: amountMl,
                drinkType: "water",
                loggedAt: Date(),
                notes: notes,
                createdAt: Date()
            ))
            calculateTodayStats()
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Try to save to cloud if authenticated (but don't block on this)
        if supabase.isAuthenticated {
            struct WaterLogInsert: Encodable {
                let user_id: String
                let amount_ml: Int
                let drink_type: String
                let logged_at: String
                let notes: String?
            }
            
            let log = WaterLogInsert(
                user_id: userId.uuidString,
                amount_ml: amountMl,
                drink_type: "water",
                logged_at: dateToISO( Date()),
                notes: notes
            )
            
            do {
                try await supabase.supabaseClient
                    .from("hydration_logs")
                    .insert(log)
                    .execute()
                
                print("✅ [Water] Logged \(amountMl)ml to cloud")
                
                // Only reload if cloud insert succeeded
                await loadTodayData()
            } catch {
                print("❌ [Water] Failed to log to cloud: \(error)")
                // Don't reload from cloud if insert failed - keep local data
            }
            
            // ⚡ REAL-TIME CHALLENGE SYNC: Push updated total to ALL challenge types
            let totalForChallenge = todayTotal
            Task {
                // Sync to 1v1 challenges
                await ChallengeService.shared.syncTrackingForType(.hydrate, value: totalForChallenge, source: "hydration")
                
                // Sync to private challenges
                await PrivateChallengeService.shared.syncTrackingForType(.hydrate, value: totalForChallenge, source: "hydration")
                
                // Sync to community challenges
                await CommunityChallengeService.shared.syncTrackingForType(.hydrate, value: totalForChallenge, source: "hydration")
                
                // Update daily quest progress for water logging
                await DailyQuestService.shared.onWaterLogged()
            }
        } else {
            print("ℹ️ [Water] Logged \(amountMl)ml locally (offline mode)")
        }
        
        return true
    }
    
    // MARK: - Delete Log
    
    @MainActor
    func deleteLog(_ log: HydrationLog) async -> Bool {
        do {
            try await supabase.supabaseClient
                .from("hydration_logs")
                .delete()
                .eq("id", value: log.id.uuidString)
                .execute()
            
            print("✅ [Water] Deleted log")
            await loadTodayData()
            
            // ⚡ Re-sync challenge progress with updated (lower) total.
            // allowDecrease: true tells the DB to accept the lower value
            // and fire a realtime event so the opponent sees the change.
            let updatedTotal = todayTotal
            Task {
                // Sync to 1v1 challenges (with decrease support)
                await ChallengeService.shared.syncTrackingForType(.hydrate, value: updatedTotal, source: "hydration", allowDecrease: true)
                
                // Sync to private challenges (re-push new total — GREATEST in DB keeps it safe)
                await PrivateChallengeService.shared.syncTrackingForType(.hydrate, value: updatedTotal, source: "hydration")
                
                // Sync to community challenges
                await CommunityChallengeService.shared.syncTrackingForType(.hydrate, value: updatedTotal, source: "hydration")
            }
            
            return true
        } catch {
            print("❌ [Water] Failed to delete log: \(error)")
            return false
        }
    }
    
    // MARK: - Update Settings
    
    @MainActor
    func updateSettings(_ newSettings: HydrationSettings) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        struct HydrationSettingsUpsert: Encodable {
            let user_id: String
            let daily_goal_ml: Int
            let reminder_enabled: Bool
            let reminder_interval_hours: Int
            let preferred_cup_size_ml: Int
            let weight_based_goal: Bool
            let updated_at: String
        }
        
        let settingsData = HydrationSettingsUpsert(
            user_id: userId.uuidString,
            daily_goal_ml: newSettings.dailyGoalMl,
            reminder_enabled: newSettings.reminderEnabled,
            reminder_interval_hours: newSettings.reminderIntervalHours,
            preferred_cup_size_ml: newSettings.preferredCupSizeMl,
            weight_based_goal: newSettings.weightBasedGoal,
            updated_at: dateToISO( Date())
        )
        
        do {
            try await supabase.supabaseClient
                .from("hydration_settings")
                .upsert(settingsData, onConflict: "user_id")
                .execute()
            
            self.settings = newSettings
            print("✅ [Water] Settings updated")
            return true
        } catch {
            print("❌ [Water] Failed to update settings: \(error)")
            // Update local settings anyway
            self.settings = newSettings
            return false
        }
    }
    
    private func createDefaultSettings(userId: UUID) async {
        var defaultSettings = HydrationSettings.default
        defaultSettings = HydrationSettings(
            id: nil,
            userId: userId,
            dailyGoalMl: defaultSettings.dailyGoalMl,
            reminderEnabled: defaultSettings.reminderEnabled,
            reminderIntervalHours: defaultSettings.reminderIntervalHours,
            reminderStartTime: defaultSettings.reminderStartTime,
            reminderEndTime: defaultSettings.reminderEndTime,
            preferredCupSizeMl: defaultSettings.preferredCupSizeMl,
            weightBasedGoal: defaultSettings.weightBasedGoal
        )
        
        let _ = await updateSettings(defaultSettings)
    }
    
    // MARK: - Computed Properties
    
    var todayProgress: Double {
        guard let summary = todaySummary, summary.goalMl > 0 else {
            return Double(todayTotal) / Double(settings.dailyGoalMl)
        }
        return summary.progress
    }
    
    var todayTotal: Int {
        todaySummary?.totalMl ?? todayLogs.reduce(0) { $0 + $1.amountMl }
    }
    
    var todayRemaining: Int {
        max(0, settings.dailyGoalMl - todayTotal)
    }
    
    var todayGoalMet: Bool {
        todayTotal >= settings.dailyGoalMl
    }
    
    // Calculate recommended goal based on weight (35ml per kg)
    func calculateRecommendedGoal(weightKg: Double, fitnessGoal: String? = nil) -> Int {
        var baseGoal = Int(weightKg * 35)
        
        // Adjust based on fitness goal
        if let goal = fitnessGoal {
            switch goal {
            case "Lose Weight", "Weight Loss":
                baseGoal += 500
            case "Build Muscle", "Gain Muscle":
                baseGoal += 750
            case "Improve Endurance", "Endurance":
                baseGoal += 500
            default:
                baseGoal += 250
            }
        }
        
        return ((baseGoal + 50) / 100) * 100  // Round to nearest 100
    }
    
    /// Call this when user profile is updated to recalculate goal
    func refreshSmartGoal() {
        Task {
            await calculateSmartGoal()
        }
    }
    
    // MARK: - Local Data Calculation
    
    /// Calculate today's summary from local logs (for offline/local mode)
    @MainActor
    private func calculateTodayStats() {
        let today = dateToISO( Date()).prefix(10)
        let totalMl = todayLogs.reduce(0) { $0 + $1.amountMl }
        let goalMl = settings.dailyGoalMl
        
        todaySummary = HydrationDailySummary(
            id: UUID(),
            userId: todayLogs.first?.userId ?? UUID(),
            date: String(today),
            totalMl: totalMl,
            goalMl: goalMl,
            waterMl: totalMl,
            teaMl: 0,
            coffeeMl: 0,
            sportsDrinkMl: 0,
            otherMl: 0,
            entryCount: todayLogs.count,
            firstDrinkTime: todayLogs.first.map { dateToISO( $0.loggedAt) },
            lastDrinkTime: todayLogs.last.map { dateToISO( $0.loggedAt) }
        )
    }
    
    // MARK: - Helpers
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

