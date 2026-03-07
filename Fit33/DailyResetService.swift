import Foundation
import SwiftUI
import Combine
import CoreData
import UserNotifications

/// DailyResetService handles all midnight reset and daily archival operations
/// - Archives daily metrics to database (nutrition, hydration, weight)
/// - Clears local "today" data so user starts fresh
/// - Refreshes challenges for new day
/// - Prompts user to log weight for trends
/// - Manages daily streaks and statistics
@MainActor
class DailyResetService: ObservableObject {
    static let shared = DailyResetService()
    
    // MARK: - Published State
    @Published var lastResetDate: Date?
    @Published var isPerformingReset = false
    @Published var dailyResetLog: [String] = []
    
    // MARK: - Private Properties
    private let supabase = SupabaseManager.shared
    private let viewContext = PersistenceController.shared.container.viewContext
    
    // UserDefaults keys
    private let lastResetDateKey = "daily_reset_last_date"
    private let lastDailySummaryDateKey = "daily_summary_last_archived"
    
    // Cached ISO8601 formatter
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    @inline(__always) private func dateToISO(_ date: Date) -> String {
        iso8601.string(from: date)
    }
    
    private init() {
        loadLastResetDate()
    }
    
    // MARK: - Public API
    
    /// Check if a new day has started and perform reset if needed
    /// Call this on app foreground, midnight timer, or manual trigger
    func checkAndPerformDailyResetIfNeeded() async {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        
        // Check if we already reset today
        if let lastReset = lastResetDate,
           calendar.isDate(lastReset, inSameDayAs: now) {
            print("🌙 [DAILY RESET] Already performed today's reset at \(lastReset)")
            return
        }
        
        print("🌙 [DAILY RESET] New day detected! Performing daily reset...")
        await performDailyReset()
    }
    
    /// Force a daily reset (for testing or manual trigger)
    func forcePerformDailyReset() async {
        await performDailyReset()
    }
    
    // MARK: - Core Reset Logic
    
    private func performDailyReset() async {
        guard !isPerformingReset else {
            print("🌙 [DAILY RESET] Reset already in progress, skipping...")
            return
        }
        
        isPerformingReset = true
        dailyResetLog = []
        
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        
        logStep("🌙 Starting daily reset for \(formatDateForLog(yesterday))")
        
        // 1. Archive yesterday's daily summary to database
        await archiveDailySummary(for: yesterday)
        
        // 2. Clear local "today" data in Core Data
        clearLocalTodayMeals()
        
        // 3. Refresh challenges for new day
        await refreshChallengesForNewDay()
        
        // 4. Refresh hydration for new day
        await refreshHydrationForNewDay()
        
        // 5. Refresh weight tracking UI
        await refreshWeightTrackingForNewDay()
        
        // 6. Send weight logging reminder if enabled
        scheduleWeightReminderIfNeeded()
        
        // 7. Update streaks
        await updateDailyStreaks()
        
        // 8. Refresh friend scores (materialized view)
        await refreshFriendScores()
        
        // 9. Run personalized insights analysis
        await runInsightsAnalysis()
        
        // 10. Mark reset as complete
        lastResetDate = now
        saveLastResetDate()
        
        logStep("✅ Daily reset complete!")
        isPerformingReset = false
        
        // Post notification for UI refresh
        NotificationCenter.default.post(name: .dailyResetCompleted, object: nil)
    }
    
    // MARK: - Step 1: Archive Daily Summary
    
