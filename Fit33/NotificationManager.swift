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
    case contactJoined = "contact_joined"
    case challengeInvite = "challenge_invite"
    case groupChallengeInvite = "group_challenge_invite"
    case challengeUpdate = "challenge_update"
    case challengeProgress = "challenge_progress"
    case challengeCancelled = "challenge_cancelled"
    
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
    case weightReminder = "weight_reminder"
    
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
        case .contactJoined: return "Contact Joined"
        case .challengeInvite: return "Challenge Invites"
        case .groupChallengeInvite: return "Group Challenge Invites"
        case .challengeUpdate: return "Challenge Updates"
        case .challengeProgress: return "Challenge Progress"
        case .challengeCancelled: return "Challenge Cancelled"
        case .personalRecord: return "Personal Records"
        case .streakMilestone: return "Streak Celebrations"
        case .levelUp: return "Level Up Alerts"
        case .goalAchieved: return "Goal Achievements"
        case .nutritionReminder: return "Meal Logging Reminders"
        case .proteinGoal: return "Protein Target Alerts"
        case .stepsGoal: return "Steps Goal Updates"
        case .waterReminder: return "Hydration Reminders"
        case .weightReminder: return "Weight Tracking Reminders"
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
        case .contactJoined: return "Notify when your contacts join Fit33"
        case .challengeInvite: return "Notify when friends challenge you"
        case .groupChallengeInvite: return "Notify when friends invite you to group challenges"
        case .challengeUpdate: return "Updates on your active challenges"
        case .challengeProgress: return "Notify when opponent completes their daily goal"
        case .challengeCancelled: return "Notify when a challenge is cancelled"
        case .personalRecord: return "Celebrate when you beat your best"
        case .streakMilestone: return "Celebrate streak milestones"
        case .levelUp: return "Notify when you level up"
        case .goalAchieved: return "Alert when you hit your goals"
        case .nutritionReminder: return "Remind you to log your meals"
        case .proteinGoal: return "Alert when protein is running low"
        case .stepsGoal: return "Update on daily steps progress"
        case .waterReminder: return "Remind you to stay hydrated"
        case .weightReminder: return "Remind you to log today's weight"
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
        case .contactJoined: return "person.crop.circle.badge.checkmark"
        case .challengeInvite: return "trophy.fill"
        case .groupChallengeInvite: return "trophy.fill"
        case .challengeUpdate: return "chart.line.uptrend.xyaxis"
        case .challengeProgress: return "flame.fill"
        case .challengeCancelled: return "xmark.circle.fill"
        case .personalRecord: return "trophy.fill"
        case .streakMilestone: return "flame.fill"
        case .levelUp: return "star.fill"
        case .goalAchieved: return "target"
        case .nutritionReminder: return "fork.knife"
        case .proteinGoal: return "leaf.fill"
        case .stepsGoal: return "figure.walk"
        case .waterReminder: return "drop.fill"
        case .weightReminder: return "scalemass.fill"
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
        case .contactJoined: return .purple
        case .challengeInvite: return .orange
        case .groupChallengeInvite: return .orange
        case .challengeUpdate: return .purple
        case .challengeProgress: return .blue
        case .challengeCancelled: return .red
        case .personalRecord: return .yellow
        case .streakMilestone: return .orange
        case .levelUp: return .purple
        case .goalAchieved: return .green
        case .nutritionReminder: return .pink
        case .proteinGoal: return .red
        case .stepsGoal: return .green
        case .waterReminder: return .cyan
        case .weightReminder: return .purple
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
             .contactJoined,           // Social engagement - contacts joining app
             .challengeInvite,         // Social engagement - friend challenges
             .groupChallengeInvite,    // Social engagement - group challenge invites
             .challengeUpdate,         // Keep users engaged with active challenges
             .challengeProgress,       // Notify when opponent completes daily goal
             .challengeCancelled,      // Important to know when challenge ends
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
             .waterReminder,           // Very frequent, opt-in only
             .weightReminder:          // Daily weight check, opt-in
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
            return [.sharedWorkout, .friendRequest, .challengeInvite, .groupChallengeInvite, .challengeUpdate]
        case .achievements:
            return [.personalRecord, .streakMilestone, .levelUp, .goalAchieved]
        case .health:
            return [.nutritionReminder, .proteinGoal, .stepsGoal, .waterReminder, .weightReminder]
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
    @Published var hasCheckedAuthStatus = false  // Track when we've actually checked
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
                self.hasCheckedAuthStatus = true
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
        
        // Challenge invite category
        let viewChallengeAction = UNNotificationAction(
            identifier: "VIEW_CHALLENGE",
            title: "View Challenge",
            options: [.foreground]
        )
        
        let acceptChallengeAction = UNNotificationAction(
            identifier: "ACCEPT_CHALLENGE",
            title: "Accept",
            options: [.foreground]
        )
        
        let challengeInviteCategory = UNNotificationCategory(
            identifier: "CHALLENGE_INVITE",
            actions: [acceptChallengeAction, viewChallengeAction],
            intentIdentifiers: []
        )
        
        // Contact joined category - add as friend action
        let addFriendAction = UNNotificationAction(
            identifier: "ADD_FRIEND",
            title: "Add Friend",
            options: [.foreground]
        )
        
        let contactJoinedCategory = UNNotificationCategory(
            identifier: "CONTACT_JOINED",
            actions: [addFriendAction],
            intentIdentifiers: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            workoutCategory,
            nutritionCategory,
            sharedWorkoutCategory,
            challengeInviteCategory,
            contactJoinedCategory
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
    
    /// Friend request accepted notification - when someone accepts your request
    func sendFriendRequestAcceptedNotification(accepterName: String, friendId: String) {
        guard isNotificationEnabled(.friendRequest) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(accepterName) accepted your request! 🎉"
        content.body = "You're now workout buddies. Start training together!"
        content.sound = .default
        
        content.userInfo = [
            "type": "friend_request_accepted",
            "friend_id": friendId,
            "accepter_name": accepterName
        ]
        
        sendImmediateNotification(content: content, identifier: "friend_accepted_\(friendId)")
    }
    
    /// Challenge invite notification - when a friend challenges you
    func sendChallengeInviteNotification(fromName: String, challengeTitle: String, challengeId: String) {
        guard isNotificationEnabled(.challengeInvite) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(fromName) wants to challenge you! 🏆"
        content.body = "Accept the \"\(challengeTitle)\" challenge and prove yourself!"
        content.sound = .default
        content.categoryIdentifier = "CHALLENGE_INVITE"
        
        content.userInfo = [
            "type": "challenge_invite",
            "challenge_id": challengeId,
            "sender_name": fromName
        ]
        
        sendImmediateNotification(content: content, identifier: "challenge_invite_\(challengeId)")
    }
    
    /// Challenge accepted notification - when opponent accepts your challenge
    func sendChallengeAcceptedNotification(opponentName: String, challengeTitle: String, challengeId: String) {
        guard isNotificationEnabled(.challengeUpdate) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Challenge Accepted! ⚔️"
        content.body = "\(opponentName) accepted your \"\(challengeTitle)\" challenge. Game on!"
        content.sound = .default
        
        content.userInfo = [
            "type": "challenge_accepted",
            "challenge_id": challengeId,
            "opponent_name": opponentName
        ]
        
        sendImmediateNotification(content: content, identifier: "challenge_accepted_\(challengeId)")
    }
    
    /// Challenge progress notification - when opponent logs progress
    func sendChallengeProgressNotification(opponentName: String, challengeTitle: String, isOpponentAhead: Bool) {
        guard isNotificationEnabled(.challengeUpdate) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        
        if isOpponentAhead {
            content.title = "\(opponentName) is pulling ahead! 😤"
            content.body = "Don't let them win the \"\(challengeTitle)\" challenge!"
        } else {
            content.title = "You're in the lead! 💪"
            content.body = "Keep it up in the \"\(challengeTitle)\" challenge!"
        }
        content.sound = .default
        
        content.userInfo = [
            "type": "challenge_progress",
            "opponent_name": opponentName
        ]
        
        sendImmediateNotification(content: content, identifier: "challenge_progress_\(Date().timeIntervalSince1970)")
    }
    
    /// Challenge completed notification - when a challenge ends
    func sendChallengeCompletedNotification(challengeTitle: String, didWin: Bool, challengeId: String) {
        guard isNotificationEnabled(.challengeUpdate) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        
        if didWin {
            content.title = "You Won! 🏆"
            content.body = "Congratulations! You crushed the \"\(challengeTitle)\" challenge!"
        } else {
            content.title = "Challenge Complete"
            content.body = "The \"\(challengeTitle)\" challenge has ended. Ready for a rematch?"
        }
        content.sound = .default
        
        content.userInfo = [
            "type": "challenge_completed",
            "challenge_id": challengeId,
            "did_win": didWin
        ]
        
        sendImmediateNotification(content: content, identifier: "challenge_completed_\(challengeId)")
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
        let userInfo = notification.request.content.userInfo
        
        // Process notification even when in foreground to refresh data
        Task { @MainActor in
            if let notificationType = userInfo["type"] as? String {
                SessionLogManager.shared.log(.info, category: .pushNotification, message: "📨 Push received (foreground)", metadata: [
                    "type": notificationType,
                    "title": notification.request.content.title
                ])
                print("🔔 [NOTIFICATIONS] Received \(notificationType) while app in foreground - refreshing data")
                
                switch notificationType {
                case "challenge_accepted", "challenge_declined", "challenge_cancelled":
                    print("🔄 [SENDER FLOW] Step 1: Received \(notificationType) - starting refresh")
                    await ChallengeService.shared.fetchPendingSentChallenges()
                    await ChallengeService.shared.fetchPendingInvites()
                    await ChallengeService.shared.fetchActiveGroupChallenges()
                    
                    // Fetch active immediately to show the challenge widget (even with 0 progress)
                    print("🔄 [SENDER FLOW] Step 2: Initial fetch of active challenges...")
                    await ChallengeService.shared.fetchActiveChallenges()
                    let initialChallenge = ChallengeService.shared.activeChallenges.first
                    print("📊 [SENDER FLOW] Step 2 result: myToday=\(initialChallenge?.myTodayProgress ?? -1), oppToday=\(initialChallenge?.opponentTodayProgress ?? -1)")
                    
                    // Sync OUR HealthKit data to any newly active challenges FIRST
                    print("🔄 [SENDER FLOW] Step 3: Syncing OUR HealthKit data...")
                    await ChallengeService.shared.syncHealthKitDataToChallenges()
                    
                    // Wait for accepter's progress sync to finish writing to DB
                    print("⏳ [SENDER FLOW] Step 4: Waiting 2s for accepter's sync to complete...")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    
                    // Final fetch - should now have BOTH users' progress
                    print("🔄 [SENDER FLOW] Step 5: Final fetch with both users' progress...")
                    await ChallengeService.shared.fetchActiveChallenges()
                    let finalChallenge = ChallengeService.shared.activeChallenges.first
                    print("📊 [SENDER FLOW] Step 5 result: myToday=\(finalChallenge?.myTodayProgress ?? -1), oppToday=\(finalChallenge?.opponentTodayProgress ?? -1)")
                    print("✅ [SENDER FLOW] Complete - widget should show real-time progress")
                    
                case "challenge_invite":
                    await ChallengeService.shared.fetchPendingInvites()
                    
                case "group_challenge_invite":
                    print("🔄 [NOTIFICATIONS] Group challenge invite received - refreshing group challenges")
                    await ChallengeService.shared.fetchActiveGroupChallenges()
                    
                case "group_challenge_started":
                    print("🔄 [NOTIFICATIONS] Group challenge started - refreshing and syncing progress")
                    await ChallengeService.shared.fetchActiveGroupChallenges()
                    await ChallengeService.shared.fetchActiveChallenges()
                    // Sync existing health data to the newly started challenge
                    await ChallengeService.shared.syncHealthKitDataToGroupChallenges()
                    print("✅ [NOTIFICATIONS] Group challenges refreshed + progress synced")
                    
                case "friend_request", "friend_request_received":
                    await FriendService.shared.fetchPendingRequests()
                    
                case "friend_request_accepted", "friend_accepted":
                    await FriendService.shared.fetchFriends()
                    
                case "shared_workout":
                    await FriendService.shared.loadReceivedWorkouts()
                    
                default:
                    break
                }
            }
        }
        
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
                // Deep link to meals tab
                DeepLinkManager.shared.pendingDestination = .mealsTab
                print("🍎 [NOTIFICATIONS] User tapped Log Food - navigating to meals")
                
            case "ADD_FRIEND":
                // Navigate to friend suggestions/requests when "Add Friend" tapped
                DeepLinkManager.shared.pendingDestination = .friendRequests
                print("👥 [NOTIFICATIONS] User tapped Add Friend from contact joined notification")
                
            case "SNOOZE_1H":
                // Reschedule notification for 1 hour later
                self.snoozeNotification(categoryIdentifier: categoryIdentifier, hours: 1)
                print("⏰ [NOTIFICATIONS] Snoozed for 1 hour")
                
            case "VIEW_SHARED_WORKOUT", UNNotificationDefaultActionIdentifier:
                // Handle notification tap based on type or category
                // First check userInfo for push notification type
                if let notificationType = userInfo["type"] as? String {
                    await self.handleNotificationType(notificationType, userInfo: userInfo)
                } else {
                    // Fall back to category identifier for local notifications
                    self.handleNotificationCategory(categoryIdentifier)
                }
                
            default:
                break
            }
        }
        
        completionHandler()
    }
    
    // MARK: - Deep Link Handlers for Notifications
    
    /// Handle push notification types (from userInfo["type"])
    private func handleNotificationType(_ type: String, userInfo: [AnyHashable: Any]) async {
        SessionLogManager.shared.log(.info, category: .pushNotification, message: "📬 Notification TAPPED", metadata: [
            "type": type,
            "has_data": !userInfo.isEmpty
        ])
        switch type {
        // Social notifications
        case "shared_workout":
            if let workoutId = userInfo["workout_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .receivedWorkout(workoutId: workoutId)
                print("📬 [NOTIFICATIONS] Opening received workout: \(workoutId)")
            } else {
                DeepLinkManager.shared.pendingDestination = .receivedWorkouts
                print("📬 [NOTIFICATIONS] Opening received workouts list")
            }
            
        case "friend_request":
            await FriendService.shared.fetchPendingRequests()
            DeepLinkManager.shared.pendingDestination = .friendRequests
            print("👥 [NOTIFICATIONS] Opening friend requests tab")
            
        case "friend_request_accepted":
            await FriendService.shared.fetchFriends()
            DeepLinkManager.shared.pendingDestination = .friends
            print("🎉 [NOTIFICATIONS] Opening friends list - request accepted!")
            
        case "contact_joined":
            DeepLinkManager.shared.pendingDestination = .friendRequests
            print("👥 [NOTIFICATIONS] Contact joined Fit33 - opening friend requests tab")
            
        case "challenge_invite":
            // Fetch invites FIRST so the widget has data when dashboard appears
            await ChallengeService.shared.fetchPendingInvites()
            DeepLinkManager.shared.pendingDestination = .dashboard
            print("🏆 [NOTIFICATIONS] Opening home screen for challenge invite widget (\(ChallengeService.shared.pendingInvites.count) invites)")
            
        case "group_challenge_invite":
            await ChallengeService.shared.fetchActiveGroupChallenges()
            DeepLinkManager.shared.pendingDestination = .dashboard
            print("🏆 [NOTIFICATIONS] Opening home screen for group challenge invite")
            
        case "group_challenge_started":
            await ChallengeService.shared.fetchActiveGroupChallenges()
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.syncHealthKitDataToGroupChallenges()
            DeepLinkManager.shared.pendingDestination = .dashboard
            print("🏆 [NOTIFICATIONS] Group challenge started - syncing progress + opening dashboard")
            
        case "challenge_accepted", "challenge_progress", "challenge_completed":
            await ChallengeService.shared.fetchPendingSentChallenges()
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchPendingInvites()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .challengeDetail(challengeId: challengeId)
                print("🏆 [NOTIFICATIONS] Opening challenge detail: \(challengeId)")
            } else {
                DeepLinkManager.shared.pendingDestination = .challenges
                print("🏆 [NOTIFICATIONS] Opening challenges list")
            }
            
        case "challenge_cancelled":
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchPendingInvites()
            await ChallengeService.shared.fetchPendingSentChallenges()
            await ChallengeService.shared.fetchActiveGroupChallenges()
            DeepLinkManager.shared.pendingDestination = .dashboard
            print("🏆 [NOTIFICATIONS] Challenge cancelled, all lists refreshed")
            
        // Achievement notifications
        case "personal_record":
            DeepLinkManager.shared.pendingDestination = .personalRecord
            print("🏆 [NOTIFICATIONS] Opening personal records")
            
        case "streak_milestone":
            DeepLinkManager.shared.pendingDestination = .streakInfo
            print("🔥 [NOTIFICATIONS] Opening streak info")
            
        case "level_up", "goal_achieved":
            DeepLinkManager.shared.pendingDestination = .statsTab
            print("⭐️ [NOTIFICATIONS] Opening stats tab for achievement")
            
        // Health/Nutrition notifications
        case "nutrition_reminder", "protein_goal":
            DeepLinkManager.shared.pendingDestination = .mealsTab
            print("🍎 [NOTIFICATIONS] Opening meals tab")
            
        case "water_reminder":
            DeepLinkManager.shared.pendingDestination = .hydration
            print("💧 [NOTIFICATIONS] Opening hydration widget")
            
        case "steps_goal":
            DeepLinkManager.shared.pendingDestination = .stepTracker
            print("👟 [NOTIFICATIONS] Opening step tracker")
            
        // Workout notifications
        case "daily_workout_reminder", "streak_protection", "comeback_reminder", "morning_motivation":
            DeepLinkManager.shared.pendingDestination = .workout
            print("🏋️ [NOTIFICATIONS] Opening workout tab")
            
        case "workout_complete":
            DeepLinkManager.shared.pendingDestination = .workoutHistory
            print("✅ [NOTIFICATIONS] Opening workout history")
            
        case "weekly_progress":
            DeepLinkManager.shared.pendingDestination = .statsTab
            print("📊 [NOTIFICATIONS] Opening stats tab for weekly progress")
            
        default:
            print("📱 [NOTIFICATIONS] Unhandled notification type: \(type)")
        }
    }
    
    /// Handle local notification categories (fallback when no userInfo type)
    private func handleNotificationCategory(_ category: String) {
        switch category {
        case "WORKOUT_REMINDER":
            DeepLinkManager.shared.pendingDestination = .workout
            print("🏋️ [NOTIFICATIONS] Opening workout tab from reminder")
            
        case "NUTRITION_REMINDER":
            DeepLinkManager.shared.pendingDestination = .mealsTab
            print("🍎 [NOTIFICATIONS] Opening meals tab from nutrition reminder")
            
        case "SHARED_WORKOUT":
            DeepLinkManager.shared.pendingDestination = .receivedWorkouts
            print("📬 [NOTIFICATIONS] Opening received workouts")
            
        case "HYDRATION_REMINDER":
            DeepLinkManager.shared.pendingDestination = .hydration
            print("💧 [NOTIFICATIONS] Opening hydration widget")
            
        case "STEPS_REMINDER":
            DeepLinkManager.shared.pendingDestination = .stepTracker
            print("👟 [NOTIFICATIONS] Opening step tracker")
            
        case "ACHIEVEMENT":
            DeepLinkManager.shared.pendingDestination = .statsTab
            print("🏆 [NOTIFICATIONS] Opening stats for achievement")
            
        case "CONTACT_JOINED":
            DeepLinkManager.shared.pendingDestination = .friendRequests
            print("👥 [NOTIFICATIONS] Opening friend requests from contact joined notification")
            
        default:
            print("📱 [NOTIFICATIONS] User opened notification: \(category)")
        }
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
    
    // MARK: - Contact Joined Notification
    
    /// Send notification when a contact joins Fit33
    func sendContactJoinedNotification(contactName: String, newUserId: String) {
        guard isNotificationEnabled(.contactJoined) else {
            print("⚠️ [NOTIFICATIONS] Contact joined notifications disabled")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "\(contactName) joined Fit33!"
        content.body = "Send them a friend request!"
        content.categoryIdentifier = "CONTACT_JOINED"
        content.sound = .default
        content.userInfo = [
            "type": "contact_joined",
            "new_user_id": newUserId
        ]
        
        // Add thread identifier for grouping
        content.threadIdentifier = "contact_joined"
        
        sendImmediateNotification(
            content: content,
            identifier: "contact_joined_\(newUserId)_\(Date().timeIntervalSince1970)"
        )
        
        print("📬 [NOTIFICATIONS] Sent contact joined notification for \(contactName)")
    }
}
