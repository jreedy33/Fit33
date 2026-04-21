//
//  DailyQuestService.swift
//  Fit33
//
//  Daily Quest System V2 — Personalized, actionable daily mini-challenges.
//  Users get 3 quests per day based on their current context (active program,
//  friends, challenges, step goal, fitness goal). Complete all 3 for a bonus.
//  Difficulty varies day-to-day: easy days, mixed days, and hard days.
//  Feeds XP + league points back into the main progression system.
//

import Foundation
import SwiftUI

// MARK: - Quest Models

struct DailyQuest: Codable, Identifiable {
    let id: UUID
    let questKey: String
    let title: String
    let description: String
    let icon: String
    let category: String
    let targetValue: Int
    let currentValue: Int
    let targetUnit: String
    let xpReward: Int
    let leaguePoints: Int
    let difficulty: String
    let isCompleted: Bool
    let completedAt: String?
    let funLabel: String?
    let verificationType: String?  // "auto", "social", or "manual"
    
    enum CodingKeys: String, CodingKey {
        case id
        case questKey = "quest_key"
        case title, description, icon, category
        case targetValue = "target_value"
        case currentValue = "current_value"
        case targetUnit = "target_unit"
        case xpReward = "xp_reward"
        case leaguePoints = "league_points"
        case difficulty
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case funLabel = "fun_label"
        case verificationType = "verification_type"
    }
    
    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(Double(currentValue) / Double(targetValue), 1.0)
    }
    
    /// Whether this quest is auto-verified by the app (HealthKit, workout tracker, etc.)
    var isAppTracked: Bool {
        verificationType == "auto"
    }
    
    /// Whether this quest is verified by in-app social action
    var isSocialAction: Bool {
        verificationType == "social"
    }
    
    /// Whether this quest relies on manual user input (logging meals, water, weight)
    var isManualInput: Bool {
        verificationType == "manual" || verificationType == nil
    }
    
    /// Short label for the verification badge shown on quest cards
    var verificationBadge: String? {
        switch verificationType {
        case "auto": return "📱 App Tracked"
        case "social": return "👥 In-App Action"
        default: return nil
        }
    }
    
    var difficultyColor: Color {
        switch difficulty {
        case "easy": return .green
        case "medium": return .orange
        case "hard": return .red
        default: return .blue
        }
    }
    
    var categoryColor: Color {
        switch category {
        case "workout": return .blue
        case "nutrition": return .green
        case "social": return .purple
        case "steps": return .cyan
        case "tracking": return .indigo
        case "wildcard": return .orange
        case "reward": return .yellow
        default: return .cyan
        }
    }
    
    var categoryEmoji: String {
        switch category {
        case "workout": return "💪"
        case "nutrition": return "🥗"
        case "social": return "👥"
        case "steps": return "🚶"
        case "tracking": return "📊"
        case "wildcard": return "🌟"
        case "reward": return "📺"
        default: return "⭐"
        }
    }
    
    var difficultyLabel: String {
        switch difficulty {
        case "easy": return "Easy"
        case "medium": return "Medium"
        case "hard": return "Hard"
        default: return difficulty.capitalized
        }
    }
}

struct DailyQuestsResponse: Codable {
    let quests: [DailyQuest]?
    let allComplete: Bool
    let bonusXp: Int
    let bonusLeaguePoints: Int
    let questDate: String
    let streak: Int
    let longestStreak: Int
    let totalCompleted: Int
    let difficultyProfile: String?
    
    enum CodingKeys: String, CodingKey {
        case quests
        case allComplete = "all_complete"
        case bonusXp = "bonus_xp"
        case bonusLeaguePoints = "bonus_league_points"
        case questDate = "quest_date"
        case streak
        case longestStreak = "longest_streak"
        case totalCompleted = "total_completed"
        case difficultyProfile = "difficulty_profile"
    }
}

struct QuestProgressResult: Codable {
    let success: Bool
    let questKey: String?
    let newValue: Int?
    let targetValue: Int?
    let justCompleted: Bool?
    let xpReward: Int?
    let leaguePoints: Int?
    let allComplete: Bool?
    let bonusUnlocked: Bool?
    let bonusXp: Int?
    let bonusLeaguePoints: Int?
    let alreadyCompleted: Bool?
    let reason: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case questKey = "quest_key"
        case newValue = "new_value"
        case targetValue = "target_value"
        case justCompleted = "just_completed"
        case xpReward = "xp_reward"
        case leaguePoints = "league_points"
        case allComplete = "all_complete"
        case bonusUnlocked = "bonus_unlocked"
        case bonusXp = "bonus_xp"
        case bonusLeaguePoints = "bonus_league_points"
        case alreadyCompleted = "already_completed"
        case reason
    }
}

// MARK: - Quest Key Constants (V2 — expanded)
// These match the quest_key values in quest_templates

enum QuestKey: String, CaseIterable {
    // Workout
    case completeWorkout = "complete_workout"
    case completeProgramDay = "complete_program_day"
    case complete2Workouts = "complete_2_workouts"
    case workout30Min = "workout_30_min"
    case exerciseSets15 = "exercise_sets_15"
    case exerciseSets25 = "exercise_sets_25"
    case tryNewExercise = "try_new_exercise"
    case upperBodyWorkout = "upper_body_workout"
    case lowerBodyWorkout = "lower_body_workout"
    
