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
    case challengeReaction = "challenge_reaction"
    case activityReaction = "activity_reaction"
    case challengeCancelled = "challenge_cancelled"
    /// Realtime Widget Server Pull, Phase 7c (2026-04-26): server-side
    /// hourly engagement nudge for users whose 1v1 opponent has been
    /// logging while they've been silent. Surfaced as a category in
    /// Settings → Notifications so users can mute it independently of
    /// other challenge notification types — some people want the
    /// banter ("Joe pulled ahead") and some find it pressure-y.
    case challengeNudge = "challenge_nudge"
    
    // Community Challenges
    case communityFriendJoined = "community_friend_joined"
    
    // Private Challenges
    case privateChallengeInvite = "private_challenge_invite"
    case privateChallengeUpdate = "private_challenge_update"
    case privateChallengeMessage = "private_challenge_message"
    
    // Progress & Achievements
    case personalRecord = "personal_record"
    case streakMilestone = "streak_milestone"
    // 2026-04-29 — League Redesign Plan §B2.
    // Renamed from `levelUp` ("level_up") to `tierPromotion` ("tier_promotion").
    // The XP-100-boundary level-up trigger is gone; this category now fires
    // on Monday-rollup tier promotions (Bronze → Silver, Stand-Out skip-tier,
    // Crown of the Week, Bounceback). Existing opt-ins stored under the old
    // `level_up_enabled` UserDefaults key are migrated automatically by
    // `NotificationManager.migrateLevelUpOptInIfNeeded()` on init.
    case tierPromotion = "tier_promotion"
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
        case .challengeReaction: return "Challenge Reactions"
        case .activityReaction: return "Activity Feed Reactions"
        case .challengeCancelled: return "Challenge Cancelled"
        case .challengeNudge: return "Challenge Nudges"
        case .communityFriendJoined: return "Friend Joined Community"
        case .privateChallengeInvite: return "Private Challenge Invites"
        case .privateChallengeUpdate: return "Private Challenge Updates"
        case .privateChallengeMessage: return "Private Challenge Messages"
        case .personalRecord: return "Personal Records"
        case .streakMilestone: return "Streak Celebrations"
        case .tierPromotion: return "Tier Promotions"
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
        case .challengeReaction: return "Battle cries and power ups from your challenge opponent"
        case .activityReaction: return "Notify when friends react to your workout, meal, or weight log"
        case .challengeCancelled: return "Notify when a challenge is cancelled"
        case .challengeNudge: return "Heads-up when an opponent pulls ahead so you can sync your progress"
        case .communityFriendJoined: return "Notify when friends join a community challenge"
        case .privateChallengeInvite: return "Notify when invited to private challenges"
        case .privateChallengeUpdate: return "Updates on your private challenge communities"
        case .privateChallengeMessage: return "Messages in your private challenge groups"
        case .personalRecord: return "Celebrate when you beat your best"
        case .streakMilestone: return "Celebrate streak milestones"
        case .tierPromotion: return "Notify when you promote to a new league tier"
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
        case .challengeReaction: return "bubble.left.fill"
        case .activityReaction: return "heart.fill"
        case .challengeCancelled: return "xmark.circle.fill"
        case .challengeNudge: return "bell.badge.fill"
        case .communityFriendJoined: return "person.2.circle.fill"
        case .privateChallengeInvite: return "lock.shield.fill"
        case .privateChallengeUpdate: return "person.3.fill"
        case .privateChallengeMessage: return "bubble.left.and.bubble.right.fill"
        case .personalRecord: return "trophy.fill"
        case .streakMilestone: return "flame.fill"
        case .tierPromotion: return "trophy.fill"
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
        case .challengeReaction: return .orange
        case .activityReaction: return .pink
        case .challengeCancelled: return .red
        case .challengeNudge: return .orange
        case .communityFriendJoined: return .cyan
        case .privateChallengeInvite: return .purple
        case .privateChallengeUpdate: return .purple
        case .privateChallengeMessage: return .pink
        case .personalRecord: return .yellow
        case .streakMilestone: return .orange
        case .tierPromotion: return .yellow
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
             .challengeReaction,       // Battle cries and power ups from opponent
             .activityReaction,        // Friends reacting to your workout / meal / weight log
             .challengeCancelled,      // Important to know when challenge ends
             .challengeNudge,          // Engagement nudge — silent opponent in active 1v1
             .communityFriendJoined,   // Social discovery - friend joined a community
             .privateChallengeInvite,  // Private challenge invites
             .privateChallengeUpdate,  // Private challenge member joins/progress
             .privateChallengeMessage, // Chat messages in private challenges
             .personalRecord,          // Celebrate achievements
             .streakMilestone,         // Celebrate consistency
             .tierPromotion,           // Weekly League rollup tier promotion
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
            return [.sharedWorkout, .friendRequest, .contactJoined,
                    .challengeInvite, .groupChallengeInvite, .challengeUpdate,
                    .challengeProgress, .challengeReaction, .activityReaction,
                    .challengeCancelled, .challengeNudge,
                    .communityFriendJoined, .privateChallengeInvite,
                    .privateChallengeUpdate, .privateChallengeMessage]
        case .achievements:
            return [.personalRecord, .streakMilestone, .tierPromotion, .goalAchieved]
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
            syncPreferencesToCloud()
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
    
    // Achievement batching: collect rapid-fire achievements into one notification
    private var pendingAchievements: [(title: String, body: String)] = []
    private var achievementBatchTimer: Task<Void, Never>?
    
    // Daily notification cap
    private static let dailyCapKey = "daily_notification_count"
    private static let dailyCapDateKey = "daily_notification_date"
    private static let dailyCapLimit = 15
    private static let criticalTypes: Set<NotificationType> = [
        .friendRequest, .challengeInvite, .privateChallengeInvite,
        .groupChallengeInvite, .sharedWorkout, .challengeUpdate,
        .challengeReaction, .challengeCancelled, .privateChallengeUpdate
    ]
    
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

        // 2026-04-29 — League Redesign Plan §B2.
        // One-time migration of the legacy `level_up` opt-in to the new
        // `tier_promotion` channel. Existing users who had Level Up alerts
        // toggled ON keep getting tier-promotion pushes; the legacy raw
        // value is removed from the set so the Settings UI reflects the
        // rename truthfully. Idempotent — runs at most once per install
        // since the second pass finds neither the legacy raw value nor an
        // outstanding migration flag.
        if !UserDefaults.standard.bool(forKey: "tier_promotion_optin_migrated_v1") {
            if enabledNotifications.contains("level_up") {
                enabledNotifications.remove("level_up")
                enabledNotifications.insert(NotificationType.tierPromotion.rawValue)
            }
            UserDefaults.standard.set(true, forKey: "tier_promotion_optin_migrated_v1")
        }

        super.init()

        // Save defaults if first launch
        if UserDefaults.standard.array(forKey: "enabled_notifications") == nil {
            saveEnabledNotifications()
        }

        // Persist the migrated set if we modified it above.
        saveEnabledNotifications()

        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            
            await MainActor.run {
                self.isAuthorized = granted
                // NUJ telemetry — flips `notification_permission_granted`
                // boolean on the user's enrollment row via the trigger.
                NewUserJourneyTracker.shared.logPermission(
                    kind: "notifications",
                    granted: granted
                )
            }
            
            if granted {
                setupNotificationCategories()
                scheduleAllNotifications()
                AppLogger.info("Authorization granted", category: .general)
            }
            
            return granted
        } catch {
            AppLogger.error("Notification authorization error: \(error.localizedDescription)", category: .general)
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
    
    // MARK: - App Icon Badge Management
    
    /// Clear the app icon badge immediately (call when app becomes active)
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                AppLogger.error("Failed to clear badge: \(error.localizedDescription)", category: .general)
            } else {
                AppLogger.debug("Badge cleared", category: .general)
            }
        }
    }
    
    /// Update the badge to reflect the real count of pending actionable items.
    /// Queries FriendService and ChallengeService for pending counts.
    @MainActor
    func updateBadgeCount() {
        let pendingFriendRequests = FriendService.shared.pendingRequests.count
        let pendingChallengeInvites = ChallengeService.shared.pendingInvites.count
        let unreadWorkouts = FriendService.shared.unreadWorkoutCount
        let pendingPrivateChallengeInvites = PrivateChallengeService.shared.pendingInvites.count
        
        let total = pendingFriendRequests + pendingChallengeInvites + unreadWorkouts + pendingPrivateChallengeInvites
        
        UNUserNotificationCenter.current().setBadgeCount(total) { error in
            if let error = error {
                AppLogger.error("Failed to update badge: \(error.localizedDescription)", category: .general)
            } else {
                AppLogger.debug("Badge updated to \(total) (friends=\(pendingFriendRequests), challenges=\(pendingChallengeInvites), private=\(pendingPrivateChallengeInvites), workouts=\(unreadWorkouts))", category: .general)
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
        case .morningMotivation:
            rescheduleMorningMotivation()
        case .weeklyProgress:
            rescheduleWeeklyProgress()
        case .waterReminder:
            rescheduleWaterReminders()
        default:
            break
        }
        
        syncPreferencesToCloud()
    }
    
    private func saveEnabledNotifications() {
        UserDefaults.standard.set(Array(enabledNotifications), forKey: "enabled_notifications")
    }
    
    /// Enable all high-value notifications for new users
    /// Called during onboarding to maximize engagement
    func enableAllDefaultNotifications() {
        enabledNotifications = Set(NotificationType.allCases.filter { $0.defaultEnabled }.map { $0.rawValue })
        saveEnabledNotifications()
        AppLogger.info("Enabled all default notifications: \(enabledNotifications.count) types", category: .general)
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
        
        // Private challenge invite category
        let acceptPrivateChallengeAction = UNNotificationAction(
            identifier: "ACCEPT_PRIVATE_CHALLENGE",
            title: "Join",
            options: [.foreground]
        )
        
        let viewPrivateChallengeAction = UNNotificationAction(
            identifier: "VIEW_PRIVATE_CHALLENGE",
            title: "View",
            options: [.foreground]
        )
        
        let privateChallengeInviteCategory = UNNotificationCategory(
            identifier: "PRIVATE_CHALLENGE_INVITE",
            actions: [acceptPrivateChallengeAction, viewPrivateChallengeAction],
            intentIdentifiers: []
        )
        
        // Private challenge message category
        let privateChallengeMessageCategory = UNNotificationCategory(
            identifier: "PRIVATE_CHALLENGE_MESSAGE",
            actions: [],
            intentIdentifiers: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            workoutCategory,
            nutritionCategory,
            sharedWorkoutCategory,
            challengeInviteCategory,
            contactJoinedCategory,
            privateChallengeInviteCategory,
            privateChallengeMessageCategory
        ])
    }
    
    private var lastScheduledAt: Date?
    
    // MARK: - Schedule All Notifications
    func scheduleAllNotifications() {
        guard masterNotificationsEnabled && isAuthorized else { return }
        
        if let last = lastScheduledAt, Date().timeIntervalSince(last) < 30 { return }
        lastScheduledAt = Date()
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        let workedOutToday: Bool = {
            if let last = UserDefaults.standard.object(forKey: "last_workout_date") as? Date {
                return Calendar.current.isDateInToday(last)
            }
            return false
        }()
        
        if isNotificationEnabled(.dailyWorkoutReminder) && !workedOutToday {
            scheduleWorkoutReminder()
        }
        
        if isNotificationEnabled(.nutritionReminder) {
            scheduleNutritionReminders()
        }
        
        if isNotificationEnabled(.streakProtection) && !workedOutToday {
            scheduleStreakProtection()
        }
        
        if isNotificationEnabled(.morningMotivation) {
            scheduleMorningMotivation()
        }
        
        if isNotificationEnabled(.weeklyProgress) {
            scheduleWeeklyProgress()
        }
        
        if isNotificationEnabled(.waterReminder) {
            scheduleWaterReminders()
        }
        
        AppLogger.debug("Scheduled all notifications", category: .general)
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
        if let last = UserDefaults.standard.object(forKey: "last_workout_date") as? Date,
           Calendar.current.isDateInToday(last) {
            return
        }
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
        
        if let last = UserDefaults.standard.object(forKey: "last_workout_date") as? Date,
           Calendar.current.isDateInToday(last) {
            return
        }
        
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
    
    private func rescheduleMorningMotivation() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationType.morningMotivation.rawValue]
        )
        if isNotificationEnabled(.morningMotivation) {
            scheduleMorningMotivation()
        }
    }
    
    // MARK: - Weekly Progress
    
    private func scheduleWeeklyProgress() {
        guard isNotificationEnabled(.weeklyProgress) else { return }
        
        let streak = UserDefaults.standard.integer(forKey: "current_streak")
        let totalWorkouts = UserDefaults.standard.integer(forKey: "total_workouts")
        
        let content = UNMutableNotificationContent()
        content.title = "Your Week in Review 📊"
        if streak > 0 {
            content.body = "You're on a \(streak)-day streak with \(totalWorkouts) total workouts. Keep the momentum going!"
        } else {
            content.body = "New week, fresh start! Set a goal and crush it this week."
        }
        content.sound = .default
        content.userInfo = ["type": NotificationType.weeklyProgress.rawValue]
        
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 18
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: NotificationType.weeklyProgress.rawValue,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    private func rescheduleWeeklyProgress() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationType.weeklyProgress.rawValue]
        )
        if isNotificationEnabled(.weeklyProgress) {
            scheduleWeeklyProgress()
        }
    }
    
    // MARK: - Water Reminders
    
    private func scheduleWaterReminders() {
        guard isNotificationEnabled(.waterReminder) else { return }
        
        let messages = [
            "Time for a glass of water! 💧",
            "Stay hydrated! Your body needs water to perform. 💦",
            "Water break! Hydration fuels your gains. 🚰",
            "Don't forget to drink water! 💧",
            "Hydration check — grab some water! 💦"
        ]
        
        // Schedule every 2 hours from 8 AM to 8 PM (7 reminders)
        for hour in stride(from: 8, through: 20, by: 2) {
            let content = UNMutableNotificationContent()
            content.title = "Hydration Reminder 💧"
            content.body = messages[((hour - 8) / 2) % messages.count]
            content.sound = .default
            content.userInfo = ["type": NotificationType.waterReminder.rawValue]
            
            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "water_reminder_\(hour)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    private func rescheduleWaterReminders() {
        let identifiers = stride(from: 8, through: 20, by: 2).map { "water_reminder_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        if isNotificationEnabled(.waterReminder) {
            scheduleWaterReminders()
        }
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
    
    /// Send comeback reminder with graduated messaging based on absence length
    func sendComebackReminder(daysAway: Int) {
        guard isNotificationEnabled(.comebackReminder) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        switch daysAway {
        case 3...7:
            content.title = "We miss you! 💙"
            content.body = "It's been \(daysAway) days. A quick workout can get you back on track!"
        case 14:
            content.title = "It's been a couple weeks 🤝"
            content.body = "Ready to get back on track? Your progress is still here waiting."
        case 30:
            content.title = "Ready for a fresh start? 🌱"
            content.body = "It's been a month — but every comeback starts with one workout."
        default:
            content.title = "We miss you! 💙"
            content.body = "It's been \(daysAway) days. A quick workout can get you back on track!"
        }
        
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
    
    /// Tier promotion notification (League Redesign Plan §B2 — replaces the
    /// legacy `sendLevelUpNotification`). Fires from the Monday rollup
    /// codepath via `WeeklyLeagueService.detectAndQueueTierPromotion`. Push
    /// channel is `.tierPromotion`; existing opt-ins under the old
    /// `level_up_enabled` UserDefaults key are migrated by
    /// `migrateLevelUpOptInIfNeeded()` on init.
    func sendTierPromotionNotification(newTierName: String, newTierRank: Int) {
        guard isNotificationEnabled(.tierPromotion) && isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Tier Up! 🏆"
        content.body = "You've reached \(newTierName) — open Fit33 to see your new league."
        content.sound = .default

        sendImmediateNotification(content: content, identifier: "tier_promote_\(newTierRank)")
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
    
    // MARK: - Private Challenge Notifications
    
    /// Private challenge invite notification - when someone invites you to a private challenge
    func sendPrivateChallengeInviteNotification(fromName: String, challengeTitle: String, challengeId: String) {
        guard isNotificationEnabled(.privateChallengeInvite) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🔒 \(fromName) invited you to a private community"
        content.body = "Join \"\(challengeTitle)\" — tap to accept or decline."
        content.sound = .default
        content.categoryIdentifier = "PRIVATE_CHALLENGE_INVITE"
        
        content.userInfo = [
            "type": "private_challenge_invite",
            "challenge_id": challengeId,
            "sender_name": fromName
        ]
        
        sendImmediateNotification(content: content, identifier: "private_invite_\(challengeId)")
    }
    
    /// Private challenge member joined notification - when someone accepts your invite
    func sendPrivateChallengeMemberJoinedNotification(memberName: String, challengeTitle: String, challengeId: String) {
        guard isNotificationEnabled(.privateChallengeUpdate) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(memberName) joined your challenge! 🎉"
        content.body = "They're now part of \"\(challengeTitle)\". The group is growing!"
        content.sound = .default
        
        content.userInfo = [
            "type": "private_challenge_member_joined",
            "challenge_id": challengeId,
            "member_name": memberName
        ]
        
        sendImmediateNotification(content: content, identifier: "private_joined_\(challengeId)_\(Date().timeIntervalSince1970)")
    }
    
    /// Private challenge progress notification - when a member hits their daily target
    func sendPrivateChallengeProgressNotification(memberName: String, challengeTitle: String, challengeId: String) {
        guard isNotificationEnabled(.privateChallengeUpdate) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(memberName) hit today's target! 🔥"
        content.body = "Keep up in \"\(challengeTitle)\" — don't fall behind!"
        content.sound = .default
        
        content.userInfo = [
            "type": "private_challenge_progress",
            "challenge_id": challengeId,
            "member_name": memberName
        ]
        
        sendImmediateNotification(content: content, identifier: "private_progress_\(challengeId)_\(Date().timeIntervalSince1970)")
    }
    
    /// Private challenge chat message notification
    func sendPrivateChallengeMessageNotification(senderName: String, message: String, challengeTitle: String, challengeId: String) {
        guard isNotificationEnabled(.privateChallengeMessage) && isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(senderName) in \(challengeTitle)"
        content.body = message.count > 100 ? String(message.prefix(100)) + "..." : message
        content.sound = .default
        content.categoryIdentifier = "PRIVATE_CHALLENGE_MESSAGE"
        content.threadIdentifier = "private_chat_\(challengeId)"
        
        content.userInfo = [
            "type": "private_challenge_message",
            "challenge_id": challengeId,
            "sender_name": senderName
        ]
        
        sendImmediateNotification(content: content, identifier: "private_msg_\(challengeId)_\(Date().timeIntervalSince1970)")
    }
    
    /// Workout completed - cancel today's reminders and celebrate
    func workoutCompleted() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                NotificationType.dailyWorkoutReminder.rawValue,
                NotificationType.streakProtection.rawValue
            ]
        )
        
        UserDefaults.standard.set(Date(), forKey: "last_workout_date")
        
        if isNotificationEnabled(.workoutComplete) && isAuthorized {
            let celebrations = [
                ("Great workout! 💪", "You crushed it today. Recovery starts now."),
                ("Workout complete! 🔥", "Another step toward your goals."),
                ("Done and dusted! ✅", "Consistency is the key — and you showed up."),
                ("Beast mode: activated 🏆", "That's another one in the books!")
            ]
            let msg = celebrations.randomElement()!
            let content = UNMutableNotificationContent()
            content.title = msg.0
            content.body = msg.1
            content.sound = .default
            content.userInfo = ["type": NotificationType.workoutComplete.rawValue]
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            let request = UNNotificationRequest(
                identifier: NotificationType.workoutComplete.rawValue,
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
        
        AppLogger.info("Workout completed - cancelled today's reminders", category: .general)
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
        
        // Comeback reminders are handled exclusively by Fit33App.checkForComebackReminder()
        // which has proper once-per-day dedup via "last_comeback_reminder" UserDefaults key.
    }
    
    // MARK: - Helper
    private func sendImmediateNotification(content: UNMutableNotificationContent, identifier: String) {
        let typeString = content.userInfo["type"] as? String ?? identifier
        
        if quietHoursEnabled && isInQuietHours() {
            SessionLogManager.shared.log(.info, category: .pushNotification, message: "Local notification blocked (quiet hours)", metadata: ["type": typeString])
            AppLogger.debug("Notification skipped - quiet hours active", category: .general)
            return
        }
        
        let notifType = NotificationType(rawValue: typeString)
        if let notifType, isDailyCapped(for: notifType) {
            SessionLogManager.shared.log(.info, category: .pushNotification, message: "Local notification blocked (daily cap)", metadata: ["type": typeString])
            AppLogger.debug("Notification skipped - daily cap reached (\(Self.dailyCapLimit))", category: .general)
            return
        }
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                SessionLogManager.shared.log(.error, category: .pushNotification, message: "Local notification FAILED", metadata: ["type": typeString, "error": error.localizedDescription])
                AppLogger.error("Failed to send notification: \(error.localizedDescription)", category: .general)
            } else {
                SessionLogManager.shared.log(.info, category: .pushNotification, message: "Local notification sent", metadata: [
                    "type": typeString,
                    "title": content.title
                ])
            }
        }
        incrementDailyCap()
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
    
    // MARK: - Achievement Batching
    
    /// Queue an achievement notification into a 30-second batch window.
    /// If multiple achievements fire in rapid succession (PR + level up + streak),
    /// they are combined into a single notification.
    func queueAchievementNotification(title: String, body: String) {
        guard isAuthorized else { return }
        
        pendingAchievements.append((title: title, body: body))
        
        if achievementBatchTimer == nil {
            achievementBatchTimer = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { return }
                flushAchievementBatch()
            }
        }
    }
    
    private func flushAchievementBatch() {
        let achievements = pendingAchievements
        pendingAchievements = []
        achievementBatchTimer = nil
        
        guard !achievements.isEmpty else { return }
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        if achievements.count == 1 {
            content.title = achievements[0].title
            content.body = achievements[0].body
        } else {
            let labels = achievements.map { $0.title.replacingOccurrences(of: "!", with: "") }
            content.title = "Multiple Achievements! 🏆"
            content.body = labels.joined(separator: ", ")
        }
        
        sendImmediateNotification(content: content, identifier: "achievement_batch_\(Date().timeIntervalSince1970)")
    }
    
    // MARK: - Daily Notification Cap
    
    private func isDailyCapped(for type: NotificationType) -> Bool {
        if Self.criticalTypes.contains(type) { return false }
        
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = UserDefaults.standard.object(forKey: Self.dailyCapDateKey) as? Date ?? .distantPast
        
        if !Calendar.current.isDate(lastDate, inSameDayAs: today) {
            UserDefaults.standard.set(today, forKey: Self.dailyCapDateKey)
            UserDefaults.standard.set(0, forKey: Self.dailyCapKey)
            return false
        }
        
        return UserDefaults.standard.integer(forKey: Self.dailyCapKey) >= Self.dailyCapLimit
    }
    
    private func incrementDailyCap() {
        let count = UserDefaults.standard.integer(forKey: Self.dailyCapKey)
        UserDefaults.standard.set(count + 1, forKey: Self.dailyCapKey)
    }
    
    // MARK: - Preference Sync to Cloud
    //
    // Two-way sync with `user_notification_preferences` (server). Writes
    // happen on every toggle (`syncPreferencesToCloud`); reads happen
    // once on auth-ready (`syncPreferencesFromCloud`) so a re-install or
    // second-device install picks up the user's existing opt-outs
    // instead of starting fresh from `defaultEnabled`.
    //
    // Conflict policy: server-wins-when-newer. We compare server
    // `updated_at` against `lastLocalPrefsChangeAt` (UserDefaults). When
    // server is older OR equal, local wins (we just saved). When server
    // is newer (another device made a change), server wins.

    /// ISO8601 timestamp of the most recent local-side prefs mutation. Used
    /// by `syncPreferencesFromCloud()` to decide whether server is newer.
    private static let lastLocalPrefsChangeKey = "notif_prefs_last_local_change_at"

    private func recordLocalPrefsChange() {
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: Self.lastLocalPrefsChangeKey)
    }

    /// Hydrate notification preferences from the server. Should be called
    /// once after auth-ready (e.g. from `Fit33App` `WindowGroup.task` after
    /// `SupabaseManager.isAuthenticated`). Server-newer-wins conflict policy.
    ///
    /// Calls `get_my_notification_preferences()` RPC (migration 20260801)
    /// which bundles preferences + the category catalogue in one round-trip.
    func syncPreferencesFromCloud() async {
        guard SupabaseManager.shared.isAuthenticated else { return }

        struct Response: Decodable {
            let preferences: ServerPrefs
            // categories: [CategoryRow]  // Hydrated by NotificationSettingsView when needed.
        }
        struct ServerPrefs: Decodable {
            let master_enabled: Bool?
            let disabled_types: [String]?
            let quiet_hours_enabled: Bool?
            let quiet_hours_start: String?
            let quiet_hours_end: String?
            let timezone: String?
            let daily_cap: Int?
            let category_disabled: [String]?
            let smart_timing_enabled: Bool?
            let updated_at: String?
            let is_default: Bool?
        }

        do {
            let resp: Response = try await SupabaseManager.shared.supabaseClient
                .rpc("get_my_notification_preferences")
                .execute()
                .value
            let prefs = resp.preferences

            // Server says "no row yet" → don't overwrite local. We'll write
            // local → server on the next user toggle.
            if prefs.is_default == true { return }

            // Conflict policy: only apply server when its updated_at is
            // strictly newer than our last local change.
            if let serverUpdatedAt = prefs.updated_at,
               let serverDate = ISO8601DateFormatter().date(from: serverUpdatedAt),
               let lastLocalRaw = UserDefaults.standard.string(forKey: Self.lastLocalPrefsChangeKey),
               let lastLocalDate = ISO8601DateFormatter().date(from: lastLocalRaw),
               serverDate <= lastLocalDate {
                AppLogger.debug("Notif prefs: server (\(serverUpdatedAt)) older than local (\(lastLocalRaw)) — skipping hydrate", category: .general)
                return
            }

            // Apply server state. We bypass the `didSet` hooks (which would
            // bounce write back to server in a loop) by mutating UserDefaults
            // first, then re-init the @Published values via the init pattern.
            if let me = prefs.master_enabled {
                UserDefaults.standard.set(me, forKey: "master_notifications_enabled")
                masterNotificationsEnabled = me
            }
            if let qhe = prefs.quiet_hours_enabled {
                UserDefaults.standard.set(qhe, forKey: "quiet_hours_enabled")
                quietHoursEnabled = qhe
            }
            if let qhs = prefs.quiet_hours_start, let qhsDate = parseHHMM(qhs) {
                UserDefaults.standard.set(qhsDate, forKey: "quiet_hours_start")
                quietHoursStart = qhsDate
            }
            if let qhe = prefs.quiet_hours_end, let qheDate = parseHHMM(qhe) {
                UserDefaults.standard.set(qheDate, forKey: "quiet_hours_end")
                quietHoursEnd = qheDate
            }
            if let disabled = prefs.disabled_types {
                let disabledSet = Set(disabled)
                let allTypes = Set(NotificationType.allCases.map { $0.rawValue })
                enabledNotifications = allTypes.subtracting(disabledSet)
                saveEnabledNotifications()
            }
            // Per-category prefs (used by Phase 4 Settings UI). Stored as
            // raw JSON in UserDefaults so the legacy didSet path doesn't
            // trip on them.
            if let catDisabled = prefs.category_disabled {
                UserDefaults.standard.set(catDisabled, forKey: "notif_category_disabled")
            }
            if let smart = prefs.smart_timing_enabled {
                UserDefaults.standard.set(smart, forKey: "notif_smart_timing_enabled")
            }
            if let cap = prefs.daily_cap {
                UserDefaults.standard.set(cap, forKey: "notif_daily_cap")
            }

            // Stamp local time so the next syncPreferencesToCloud() write is
            // newer than what we just hydrated.
            recordLocalPrefsChange()
            AppLogger.info("Hydrated notification prefs from server (server_updated_at=\(prefs.updated_at ?? "nil"))", category: .general)
        } catch {
            if await hydrateNotificationPrefsFromTableWhenRPCUnavailable(error) {
                return
            }
            _ = NetworkErrorClassifier.log(
                error,
                context: "Failed to hydrate notification preferences",
                category: .general,
                endpoint: "rpc/get_my_notification_preferences",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }

    /// When PostgREST returns PGRST202 (RPC not in schema cache / migration not
    /// applied yet), read `user_notification_preferences` directly so launch
    /// still hydrates toggles (`626608eb` / `3b9dd28b`).
    private func hydrateNotificationPrefsFromTableWhenRPCUnavailable(_ rpcError: Error) async -> Bool {
        let msg = rpcError.localizedDescription
        guard msg.contains("PGRST202")
            || msg.localizedCaseInsensitiveContains("could not find the function")
            || msg.localizedCaseInsensitiveContains("does not exist") else {
            return false
        }
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return false }

        struct TablePrefs: Decodable {
            let master_enabled: Bool?
            let disabled_types: [String]?
            let quiet_hours_enabled: Bool?
            let quiet_hours_start: String?
            let quiet_hours_end: String?
            let timezone: String?
            let daily_cap: Int?
            let category_disabled: [String]?
            let smart_timing_enabled: Bool?
            let updated_at: String?
        }

        do {
            let prefs: TablePrefs = try await SupabaseManager.shared.supabaseClient
                .from("user_notification_preferences")
                .select(
                    "master_enabled, disabled_types, quiet_hours_enabled, quiet_hours_start, quiet_hours_end, timezone, daily_cap, category_disabled, smart_timing_enabled, updated_at"
                )
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            if let serverUpdatedAt = prefs.updated_at,
               let serverDate = ISO8601DateFormatter().date(from: serverUpdatedAt),
               let lastLocalRaw = UserDefaults.standard.string(forKey: Self.lastLocalPrefsChangeKey),
               let lastLocalDate = ISO8601DateFormatter().date(from: lastLocalRaw),
               serverDate <= lastLocalDate {
                AppLogger.debug("Notif prefs (table fallback): server older than local — skipping", category: .general)
                return true
            }

            if let me = prefs.master_enabled {
                UserDefaults.standard.set(me, forKey: "master_notifications_enabled")
                masterNotificationsEnabled = me
            }
            if let qhe = prefs.quiet_hours_enabled {
                UserDefaults.standard.set(qhe, forKey: "quiet_hours_enabled")
                quietHoursEnabled = qhe
            }
            if let qhs = prefs.quiet_hours_start, let qhsDate = parseHHMM(qhs) {
                UserDefaults.standard.set(qhsDate, forKey: "quiet_hours_start")
                quietHoursStart = qhsDate
            }
            if let qhe = prefs.quiet_hours_end, let qheDate = parseHHMM(qhe) {
                UserDefaults.standard.set(qheDate, forKey: "quiet_hours_end")
                quietHoursEnd = qheDate
            }
            if let disabled = prefs.disabled_types {
                let disabledSet = Set(disabled)
                let allTypes = Set(NotificationType.allCases.map { $0.rawValue })
                enabledNotifications = allTypes.subtracting(disabledSet)
                saveEnabledNotifications()
            }
            if let catDisabled = prefs.category_disabled {
                UserDefaults.standard.set(catDisabled, forKey: "notif_category_disabled")
            }
            if let smart = prefs.smart_timing_enabled {
                UserDefaults.standard.set(smart, forKey: "notif_smart_timing_enabled")
            }
            if let cap = prefs.daily_cap {
                UserDefaults.standard.set(cap, forKey: "notif_daily_cap")
            }

            recordLocalPrefsChange()
            AppLogger.info("Hydrated notification prefs via table fallback (RPC unavailable)", category: .general)
            return true
        } catch {
            return false
        }
    }

    /// Parse "HH:mm:ss" / "HH:mm" → Date today.
    private func parseHHMM(_ raw: String) -> Date? {
        let parts = raw.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        var components = DateComponents()
        components.hour = h
        components.minute = m
        return Calendar.current.date(from: components)
    }

    private struct NotificationPreferencesInsert: Codable {
        let user_id: String
        let master_enabled: Bool
        let disabled_types: [String]
        let quiet_hours_enabled: Bool
        let quiet_hours_start: String
        let quiet_hours_end: String
        let timezone: String
        let updated_at: String
    }
    
    /// Upserts current notification preferences to Supabase so server-side push
    /// notifications can respect user toggles and quiet hours.
    func syncPreferencesToCloud() {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let disabledTypes = NotificationType.allCases
            .filter { !isNotificationEnabled($0) }
            .map { $0.rawValue }
        
        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: quietHoursStart)
        let startMin = calendar.component(.minute, from: quietHoursStart)
        let endHour = calendar.component(.hour, from: quietHoursEnd)
        let endMin = calendar.component(.minute, from: quietHoursEnd)
        
        let insert = NotificationPreferencesInsert(
            user_id: userId.uuidString,
            master_enabled: masterNotificationsEnabled,
            disabled_types: disabledTypes,
            quiet_hours_enabled: quietHoursEnabled,
            quiet_hours_start: String(format: "%02d:%02d:00", startHour, startMin),
            quiet_hours_end: String(format: "%02d:%02d:00", endHour, endMin),
            timezone: TimeZone.current.identifier,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        recordLocalPrefsChange()
        Task {
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("user_notification_preferences")
                    .upsert(insert, onConflict: "user_id")
                    .execute()
                AppLogger.debug("Synced notification preferences to cloud", category: .general)
            } catch {
                AppLogger.error("Failed to sync notification preferences: \(error.localizedDescription)", category: .general)
            }
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
        
        // Smart Notification Engine — Phase 2 (2026-08-02). Report
        // foreground-time delivery so the funnel captures it. The dedicated
        // service-extension target (when wired in Xcode) handles
        // background-delivered events; this covers the foreground case so
        // we never lose a delivery signal even before the extension ships.
        PushEventReporter.shared.report(.delivered, userInfo: userInfo)

        // Process notification even when in foreground to refresh data
        Task { @MainActor in
            if let notificationType = userInfo["type"] as? String {
                SessionLogManager.shared.log(.info, category: .pushNotification, message: "📨 Push received (foreground)", metadata: [
                    "type": notificationType,
                    "title": notification.request.content.title
                ])
                AppLogger.debug("Received \(notificationType) while app in foreground - refreshing data", category: .general)
                
                switch notificationType {
                case "challenge_accepted", "challenge_declined", "challenge_cancelled":
                    AppLogger.debug("[SENDER FLOW] Step 1: Received \(notificationType) - starting refresh", category: .general)
                    await ChallengeService.shared.fetchPendingSentChallenges()
                    await ChallengeService.shared.fetchPendingInvites()
                    await ChallengeService.shared.fetchActiveGroupChallenges()
                    
                    // Fetch active immediately to show the challenge widget (even with 0 progress)
                    AppLogger.debug("[SENDER FLOW] Step 2: Initial fetch of active challenges...", category: .general)
                    await ChallengeService.shared.fetchActiveChallenges()
                    let initialChallenge = ChallengeService.shared.activeChallenges.first
                    AppLogger.debug("[SENDER FLOW] Step 2 result: myToday=\(initialChallenge?.myTodayProgress ?? -1), oppToday=\(initialChallenge?.opponentTodayProgress ?? -1)", category: .general)
                    
                    // Sync OUR HealthKit data to any newly active challenges FIRST
                    AppLogger.debug("[SENDER FLOW] Step 3: Syncing OUR HealthKit data...", category: .general)
                    await ChallengeService.shared.syncHealthKitDataToChallenges()
                    
                    // Wait for accepter's progress sync to finish writing to DB
                    AppLogger.debug("[SENDER FLOW] Step 4: Waiting 2s for accepter's sync to complete...", category: .general)
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    
                    // Final fetch - should now have BOTH users' progress
                    AppLogger.debug("[SENDER FLOW] Step 5: Final fetch with both users' progress...", category: .general)
                    await ChallengeService.shared.fetchActiveChallenges()
                    let finalChallenge = ChallengeService.shared.activeChallenges.first
                    AppLogger.debug("[SENDER FLOW] Step 5 result: myToday=\(finalChallenge?.myTodayProgress ?? -1), oppToday=\(finalChallenge?.opponentTodayProgress ?? -1)", category: .general)
                    AppLogger.info("[SENDER FLOW] Complete - widget should show real-time progress", category: .general)
                    
                case "challenge_invite":
                    await ChallengeService.shared.fetchPendingInvites()
                    // Also fetch group challenges — group invites may arrive as "challenge_invite" type
                    await ChallengeService.shared.fetchActiveGroupChallenges()
                    
                case "group_challenge_invite":
                    AppLogger.debug("Group challenge invite received - refreshing group challenges", category: .general)
                    await ChallengeService.shared.fetchActiveGroupChallenges()
                    
                case "group_challenge_started":
                    AppLogger.debug("Group challenge started - refreshing and syncing progress", category: .general)
                    await ChallengeService.shared.fetchActiveGroupChallenges()
                    await ChallengeService.shared.fetchActiveChallenges()
                    // Sync existing health data to the newly started challenge
                    await ChallengeService.shared.syncHealthKitDataToGroupChallenges()
                    AppLogger.info("Group challenges refreshed + progress synced", category: .general)
                    
                case "community_friend_joined":
                    AppLogger.debug("Community friend joined - refreshing discoverable", category: .general)
                    await CommunityChallengeService.shared.fetchDiscoverableChallenges()
                    
                case "private_challenge_invite":
                    AppLogger.debug("Private challenge invite received - refreshing", category: .general)
                    await PrivateChallengeService.shared.fetchPendingInvites()
                    
                case "private_challenge_member_joined", "private_challenge_progress":
                    AppLogger.debug("Private challenge update - refreshing", category: .general)
                    await PrivateChallengeService.shared.refreshAll(force: true)
                    
                case "private_challenge_message":
                    AppLogger.debug("Private challenge message - refreshing", category: .general)
                    await PrivateChallengeService.shared.fetchMyChallenges()
                    
                case "friend_request", "friend_request_received":
                    await FriendService.shared.fetchPendingRequests()
                    
                case "friend_request_accepted", "friend_accepted":
                    await FriendService.shared.fetchFriends()
                    
                case "shared_workout":
                    await FriendService.shared.loadReceivedWorkouts()

                // Realtime Widget Server Pull, Phase 7c (2026-04-26):
                // Server-side hourly cron (`enqueue_engagement_nudges_for_stale_opponents`,
                // migration #123) fires `challenge_nudge` to users whose
                // opponent has been logging while they've been silent.
                // When the foreground app receives one, refresh the
                // active 1v1 challenges so the dashboard card and the
                // home-screen widget are in sync the moment the user
                // sees the banner. Critically, also trigger a HealthKit
                // sync so the user's own progress flows server-side
                // before they tap into the challenge detail — that's
                // the whole point of the nudge.
                case "challenge_nudge":
                    AppLogger.debug("Engagement nudge received - syncing HealthKit + refreshing challenges", category: .general)
                    await ChallengeService.shared.fetchActiveChallenges()
                    await ChallengeService.shared.syncHealthKitDataToChallenges()
                    // Re-fetch after the HK sync so any newly-written
                    // progress is reflected. The widget picks this up
                    // through `ActiveChallengeWidgetBridge.publish`.
                    await ChallengeService.shared.fetchActiveChallenges()

                default:
                    break
                }
                
                // After refreshing data, update the badge to reflect new counts
                self.updateBadgeCount()
            }
        }
        
        // Show notification even when app is in foreground
        // NOTE: We manage the badge count ourselves via updateBadgeCount(),
        // so we don't include .badge here to prevent stale badge values
        completionHandler([.banner, .sound])
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
        
        let notifType = userInfo["type"] as? String ?? categoryIdentifier
        SessionLogManager.shared.log(.info, category: .pushNotification, message: "Notification tapped", metadata: [
            "type": notifType,
            "action": actionIdentifier
        ])

        // Smart Notification Engine — Phase 2. Report tap to the engagement
        // funnel. `opened` covers the default action; custom action buttons
        // ALSO report `action_taken` below in the action-handling switch.
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            PushEventReporter.shared.report(.opened, userInfo: userInfo)
        } else if actionIdentifier == UNNotificationDismissActionIdentifier {
            PushEventReporter.shared.report(.dismissed, userInfo: userInfo)
        } else {
            PushEventReporter.shared.report(.actionTaken, userInfo: userInfo, actionId: actionIdentifier)
        }

        Task { @MainActor in
            switch actionIdentifier {
            case "START_WORKOUT":
                // Deep link to workout tab
                DeepLinkManager.shared.pendingDestination = .workout
                AppLogger.debug("User tapped Start Workout", category: .general)
                
            case "LOG_FOOD":
                // Deep link to meals tab
                DeepLinkManager.shared.pendingDestination = .mealsTab
                AppLogger.debug("User tapped Log Food - navigating to meals", category: .general)
                
            case "ADD_FRIEND":
                // Navigate to friend suggestions/requests when "Add Friend" tapped
                DeepLinkManager.shared.pendingDestination = .friendRequests
                AppLogger.debug("User tapped Add Friend from contact joined notification", category: .general)
                
            case "ACCEPT_PRIVATE_CHALLENGE", "VIEW_PRIVATE_CHALLENGE":
                // Navigate to dashboard so user sees the private challenge invite widget
                await PrivateChallengeService.shared.fetchPendingInvites()
                DeepLinkManager.shared.pendingDestination = .dashboard
                AppLogger.debug("User tapped private challenge action", category: .general)
                
            case "SNOOZE_1H":
                // Reschedule notification for 1 hour later
                self.snoozeNotification(categoryIdentifier: categoryIdentifier, hours: 1)
                AppLogger.debug("Snoozed for 1 hour", category: .general)
                
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
            
            // User tapped a notification — clear/update badge since they're entering the app
            self.clearBadge()
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
                AppLogger.debug("Opening received workout: \(workoutId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .receivedWorkouts
                AppLogger.debug("Opening received workouts list", category: .general)
            }
            
        case "friend_request":
            await FriendService.shared.fetchPendingRequests()
            DeepLinkManager.shared.pendingDestination = .friendRequests
            AppLogger.debug("Opening friend requests tab", category: .general)
            
        case "friend_request_accepted", "friend_accepted":
            await FriendService.shared.fetchFriends()
            DeepLinkManager.shared.pendingDestination = .friends
            AppLogger.debug("Opening friends list - request accepted!", category: .general)
            
        case "contact_joined":
            DeepLinkManager.shared.pendingDestination = .friendRequests
            AppLogger.debug("Contact joined Fit33 - opening friend requests tab", category: .general)
            
        case "community_friend_joined":
            // Deep link to the community join sheet so the user can join too
            if let slug = userInfo["invite_slug"] as? String {
                DeepLinkManager.shared.pendingCommunitySlug = slug
                DeepLinkManager.shared.showCommunityJoinSheet = true
                AppLogger.debug("Friend joined community — opening join sheet for: \(slug)", category: .general)
            } else {
                // Fallback: browse communities
                DeepLinkManager.shared.pendingDestination = .communityChallengeBrowse
                AppLogger.debug("Friend joined community — opening browse", category: .general)
            }
            
        case "challenge_invite":
            // Fetch invites FIRST so the widget has data when dashboard appears
            await ChallengeService.shared.fetchPendingInvites()
            // Also fetch group challenges — group invites may arrive as "challenge_invite" type
            await ChallengeService.shared.fetchActiveGroupChallenges()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .challengeInvite(challengeId: challengeId)
                AppLogger.debug("Opening challenge invite: \(challengeId) (\(ChallengeService.shared.pendingInvites.count) invites)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
                AppLogger.debug("Opening home screen for challenge invite widget (\(ChallengeService.shared.pendingInvites.count) invites, \(ChallengeService.shared.activeGroupChallenges.count) group)", category: .general)
            }
            
        case "group_challenge_invite":
            await ChallengeService.shared.fetchActiveGroupChallenges()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .challengeDetail(challengeId: challengeId)
                AppLogger.debug("Opening group challenge invite detail: \(challengeId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
                AppLogger.debug("Opening home screen for group challenge invite", category: .general)
            }
            
        case "group_challenge_started":
            await ChallengeService.shared.fetchActiveGroupChallenges()
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.syncHealthKitDataToGroupChallenges()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .challengeDetail(challengeId: challengeId)
                AppLogger.debug("Group challenge started — opening detail: \(challengeId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
                AppLogger.debug("Group challenge started - syncing progress + opening dashboard", category: .general)
            }
            
        case "private_challenge_invite":
            await PrivateChallengeService.shared.fetchPendingInvites()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .privateChallengeInvite(challengeId: challengeId)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
            }
            AppLogger.debug("Opening dashboard for private challenge invite", category: .general)
            
        case "private_challenge_member_joined", "private_challenge_progress":
            await PrivateChallengeService.shared.refreshAll(force: true)
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .privateChallengeDetail(challengeId: challengeId)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
            }
            AppLogger.debug("Private challenge update — opening detail", category: .general)
            
        case "private_challenge_message":
            await PrivateChallengeService.shared.fetchMyChallenges()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .privateChallengeDetail(challengeId: challengeId)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
            }
            AppLogger.debug("Private challenge message — opening detail", category: .general)
            
        case "challenge_accepted", "challenge_progress", "challenge_completed", "challenge_update":
            // 2026-08-01: `challenge_update` was in `knownNotificationTypes` but
            // had no specific case — fell through to default and lost the
            // `challenge_id` deep-link. Routed identically to `challenge_progress`
            // since the user intent ("see what changed in this challenge") is
            // the same.
            await ChallengeService.shared.fetchPendingSentChallenges()
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchActiveGroupChallenges()  // Group challenge may have been activated
            await ChallengeService.shared.fetchPendingInvites()
            // Navigate to specific challenge detail if ID available, else dashboard carousel
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .challengeDetail(challengeId: challengeId)
                AppLogger.debug("Challenge \(type) — opening challenge detail: \(challengeId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
                AppLogger.debug("Challenge \(type) — opening dashboard with active widget", category: .general)
            }

        // 2026-08-01: `challenge_declined` was refreshed in willPresent but
        // had no specific tap-routing case. The sender wants to see WHO
        // declined — route them to the challenge invite list (where the
        // declined badge will surface) rather than dashboard.
        case "challenge_declined":
            await ChallengeService.shared.fetchPendingSentChallenges()
            await ChallengeService.shared.fetchActiveChallenges()
            DeepLinkManager.shared.pendingDestination = .challenges
            AppLogger.debug("Challenge declined — opening challenges list", category: .general)

        // 2026-08-01: `challenge_reaction` ("smack talk") had no tap-routing
        // before — defaulted to dashboard. Now routes to the smack-talk
        // composer on the specific challenge so the recipient can clap back
        // in one tap (this is the user's example: "talk smack > opens to
        // smack talk menu").
        case "challenge_reaction":
            await ChallengeService.shared.fetchActiveChallenges()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .smackTalk(challengeId: challengeId)
                AppLogger.debug("Smack reaction — opening smack-talk composer: \(challengeId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
            }

        case "challenge_cancelled":
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchPendingInvites()
            await ChallengeService.shared.fetchPendingSentChallenges()
            await ChallengeService.shared.fetchActiveGroupChallenges()
            DeepLinkManager.shared.pendingDestination = .dashboard
            AppLogger.debug("Challenge cancelled, all lists refreshed", category: .general)

        // Bug-intel `184e70c6` (Sprint Q2-37): "activity_reaction" pushes were
        // landing in the `default` arm and being silently no-op'd into a
        // `.dashboard` fallback. Refresh the friend activity feed so the
        // reaction count is fresh, then surface the Friends-tab landing
        // screen where the inline feed lives. We deliberately do NOT push
        // `FriendsList` — that view doesn't show the activity feed.
        case "activity_reaction":
            await ActivityFeedService.shared.fetchFeed()
            DeepLinkManager.shared.pendingDestination = .friendsActivity
            AppLogger.debug("Activity reaction — opening Friends tab activity feed", category: .general)
            
        // Achievement notifications
        case "personal_record":
            DeepLinkManager.shared.pendingDestination = .personalRecord
            AppLogger.debug("Opening personal records", category: .general)
            
        case "streak_milestone":
            DeepLinkManager.shared.pendingDestination = .streakInfo
            AppLogger.debug("Opening streak info", category: .general)
            
        // 2026-04-29 — League Redesign Plan §B2.
        // "level_up" kept as inbound alias for any in-flight push payloads
        // that were enqueued before the rename; new push types use
        // "tier_promotion" and route to the same destination (the league
        // tab — a tier promotion is a league moment, not a stats moment).
        case "tier_promotion":
            DeepLinkManager.shared.pendingDestination = .statsTab
            AppLogger.debug("Opening stats tab for tier promotion", category: .general)
        case "level_up", "goal_achieved":
            DeepLinkManager.shared.pendingDestination = .statsTab
            AppLogger.debug("Opening stats tab for achievement", category: .general)
            
        // Health/Nutrition notifications
        case "nutrition_reminder", "protein_goal":
            DeepLinkManager.shared.pendingDestination = .mealsTab
            AppLogger.debug("Opening meals tab", category: .general)
            
        case "water_reminder":
            DeepLinkManager.shared.pendingDestination = .hydration
            AppLogger.debug("Opening hydration widget", category: .general)
            
        case "steps_goal":
            DeepLinkManager.shared.pendingDestination = .stepTracker
            AppLogger.debug("Opening step tracker", category: .general)
            
        // Workout notifications
        case "daily_workout_reminder", "streak_protection", "comeback_reminder", "morning_motivation":
            DeepLinkManager.shared.pendingDestination = .workout
            AppLogger.debug("Opening workout tab", category: .general)
            
        case "workout_complete":
            DeepLinkManager.shared.pendingDestination = .workoutHistory
            AppLogger.info("Opening workout history", category: .general)
            
        case "weekly_progress":
            DeepLinkManager.shared.pendingDestination = .statsTab
            AppLogger.debug("Opening stats tab for weekly progress", category: .general)

        // Realtime Widget Server Pull, Phase 7c (2026-04-26):
        // Tap on a `challenge_nudge` banner → refresh active 1v1s,
        // sync HealthKit so the recipient's just-now data flows
        // server-side BEFORE they see the challenge detail (so
        // they don't re-open to "wait, where's my progress?"),
        // then deep-link straight to the challenge in question.
        // The `data.challenge_id` field is set by migration #123;
        // fall back to the dashboard if for any reason it's
        // missing (older queue rows, manual test inserts, etc.).
        case "challenge_nudge":
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.syncHealthKitDataToChallenges()
            await ChallengeService.shared.fetchActiveChallenges()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .challengeDetail(challengeId: challengeId)
                AppLogger.debug("Engagement nudge — opening challenge detail: \(challengeId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
                AppLogger.debug("Engagement nudge tapped without challenge_id — falling back to dashboard", category: .general)
            }

        // 2026-04-30 — Challenge League Points Expansion ("Daily Duels, Final
        // Bell"). Fired by the server after `compute_challenge_daily_awards`
        // or `compute_challenge_final_bell` writes a row the user should know
        // about ("You won Day 3 vs Paul — +45 LP"). Deep-links to the
        // challenge so the user can see the freshly rendered LP chip on
        // BattleLogRow. When `challenge_id` is missing (e.g. a weekly summary
        // variant) we fall back to the leagues tab so the leaderboard
        // breakdown panel is one tap away.
        case "challenge_lp_awarded":
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .challengeDetail(challengeId: challengeId)
                AppLogger.debug("challenge_lp_awarded — opening challenge detail: \(challengeId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .leagues
                AppLogger.debug("challenge_lp_awarded without challenge_id — opening leagues tab", category: .general)
            }
            // Refresh the standing so the in-app badge reflects the new total.
            await WeeklyLeagueService.shared.fetchOrJoinLeague(force: true)

        // ── Smart Notification Engine Phase 3 trigger types (2026-08-01) ──
        //
        // These are the new orchestrator-driven intent types (see
        // `notification_intents` table, migration 20260802). Adding a new
        // server intent_kind requires (a) a route here, (b) an entry in
        // `knownNotificationTypes` below, and (c) a NotificationCategory
        // membership (see `NotificationCategory.notifications`).

        case "league_started", "league_promoted", "league_demoted":
            DeepLinkManager.shared.pendingDestination = .leagues
            AppLogger.debug("League event \(type) — opening leagues tab", category: .general)

        case "rivalry_behind", "rivalry_lead", "comeback_window":
            await ChallengeService.shared.fetchActiveChallenges()
            if let challengeId = userInfo["challenge_id"] as? String {
                DeepLinkManager.shared.pendingDestination = .smackTalk(challengeId: challengeId)
                AppLogger.debug("Rivalry alert \(type) — opening smack-talk for: \(challengeId)", category: .general)
            } else {
                DeepLinkManager.shared.pendingDestination = .dashboard
            }

        case "recovery_alert", "recovery_yellow", "recovery_pr_opportunity":
            DeepLinkManager.shared.pendingDestination = .readinessDetail
            AppLogger.debug("Recovery alert \(type) — opening readiness detail", category: .general)

        case "sleep_debt", "sleep_low":
            DeepLinkManager.shared.pendingDestination = .readinessDetail
            AppLogger.debug("Sleep alert \(type) — opening readiness detail", category: .general)

        case "hydration_pace", "hydration_reminder":
            DeepLinkManager.shared.pendingDestination = .hydration
            AppLogger.debug("Hydration alert \(type) — opening hydration widget", category: .general)

        case "streak_risk":
            DeepLinkManager.shared.pendingDestination = .dashboard
            AppLogger.debug("Streak risk — opening dashboard (quests widget)", category: .general)

        case "friend_workout_match":
            DeepLinkManager.shared.pendingDestination = .workout
            AppLogger.debug("Friend workout match — opening workout tab", category: .general)

        case "pr_opportunity", "overdue_muscle_group":
            DeepLinkManager.shared.pendingDestination = .workout
            AppLogger.debug("Workout opportunity \(type) — opening workout tab", category: .general)

        case "strava_celebration":
            DeepLinkManager.shared.pendingDestination = .dashboard
            AppLogger.debug("Strava celebration — opening dashboard recap", category: .general)

        case "morning_kickstart":
            DeepLinkManager.shared.pendingDestination = .dashboard
            AppLogger.debug("Morning kickstart — opening dashboard", category: .general)

        case "meal_reminder", "protein_deficit", "breakfast_reminder":
            DeepLinkManager.shared.pendingDestination = .mealsTab
            AppLogger.debug("Meal alert \(type) — opening meals tab", category: .general)

        case "activity_reaction":
            // Allowlisted in `knownNotificationTypes` but must route here — otherwise
            // taps fell through to default and logged false-positive "unknown type"
            // (bug-intel `184e70c6`).
            DeepLinkManager.shared.pendingDestination = .friendsActivity
            AppLogger.debug("Activity reaction — opening friends activity feed", category: .general)

        default:
            // Sprint 2 Q2-36 — hard allowlist. Anything not in
            // `NotificationManager.knownNotificationTypes` is a server drift
            // bug; log at .error so it surfaces in crash reports / analytics
            // instead of silently no-opping.
            if NotificationManager.knownNotificationTypes.contains(type) {
                AppLogger.debug("Notification type \(type) known but routed to default — review handleNotificationType", category: .general)
            } else {
                AppLogger.error("⚠️ Unknown notification type received from server: \(type)", category: .general)
                SessionLogManager.shared.log(.warning, category: .pushNotification, message: "Unknown notification type", metadata: ["type": type])
            }
            DeepLinkManager.shared.pendingDestination = .dashboard
        }
    }

    /// Every notification `type` string this client will ever route. Used by
    /// `handleNotificationType` to distinguish server drift (unknown) from
    /// "handled but currently no-ops" (known). Keep in lockstep with the
    /// switch above and the edge-function / server-side senders.
    ///
    /// A Fit33Tests unit test (`NotificationAllowlistTests`) enforces parity
    /// with `NotificationType.allCases` so new enum cases can't be added
    /// without also being added here.
    static let knownNotificationTypes: Set<String> = [
        // Social
        "shared_workout", "friend_request", "friend_request_accepted",
        "friend_accepted", "contact_joined", "community_friend_joined",
        // 1v1 / group challenges
        "challenge_invite", "group_challenge_invite", "group_challenge_started",
        "challenge_accepted", "challenge_progress", "challenge_completed",
        "challenge_cancelled", "challenge_declined", "challenge_update",
        "challenge_reaction",
        // 2026-04-30 — Challenge League Points Expansion. Fired post-rollup
        // (daily or Final Bell) when a user earned notable LP. Routes to
        // `.challengeDetail(...)` so the BattleLogRow LP chip is visible.
        "challenge_lp_awarded",
        // Activity-feed reactions (friends ❤️ your workout / meal / weight log)
        "activity_reaction",
        // Realtime Widget Server Pull, Phase 7c (2026-04-26): server
        // hourly cron fires `challenge_nudge` to silent users in active
        // 1v1s. Routed to `.challengeDetail(...)` and triggers a
        // HealthKit sync so the user's value lands server-side.
        "challenge_nudge",
        // Private challenges
        "private_challenge_invite", "private_challenge_member_joined",
        "private_challenge_progress", "private_challenge_message",
        "private_challenge_update",
        // Achievements & motivation
        // 2026-04-29 — League Redesign Plan §B2. `tier_promotion` is the new
        // forward type; `level_up` stays in the allowlist for back-compat with
        // already-queued payloads from before the rename.
        "personal_record", "streak_milestone", "tier_promotion", "level_up", "goal_achieved",
        "weekly_progress", "morning_motivation",
        // Health / nutrition
        "nutrition_reminder", "protein_goal", "water_reminder", "steps_goal",
        "weight_reminder",
        // Workout reminders
        "daily_workout_reminder", "streak_protection", "comeback_reminder",
        "workout_complete",

        // ── Smart Notification Engine Phase 3 trigger types (2026-08-01) ──
        // Server-orchestrated personalized intents. See `notification_intents`
        // (migration 20260802) and `handleNotificationType` switch above.
        // Adding a new server intent_kind requires: (a) tap-routing case
        // above, (b) entry here, (c) NotificationCategory membership.
        "league_started", "league_promoted", "league_demoted",
        "rivalry_behind", "rivalry_lead", "comeback_window",
        "recovery_alert", "recovery_yellow", "recovery_pr_opportunity",
        "sleep_debt", "sleep_low",
        "hydration_pace", "hydration_reminder",
        "streak_risk",
        "friend_workout_match", "pr_opportunity", "overdue_muscle_group",
        "strava_celebration",
        "morning_kickstart",
        "meal_reminder", "protein_deficit", "breakfast_reminder"
    ]

    /// Handle local notification categories (fallback when no userInfo type)
    private func handleNotificationCategory(_ category: String) {
        switch category {
        case "WORKOUT_REMINDER":
            DeepLinkManager.shared.pendingDestination = .workout
            AppLogger.debug("Opening workout tab from reminder", category: .general)
            
        case "NUTRITION_REMINDER":
            DeepLinkManager.shared.pendingDestination = .mealsTab
            AppLogger.debug("Opening meals tab from nutrition reminder", category: .general)
            
        case "SHARED_WORKOUT":
            DeepLinkManager.shared.pendingDestination = .receivedWorkouts
            AppLogger.debug("Opening received workouts", category: .general)
            
        case "HYDRATION_REMINDER":
            DeepLinkManager.shared.pendingDestination = .hydration
            AppLogger.debug("Opening hydration widget", category: .general)
            
        case "STEPS_REMINDER":
            DeepLinkManager.shared.pendingDestination = .stepTracker
            AppLogger.debug("Opening step tracker", category: .general)
            
        case "ACHIEVEMENT":
            DeepLinkManager.shared.pendingDestination = .statsTab
            AppLogger.debug("Opening stats for achievement", category: .general)
            
        case "CONTACT_JOINED":
            DeepLinkManager.shared.pendingDestination = .friendRequests
            AppLogger.debug("Opening friend requests from contact joined notification", category: .general)
            
        default:
            AppLogger.debug("User opened notification: \(category)", category: .general)
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
    // MARK: - Community Friend Joined
    
    /// Throttle key for community friend joined notifications.
    /// We only send 1 of these every 6 hours to avoid spam.
    private static let communityFriendJoinedThrottleKey = "last_community_friend_joined_notif"
    private static let communityFriendJoinedThrottleInterval: TimeInterval = 6 * 60 * 60 // 6 hours
    
    func sendCommunityFriendJoinedNotification(friendName: String, challengeTitle: String, challengeEmoji: String, inviteSlug: String) {
        guard isNotificationEnabled(.communityFriendJoined) else {
            AppLogger.warning("Community friend joined notifications disabled", category: .general)
            return
        }
        
        // Throttle: max 1 notification per 6 hours to avoid being annoying
        let lastSent = UserDefaults.standard.double(forKey: Self.communityFriendJoinedThrottleKey)
        if lastSent > 0 && Date().timeIntervalSince1970 - lastSent < Self.communityFriendJoinedThrottleInterval {
            AppLogger.debug("Community friend joined throttled — last sent \(Int((Date().timeIntervalSince1970 - lastSent) / 60))min ago", category: .general)
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "\(challengeEmoji) \(friendName) joined a community!"
        content.body = "Your friend joined the \"\(challengeTitle)\" challenge. Tap to check it out!"
        content.categoryIdentifier = "COMMUNITY_FRIEND_JOINED"
        content.sound = .default
        content.userInfo = [
            "type": "community_friend_joined",
            "invite_slug": inviteSlug,
            "friend_name": friendName,
            "challenge_title": challengeTitle
        ]
        content.threadIdentifier = "community_discovery"
        
        sendImmediateNotification(
            content: content,
            identifier: "community_friend_joined_\(inviteSlug)_\(Date().timeIntervalSince1970)"
        )
        
        // Record the send time for throttling
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.communityFriendJoinedThrottleKey)
        
        AppLogger.debug("Sent community friend joined notification: \(friendName) → \(challengeTitle)", category: .general)
    }
    
    func sendContactJoinedNotification(contactName: String, newUserId: String) {
        guard isNotificationEnabled(.contactJoined) else {
            AppLogger.warning("Contact joined notifications disabled", category: .general)
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
        
        AppLogger.debug("Sent contact joined notification for \(contactName)", category: .general)
    }
}