    private func archiveDailySummary(for date: Date) async {
        guard supabase.isAuthenticated, let userId = supabase.currentUser?.id else {
            logStep("⚠️ User not authenticated - skipping cloud archive")
            return
        }
        
        logStep("📦 Archiving daily summary to database...")
        
        // Get yesterday's nutrition data
        let nutritionSummary = MealService.shared.getDailySummary(for: date)
        
        // Get yesterday's hydration data
        let hydrationTotal = HydrationService.shared.todaySummary?.totalMl ?? 0
        let hydrationGoal = HydrationService.shared.settings.dailyGoalMl
        
        // Get yesterday's weight (if logged)
        let weightLog = WeightTrackingService.shared.todayLog
        
        // Get yesterday's workout data
        let workoutCount = await getWorkoutCount(for: date)
        let workoutMinutes = await getWorkoutMinutes(for: date)
        let caloriesBurned = await getCaloriesBurned(for: date)
        
        // Get step count from HealthKit
        let stepCount = await getStepCount(for: date)
        
        // Create daily summary record
        struct DailySummaryInsert: Encodable {
            let user_id: String
            let date: String
            let calories_consumed: Int
            let protein_g: Int
            let carbs_g: Int
            let fat_g: Int
            let meals_logged: Int
            let hydration_ml: Int
            let hydration_goal_ml: Int
            let hydration_goal_met: Bool
            let weight_kg: Double?
            let weight_lbs: Double?
            let workout_count: Int
            let workout_minutes: Int
            let calories_burned: Int
            let step_count: Int
            let created_at: String
        }
        
        let dateString = formatDateForDB(date)
        
        let summary = DailySummaryInsert(
            user_id: userId.uuidString,
            date: dateString,
            calories_consumed: nutritionSummary.calories,
            protein_g: nutritionSummary.protein,
            carbs_g: nutritionSummary.carbs,
            fat_g: nutritionSummary.fat,
            meals_logged: nutritionSummary.mealCount,
            hydration_ml: hydrationTotal,
            hydration_goal_ml: hydrationGoal,
            hydration_goal_met: hydrationTotal >= hydrationGoal,
            weight_kg: weightLog?.weightKg,
            weight_lbs: weightLog?.weightLbs,
            workout_count: workoutCount,
            workout_minutes: workoutMinutes,
            calories_burned: caloriesBurned,
            step_count: stepCount,
            created_at: dateToISO(Date())
        )
        
        do {
            try await supabase.supabaseClient
                .from("daily_summaries")
                .upsert(summary, onConflict: "user_id,date")
                .execute()
            
            logStep("✅ Daily summary archived: \(nutritionSummary.calories)cal, \(hydrationTotal)ml water, \(workoutCount) workouts")
        } catch {
            logStep("❌ Failed to archive daily summary: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Step 2: Clear Local Today Meals
    
    private func clearLocalTodayMeals() {
        logStep("🗑️ Clearing yesterday's local meal data...")
        
        // Note: We don't actually delete meals - they stay in Core Data for history
        // We just tell MealService to reload for today (which will be empty)
        MealService.shared.loadTodaysMeals()
        
        logStep("✅ Today's meal view ready for fresh input")
    }
    
    // MARK: - Step 3: Refresh Challenges
    
    private func refreshChallengesForNewDay() async {
        logStep("🏆 Refreshing challenges for new day...")
        
        // Clear stale cached challenges so any temporary display between now and
        // the fresh fetch won't show yesterday's today-progress values.
        ChallengeService.shared.clearCache()
        
        // Force fetch fresh challenge data from server.
        // The server's get_active_challenges uses (NOW() AT TIME ZONE p_timezone)::DATE
        // to determine "today", so fetching after midnight local time will return
        // today_progress = 0 for both users (clean daily reset).
        await ChallengeService.shared.fetchActiveChallenges()
        await ChallengeService.shared.fetchActiveGroupChallenges()
        await ChallengeService.shared.fetchPendingInvites()
        
        // Sync HealthKit data which updates challenge progress for the new day
        await HealthKitService.shared.syncAllData(force: true)
        
        logStep("✅ Challenges refreshed - today's progress starts at 0")
    }
    
    // MARK: - Step 4: Refresh Hydration
    
    private func refreshHydrationForNewDay() async {
        logStep("💧 Refreshing hydration for new day...")
        
        // Reload today's data (will be empty/fresh for new day)
        await HydrationService.shared.loadTodayData()
        
        logStep("✅ Hydration reset - today: 0ml")
    }
    
    // MARK: - Step 5: Refresh Weight Tracking
    
    private func refreshWeightTrackingForNewDay() async {
        logStep("⚖️ Refreshing weight tracking for new day...")
        
        // Reload today's weight status
        await WeightTrackingService.shared.loadAllData()
        
        let hasLoggedToday = WeightTrackingService.shared.hasLoggedToday
        logStep("✅ Weight tracking refreshed - logged today: \(hasLoggedToday)")
    }
    
    // MARK: - Step 6: Weight Reminder
    
    private func scheduleWeightReminderIfNeeded() {
        logStep("📲 Checking if weight reminder needed...")
        
        // Only remind if user hasn't logged weight today AND has enabled reminders
        let hasLoggedToday = WeightTrackingService.shared.hasLoggedToday
        let remindersEnabled = NotificationManager.shared.weightRemindersEnabled
        
        if !hasLoggedToday && remindersEnabled {
            // Schedule a gentle reminder for later in the day
            let content = UNMutableNotificationContent()
            content.title = "Track Your Progress"
            content.body = "Log today's weight to see your trends! 📈"
            content.sound = .default
            content.categoryIdentifier = "weight_reminder"
            
            // Schedule for 9 AM if it's before that, otherwise 8 PM
            var triggerDate = DateComponents()
            let hour = Calendar.current.component(.hour, from: Date())
            triggerDate.hour = hour < 9 ? 9 : 20
            triggerDate.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            let request = UNNotificationRequest(
                identifier: "daily_weight_reminder",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ [DAILY RESET] Failed to schedule weight reminder: \(error)")
                }
            }
            
            logStep("📲 Weight reminder scheduled")
        } else {
            logStep("📲 Weight reminder not needed (logged: \(hasLoggedToday), enabled: \(remindersEnabled))")
        }
    }
    
    // MARK: - Step 7: Update Streaks
    
    private func updateDailyStreaks() async {
        logStep("🔥 Checking daily streaks...")

        // Check if workout streak should be broken due to inactivity
        // NOTE: We only CHECK for breaks here, NOT increment.
        // Streak increments happen in UserManager.updateStreak() which is called
        // on actual workout completion (completeWorkout, Strava sync, Fitbit sync).
        UserManager.shared.checkAndBreakStreakIfNeeded()

        // Hydration streak is handled by HydrationService
        // Weight streak is handled by WeightTrackingService

        logStep("✅ Streaks checked")
    }
    
    // MARK: - Step 8: Refresh Friend Scores
    
    private func refreshFriendScores() async {
        logStep("👥 Refreshing friend ranking scores...")
        
        await FriendRankingService.shared.refreshScores()
        
        logStep("✅ Friend scores refreshed")
    }
    
    // MARK: - Step 9: Personalized Insights
    
    private func runInsightsAnalysis() async {
        logStep("🧠 Running personalized insights analysis...")
        
        // Run insights analysis (PersonalizedInsightsService handles all the work)
        await PersonalizedInsightsService.shared.runDailyAnalysis()
        let insightCount = PersonalizedInsightsService.shared.activeInsights.count
        logStep("✅ Insights analysis complete - \(insightCount) active insights")
    }
    
    // MARK: - Helper: Get Workout Data
    
    private func getWorkoutCount(for date: Date) async -> Int {
        // Query Core Data for completed workouts on this date
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND isCompleted == YES", startOfDay as NSDate, endOfDay as NSDate)
        
        do {
            let results = try viewContext.fetch(request)
            return results.count
        } catch {
            print("❌ [DAILY RESET] Error fetching workout count: \(error)")
            return 0
        }
    }
    
    private func getWorkoutMinutes(for date: Date) async -> Int {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND isCompleted == YES", startOfDay as NSDate, endOfDay as NSDate)
        
        do {
            let results = try viewContext.fetch(request)
            return results.reduce(0) { $0 + Int($1.duration / 60) }
        } catch {
            return 0
        }
    }
    
    private func getCaloriesBurned(for date: Date) async -> Int {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND isCompleted == YES", startOfDay as NSDate, endOfDay as NSDate)
        
        do {
            let results = try viewContext.fetch(request)
            // Workout entity doesn't have caloriesBurned - estimate from duration
            // ~5 calories per minute of workout
            return results.reduce(0) { $0 + Int($1.duration / 60) * 5 }
        } catch {
            return 0
        }
    }
    
    private func getStepCount(for date: Date) async -> Int {
        // Get from HealthKit via HealthKitService
        return await HealthKitService.shared.getStepCount(for: date)
    }
    
    // MARK: - Persistence
    
    private func loadLastResetDate() {
        if let date = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date {
            lastResetDate = date
        }
    }
    
    private func saveLastResetDate() {
        UserDefaults.standard.set(lastResetDate, forKey: lastResetDateKey)
    }
    
    // MARK: - Formatting Helpers
    
    private func formatDateForDB(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func formatDateForLog(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func logStep(_ message: String) {
        print("🌙 [DAILY RESET] \(message)")
        dailyResetLog.append(message)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let dailyResetCompleted = Notification.Name("dailyResetCompleted")
}

// MARK: - NotificationManager Extension

extension NotificationManager {
    var weightRemindersEnabled: Bool {
        // Check if weight reminders are enabled
        return isNotificationEnabled(.weightReminder)
    }
}

// MARK: - HealthKitService Extension

extension HealthKitService {
    /// Get step count for a specific date
    func getStepCount(for date: Date) async -> Int {
        // This should query HealthKit for step count
        // For now return 0 if the method doesn't exist
        // The actual implementation depends on existing HealthKit setup
        
        guard let stepCount = await fetchStepCountForDate(date) else {
            return 0
        }
        return stepCount
    }
    
    private func fetchStepCountForDate(_ date: Date) async -> Int? {
        // This is a placeholder - the actual implementation
        // would use the existing HealthKit infrastructure
        return nil
    }
}
