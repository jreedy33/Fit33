import Foundation
import UserNotifications
import SwiftUI

// MARK: - Notification Types
enum NotificationType: String, CaseIterable, Identifiable {
    // Workout Related
    case dailyWorkoutReminder = "daily_workout_reminder"
    case streakProtection = "streak_protection"
    case workoutComplete = "workout_complete"
    case comebackReminder = "comeback_reminder"
    
    // Social / Friends
    case sharedWorkout = "shared_workout"
    case friendRequest = "friend_request"
    
    // Progress & Achievements
    case personalRecord = "personal_record"
    case streakMilestone = "streak_milestone"
    case levelUp = "level_up"
    case goalAchieved = "goal_achieved"
    
    // Health & Nutrition
    case nutritionReminder = "nutrition_reminder"
    case proteinGoal = "protein_goal"
    case stepsGoal = "steps_goal"
    case waterReminder = "water_reminder"
    
    // Motivation
    case morningMotivation = "morning_motivation"
    case weeklyProgress = "weekly_progress"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .dailyWorkoutReminder: return "Daily Workout Reminder"
        case .streakProtection: return "Streak Protection Alert"
        case .workoutComplete: return "Workout Completion"
        case .comebackReminder: return "Comeback Motivation"
        case .sharedWorkout: return "Shared Workouts"
        case .friendRequest: return "Friend Requests"
        case .personalRecord: return "Personal Records"
        case .streakMilestone: return "Streak Celebrations"
        case .levelUp: return "Level Up Alerts"
        case .goalAchieved: return "Goal Achievements"
        case .nutritionReminder: return "Meal Logging Reminders"
        case .proteinGoal: return "Protein Target Alerts"
        case .stepsGoal: return "Steps Goal Updates"
        case .waterReminder: return "Hydration Reminders"
        case .morningMotivation: return "Morning Motivation"
        case .weeklyProgress: return "Weekly Summary"
        }
    }
    
    var description: String {
        switch self {
        case .dailyWorkoutReminder: return "Remind you to complete your workout"
        case .streakProtection: return "Alert when your streak is at risk"
        case .workoutComplete: return "Celebrate when you finish a workout"
        case .comebackReminder: return "Motivate you to return after time away"
        case .sharedWorkout: return "Notify when friends send you workouts"
        case .friendRequest: return "Notify when you receive friend requests"
        case .personalRecord: return "Celebrate when you beat your best"
        case .streakMilestone: return "Celebrate streak milestones"
        case .levelUp: return "Notify when you level up"
        case .goalAchieved: return "Alert when you hit your goals"
        case .nutritionReminder: return "Remind you to log your meals"
        case .proteinGoal: return "Alert when protein is running low"
        case .stepsGoal: return "Update on daily steps progress"
        case .waterReminder: return "Remind you to stay hydrated"
        case .morningMotivation: return "Start your day with motivation"
        case .weeklyProgress: return "Weekly fitness summary"
        }
    }
    
    var icon: String {
        switch self {
        case .dailyWorkoutReminder: return "clock.fill"
        case .streakProtection: return "flame.fill"
        case .workoutComplete: return "checkmark.circle.fill"
        case .comebackReminder: return "arrow.counterclockwise"
        case .sharedWorkout: return "paperplane.fill"
        case .friendRequest: return "person.badge.plus"
        case .personalRecord: return "trophy.fill"
        case .streakMilestone: return "flame.fill"
        case .levelUp: return "star.fill"
        case .goalAchieved: return "target"
        case .nutritionReminder: return "fork.knife"
        case .proteinGoal: return "leaf.fill"
        case .stepsGoal: return "figure.walk"
        case .waterReminder: return "drop.fill"
        case .morningMotivation: return "sun.max.fill"
        case .weeklyProgress: return "chart.bar.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .dailyWorkoutReminder: return .blue
        case .streakProtection: return .orange
        case .workoutComplete: return .green
        case .comebackReminder: return .purple
        case .sharedWorkout: return .blue
        case .friendRequest: return .green
        case .personalRecord: return .yellow
        case .streakMilestone: return .orange
        case .levelUp: return .purple
        case .goalAchieved: return .green
        case .nutritionReminder: return .pink
        case .proteinGoal: return .red
        case .stepsGoal: return .green
        case .waterReminder: return .cyan
        case .morningMotivation: return .yellow
        case .weeklyProgress: return .indigo
        }
    }
    
    var defaultEnabled: Bool {
        switch self {
        // HIGH RETENTION NOTIFICATIONS - Default ON for maximum engagement
        case .dailyWorkoutReminder,    // Core engagement - remind to work out
             .streakProtection,        // Prevent churn by protecting streaks
             .workoutComplete,         // Celebrate wins - positive reinforcement
             .comebackReminder,        // Re-engage dormant users
             .sharedWorkout,           // Social engagement - friends sending workouts
             .friendRequest,           // Social engagement - new friends
             .personalRecord,          // Celebrate achievements
             .streakMilestone,         // Celebrate consistency
             .levelUp,                 // Gamification engagement
             .goalAchieved,            // Progress celebration
             .nutritionReminder,       // Full app engagement
             .morningMotivation,       // Daily engagement touchpoint
             .weeklyProgress:          // Weekly recap keeps users invested
            return true
        // OPTIONAL NOTIFICATIONS - Default OFF to avoid notification fatigue
        case .proteinGoal,             // Can feel nagging
             .stepsGoal,               // Better handled by Apple Health
             .waterReminder:           // Very frequent, opt-in only
            return false
        }
    }
}