    // Nutrition
    case logBreakfast = "log_breakfast"
    case logLunch = "log_lunch"
    case logDinner = "log_dinner"
    case log3Meals = "log_3_meals"
    case logSnack = "log_snack"
    case logWater3 = "log_water_3"
    case logWater8 = "log_water_8"
    case hitProteinGoal = "hit_protein_goal"
    case logHighProteinMeal = "log_high_protein_meal"
    
    // Steps & Movement
    case walk3kSteps = "walk_3k_steps"
    case walk5kSteps = "walk_5k_steps"
    case walk7500Steps = "walk_7500_steps"
    case hitStepGoal = "hit_step_goal"
    case walk10kSteps = "walk_10k_steps"
    
    // Social
    case sendChallenge = "send_challenge"
    case start1v1Challenge = "start_1v1_challenge"
    case reactToWorkout = "react_to_workout"
    case inviteFriend = "invite_friend"
    case addFriend = "add_friend"
    case startFirstChallenge = "start_first_challenge"
    
    // Tracking
    case logWeight = "log_weight"
    case checkProgress = "check_progress"
    case beatPersonalRecord = "beat_personal_record"
    case logCardio = "log_cardio"
    
    // Wildcard / Fun
    case perfectDay = "perfect_day"
    case earlyBirdWorkout = "early_bird_workout"
    case shareWorkout = "share_workout"
    case favoriteAWorkout = "favorite_a_workout"
    
    // Reward (free users only)
    case watchAds = "watch_ads"
    
    // Workout-metric quests
    case beatVolumePR = "beat_volume_pr"
    case maintainStreak = "maintain_streak"
    case stretchSession = "stretch_session"
    
    // Health-metric quests (HealthKit auto-tracked)
    case activeMinutes30 = "active_minutes_30"
    case burn300Calories = "burn_300_calories"
    case sleep7Hours = "sleep_7_hours"
    
    // Social-competitive quests
    case beatFriendSteps = "beat_friend_steps"
    case league3Workouts = "league_3_workouts"
    case top3League = "top_3_league"
    
    // Tracking/consistency quests
    case logAllMacros = "log_all_macros"
    case hydrationBeforeNoon = "hydration_before_noon"
    case weeklyWeighIn = "weekly_weigh_in"
    
    // MARK: - Legacy keys (for backwards compat with existing quests)
    case logMeal = "log_meal"
    case logWater = "log_water"
    case exerciseSets10 = "exercise_sets_10"
    case exerciseSets20 = "exercise_sets_20"
    
    // MARK: - Day 1 beginner quests (hardcoded, not from server)
    case beginnerSyncContacts = "beginner_sync_contacts"
    case beginnerAddFriend = "beginner_add_friend"
    case beginnerSendChallenge = "beginner_send_challenge"
    case beginnerFirstWorkout = "beginner_first_workout"
    case beginnerExploreProgram = "beginner_explore_program"
}

// MARK: - Daily Quest Service

@MainActor
class DailyQuestService: ObservableObject {
    static let shared = DailyQuestService()
    
    // MARK: - Published State
    @Published var quests: [DailyQuest] = []
    @Published var allComplete: Bool = false
    @Published var bonusXp: Int = 0
    @Published var bonusLeaguePoints: Int = 0
    @Published var questStreak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var totalCompleted: Int = 0
    @Published var difficultyProfile: String?  // "easy_day", "mixed_day", "hard_day"
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var showQuestCompletionCelebration: Bool = false
    @Published var showBonusCelebration: Bool = false
    @Published var lastCompletedQuest: DailyQuest?
    
    // MARK: - Step Delta Tracking
    private var lastReportedSteps: Int = 0
    private let lastReportedStepsKey = "fit33_lastReportedSteps"
    private let lastReportedStepsDateKey = "fit33_lastReportedStepsDate"
    
    // MARK: - Cache
    private let cacheKey = "fit33_daily_quests_v2"
    private let cacheDateKey = "fit33_daily_quests_v2_date"
    private let cacheDuration: TimeInterval = 60 // 1 minute
    
    private init() {
        loadCachedQuests()
        restoreLastReportedSteps()
    }
    
    // MARK: - Computed Properties
    
    var completedCount: Int {
        quests.filter(\.isCompleted).count
    }
    
    var totalCount: Int {
        quests.count
    }
    
    var overallProgress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
    
    var totalXpAvailable: Int {
        quests.reduce(0) { $0 + $1.xpReward } + (allComplete ? 0 : 50)
    }
    
    var totalXpEarned: Int {
        quests.filter(\.isCompleted).reduce(0) { $0 + $1.xpReward } + bonusXp
    }
    
    /// Human-readable label for today's difficulty
    var difficultyProfileLabel: String {
        switch difficultyProfile {
        case "easy_day": return "Chill Day 😌"
        case "mixed_day": return "Mixed Bag 🎲"
        case "hard_day": return "Challenge Day 🔥"
        default: return ""
        }
    }
    
    /// Checks if a given quest key is active today (assigned to user)
    func hasQuest(_ key: QuestKey) -> Bool {
        quests.contains(where: { $0.questKey == key.rawValue && !$0.isCompleted })
    }
    
    // MARK: - Gather User Context
    
