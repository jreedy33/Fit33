import Foundation
import SwiftUI
import Combine
import CoreData

// MARK: - Notification for Weight Updates
extension Notification.Name {
    static let weightDidUpdate = Notification.Name("weightDidUpdate")
}

// MARK: - Weight Log Model

struct WeightLog: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let weightKg: Double
    let weightLbs: Double
    let loggedAt: Date
    let notes: String?
    let source: String  // "manual", "apple_health", etc.
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weightKg = "weight_kg"
        case weightLbs = "weight_lbs"
        case loggedAt = "logged_at"
        case notes
        case source
        case createdAt = "created_at"
    }
}

// MARK: - Weight Statistics Model

struct WeightStatistics: Codable {
    let userId: UUID
    let currentWeight: Double
    let startingWeight: Double
    let lowestWeight: Double
    let highestWeight: Double
    let totalChange: Double
    let weeklyChange: Double
    let monthlyChange: Double
    let averageWeight: Double
    let totalEntries: Int
    let streakDays: Int
    let lastLoggedDate: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentWeight = "current_weight"
        case startingWeight = "starting_weight"
        case lowestWeight = "lowest_weight"
        case highestWeight = "highest_weight"
        case totalChange = "total_change"
        case weeklyChange = "weekly_change"
        case monthlyChange = "monthly_change"
        case averageWeight = "average_weight"
        case totalEntries = "total_entries"
        case streakDays = "streak_days"
        case lastLoggedDate = "last_logged_date"
    }
}

// MARK: - Weight Trend Data Point

struct WeightTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
    let isProjected: Bool
    
    init(date: Date, weight: Double, isProjected: Bool = false) {
        self.date = date
        self.weight = weight
        self.isProjected = isProjected
    }
}

// MARK: - Weight Goal

struct WeightGoal: Codable {
    let userId: UUID
    var targetWeight: Double
    var targetDate: Date?
    var goalType: GoalType
    
    enum GoalType: String, Codable, CaseIterable {
        case lose = "lose"
        case gain = "gain"
        case maintain = "maintain"
        
        var displayName: String {
            switch self {
            case .lose: return "Lose Weight"
            case .gain: return "Gain Weight"
            case .maintain: return "Maintain Weight"
            }
        }
        
        var icon: String {
            switch self {
            case .lose: return "arrow.down.circle.fill"
            case .gain: return "arrow.up.circle.fill"
            case .maintain: return "equal.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .lose: return .orange
            case .gain: return .green
            case .maintain: return .blue
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case targetWeight = "target_weight"
        case targetDate = "target_date"
        case goalType = "goal_type"
    }
}

// MARK: - Weight Tracking Service
/// Single source of truth for weight data. Other services (UserManager, onboarding)
/// may cache weight locally for quick access, but this service owns the authoritative
/// value synced with Supabase and HealthKit.
class WeightTrackingService: ObservableObject {
    static let shared = WeightTrackingService()
    
    // MARK: - Published Properties
    @Published var todayLog: WeightLog? {
        didSet {
            // Cache today's weight locally for immediate display on app restart
            cacheTodayWeight()
        }
    }
    @Published var recentLogs: [WeightLog] = []
    @Published var weeklyTrend: [WeightTrendPoint] = []
    @Published var monthlyTrend: [WeightTrendPoint] = []
    @Published var statistics: WeightStatistics?
    @Published var weightGoal: WeightGoal?
    @Published var isLoading = false
    @Published var hasLoggedToday = false
    
    private let supabase = SupabaseManager.shared
    private let unitSettings = UnitSettingsManager.shared
    
    // Local cache keys for today's weight (survives app force quit)
    private let todayWeightKgKey = "cached_today_weight_kg"
    private let todayWeightLbsKey = "cached_today_weight_lbs"
    private let todayWeightDateKey = "cached_today_weight_date"
    