// MARK: - Notification Categories
enum NotificationCategory: String, CaseIterable, Identifiable {
    case workout = "Workouts"
    case social = "Social"
    case achievements = "Achievements"
    case health = "Health & Nutrition"
    case motivation = "Motivation"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .workout: return "dumbbell.fill"
        case .social: return "person.2.fill"
        case .achievements: return "trophy.fill"
        case .health: return "heart.fill"
        case .motivation: return "sparkles"
        }
    }
    
    var color: Color {
        switch self {
        case .workout: return .blue
        case .social: return .green
        case .achievements: return .yellow
        case .health: return .pink
        case .motivation: return .purple
        }
    }
    
    var notifications: [NotificationType] {
        switch self {
        case .workout:
            return [.dailyWorkoutReminder, .streakProtection, .workoutComplete, .comebackReminder]
        case .social:
            return [.sharedWorkout, .friendRequest]
        case .achievements:
            return [.personalRecord, .streakMilestone, .levelUp, .goalAchieved]
        case .health:
            return [.nutritionReminder, .proteinGoal, .stepsGoal, .waterReminder]
        case .motivation:
            return [.morningMotivation, .weeklyProgress]
        }
    }
}

// MARK: - Notification Manager
@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    @Published var isAuthorized = false
    @Published var masterNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(masterNotificationsEnabled, forKey: "master_notifications_enabled")
            if masterNotificationsEnabled {
                scheduleAllNotifications()
            } else {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
        }
    }
    
    @Published var dailyReminderTime: Date {
        didSet {
            UserDefaults.standard.set(dailyReminderTime, forKey: "daily_reminder_time")
            rescheduleWorkoutReminder()
        }
    }
    
    @Published var quietHoursEnabled: Bool {
        didSet { UserDefaults.standard.set(quietHoursEnabled, forKey: "quiet_hours_enabled") }
    }
    
    @Published var quietHoursStart: Date {
        didSet { UserDefaults.standard.set(quietHoursStart, forKey: "quiet_hours_start") }
    }
    
    @Published var quietHoursEnd: Date {
        didSet { UserDefaults.standard.set(quietHoursEnd, forKey: "quiet_hours_end") }
    }
    
    // MARK: - Private Properties
    private var enabledNotifications: Set<String> = []
    
    // MARK: - Initialization
    private override init() {
        // Set default values first
        let defaultTime: Date = {
            var components = DateComponents()
            components.hour = 17
            components.minute = 0
            return Calendar.current.date(from: components) ?? Date()
        }()
        
        let defaultQuietStart: Date = {
            var components = DateComponents()
            components.hour = 22
            components.minute = 0
            return Calendar.current.date(from: components) ?? Date()
        }()
        
        let defaultQuietEnd: Date = {
            var components = DateComponents()
            components.hour = 7
            components.minute = 0
            return Calendar.current.date(from: components) ?? Date()
        }()
        
        // Initialize stored properties
        _masterNotificationsEnabled = Published(initialValue: UserDefaults.standard.object(forKey: "master_notifications_enabled") as? Bool ?? true)
        _dailyReminderTime = Published(initialValue: UserDefaults.standard.object(forKey: "daily_reminder_time") as? Date ?? defaultTime)
        _quietHoursEnabled = Published(initialValue: UserDefaults.standard.bool(forKey: "quiet_hours_enabled"))
        _quietHoursStart = Published(initialValue: UserDefaults.standard.object(forKey: "quiet_hours_start") as? Date ?? defaultQuietStart)
        _quietHoursEnd = Published(initialValue: UserDefaults.standard.object(forKey: "quiet_hours_end") as? Date ?? defaultQuietEnd)
        
        // Load enabled notifications (set defaults on first launch)
        if let saved = UserDefaults.standard.array(forKey: "enabled_notifications") as? [String] {
            enabledNotifications = Set(saved)
        } else {
            // First launch: enable defaults
            enabledNotifications = Set(NotificationType.allCases.filter { $0.defaultEnabled }.map { $0.rawValue })
        }
        
        super.init()
        
        // Save defaults if first launch
        if UserDefaults.standard.array(forKey: "enabled_notifications") == nil {
            saveEnabledNotifications()
        }
        
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            
            await MainActor.run {
                self.isAuthorized = granted
            }
            
            if granted {
                setupNotificationCategories()
                scheduleAllNotifications()
                print("✅ [NOTIFICATIONS] Authorization granted")
            }
            
            return granted
        } catch {
            print("❌ [NOTIFICATIONS] Authorization error: \(error)")
            return false
        }
    }
    
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Notification Toggle
    func isNotificationEnabled(_ type: NotificationType) -> Bool {
        enabledNotifications.contains(type.rawValue)
    }
    
    func toggleNotification(_ type: NotificationType, enabled: Bool) {
        if enabled {
            enabledNotifications.insert(type.rawValue)
        } else {
            enabledNotifications.remove(type.rawValue)
        }
        saveEnabledNotifications()
        
        // Reschedule affected notifications
        switch type {
        case .dailyWorkoutReminder:
            rescheduleWorkoutReminder()
        case .nutritionReminder:
            rescheduleNutritionReminders()
        case .streakProtection:
            rescheduleStreakProtection()
        default:
            break
        }
    }
    
    private func saveEnabledNotifications() {
        UserDefaults.standard.set(Array(enabledNotifications), forKey: "enabled_notifications")
    }
    
    /// Enable all high-value notifications for new users
    /// Called during onboarding to maximize engagement
    func enableAllDefaultNotifications() {
        enabledNotifications = Set(NotificationType.allCases.filter { $0.defaultEnabled }.map { $0.rawValue })
        saveEnabledNotifications()
        print("📬 [NOTIFICATIONS] Enabled all default notifications: \(enabledNotifications.count) types")
    }
    
    /// Check if this is a returning user who previously had notifications enabled
    /// but iOS permissions got reset (app reinstall, etc)
    func checkAndPromptIfNeeded() async -> Bool {
        // If user had notifications enabled before but iOS permissions are now denied
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let hadNotificationsEnabled = UserDefaults.standard.bool(forKey: "master_notifications_enabled")
        
        if hadNotificationsEnabled && settings.authorizationStatus == .denied {
            // User wanted notifications but they're now blocked
            return true // Should prompt to enable in Settings
        }
        
        return false
    }
    
    // MARK: - Setup Categories
    private func setupNotificationCategories() {
        let startWorkoutAction = UNNotificationAction(
            identifier: "START_WORKOUT",
            title: "Start Workout",
            options: [.foreground]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_1H",
            title: "Remind in 1 Hour",
            options: []
        )
        
        let workoutCategory = UNNotificationCategory(
            identifier: "WORKOUT_REMINDER",
            actions: [startWorkoutAction, snoozeAction],
            intentIdentifiers: []
        )
        
        let logFoodAction = UNNotificationAction(
            identifier: "LOG_FOOD",
            title: "Log Food",
            options: [.foreground]
        )
        
        let nutritionCategory = UNNotificationCategory(
            identifier: "NUTRITION_REMINDER",
            actions: [logFoodAction],
            intentIdentifiers: []
        )
        
        // Shared workout category - tap to view the workout
        let viewWorkoutAction = UNNotificationAction(
            identifier: "VIEW_SHARED_WORKOUT",
            title: "View Workout",
            options: [.foreground]
        )
        
        let sharedWorkoutCategory = UNNotificationCategory(
            identifier: "SHARED_WORKOUT",
            actions: [viewWorkoutAction],
            intentIdentifiers: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            workoutCategory,
            nutritionCategory,
            sharedWorkoutCategory
        ])
    }
    
    // MARK: - Schedule All Notifications
    func scheduleAllNotifications() {
        guard masterNotificationsEnabled && isAuthorized else { return }
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        if isNotificationEnabled(.dailyWorkoutReminder) {
            scheduleWorkoutReminder()
        }
        
        if isNotificationEnabled(.nutritionReminder) {
            scheduleNutritionReminders()
        }
        
        if isNotificationEnabled(.streakProtection) {
            scheduleStreakProtection()
        }
        
        if isNotificationEnabled(.morningMotivation) {
            scheduleMorningMotivation()
        }
        
        print("📅 [NOTIFICATIONS] Scheduled all notifications")
    }
    
    // MARK: - Workout Reminder
    private func scheduleWorkoutReminder() {
        guard isNotificationEnabled(.dailyWorkoutReminder) else { return }
        
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "WORKOUT_REMINDER"
        content.sound = .default
        
        let messages = [
            ("Time to crush it! 💪", "Your workout is waiting. Let's make today count!"),
            ("Ready to sweat?", "A quick workout now = feeling amazing later."),
            ("Don't break the chain! 🔥", "Keep your momentum going with today's workout."),
            ("Your future self will thank you", "Just 30 minutes can change your day."),
            ("Fit33 check-in", "Have you moved your body today? Let's go!")
        ]
        
        let message = messages.randomElement()!
        content.title = message.0
        content.body = message.1
        
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.hour, .minute], from: dailyReminderTime)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: NotificationType.dailyWorkoutReminder.rawValue,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func rescheduleWorkoutReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationType.dailyWorkoutReminder.rawValue]
        )
        if isNotificationEnabled(.dailyWorkoutReminder) {
            scheduleWorkoutReminder()
        }
    }
    
    // MARK: - Nutrition Reminders
    private func scheduleNutritionReminders() {
        guard isNotificationEnabled(.nutritionReminder) else { return }
        
        // Lunch reminder at 1 PM
        scheduleNutritionReminder(
            identifier: "lunch_reminder",
            hour: 13,
            title: "Log your lunch 🥗",
            body: "Don't forget to track what you ate!"
        )
        
        // Dinner reminder at 7 PM
        scheduleNutritionReminder(
            identifier: "dinner_reminder",
            hour: 19,
            title: "How was dinner?",
            body: "Log your evening meal to stay on track."
        )
    }
    
    private func scheduleNutritionReminder(identifier: String, hour: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = "NUTRITION_REMINDER"
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func rescheduleNutritionReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["lunch_reminder", "dinner_reminder"]
        )
        if isNotificationEnabled(.nutritionReminder) {
            scheduleNutritionReminders()
        }
    }
    
    // MARK: - Streak Protection
    private func scheduleStreakProtection() {
        guard isNotificationEnabled(.streakProtection) else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Protect your streak! 🔥"
        content.body = "You haven't worked out today. Quick workout to keep your streak alive!"
        content.categoryIdentifier = "WORKOUT_REMINDER"
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: NotificationType.streakProtection.rawValue,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func rescheduleStreakProtection() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationType.streakProtection.rawValue]
        )
        if isNotificationEnabled(.streakProtection) {
            scheduleStreakProtection()
        }
    }
    
    // MARK: - Morning Motivation
    private func scheduleMorningMotivation() {
        guard isNotificationEnabled(.morningMotivation) else { return }
        
        let messages = [
            ("Good morning champion! ☀️", "Today is another chance to be better than yesterday."),
            ("Rise and grind!", "Your goals are waiting. Let's make it happen."),
            ("New day, new gains 💪", "What will you accomplish today?"),
            ("Wake up and crush it!", "Every rep brings you closer to your goals.")
        ]
        
        let message = messages.randomElement()!
        
        let content = UNMutableNotificationContent()
        content.title = message.0
        content.body = message.1
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = 8
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: NotificationType.morningMotivation.rawValue,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Instant Notifications
    
    /// Celebrate streak milestones
    func sendStreakCelebration(streakCount: Int) {
        guard isNotificationEnabled(.streakMilestone) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        switch streakCount {
        case 7:
            content.title = "1 Week Strong! 🔥"
            content.body = "7 days in a row! You're building a real habit."
        case 14:
            content.title = "2 Weeks Unstoppable! 💪"
            content.body = "14 days of dedication. Keep it up!"
        case 21:
            content.title = "21 Days - Habit Formed! 🏆"
            content.body = "They say 21 days makes a habit. You did it!"
        case 30:
            content.title = "30 Day Warrior! ⚔️"
            content.body = "A full month of crushing it!"
        case 100:
            content.title = "TRIPLE DIGITS! 💯"
            content.body = "100 days straight. You're legendary!"
        case 365:
            content.title = "ONE YEAR! 🎊"
            content.body = "365 days of dedication. Absolutely incredible!"
        default:
            content.title = "\(streakCount) Day Streak! 🔥"
            content.body = "You're on fire! Keep the streak alive!"
        }
        
        sendImmediateNotification(content: content, identifier: "streak_\(streakCount)")
    }
    
    /// Send comeback reminder after days away
    func sendComebackReminder(daysAway: Int) {
        guard isNotificationEnabled(.comebackReminder) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "We miss you! 💙"
        content.body = "It's been \(daysAway) days. A quick workout can get you back on track!"
        content.sound = .default
        
        sendImmediateNotification(content: content, identifier: "comeback_\(daysAway)")
    }
    
    /// Celebrate personal record
    func sendPersonalRecordNotification(exercise: String, weight: Int, previousBest: Int) {
        guard isNotificationEnabled(.personalRecord) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "NEW PERSONAL RECORD! 🏆"
        content.body = "\(exercise): \(weight) lbs! You beat your previous best of \(previousBest) lbs!"
        content.sound = .default
        
        sendImmediateNotification(content: content, identifier: "pr_\(Date().timeIntervalSince1970)")
    }
    
    /// Level up notification
    func sendLevelUpNotification(newLevel: Int, title: String) {
        guard isNotificationEnabled(.levelUp) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "LEVEL UP! ⬆️"
        content.body = "You've reached Level \(newLevel): \(title)!"
        content.sound = .default
        
        sendImmediateNotification(content: content, identifier: "levelup_\(newLevel)")
    }
    
    /// Steps goal achieved
    func sendStepsGoalAchieved(steps: Int) {
        guard isNotificationEnabled(.stepsGoal) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Steps Goal Crushed! 👟"
        content.body = "You hit \(steps.formatted()) steps today! Keep moving!"
        content.sound = .default
        
        sendImmediateNotification(content: content, identifier: "steps_\(Date().timeIntervalSince1970)")
    }
    
    /// Protein reminder
    func sendProteinReminder(currentProtein: Double, targetProtein: Double) {
        guard isNotificationEnabled(.proteinGoal) && isAuthorized else { return }
        
        let remaining = Int(targetProtein - currentProtein)
        guard remaining > 20 else { return } // Only remind if significantly under
        
        let content = UNMutableNotificationContent()
        content.title = "Protein Check-in 🥩"
        content.body = "You need \(remaining)g more protein today. Time for a protein-rich snack!"
        content.sound = .default
        
        sendImmediateNotification(content: content, identifier: "protein_\(Date().timeIntervalSince1970)")
    }
    
    /// Goal progress notification
    func sendGoalProgressNotification(percentage: Int, goalType: String) {
        guard isNotificationEnabled(.goalAchieved) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        
        if percentage >= 100 {
            content.title = "Goal Achieved! 🎯"
            content.body = "You crushed your \(goalType) goal today!"
        } else {
            content.title = "Almost There! 🎯"
            content.body = "You're \(percentage)% to your \(goalType) goal. Keep pushing!"
        }
        content.sound = .default
        
        sendImmediateNotification(content: content, identifier: "goal_\(Date().timeIntervalSince1970)")
    }
    
    /// Shared workout notification - when a friend sends you a workout
    func sendSharedWorkoutNotification(senderName: String, workoutName: String, workoutId: String) {
        guard isNotificationEnabled(.sharedWorkout) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(senderName) sent you a workout! 💪"
        content.body = "Tap to check out \"\(workoutName)\" and start training."
        content.sound = .default
        content.categoryIdentifier = "SHARED_WORKOUT"
        
        // Store workout ID in userInfo for deep linking
        content.userInfo = [
            "type": "shared_workout",
            "workout_id": workoutId,
            "sender_name": senderName
        ]
        
        sendImmediateNotification(content: content, identifier: "shared_workout_\(workoutId)")
    }
    
    /// Friend request notification
    func sendFriendRequestNotification(fromName: String, requestId: String) {
        guard isNotificationEnabled(.friendRequest) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "New Friend Request! 👋"
        content.body = "\(fromName) wants to be your workout buddy."
        content.sound = .default
        
        content.userInfo = [
            "type": "friend_request",
            "request_id": requestId,
            "sender_name": fromName
        ]
        
        sendImmediateNotification(content: content, identifier: "friend_request_\(requestId)")
    }
    
    /// Workout completed - cancel today's reminders
    func workoutCompleted() {
        // Cancel today's workout reminders since they did it
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                NotificationType.dailyWorkoutReminder.rawValue,
                NotificationType.streakProtection.rawValue
            ]
        )
        
        // Record workout date
        UserDefaults.standard.set(Date(), forKey: "last_workout_date")
        
        print("✅ [NOTIFICATIONS] Workout completed - cancelled today's reminders")
    }
    
    /// Food logged - update reminder state
    func foodLogged() {
        UserDefaults.standard.set(Date(), forKey: "last_food_log_date")
        
        // Cancel meal reminders for past meals
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 14 {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["lunch_reminder"]
            )
        }
        if hour >= 20 {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["dinner_reminder"]
            )
        }
    }
    
    // MARK: - Smart Check (call on app foreground)
    func performSmartCheck() {
        guard masterNotificationsEnabled && isAuthorized else { return }
        
        // Check if user already worked out today
        if let lastWorkout = UserDefaults.standard.object(forKey: "last_workout_date") as? Date {
            if Calendar.current.isDateInToday(lastWorkout) {
                // Already worked out - cancel reminders
                UNUserNotificationCenter.current().removePendingNotificationRequests(
                    withIdentifiers: [
                        NotificationType.dailyWorkoutReminder.rawValue,
                        NotificationType.streakProtection.rawValue
                    ]
                )
            }
        }
        
        // Check for comeback reminder
        if let lastWorkout = UserDefaults.standard.object(forKey: "last_workout_date") as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: lastWorkout, to: Date()).day ?? 0
            if daysSince >= 3 && daysSince <= 7 {
                sendComebackReminder(daysAway: daysSince)
            }
        }
    }
    
    // MARK: - Helper
    private func sendImmediateNotification(content: UNMutableNotificationContent, identifier: String) {
        // Check quiet hours
        if quietHoursEnabled && isInQuietHours() {
            print("🌙 [NOTIFICATIONS] Skipped - quiet hours active")
            return
        }
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [NOTIFICATIONS] Failed to send: \(error)")
            }
        }
    }
    
    private func isInQuietHours() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let startMinutes = calendar.component(.hour, from: quietHoursStart) * 60 + calendar.component(.minute, from: quietHoursStart)
        let endMinutes = calendar.component(.hour, from: quietHoursEnd) * 60 + calendar.component(.minute, from: quietHoursEnd)
        
        if startMinutes < endMinutes {
            // Normal range (e.g., 22:00 to 23:00)
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            // Overnight range (e.g., 22:00 to 07:00)
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification action (when user taps notification)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let userInfo = response.notification.request.content.userInfo
        
        Task { @MainActor in
            switch actionIdentifier {
            case "START_WORKOUT":
                // Deep link to workout tab
                DeepLinkManager.shared.pendingDestination = .workout
                print("🏋️ [NOTIFICATIONS] User tapped Start Workout")
                
            case "LOG_FOOD":
                // Deep link to nutrition (if implemented)
                print("🍎 [NOTIFICATIONS] User tapped Log Food")
                
            case "SNOOZE_1H":
                // Reschedule notification for 1 hour later
                self.snoozeNotification(categoryIdentifier: categoryIdentifier, hours: 1)
                print("⏰ [NOTIFICATIONS] Snoozed for 1 hour")
                
            case "VIEW_SHARED_WORKOUT", UNNotificationDefaultActionIdentifier:
                // Handle shared workout notifications
                if let notificationType = userInfo["type"] as? String {
                    if notificationType == "shared_workout", let workoutId = userInfo["workout_id"] as? String {
                        // Navigate to received workout preview
                        DeepLinkManager.shared.pendingDestination = .receivedWorkout(workoutId: workoutId)
                        print("📬 [NOTIFICATIONS] Opening received workout: \(workoutId)")
                    } else if notificationType == "friend_request" {
                        // Navigate to friends list
                        DeepLinkManager.shared.pendingDestination = .friends
                        print("👥 [NOTIFICATIONS] Opening friends list")
                    } else {
                        print("📱 [NOTIFICATIONS] User opened notification: \(categoryIdentifier)")
                    }
                } else {
                    print("📱 [NOTIFICATIONS] User opened notification: \(categoryIdentifier)")
                }
                
            default:
                break
            }
        }
        
        completionHandler()
    }
    
    private func snoozeNotification(categoryIdentifier: String, hours: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Reminder ⏰"
        content.body = "Don't forget about your workout!"
        content.categoryIdentifier = categoryIdentifier
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(hours * 3600),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "snooze_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}