    struct UserQuestContext {
        let hasProgram: Bool
        let hasFriends: Bool
        let hasChallenge: Bool
        let stepGoal: Int
        let activeStepChallengeTarget: Int
        let fitnessGoal: String
        let workoutStreak: Int
        let totalWorkouts: Int
        let preferredTime: String
        let avgDuration: Int
        let hasWeightLog: Bool
        let hydrationActive: Bool
        let leagueRank: Int
        /// Recommended split for today based on muscle recovery history.
        /// One of "push" | "pull" | "legs" | "upper" | "full" | "core_cardio", or nil
        /// when the user has an active program (server uses `complete_program_day`).
        let suggestedSplit: String?
        /// Fatigued body regions the server should avoid scheduling. Subset of
        /// {"upper","lower"}. Upper = any of chest/back/shoulders/biceps/triceps
        /// still recovering; lower = any of quads/hamstrings/glutes/calves.
        let fatiguedRegions: [String]
    }
    
    /// Builds the per-user context used to personalize today's quest selection.
    /// Async because it awaits `WorkoutSuggestionEngine` for off-main-thread
    /// muscle-recovery state from Core Data.
    private func gatherUserContext() async -> UserQuestContext {
        let hasCloudProgram = CloudProgramService.shared.activeProgram != nil
        let hasGeneratedProgram = GeneratedProgramService.shared.activeProgram != nil
        let hasSmartProgram = SmartProgramEngine.shared.userPrograms.contains { !$0.isCompleted }
        let hasProgram = hasCloudProgram || hasGeneratedProgram || hasSmartProgram
        let hasFriends = !FriendService.shared.friends.isEmpty
        let hasChallenge = !ChallengeService.shared.activeChallenges.isEmpty ||
                           !ChallengeService.shared.activeGroupChallenges.isEmpty
        let stepGoal = HealthKitManager.shared.stepGoal
        let fitnessGoal = UserManager.shared.currentUser?.fitnessGoal ?? "general"
        
        let stepTypes: Set<String> = ["steps", "walk"]
        let oneOnOneStepTarget = ChallengeService.shared.activeChallenges
            .filter { stepTypes.contains($0.challengeType) }
            .compactMap(\.dailyTarget)
            .max() ?? 0
        let groupStepTarget = ChallengeService.shared.activeGroupChallenges
            .filter { stepTypes.contains($0.challengeType) }
            .compactMap(\.dailyTarget)
            .max() ?? 0
        let activeStepChallengeTarget = max(oneOnOneStepTarget, groupStepTarget)
        
        let workoutStreak = Int(UserManager.shared.currentUser?.currentStreak ?? 0)
        let totalWorkouts = Int(UserManager.shared.currentUser?.totalWorkouts ?? 0)
        let preferredTime = UserBehaviorLearningEngine.shared.userPreferences?.preferredTimeOfDay ?? "any"
        let avgDuration = UserBehaviorLearningEngine.shared.userPreferences?.preferredWorkoutDuration ?? 45
        let hasWeightLog = WeightTrackingService.shared.statistics != nil
        let hydrationActive = HydrationService.shared.settings.dailyGoalMl > 0
        let leagueRank = WeeklyLeagueService.shared.standing?.myRank ?? 0

        // Muscle-recovery-aware split suggestion. Program users get their
        // `complete_program_day` slot via the `requires_context` gate, so we
        // skip the suggestion to keep the RPC payload minimal.
        var suggestedSplit: String? = nil
        var fatiguedRegions: [String] = []
        if !hasProgram {
            let suggestion = await WorkoutSuggestionEngine.shared.suggestForTodayAsync()
            suggestedSplit = Self.encodeSplitFamily(suggestion.splitFamily)

            let states = await WorkoutSuggestionEngine.shared.getMuscleRecoveryStatesAsync()
            let upperCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [.chest, .back, .shoulders, .biceps, .triceps]
            let lowerCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [.quads, .hamstrings, .glutes, .calves]
            let upperFatigued = states.contains { upperCats.contains($0.category) && !$0.isRecovered }
            let lowerFatigued = states.contains { lowerCats.contains($0.category) && !$0.isRecovered }
            if upperFatigued { fatiguedRegions.append("upper") }
            if lowerFatigued { fatiguedRegions.append("lower") }
        }

        return UserQuestContext(
            hasProgram: hasProgram,
            hasFriends: hasFriends,
            hasChallenge: hasChallenge,
            stepGoal: stepGoal,
            activeStepChallengeTarget: activeStepChallengeTarget,
            fitnessGoal: fitnessGoal,
            workoutStreak: workoutStreak,
            totalWorkouts: totalWorkouts,
            preferredTime: preferredTime,
            avgDuration: avgDuration,
            hasWeightLog: hasWeightLog,
            hydrationActive: hydrationActive,
            leagueRank: leagueRank,
            suggestedSplit: suggestedSplit,
            fatiguedRegions: fatiguedRegions
        )
    }

    /// Contract: must match the string literals accepted by `get_daily_quests`
    /// (`p_suggested_split`). Keep in sync with the SQL migration.
    private static func encodeSplitFamily(_ family: WorkoutSuggestionEngine.SplitFamily) -> String {
        switch family {
        case .push:       return "push"
        case .pull:       return "pull"
        case .legs:       return "legs"
        case .upperBody:  return "upper"
        case .fullBody:   return "full"
        case .coreCardio: return "core_cardio"
        }
    }
    
    // MARK: - Day 1 Beginner Quests
    