    // Cached ISO8601 formatter
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    @inline(__always) private func dateToISO(_ date: Date) -> String {
        iso8601.string(from: date)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    // MARK: - Init
    
    private init() {
        // Load cached weight immediately (instant display on app restart)
        loadCachedTodayWeight()
        
        // Then load from cloud to update with latest data
        Task {
            await loadAllData()
        }
    }
    
    // MARK: - Local Weight Caching (survives force quit)
    
    /// Cache today's weight to UserDefaults for instant display on app restart
    private func cacheTodayWeight() {
        guard let log = todayLog else {
            // Clear cache if no weight today
            UserDefaults.standard.removeObject(forKey: todayWeightKgKey)
            UserDefaults.standard.removeObject(forKey: todayWeightLbsKey)
            UserDefaults.standard.removeObject(forKey: todayWeightDateKey)
            UserDefaults.standard.synchronize() // Force immediate write
            print("🗑️ [Weight] Cleared cached weight")
            return
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(log.weightKg, forKey: todayWeightKgKey)
        UserDefaults.standard.set(log.weightLbs, forKey: todayWeightLbsKey)
        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: todayWeightDateKey)
        UserDefaults.standard.synchronize() // Force immediate write to disk
        print("💾 [Weight] Cached weight: \(log.weightKg) kg / \(log.weightLbs) lbs (source: \(log.source))")
        
        // Verify it was saved
        let verifyKg = UserDefaults.standard.double(forKey: todayWeightKgKey)
        let verifyLbs = UserDefaults.standard.double(forKey: todayWeightLbsKey)
        let verifyDate = UserDefaults.standard.double(forKey: todayWeightDateKey)
        print("✅ [Weight] Verified cache - kg:\(verifyKg) lbs:\(verifyLbs) date:\(verifyDate)")
    }
    
    /// Load cached today's weight from UserDefaults (called on init for instant display)
    private func loadCachedTodayWeight() {
        print("🔍 [Weight] Checking for cached weight...")
        let cachedDate = UserDefaults.standard.double(forKey: todayWeightDateKey)
        guard cachedDate > 0 else {
            print("⚠️ [Weight] No cached date found")
            return
        }
        
        let cachedDateObj = Date(timeIntervalSince1970: cachedDate)
        let today = Calendar.current.startOfDay(for: Date())
        
        // Only use cache if it's from today
        guard Calendar.current.isDate(cachedDateObj, inSameDayAs: today) else {
            // Cache is stale, clear it
            UserDefaults.standard.removeObject(forKey: todayWeightKgKey)
            UserDefaults.standard.removeObject(forKey: todayWeightLbsKey)
            UserDefaults.standard.removeObject(forKey: todayWeightDateKey)
            print("🗑️ [Weight] Cache is stale (from \(cachedDateObj)), clearing")
            return
        }
        
        let cachedKg = UserDefaults.standard.double(forKey: todayWeightKgKey)
        let cachedLbs = UserDefaults.standard.double(forKey: todayWeightLbsKey)
        
        guard cachedKg > 0 || cachedLbs > 0 else {
            print("⚠️ [Weight] Cached weight is 0")
            return
        }
        
        // Create a synthetic log from cache
        let cachedLog = WeightLog(
            id: UUID(),
            userId: supabase.currentUser?.id ?? UUID(),
            weightKg: cachedKg,
            weightLbs: cachedLbs,
            loggedAt: Date(),
            notes: nil,
            source: "cached",
            createdAt: Date()
        )
        
        todayLog = cachedLog
        hasLoggedToday = true
        print("✅ [Weight] Loaded cached today's weight: \(cachedKg) kg / \(cachedLbs) lbs")
    }
    
    // MARK: - Computed Properties
    
    /// Current weight in user's preferred unit
    var currentWeight: Double {
        guard let latest = recentLogs.first else {
            return getUserStoredWeight()
        }
        return unitSettings.weightUnit == .imperial ? latest.weightLbs : latest.weightKg
    }
    
    /// Weight change this week
    var weeklyChange: Double {
        statistics?.weeklyChange ?? 0
    }
    
    /// Weight change this month
    var monthlyChange: Double {
        statistics?.monthlyChange ?? 0
    }
    
    /// Progress towards goal (0-1), works for both weight loss and gain
    var goalProgress: Double {
        guard let goal = weightGoal, let stats = statistics else { return 0 }
        let current = stats.currentWeight
        let start = stats.startingWeight
        let target = goal.targetWeight
        
        guard abs(target - start) > 0.01 else { return 1.0 }
        
        let progress = abs(current - start) / abs(target - start)
        return min(max(progress, 0), 1.0)
    }
    
    /// Estimated date to reach goal based on current trend
    var estimatedGoalDate: Date? {
        guard let goal = weightGoal,
              let stats = statistics,
              stats.weeklyChange != 0 else { return nil }
        
        let remaining = abs(stats.currentWeight - goal.targetWeight)
        let weeksNeeded = remaining / abs(stats.weeklyChange)
        
        return Calendar.current.date(byAdding: .weekOfYear, value: Int(ceil(weeksNeeded)), to: Date())
    }
    
    /// Weight unit suffix
    var weightUnitSuffix: String {
        unitSettings.weightUnit == .imperial ? "lbs" : "kg"
    }
    
    /// Check if user prefers pounds
    var usesLbs: Bool {
        unitSettings.weightUnit == .imperial
    }
    
    // MARK: - Load Data
    
    @MainActor
    func loadAllData() async {
        guard supabase.isAuthenticated, let userId = supabase.currentUser?.id else {
            // Load from local storage if offline
            loadLocalData()
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRecentLogs(userId: userId) }
            group.addTask { await self.loadTodayLog(userId: userId) }
            group.addTask { await self.loadStatistics(userId: userId) }
            group.addTask { await self.loadWeightGoal(userId: userId) }
        }
        
        // Calculate trends from loaded data
        calculateTrends()
    }
    