    private func beginnerSocialQuest() -> DailyQuest {
        let canAccess = ContactsService.shared.canAccessContacts
        let hasFriends = !FriendService.shared.friends.isEmpty
        
        if !canAccess {
            return DailyQuest(
                id: UUID(),
                questKey: QuestKey.beginnerSyncContacts.rawValue,
                title: "Sync Your Contacts",
                description: "Find friends already on Fit33 to challenge!",
                icon: "person.crop.circle.badge.plus",
                category: "social",
                targetValue: 1, currentValue: 0,
                targetUnit: "action",
                xpReward: 50, leaguePoints: 10,
                difficulty: "easy",
                isCompleted: false, completedAt: nil,
                funLabel: "Connect",
                verificationType: "social"
            )
        } else if !hasFriends {
            return DailyQuest(
                id: UUID(),
                questKey: QuestKey.beginnerAddFriend.rawValue,
                title: "Add a Friend",
                description: "Send a friend request to someone you know",
                icon: "person.badge.plus",
                category: "social",
                targetValue: 1, currentValue: 0,
                targetUnit: "friend",
                xpReward: 50, leaguePoints: 10,
                difficulty: "easy",
                isCompleted: false, completedAt: nil,
                funLabel: "Connect",
                verificationType: "social"
            )
        } else {
            let friendName = FriendService.shared.friends.first?.displayName ?? "a Friend"
            return DailyQuest(
                id: UUID(),
                questKey: QuestKey.beginnerSendChallenge.rawValue,
                title: "Send a Challenge",
                description: "Challenge \(friendName) to a workout!",
                icon: "flame.fill",
                category: "social",
                targetValue: 1, currentValue: 0,
                targetUnit: "challenge",
                xpReward: 75, leaguePoints: 15,
                difficulty: "easy",
                isCompleted: false, completedAt: nil,
                funLabel: "Let's go",
                verificationType: "social"
            )
        }
    }
    
    private func beginnerWorkoutQuest() -> DailyQuest {
        DailyQuest(
            id: UUID(),
            questKey: QuestKey.beginnerFirstWorkout.rawValue,
            title: "Start Your First Workout",
            description: "A custom workout made just for you",
            icon: "dumbbell.fill",
            category: "workout",
            targetValue: 1, currentValue: 0,
            targetUnit: "workout",
            xpReward: 100, leaguePoints: 25,
            difficulty: "easy",
            isCompleted: false, completedAt: nil,
            funLabel: "Let's lift",
            verificationType: "social"
        )
    }
    
    private func beginnerProgramQuest() -> DailyQuest {
        DailyQuest(
            id: UUID(),
            questKey: QuestKey.beginnerExploreProgram.rawValue,
            title: "Explore Your Program",
            description: "Check out the weekly plan built for your goals",
            icon: "calendar.badge.clock",
            category: "tracking",
            targetValue: 1, currentValue: 0,
            targetUnit: "action",
            xpReward: 50, leaguePoints: 10,
            difficulty: "easy",
            isCompleted: false, completedAt: nil,
            funLabel: "Take a look",
            verificationType: "social"
        )
    }
    
    /// Fallback goals that are always returned when the server returns empty or errors.
    /// Context-aware: experienced users get real generic quests, beginners get onboarding quests.
    private func defaultGoals() -> [DailyQuest] {
        let totalWorkouts = Int(UserManager.shared.currentUser?.totalWorkouts ?? 0)
        if totalWorkouts > 0 {
            return experiencedUserFallbackGoals()
        }
        return [beginnerSocialQuest(), beginnerWorkoutQuest(), beginnerProgramQuest()]
    }
    
    private func experiencedUserFallbackGoals() -> [DailyQuest] {
        [
            DailyQuest(
                id: UUID(),
                questKey: QuestKey.completeWorkout.rawValue,
                title: "Crush a Workout",
                description: "Complete any workout today",
                icon: "dumbbell.fill",
                category: "workout",
                targetValue: 1, currentValue: 0,
                targetUnit: "workout",
                xpReward: 30, leaguePoints: 20,
                difficulty: "easy",
                isCompleted: false, completedAt: nil,
                funLabel: "💪 Just show up",
                verificationType: "auto"
            ),
            DailyQuest(
                id: UUID(),
                questKey: QuestKey.walk5kSteps.rawValue,
                title: "Halfway There",
                description: "Walk 5,000 steps today",
                icon: "figure.walk.motion",
                category: "steps",
                targetValue: 5000, currentValue: 0,
                targetUnit: "steps",
                xpReward: 30, leaguePoints: 18,
                difficulty: "medium",
                isCompleted: false, completedAt: nil,
                funLabel: "👟 Solid effort",
                verificationType: "auto"
            ),
            DailyQuest(
                id: UUID(),
                questKey: QuestKey.logBreakfast.rawValue,
                title: "Breakfast Check-in",
                description: "Log your breakfast to start the day right",
                icon: "sunrise.fill",
                category: "nutrition",
                targetValue: 1, currentValue: 0,
                targetUnit: "meal",
                xpReward: 20, leaguePoints: 12,
                difficulty: "easy",
                isCompleted: false, completedAt: nil,
                funLabel: "🌅 Morning fuel",
                verificationType: "manual"
            )
        ]
    }
    
    // MARK: - Fetch Daily Quests
    