    private func loadLocalData() {
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        
        if let user = try? viewContext.fetch(request).first {
            let weightKg = Double(user.weight)
            let weightLbs = user.weightLbs
            
            if weightKg > 0 || weightLbs > 0 {
                // Create a synthetic log from stored profile weight
                let syntheticLog = WeightLog(
                    id: UUID(),
                    userId: user.id ?? UUID(),
                    weightKg: weightKg,
                    weightLbs: weightLbs,
                    loggedAt: Date(),
                    notes: nil,
                    source: "profile",
                    createdAt: Date()
                )
                recentLogs = [syntheticLog]
            }
        }
    }
    
    private func loadRecentLogs(userId: UUID) async {
        do {
            let logs: [WeightLog] = try await supabase.supabaseClient
                .from("weight_logs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("logged_at", ascending: false)
                .limit(90)  // Last 90 days of entries
                .execute()
                .value
            
            await MainActor.run {
                self.recentLogs = logs
            }
            print("✅ [Weight] Loaded \(logs.count) recent weight logs")
        } catch {
            print("❌ [Weight] Failed to load recent logs: \(error)")
        }
    }
    
    private func loadTodayLog(userId: UUID) async {
        let today = Self.dateFormatter.string(from: Date())
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        do {
            let logs: [WeightLog] = try await supabase.supabaseClient
                .from("weight_logs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("logged_at", value: dateToISO(startOfDay))
                .lt("logged_at", value: dateToISO(endOfDay))
                .order("logged_at", ascending: false)
                .limit(1)
                .execute()
                .value
            
            await MainActor.run {
                // IMPORTANT: Only update if we got a result from server
                // This prevents overwriting cached/optimistic updates with empty database results
                if let serverLog = logs.first {
                    print("✅ [Weight] Loaded today's log from server (id: \(serverLog.id))")
                    self.todayLog = serverLog  // This will trigger cacheTodayWeight() via didSet
                    self.hasLoggedToday = true
                } else {
                    // No server log found
                    if let existingLog = self.todayLog {
                        // Keep cached or manual entry - don't overwrite with empty result
                        print("ℹ️ [Weight] No server log, keeping existing entry (source: \(existingLog.source))")
                        // Don't change todayLog or hasLoggedToday
                    } else {
                        // No cached data either, truly no weight logged today
                        print("ℹ️ [Weight] No weight logged today")
                        self.todayLog = nil
                        self.hasLoggedToday = false
                    }
                }
            }
        } catch {
            print("❌ [Weight] Failed to load today's log: \(error)")
            // On error, keep any cached data we have
        }
    }
    
    private func loadStatistics(userId: UUID) async {
        do {
            let stats: [WeightStatistics] = try await supabase.supabaseClient
                .from("weight_statistics")
                .select()
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            
            await MainActor.run {
                self.statistics = stats.first
            }
        } catch {
            print("❌ [Weight] Failed to load statistics: \(error)")
            // Calculate stats locally if view doesn't exist
            await calculateLocalStatistics()
        }
    }
    
    private func loadWeightGoal(userId: UUID) async {
        do {
            let goals: [WeightGoal] = try await supabase.supabaseClient
                .from("weight_goals")
                .select()
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            
            await MainActor.run {
                self.weightGoal = goals.first
            }
        } catch {
            print("❌ [Weight] Failed to load weight goal: \(error)")
        }
    }
    
    // MARK: - Log Weight
    
    @MainActor
    func logWeight(_ weight: Double, notes: String? = nil) async -> Bool {
        guard let userId = supabase.currentUser?.id else {
            print("❌ [Weight] No user ID available")
            return false
        }
        
        // Convert based on unit preference
        let weightKg: Double
        let weightLbs: Double
        
        if usesLbs {
            weightLbs = weight
            weightKg = weight / 2.20462
        } else {
            weightKg = weight
            weightLbs = weight * 2.20462
        }
        
        // Create optimistic local update
        let newLog = WeightLog(
            id: UUID(),
            userId: userId,
            weightKg: weightKg,
            weightLbs: weightLbs,
            loggedAt: Date(),
            notes: notes,
            source: "manual",
            createdAt: Date()
        )
        
        // Update UI immediately (optimistic update)
        print("📝 [Weight] Updating UI with new weight: \(weight) \(usesLbs ? "lbs" : "kg")")
        print("📝 [Weight] Creating log: kg=\(weightKg), lbs=\(weightLbs), source=manual")
        
        todayLog = newLog  // This triggers didSet → cacheTodayWeight()
        hasLoggedToday = true
        recentLogs.insert(newLog, at: 0)
        calculateTrends()
        
        // Post notification so all weight widgets refresh (home screen + nutrition tab)
        NotificationCenter.default.post(name: .weightDidUpdate, object: nil)
        
        print("✅ [Weight] UI updated - todayLog.id=\(newLog.id), hasLoggedToday=\(hasLoggedToday)")
        print("✅ [Weight] didSet should have triggered cacheTodayWeight()")
        
        // Haptic feedback
        HapticManager.impact(.medium)
        
        // Save to cloud
        struct WeightLogInsert: Encodable {
            let user_id: String
            let weight_kg: Double
            let weight_lbs: Double
            let logged_at: String
            let notes: String?
            let source: String
        }
        
        let logInsert = WeightLogInsert(
            user_id: userId.uuidString,
            weight_kg: weightKg,
            weight_lbs: weightLbs,
            logged_at: dateToISO(Date()),
            notes: notes,
            source: "manual"
        )
        
        do {
            try await supabase.supabaseClient
                .from("weight_logs")
                .insert(logInsert)
                .execute()
            
            print("✅ [Weight] Logged \(weight) \(weightUnitSuffix) to cloud")
            
            // Update daily quest progress for weight logging
            Task { @MainActor in
                await DailyQuestService.shared.onWeightLogged()
            }
            
            // Update user profile weight
            await updateUserProfileWeight(weightKg: weightKg, weightLbs: weightLbs)
            
            // DON'T reload todayLog from server - keep the optimistic update
            // Only reload statistics and recent logs for trends/graphs
            // This ensures the widget shows the weight immediately without flickering
            if let userId = supabase.currentUser?.id {
                await loadStatistics(userId: userId)
                // Load recent logs but skip the first one since we already have it optimistically
                await loadRecentLogs(userId: userId)
            }
            
            print("✅ [Weight] Save complete, todayLog retained")
            return true
        } catch {
            print("❌ [Weight] Failed to log weight: \(error)")
            return false
        }
    }
    
    // MARK: - Update Weight Goal
    
    @MainActor
    func setWeightGoal(targetWeight: Double, targetDate: Date?, goalType: WeightGoal.GoalType) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        struct WeightGoalUpsert: Encodable {
            let user_id: String
            let target_weight: Double
            let target_date: String?
            let goal_type: String
            let updated_at: String
        }
        
        let goalData = WeightGoalUpsert(
            user_id: userId.uuidString,
            target_weight: targetWeight,
            target_date: targetDate.map { Self.dateFormatter.string(from: $0) },
            goal_type: goalType.rawValue,
            updated_at: dateToISO(Date())
        )
        
        do {
            try await supabase.supabaseClient
                .from("weight_goals")
                .upsert(goalData, onConflict: "user_id")
                .execute()
            
            self.weightGoal = WeightGoal(
                userId: userId,
                targetWeight: targetWeight,
                targetDate: targetDate,
                goalType: goalType
            )
            
            print("✅ [Weight] Goal updated: \(targetWeight) \(weightUnitSuffix)")
            return true
        } catch {
            print("❌ [Weight] Failed to set goal: \(error)")
            return false
        }
    }
    
    // MARK: - Delete Log
    
    @MainActor
    func deleteLog(_ log: WeightLog) async -> Bool {
        do {
            try await supabase.supabaseClient
                .from("weight_logs")
                .delete()
                .eq("id", value: log.id.uuidString)
                .execute()
            
            // Remove from local array
            recentLogs.removeAll { $0.id == log.id }
            if todayLog?.id == log.id {
                todayLog = nil
                hasLoggedToday = false
            }
            
            calculateTrends()
            print("✅ [Weight] Deleted log")
            return true
        } catch {
            print("❌ [Weight] Failed to delete log: \(error)")
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    private func getUserStoredWeight() -> Double {
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        
        if let user = try? viewContext.fetch(request).first {
            return usesLbs ? user.weightLbs : Double(user.weight)
        }
        return 0
    }
    
    private func updateUserProfileWeight(weightKg: Double, weightLbs: Double) async {
        // Update Core Data
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        
        await MainActor.run {
            if let user = try? viewContext.fetch(request).first {
                user.weight = Int16(weightKg)
                user.weightLbs = weightLbs
                try? viewContext.save()
                print("✅ [Weight] Updated Core Data profile weight")
            }
        }
        
        // Update cloud profile
        do {
            try await supabase.updateUserProfile(
                name: nil,
                heightCm: nil,
                weightKg: weightKg,
                fitnessGoal: nil,
                experienceLevel: nil
            )
            print("✅ [Weight] Updated cloud profile weight")
        } catch {
            print("⚠️ [Weight] Failed to update cloud profile: \(error)")
        }
    }
    
    private func calculateTrends() {
        // Weekly trend (last 7 days)
        let calendar = Calendar.current
        let today = Date()
        
        weeklyTrend = (0..<7).compactMap { daysAgo -> WeightTrendPoint? in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayStart = calendar.startOfDay(for: date)
            
            // Find log for this day
            if let log = recentLogs.first(where: {
                calendar.isDate($0.loggedAt, inSameDayAs: dayStart)
            }) {
                let weight = usesLbs ? log.weightLbs : log.weightKg
                return WeightTrendPoint(date: dayStart, weight: weight)
            }
            return nil
        }.reversed()
        
        // Monthly trend (last 30 days, but only show days with logs)
        monthlyTrend = (0..<30).compactMap { daysAgo -> WeightTrendPoint? in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayStart = calendar.startOfDay(for: date)
            
            if let log = recentLogs.first(where: {
                calendar.isDate($0.loggedAt, inSameDayAs: dayStart)
            }) {
                let weight = usesLbs ? log.weightLbs : log.weightKg
                return WeightTrendPoint(date: dayStart, weight: weight)
            }
            return nil
        }.reversed()
    }
    
    @MainActor
    private func calculateLocalStatistics() async {
        guard !recentLogs.isEmpty else { return }
        
        let weights = recentLogs.map { usesLbs ? $0.weightLbs : $0.weightKg }
        let currentWeight = weights.first ?? 0
        let startingWeight = weights.last ?? currentWeight
        
        // Calculate weekly change
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let weekAgoWeight = recentLogs.first(where: { $0.loggedAt <= weekAgo }).map { usesLbs ? $0.weightLbs : $0.weightKg } ?? currentWeight
        let weeklyChange = currentWeight - weekAgoWeight
        
        // Calculate monthly change
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        let monthAgoWeight = recentLogs.first(where: { $0.loggedAt <= monthAgo }).map { usesLbs ? $0.weightLbs : $0.weightKg } ?? currentWeight
        let monthlyChange = currentWeight - monthAgoWeight
        
        statistics = WeightStatistics(
            userId: recentLogs.first?.userId ?? UUID(),
            currentWeight: currentWeight,
            startingWeight: startingWeight,
            lowestWeight: weights.min() ?? currentWeight,
            highestWeight: weights.max() ?? currentWeight,
            totalChange: currentWeight - startingWeight,
            weeklyChange: weeklyChange,
            monthlyChange: monthlyChange,
            averageWeight: weights.reduce(0, +) / Double(weights.count),
            totalEntries: recentLogs.count,
            streakDays: calculateStreak(),
            lastLoggedDate: recentLogs.first.map { Self.dateFormatter.string(from: $0.loggedAt) }
        )
    }
    
    private func calculateStreak() -> Int {
        guard !recentLogs.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        
        // Check if logged today
        let hasToday = recentLogs.contains { calendar.isDate($0.loggedAt, inSameDayAs: currentDate) }
        if !hasToday {
            // Start checking from yesterday
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }
        
        while true {
            let hasLog = recentLogs.contains { calendar.isDate($0.loggedAt, inSameDayAs: currentDate) }
            if hasLog {
                streak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
            } else {
                break
            }
        }
        
        return streak
    }
    
    // MARK: - Fitness Intelligence Integration
    
    /// Returns weight trend data for workout/program recommendations
    func getWeightTrendForRecommendations() -> (trend: String, weeklyChange: Double, isOnTrack: Bool) {
        guard let stats = statistics, let goal = weightGoal else {
            return ("stable", 0, true)
        }
        
        let trend: String
        let isOnTrack: Bool
        
        switch goal.goalType {
        case .lose:
            trend = stats.weeklyChange < 0 ? "losing" : (stats.weeklyChange > 0 ? "gaining" : "stable")
            // On track if losing 0.5-2 lbs per week (or 0.2-1 kg)
            let healthyLossMin = usesLbs ? -2.0 : -1.0
            let healthyLossMax = usesLbs ? -0.5 : -0.2
            isOnTrack = stats.weeklyChange >= healthyLossMin && stats.weeklyChange <= healthyLossMax
            
        case .gain:
            trend = stats.weeklyChange > 0 ? "gaining" : (stats.weeklyChange < 0 ? "losing" : "stable")
            // On track if gaining 0.25-0.5 lbs per week (or 0.1-0.25 kg)
            let healthyGainMin = usesLbs ? 0.25 : 0.1
            let healthyGainMax = usesLbs ? 0.5 : 0.25
            isOnTrack = stats.weeklyChange >= healthyGainMin && stats.weeklyChange <= healthyGainMax
            
        case .maintain:
            trend = abs(stats.weeklyChange) < (usesLbs ? 1.0 : 0.5) ? "stable" : (stats.weeklyChange > 0 ? "gaining" : "losing")
            // On track if within ±1 lb (or ±0.5 kg) per week
            isOnTrack = abs(stats.weeklyChange) < (usesLbs ? 1.0 : 0.5)
        }
        
        return (trend, stats.weeklyChange, isOnTrack)
    }
    
    /// Suggests adjustments based on weight trend and goals
    func getWorkoutAdjustmentSuggestion() -> String? {
        let (trend, change, isOnTrack) = getWeightTrendForRecommendations()
        
        guard let goal = weightGoal, !isOnTrack else { return nil }
        
        switch goal.goalType {
        case .lose:
            if change > 0 {
                return "Consider adding more cardio or reducing rest periods between sets."
            } else if change < (usesLbs ? -2.0 : -1.0) {
                return "You're losing weight quickly! Ensure you're eating enough protein to preserve muscle."
            }
            
        case .gain:
            if change < 0 {
                return "You're losing weight. Consider reducing cardio and focusing on progressive overload."
            } else if change > (usesLbs ? 1.0 : 0.5) {
                return "You're gaining quickly! Add more cardio to ensure lean gains."
            }
            
        case .maintain:
            if change > (usesLbs ? 1.0 : 0.5) {
                return "Weight is trending up. Consider adding light cardio sessions."
            } else if change < (usesLbs ? -1.0 : -0.5) {
                return "Weight is trending down. You may need more recovery days or calories."
            }
        }
        
        return nil
    }
}