    func fetchDailyQuests(force: Bool = false) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("📋 [QUESTS] ⚠️ No currentUser — skipping fetch", category: .general)
            if quests.isEmpty {
                self.quests = defaultGoals()
            }
            return
        }
        
        // Throttle
        if !force, let cacheDate = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
           Date().timeIntervalSince(cacheDate) < cacheDuration,
           !quests.isEmpty {
            AppLogger.debug("📋 [QUESTS] Throttled — using cache (\(quests.count) quests)", category: .general)
            return
        }
        
        AppLogger.debug("📋 [QUESTS] Fetching daily quests for user \(userId.uuidString.prefix(8))...", category: .general)
        isLoading = true
        error = nil
        
        // Gather user context for personalized quest selection
        let ctx = await gatherUserContext()
        
        // Day 1: show hardcoded beginner quests instead of server quests
        if ctx.totalWorkouts == 0 {
            AppLogger.info("📋 [QUESTS] Day 1 — showing beginner goal cards", category: .general)
            self.quests = [beginnerSocialQuest(), beginnerWorkoutQuest(), beginnerProgramQuest()]
            self.isLoading = false
            return
        }
        
        do {
            struct GetDailyQuestsParams: Encodable {
                let p_user_id: String
                let p_timezone: String
                let p_has_program: Bool
                let p_has_friends: Bool
                let p_has_challenge: Bool
                let p_step_goal: Int
                let p_fitness_goal: String
                let p_is_subscriber: Bool
                let p_workout_streak: Int
                let p_total_workouts: Int
                let p_preferred_time: String
                let p_avg_duration: Int
                let p_has_weight_log: Bool
                let p_hydration_active: Bool
                let p_league_rank: Int
                let p_active_step_challenge_target: Int?
                let p_suggested_split: String?
                let p_fatigued_regions: [String]?

                enum CodingKeys: String, CodingKey {
                    case p_user_id, p_timezone, p_has_program, p_has_friends, p_has_challenge
                    case p_step_goal, p_fitness_goal, p_is_subscriber, p_workout_streak
                    case p_total_workouts, p_preferred_time, p_avg_duration
                    case p_has_weight_log, p_hydration_active, p_league_rank
                    case p_active_step_challenge_target
                    case p_suggested_split, p_fatigued_regions
                }
                
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(p_user_id, forKey: .p_user_id)
                    try container.encode(p_timezone, forKey: .p_timezone)
                    try container.encode(p_has_program, forKey: .p_has_program)
                    try container.encode(p_has_friends, forKey: .p_has_friends)
                    try container.encode(p_has_challenge, forKey: .p_has_challenge)
                    try container.encode(p_step_goal, forKey: .p_step_goal)
                    try container.encode(p_fitness_goal, forKey: .p_fitness_goal)
                    try container.encode(p_is_subscriber, forKey: .p_is_subscriber)
                    try container.encode(p_workout_streak, forKey: .p_workout_streak)
                    try container.encode(p_total_workouts, forKey: .p_total_workouts)
                    try container.encode(p_preferred_time, forKey: .p_preferred_time)
                    try container.encode(p_avg_duration, forKey: .p_avg_duration)
                    try container.encode(p_has_weight_log, forKey: .p_has_weight_log)
                    try container.encode(p_hydration_active, forKey: .p_hydration_active)
                    try container.encode(p_league_rank, forKey: .p_league_rank)
                    if let stepTarget = p_active_step_challenge_target, stepTarget > 0 {
                        try container.encode(stepTarget, forKey: .p_active_step_challenge_target)
                    }
                    if let split = p_suggested_split, !split.isEmpty {
                        try container.encode(split, forKey: .p_suggested_split)
                    }
                    if let regions = p_fatigued_regions, !regions.isEmpty {
                        try container.encode(regions, forKey: .p_fatigued_regions)
                    }
                }
            }
            
            let params = GetDailyQuestsParams(
                p_user_id: userId.uuidString,
                p_timezone: TimeZone.current.identifier,
                p_has_program: ctx.hasProgram,
                p_has_friends: ctx.hasFriends,
                p_has_challenge: ctx.hasChallenge,
                p_step_goal: ctx.stepGoal,
                p_fitness_goal: ctx.fitnessGoal,
                p_is_subscriber: PremiumManager.shared.isPremiumUser,
                p_workout_streak: ctx.workoutStreak,
                p_total_workouts: ctx.totalWorkouts,
                p_preferred_time: ctx.preferredTime,
                p_avg_duration: ctx.avgDuration,
                p_has_weight_log: ctx.hasWeightLog,
                p_hydration_active: ctx.hydrationActive,
                p_league_rank: ctx.leagueRank,
                p_active_step_challenge_target: ctx.activeStepChallengeTarget > 0 ? ctx.activeStepChallengeTarget : nil,
                p_suggested_split: ctx.suggestedSplit,
                p_fatigued_regions: ctx.fatiguedRegions.isEmpty ? nil : ctx.fatiguedRegions
            )
            
            let response: DailyQuestsResponse = try await SupabaseManager.shared.supabaseClient
                .rpc("get_daily_quests", params: params)
                .execute()
                .value
            
            let serverQuests = response.quests ?? []
            self.quests = serverQuests.isEmpty ? defaultGoals() : serverQuests
            self.allComplete = response.allComplete
            self.bonusXp = response.bonusXp
            self.bonusLeaguePoints = response.bonusLeaguePoints
            self.questStreak = response.streak
            self.longestStreak = response.longestStreak
            self.totalCompleted = response.totalCompleted
            self.difficultyProfile = response.difficultyProfile
            
            cacheQuests()
            
            #if DEBUG
            let completed = quests.filter(\.isCompleted).count
            AppLogger.debug("📋 [QUESTS] Fetched \(quests.count) quests (\(completed)/\(quests.count) done), streak: \(response.streak), profile: \(response.difficultyProfile ?? "?")", category: .general)
            for q in quests {
                AppLogger.info("   → \(q.questKey): \"\(q.title)\" [\(q.difficulty)] \(q.isCompleted ? "✅" : "⬜")", category: .general)
            }
            #endif
            
            // If the watch_ads quest is active and not completed, preload a rewarded ad
            if hasQuest(.watchAds) {
                AdManager.shared.prepareRewardedAd()
            }
            
        } catch {
            self.error = error.localizedDescription
            
            // Extract Postgres error code for diagnostics (e.g. "42703" = undefined column)
            let errorString = String(describing: error)
            let isStreakFieldError = errorString.contains("current_streak") || errorString.contains("v_streak")
            let isAuthError = errorString.localizedCaseInsensitiveContains("not authenticated") || errorString.localizedCaseInsensitiveContains("JWT")
            
            if isStreakFieldError {
                AppLogger.warning("[QUESTS] Known v_streak field error — SQL migration may not be deployed yet. Error: \(error.localizedDescription)", category: .general)
            } else if isAuthError {
                AppLogger.warning("[QUESTS] Auth expired during quest fetch — will retry on next session", category: .general)
            } else {
                AppLogger.error("[QUESTS] Failed to fetch: \(error)", category: .general)
                AppLogger.error("[QUESTS] Error details (raw): \(errorString)", category: .general)
            }
            
            if quests.isEmpty {
                AppLogger.info("[QUESTS] Fetch failed with empty goals — activating defaults (\(isStreakFieldError ? "streak_field" : isAuthError ? "auth" : "unknown") cause)", category: .general)
                self.quests = defaultGoals()
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Update Quest Progress
    
    /// Call this when the user completes an action that might advance a quest.
    /// The function checks if the quest is active today before making the RPC call.
    func reportProgress(questKey: QuestKey, increment: Int = 1) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Only call RPC if this quest is actually assigned today and not yet done
        guard hasQuest(questKey) else {
            #if DEBUG
            AppLogger.debug("📋 [QUESTS] Quest '\(questKey.rawValue)' not active today, skipping", category: .general)
            #endif
            return
        }
        
        do {
            let result: QuestProgressResult = try await SupabaseManager.shared.supabaseClient
                .rpc("update_quest_progress", params: [
                    "p_user_id": userId.uuidString,
                    "p_quest_key": questKey.rawValue,
                    "p_increment": "\(increment)",
                    "p_timezone": TimeZone.current.identifier
                ])
                .execute()
                .value
            
            guard result.success else {
                #if DEBUG
                AppLogger.debug("📋 [QUESTS] Progress update returned false: \(result.reason ?? "unknown")", category: .general)
                #endif
                return
            }
            
            // Update local state optimistically
            if let newValue = result.newValue,
               let idx = quests.firstIndex(where: { $0.questKey == questKey.rawValue }) {
                let old = quests[idx]
                let nowComplete = result.justCompleted ?? false
                
                quests[idx] = DailyQuest(
                    id: old.id,
                    questKey: old.questKey,
                    title: old.title,
                    description: old.description,
                    icon: old.icon,
                    category: old.category,
                    targetValue: old.targetValue,
                    currentValue: newValue,
                    targetUnit: old.targetUnit,
                    xpReward: old.xpReward,
                    leaguePoints: old.leaguePoints,
                    difficulty: old.difficulty,
                    isCompleted: nowComplete,
                    completedAt: nowComplete ? ISO8601DateFormatter().string(from: Date()) : nil,
                    funLabel: old.funLabel,
                    verificationType: old.verificationType
                )
                
                // Trigger celebration if quest just completed
                if nowComplete {
                    lastCompletedQuest = quests[idx]
                    showQuestCompletionCelebration = true
                    
                    // Award XP to user profile for quest completion
                    if old.xpReward > 0 {
                        UserManager.shared.addXP(Int32(old.xpReward))
                    }
                    
                    // Award league points for quest completion
                    await WeeklyLeagueService.shared.addPoints(source: .challengeTarget)
                    
                    // Auto-hide celebration
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        showQuestCompletionCelebration = false
                    }
                    
                    #if DEBUG
                    AppLogger.info("✅ [QUESTS] Completed '\(questKey.rawValue)' (+\(old.xpReward) XP, +\(old.leaguePoints) league pts)", category: .general)
                    #endif
                }
                
                // Check if bonus was just unlocked (all 3 complete)
                if result.bonusUnlocked == true {
                    allComplete = true
                    bonusXp = result.bonusXp ?? 50
                    bonusLeaguePoints = result.bonusLeaguePoints ?? 30
                    
                    // Award bonus XP to user profile
                    if bonusXp > 0 {
                        UserManager.shared.addXP(Int32(bonusXp))
                    }
                    
                    // Celebrate bonus!
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        showBonusCelebration = true
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        showBonusCelebration = false
                    }
                    
                    #if DEBUG
                    AppLogger.debug("🎉 [QUESTS] ALL QUESTS COMPLETE! Bonus: +\(bonusXp) XP, +\(bonusLeaguePoints) league pts", category: .general)
                    #endif
                }
                
                cacheQuests()
            }
            
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [QUESTS] Failed to update progress: \(error)", category: .general)
            #endif
            // Silently fail — quest progress is best-effort
        }
    }
    
    // MARK: - Convenience Methods for Common Actions
    
    /// Call when a workout is completed
    func onWorkoutCompleted(durationSeconds: Int, totalSets: Int) async {
        // General workout completion
        await reportProgress(questKey: .completeWorkout)
        await reportProgress(questKey: .complete2Workouts)
        
        // Sets quests (V2 thresholds: 15 and 25)
        if totalSets >= 15 {
            await reportProgress(questKey: .exerciseSets15, increment: totalSets)
        }
        if totalSets >= 25 {
            await reportProgress(questKey: .exerciseSets25, increment: totalSets)
        }
        // Legacy keys (in case old quests are still assigned)
        if totalSets >= 10 {
            await reportProgress(questKey: .exerciseSets10, increment: totalSets)
        }
        if totalSets >= 20 {
            await reportProgress(questKey: .exerciseSets20, increment: totalSets)
        }
        
        // Duration quest (30+ minutes)
        if durationSeconds >= 1800 {
            await reportProgress(questKey: .workout30Min, increment: durationSeconds / 60)
        }
        
        // Early bird quest (completed before noon)
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            await reportProgress(questKey: .earlyBirdWorkout)
        }
    }
    
    /// Call when a program day is completed
    func onProgramDayCompleted() async {
        await reportProgress(questKey: .completeProgramDay)
        // Also counts as a general workout
        await reportProgress(questKey: .completeWorkout)
    }
    
    /// Call when a workout targets specific body parts. `bodyParts` is the set
    /// of muscle-group strings pulled from `WorkoutExercise.safeMuscleGroups`
    /// (e.g. "chest", "upper chest", "lats", "front delts", "quads"). We match
    /// on substring so the full exercise-database vocabulary is covered — the
    /// previous exact-match set missed "lats", "delts", "hamstrings" variants,
    /// etc., which was preventing upper/lower-body quests from progressing.
    func onWorkoutWithFocus(bodyParts: Set<String>) async {
        let normalized = bodyParts.map { $0.lowercased() }

        // Any token that contributes to the upper body. Includes delt/trap/lat
        // variants so "Front Delts" / "Upper Back" / "Side Delts" all count.
        let upperTokens: [String] = [
            "chest", "back", "lat", "shoulder", "delt", "trap",
            "arm", "bicep", "tricep", "forearm"
        ]
        let lowerTokens: [String] = [
            "leg", "quad", "hamstring", "glute", "calf", "calves", "hip", "thigh"
        ]

        let isUpperBody = normalized.contains { muscle in
            upperTokens.contains { muscle.contains($0) }
        }
        let isLowerBody = normalized.contains { muscle in
            lowerTokens.contains { muscle.contains($0) }
        }

        if isUpperBody {
            await reportProgress(questKey: .upperBodyWorkout)
        }
        if isLowerBody {
            await reportProgress(questKey: .lowerBodyWorkout)
        }
    }
    
    /// Call when a meal is logged
    func onMealLogged(mealType: String? = nil) async {
        // Specific meal quests
        if let type = mealType?.lowercased() {
            switch type {
            case "breakfast":
                await reportProgress(questKey: .logBreakfast)
            case "lunch":
                await reportProgress(questKey: .logLunch)
            case "dinner":
                await reportProgress(questKey: .logDinner)
            case "snack":
                await reportProgress(questKey: .logSnack)
            default:
                break
            }
        }
        
        // General meal logging (for 3-meals quest)
        await reportProgress(questKey: .log3Meals)
        // Legacy
        await reportProgress(questKey: .logMeal)
    }
    
    /// Call when a high-protein meal is logged (30g+ protein)
    func onHighProteinMealLogged() async {
        await reportProgress(questKey: .logHighProteinMeal)
    }
    
    /// Call when water is logged
    func onWaterLogged(glasses: Int = 1) async {
        await reportProgress(questKey: .logWater3, increment: glasses)
        await reportProgress(questKey: .logWater8, increment: glasses)
        // Legacy
        await reportProgress(questKey: .logWater)
    }
    
    /// Call when step count updates (pass total steps for today).
    /// Reports incremental progress for all active step quests regardless of threshold.
    func onStepsUpdated(todaySteps: Int) async {
        let delta = todaySteps - lastReportedSteps
        guard delta > 0 else { return }
        
        // Report progress for ALL step quests — the server caps at target_value
        await reportProgress(questKey: .walk3kSteps, increment: delta)
        await reportProgress(questKey: .walk5kSteps, increment: delta)
        await reportProgress(questKey: .walk7500Steps, increment: delta)
        await reportProgress(questKey: .walk10kSteps, increment: delta)
        
        // Check if step goal was just hit
        if todaySteps >= HealthKitManager.shared.stepGoal && lastReportedSteps < HealthKitManager.shared.stepGoal {
            await reportProgress(questKey: .hitStepGoal)
        }
        
        lastReportedSteps = todaySteps
        persistLastReportedSteps()
    }
    
    /// Call when step goal is hit
    func onStepGoalHit() async {
        await reportProgress(questKey: .hitStepGoal)
    }
    
    /// Call when a challenge is sent
    func onChallengeSent() async {
        await reportProgress(questKey: .sendChallenge)
        await reportProgress(questKey: .start1v1Challenge)
        await reportProgress(questKey: .startFirstChallenge)
    }
    
    /// Call when a personal record is achieved
    func onPersonalRecord() async {
        await reportProgress(questKey: .beatPersonalRecord)
    }
    
    /// Call when weight is logged
    func onWeightLogged() async {
        await reportProgress(questKey: .logWeight)
    }
    
    /// Call when reacting to a friend's workout
    func onWorkoutReaction() async {
        await reportProgress(questKey: .reactToWorkout)
    }
    
    /// Call when inviting a friend to the app
    func onFriendInvited() async {
        await reportProgress(questKey: .inviteFriend)
    }
    
    /// Call when sending a friend request
    func onFriendRequestSent() async {
        await reportProgress(questKey: .addFriend)
    }
    
    /// Call when sharing a workout with a friend
    func onWorkoutShared() async {
        await reportProgress(questKey: .shareWorkout)
    }
    
    /// Call when favoriting a workout
    func onWorkoutFavorited() async {
        await reportProgress(questKey: .favoriteAWorkout)
    }
    
    /// Call when user watches a rewarded video ad (for the "Watch 2 Videos" quest)
    func onAdWatched() async {
        await reportProgress(questKey: .watchAds)
    }
    
    /// Call when logging a cardio session
    func onCardioLogged() async {
        await reportProgress(questKey: .logCardio)
    }
    
    /// Call when viewing progress/stats page
    func onProgressViewed() async {
        await reportProgress(questKey: .checkProgress)
    }
    
    /// Call when protein goal is hit
    func onProteinGoalHit() async {
        await reportProgress(questKey: .hitProteinGoal)
    }
    
    /// Call with total protein grams eaten today for incremental progress
    func onProteinProgress(totalGrams: Int) async {
        guard hasQuest(.hitProteinGoal),
              let idx = quests.firstIndex(where: { $0.questKey == QuestKey.hitProteinGoal.rawValue }) else { return }
        let quest = quests[idx]
        let needed = totalGrams - quest.currentValue
        if needed > 0 {
            await reportProgress(questKey: .hitProteinGoal, increment: needed)
        }
    }
    
    /// Check and report "perfect day" (workout + 3 meals + step goal)
    func checkPerfectDay(hasWorkout: Bool, mealCount: Int, stepGoalHit: Bool) async {
        var actions = 0
        if hasWorkout { actions += 1 }
        if mealCount >= 3 { actions += 1 }
        if stepGoalHit { actions += 1 }
        
        if actions >= 3 {
            await reportProgress(questKey: .perfectDay, increment: actions)
        }
    }
    
    // MARK: - New Metric-Driven Quest Hooks
    
    func onStretchCompleted(durationSeconds: Int) async {
        await reportProgress(questKey: .stretchSession, increment: durationSeconds / 60)
    }
    
    func onActiveMinutesUpdated(minutes: Int) async {
        await reportProgress(questKey: .activeMinutes30, increment: minutes)
    }
    
    func onCaloriesBurned(kcal: Int) async {
        await reportProgress(questKey: .burn300Calories, increment: kcal)
    }
    
    func onSleepLogged(hours: Double) async {
        if hours >= 7.0 {
            await reportProgress(questKey: .sleep7Hours)
        }
    }
    
    func onVolumePRBeat(totalVolume: Double) async {
        await reportProgress(questKey: .beatVolumePR)
    }
    
    func onStreakMaintained() async {
        await reportProgress(questKey: .maintainStreak)
    }
    
    func onLeagueWorkoutLogged() async {
        await reportProgress(questKey: .league3Workouts)
    }
    
    func onAllMacrosLogged() async {
        await reportProgress(questKey: .logAllMacros)
    }
    
    func onHydrationBeforeNoon(glasses: Int) async {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 && glasses >= 4 {
            await reportProgress(questKey: .hydrationBeforeNoon, increment: glasses)
        }
    }
    
    func onWeeklyWeighIn() async {
        await reportProgress(questKey: .weeklyWeighIn)
        await reportProgress(questKey: .logWeight)
    }
    
    // MARK: - Step Delta Persistence
    
    private func restoreLastReportedSteps() {
        let todayKey = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let savedDate = UserDefaults.standard.double(forKey: lastReportedStepsDateKey)
        if savedDate == todayKey {
            lastReportedSteps = UserDefaults.standard.integer(forKey: lastReportedStepsKey)
        } else {
            lastReportedSteps = 0
        }
    }
    
    private func persistLastReportedSteps() {
        let todayKey = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        UserDefaults.standard.set(lastReportedSteps, forKey: lastReportedStepsKey)
        UserDefaults.standard.set(todayKey, forKey: lastReportedStepsDateKey)
    }
    
    // MARK: - Cache
    
    private func cacheQuests() {
        let cacheData = DailyQuestsResponse(
            quests: quests,
            allComplete: allComplete,
            bonusXp: bonusXp,
            bonusLeaguePoints: bonusLeaguePoints,
            questDate: "", // Not needed for cache
            streak: questStreak,
            longestStreak: longestStreak,
            totalCompleted: totalCompleted,
            difficultyProfile: difficultyProfile
        )
        
        if let data = try? JSONEncoder().encode(cacheData) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheDateKey)
        }
    }
    
    private func loadCachedQuests() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(DailyQuestsResponse.self, from: data) else {
            self.quests = defaultGoals()
            return
        }
        
        // Only load cache if it's from today
        let today = Calendar.current.startOfDay(for: Date())
        if let cacheDate = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
           Calendar.current.isDate(cacheDate, inSameDayAs: today) {
            let cachedQuests = cached.quests ?? []
            self.quests = cachedQuests.isEmpty ? defaultGoals() : cachedQuests
            self.allComplete = cached.allComplete
            self.bonusXp = cached.bonusXp
            self.bonusLeaguePoints = cached.bonusLeaguePoints
            self.questStreak = cached.streak
            self.longestStreak = cached.longestStreak
            self.totalCompleted = cached.totalCompleted
            self.difficultyProfile = cached.difficultyProfile
        } else {
            self.quests = defaultGoals()
        }
    }
}
