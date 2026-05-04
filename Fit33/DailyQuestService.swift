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
import CoreData

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
    /// Smart Adaptive Daily Goals (20260601): "free" or "pro". Free clients
    /// never see "pro" rows because the RPC tier-gates them server-side.
    let tier: String?
    /// Smart Adaptive Daily Goals (20260607): set by `claim_double_xp_day`
    /// (Pro 1/week). The server-side `apply_double_xp_on_complete` trigger
    /// awards an extra `xp_reward` worth of XP on completion.
    let doubleXp: Bool?
    /// User-authored quest from `submit_custom_quest` (Pro 1/day, manual).
    let isCustom: Bool?
    /// Stamped by `reroll_daily_quest` so the UI can show "Rerolled".
    let isReroll: Bool?
    /// Daily Mission Unification (20260703 — Phase 1): TRUE when the
    /// server's Layer 7 (red-day recovery elevation) or Layer 8
    /// (debt booster) chose this quest specifically because of the
    /// brief signals the client passed in. iOS uses this to render
    /// the "← from your brief" chip on the quest card. Optional —
    /// nil for legacy slates returned by pre-v4 server overloads.
    let isBriefInfluenced: Bool?

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
        case tier
        case doubleXp = "double_xp"
        case isCustom = "is_custom"
        case isReroll = "is_reroll"
        case isBriefInfluenced = "is_brief_influenced"
    }

    init(
        id: UUID, questKey: String, title: String, description: String,
        icon: String, category: String, targetValue: Int, currentValue: Int,
        targetUnit: String, xpReward: Int, leaguePoints: Int,
        difficulty: String, isCompleted: Bool, completedAt: String?,
        funLabel: String?, verificationType: String?,
        tier: String? = nil, doubleXp: Bool? = nil,
        isCustom: Bool? = nil, isReroll: Bool? = nil,
        isBriefInfluenced: Bool? = nil
    ) {
        self.id = id
        self.questKey = questKey
        self.title = title
        self.description = description
        self.icon = icon
        self.category = category
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.targetUnit = targetUnit
        self.xpReward = xpReward
        self.leaguePoints = leaguePoints
        self.difficulty = difficulty
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.funLabel = funLabel
        self.verificationType = verificationType
        self.tier = tier
        self.doubleXp = doubleXp
        self.isCustom = isCustom
        self.isReroll = isReroll
        self.isBriefInfluenced = isBriefInfluenced
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

    /// Smart Adaptive Daily Goals (20260603): xp_reward in `quest_templates`
    /// is already pre-multiplied by verification_type (auto×1.5, social×1.0,
    /// manual×0.7). Surface that as a soft sub-label on the quest card so
    /// users understand WHY auto-tracked quests reward more — and feel the
    /// tradeoff when they pick a manual one.
    var verificationXpMultiplierLabel: String? {
        switch verificationType {
        case "auto":   return "1.5× XP — auto-tracked"
        case "social": return "1.0× XP — social"
        case "manual": return "0.7× XP — honor system"
        default:       return nil
        }
    }

    /// Smart Adaptive Daily Goals (20260607): tag used by quest cards when
    /// the user has activated a Pro Double-XP day for this quest's date.
    var doubleXpBadge: String? {
        (doubleXp ?? false) ? "✨ 2× XP today" : nil
    }

    /// Custom user-authored Pro quest — can be rerolled but never
    /// auto-completed. Allows the UI to show a "manual mark complete" CTA.
    var isCustomPro: Bool {
        isCustom ?? false
    }

    /// Just rerolled — UI can pulse the card or show a tag.
    var wasRerolled: Bool {
        isReroll ?? false
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
    
    /// Smart, content-aware emoji for the quest. Resolution order:
    ///   1. Exact `quest_key` mapping (curated for every canonical key)
    ///   2. Keyword scan of `title` + `description` (priority-ordered table —
    ///      "strawberry" wins over "berry", "heart health" wins over "heart")
    ///   3. Leading emoji of `fun_label` (server-curated fallback)
    ///   4. Category fallback (workout / nutrition / social / steps / etc.)
    ///   5. Generic ⭐
    /// See `QuestEmojiResolver` at the bottom of this file for the tables.
    var categoryEmoji: String {
        QuestEmojiResolver.resolve(
            questKey: questKey,
            title: title,
            description: description,
            category: category,
            funLabel: funLabel
        )
    }

    /// Alias for `categoryEmoji` that better describes the new behavior —
    /// kept distinct so future call sites can opt in by name.
    var smartEmoji: String { categoryEmoji }
    
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
    
    // MARK: - Smart Adaptive Daily Goals (20260604)
    // Strava PRs / outdoor cardio (auto-verified by verify_strava_quests_for_today)
    case beatYour5kPR = "beat_your_5k_pr"
    case negativeSplitRun = "negative_split_run"
    case runOutside8km = "run_outside_8km"
    case cycleOutside30km = "cycle_outside_30km"
    case completeStravaSegment = "complete_strava_segment"
    // Wearable-driven (auto-verified by verify_wearable_quests_for_today)
    case matchYesterdayStrain = "match_yesterday_strain"
    case walkWhenRed = "walk_when_red"
    // Friend-named social (manual + social verification)
    case doFriendWorkout = "do_friend_workout"
    case commentOnFriendsWorkout = "comment_on_friends_workout"
    case start1v1WithTopFriend = "start_1v1_with_top_friend"
    case reactTo3Workouts = "react_to_3_workouts"

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
        /// Active-challenge types the user is currently competing on. Powers the
        /// server-side CHALLENGE OVERRIDE in `get_daily_quests` (migration
        /// 20260423). Subset of: steps, walk, run, active_minutes, calories,
        /// hydrate, protein, workout_streak, lift. De-duped + stable order so
        /// the RPC cache stays warm across identical inputs.
        let activeChallengeTypes: [String]

        // ── Smart Adaptive Daily Goals (20260605) ──────────────────────────
        /// Per-integration connection state. Drives the new
        /// `requires_context = 'has_strava' | 'has_whoop' | 'has_oura' |
        /// 'has_fitbit'` predicates so the server can selectively surface
        /// integration-specific quests (Strava PRs, WHOOP strain matching,
        /// Oura/Fitbit walk-when-red, etc.) without firing for users who
        /// can't action them.
        let stravaConnected: Bool
        let whoopConnected: Bool
        let ouraConnected: Bool
        let fitbitConnected: Bool

        /// 28-day activity bucket distribution (strength/cardio/walk/stretch).
        /// Encoded into the `p_activity_mix` JSONB hint
        /// (`{ "dominant": "...", "least": "..." }`). The server falls back
        /// to `user_activity_mix` (computed nightly) when the JSONB is empty.
        let activityMix28d: ActivityMixSnapshot

        /// Best target from the user's active step / walk / run challenges
        /// against a friend. Powers the "Beat <Friend>: 8.4K" copy when
        /// the server picks a step quest in slot N.
        let friendStepTarget: Int
        /// Friend display name for the step copy. May be `nil` even when
        /// `friendStepTarget > 0` (group challenge, etc.) — server falls back
        /// to "your friend" in that case.
        let friendName: String?

        /// Most recent shared workout from a top friend that we'd like to
        /// surface as the "Do <Friend>'s <Title>" slot. The full bundle is
        /// what the server needs for `do_friend_workout` copy + deep-linking.
        let friendTopWorkoutId: UUID?
        let friendTopWorkoutTitle: String?
        let friendTopWorkoutSplit: String?
        /// Whether the friend's workout split equals the user's
        /// `suggestedSplit`. When TRUE the RPC writes the
        /// recovery-aware copy "You're due for <split> — do <Friend>'s".
        let friendTopWorkoutMatchesRecommendation: Bool

        /// Pro tier flag — drives access to premium-tier templates.
        /// 20260619: slot count is now locked at 3 for all tiers (server
        /// migration `20260619_lock_daily_quests_to_3_slots.sql`); Pro
        /// no longer expands to 5 slots.
        let questTier: String
    }

    /// Shared snapshot of a user's 28-day session distribution. Computed
    /// client-side from Core Data + cardio_workouts so the RPC has a fresh
    /// hint before the nightly `compute_user_quest_personalization` job
    /// hydrates `user_activity_mix`.
    struct ActivityMixSnapshot {
        let totalSessions: Int
        let strengthShare: Double
        let cardioShare: Double
        let walkShare: Double
        let stretchShare: Double

        var dominant: String? {
            guard totalSessions > 0 else { return nil }
            let pairs: [(String, Double)] = [
                ("strength", strengthShare),
                ("cardio",   cardioShare),
                ("walk",     walkShare),
                ("stretch",  stretchShare)
            ]
            return pairs.max(by: { $0.1 < $1.1 })?.0
        }
        var least: String? {
            guard totalSessions > 0 else { return nil }
            let pairs: [(String, Double)] = [
                ("strength", strengthShare),
                ("cardio",   cardioShare),
                ("walk",     walkShare),
                ("stretch",  stretchShare)
            ]
            // Ignore zero-share buckets — they'd always "win" the least
            // comparison and bias the exploration bump toward something
            // the user doesn't have data for at all.
            let nonZero = pairs.filter { $0.1 > 0.0 }
            return nonZero.min(by: { $0.1 < $1.1 })?.0
        }

        /// JSONB payload sent as `p_activity_mix`.
        var rpcHint: [String: String] {
            var dict: [String: String] = [:]
            if let d = dominant { dict["dominant"] = d }
            if let l = least    { dict["least"]    = l }
            return dict
        }

        static let empty = ActivityMixSnapshot(
            totalSessions: 0,
            strengthShare: 0,
            cardioShare: 0,
            walkShare: 0,
            stretchShare: 0
        )
    }

    /// Bundle for a "do friend's workout" candidate — passed to the RPC
    /// so it can write split-recommendation-aware copy.
    struct FriendWorkoutSeed {
        let friendName: String
        let workoutId: UUID
        let title: String
        /// One of "push" | "pull" | "legs" | "upper" | "full" | "core_cardio"
        /// (matches the contract of `p_suggested_split`).
        let split: String
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
        // Phase 7 (2026-04-27 — Daily Mission Unification): when V2
        // has fired a `best_workout_time` insight in the last 14 days,
        // prefer it over the legacy `UserBehaviorLearningEngine`
        // preference. The V2 insight is significance-gated
        // (Pearson n>=12, delta>=15%, p<=0.15) so it only overrides
        // when the signal is real. Falls back to the legacy
        // preference when no insight is available OR V2 is off.
        let preferredTime: String = {
            guard AppConfig.FeatureFlags.personalizedInsightsV2 else {
                return UserBehaviorLearningEngine.shared.userPreferences?.preferredTimeOfDay ?? "any"
            }
            // Look for the V2 best-workout-time insight by title
            // prefix (set in `PersonalizedInsightsService
            // .detectBestWorkoutTime`). We accept any of the three
            // canonical titles below and parse the slot from the
            // message text — a tiny coupling cost vs. an extra
            // column on `user_personalized_insights`.
            let candidate = PersonalizedInsightsService.shared.activeInsights.first { insight in
                insight.title == "You crush mornings."
                    || insight.title == "Afternoon is your sweet spot."
                    || insight.title == "Evening lifts hit hardest."
            }
            if let candidate {
                let lower = candidate.message.lowercased()
                if lower.contains("morning") { return "morning" }
                if lower.contains("afternoon") { return "afternoon" }
                if lower.contains("evening") { return "evening" }
            }
            return UserBehaviorLearningEngine.shared.userPreferences?.preferredTimeOfDay ?? "any"
        }()
        let avgDuration = UserBehaviorLearningEngine.shared.userPreferences?.preferredWorkoutDuration ?? 45
        let hasWeightLog = WeightTrackingService.shared.statistics != nil
        let hydrationActive = HydrationService.shared.settings.dailyGoalMl > 0
        let leagueRank = WeeklyLeagueService.shared.standing?.myRank ?? 0

        // Collect active-challenge types (both 1v1 + group). Sorted + de-duped
        // so the RPC sees a stable input and skips re-selection on re-fetch.
        // Types mirror `ChallengeType.rawValue` — keep in sync with the SQL
        // override table in migration 20260423.
        let oneOnOneTypes  = ChallengeService.shared.activeChallenges.map { $0.challengeType }
        let groupTypes     = ChallengeService.shared.activeGroupChallenges.map { $0.challengeType }
        let activeChallengeTypes = Array(Set(oneOnOneTypes + groupTypes))
            .filter { !$0.isEmpty }
            .sorted()

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

        // ── Smart Adaptive Daily Goals (20260605) ──────────────────────────
        // Wearable connection bools (separated for finer-grained server
        // gating). The aggregate `p_has_connected_wearable` flag still
        // covers the legacy `has_wearable` requires_context.
        let stravaConn = StravaService.shared.isConnected
        let whoopConn  = WhoopService.shared.isConnected
        let ouraConn   = OuraService.shared.isConnected
        let fitbitConn = FitbitService.shared.isConnected

        // 28-day activity-mix hint. Computed off-main via Core Data
        // background context — fast (single fetch) and the server
        // already falls back to the persisted `user_activity_mix` row.
        let activityMix = await Self.computeActivityMix28d()

        // Friend step / workout seeds. Best one-on-one step challenge
        // target gives us "Beat <Friend>: 8.4K" copy; the friend's most
        // recent shared workout (split-matched if possible) gives us
        // "Due for <split> — do <Friend>'s".
        let friendStepSeed = friendStepChallengeSeed()
        let friendWorkoutSeed = await friendWorkoutSeed(suggestedSplit: suggestedSplit)
        let matches = friendWorkoutSeed.flatMap { seed -> Bool? in
            guard let s = suggestedSplit, !s.isEmpty else { return false }
            return seed.split == s
        } ?? false

        let questTier = PremiumManager.shared.isPremiumUser ? "pro" : "free"

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
            fatiguedRegions: fatiguedRegions,
            activeChallengeTypes: activeChallengeTypes,
            stravaConnected: stravaConn,
            whoopConnected: whoopConn,
            ouraConnected: ouraConn,
            fitbitConnected: fitbitConn,
            activityMix28d: activityMix,
            friendStepTarget: friendStepSeed?.target ?? 0,
            friendName: friendStepSeed?.name ?? friendWorkoutSeed?.friendName,
            friendTopWorkoutId: friendWorkoutSeed?.workoutId,
            friendTopWorkoutTitle: friendWorkoutSeed?.title,
            friendTopWorkoutSplit: friendWorkoutSeed?.split,
            friendTopWorkoutMatchesRecommendation: matches,
            questTier: questTier
        )
    }

    // MARK: - Smart Adaptive Daily Goals: helpers
    //
    // These helpers feed the new RPC parameters introduced in migration
    // 20260605. They're best-effort — the server has authoritative copies
    // (`user_activity_mix`, `friend_activity_feed`, etc.) and falls back
    // gracefully when a hint is missing.

    /// Builds the per-user 28-day activity-mix snapshot. Workouts come from
    /// Core Data (off-main background context), cardio sessions come from
    /// the live `StravaService` cache for snappy boot-time hints. Buckets
    /// match the server-side mapping in `compute_user_quest_personalization`:
    ///
    ///   workouts              → strength
    ///   cardio activity_type IN ('walk', 'hike')  → walk
    ///   cardio activity_type IN ('yoga','stretch','flexibility') → stretch
    ///   any other cardio_workouts row             → cardio
    private static func computeActivityMix28d() async -> ActivityMixSnapshot {
        // Workout counts from Core Data — `WorkoutFetcher` already manages
        // the bg context + threadsafe predicate evaluation.
        let cal = Calendar.current
        let now = Date()
        guard let cutoff = cal.date(byAdding: .day, value: -28, to: now) else {
            return .empty
        }

        let strengthCount: Int = await Task.detached {
            let bg = PersistenceController.shared.container.newBackgroundContext()
            return await bg.perform {
                let req: NSFetchRequest<Workout> = Workout.fetchRequest()
                req.predicate = NSPredicate(
                    format: "isCompleted == true AND date >= %@ AND date < %@",
                    cutoff as NSDate, now as NSDate
                )
                req.includesSubentities = false
                return (try? bg.count(for: req)) ?? 0
            }
        }.value

        // Cardio breakdown — read from local Strava cache (already a 30-day
        // window). Intentionally lightweight; the nightly job is the
        // source of truth.
        let stravaActivities = await MainActor.run { StravaService.shared.recentActivities }
        var walkCount = 0
        var stretchCount = 0
        var cardioCount = 0
        for activity in stravaActivities where activity.startDate >= cutoff {
            // Map Strava sport_type to our bucket. Mirrors the SQL
            // mapping in `compute_user_quest_personalization`.
            switch activity.type.lowercased() {
            case "walk", "hike":
                walkCount += 1
            case "yoga":
                stretchCount += 1
            default:
                cardioCount += 1
            }
        }

        let total = strengthCount + walkCount + stretchCount + cardioCount
        guard total > 0 else { return .empty }
        return ActivityMixSnapshot(
            totalSessions: total,
            strengthShare: Double(strengthCount) / Double(total),
            cardioShare:   Double(cardioCount)   / Double(total),
            walkShare:     Double(walkCount)     / Double(total),
            stretchShare:  Double(stretchCount)  / Double(total)
        )
    }

    /// One-on-one step / walk / run challenge anchor for the
    /// "Beat <FriendName>" goal copy. Opponent ranking is the canonical
    /// social-anchor priority (PE invariant 25e):
    ///   Tier 1 — today's signals: opponent who actually moved today
    ///            wins (Abbie 0 / Manuel 877 → Manuel anchors).
    ///   Tier 2 — long-term Fit33 engagement: when both are at 0
    ///            (e.g. 7am, app hasn't synced), prefer the friend
    ///            who uses Fit33 in general.
    ///   Tier 3 — daily target descending: existing tiebreaker so a
    ///            harder challenge still wins when tier 1+2 are even.
    private struct FriendStepSeed { let name: String; let target: Int }
    private func friendStepChallengeSeed() -> FriendStepSeed? {
        let stepTypes: Set<String> = ["steps", "walk", "run"]
        let now = Date()
        struct Scored {
            let seed: FriendStepSeed
            let engagement: Double
            let target: Int
        }
        let candidates: [Scored] = ChallengeService.shared.activeChallenges.compactMap { ch in
            guard stepTypes.contains(ch.challengeType),
                  let target = ch.dailyTarget, target > 0,
                  let opp = ch.opponentName, !opp.isEmpty else { return nil }
            let engagement = FriendRankingService.opponentEngagementScore(
                opponentId: ch.opponentId,
                opponentTodayProgress: ch.opponentTodayProgress,
                opponentLastProgressAt: ch.opponentLastProgressAt,
                now: now
            )
            return Scored(
                seed: FriendStepSeed(name: Self.firstName(opp), target: target),
                engagement: engagement,
                target: target
            )
        }
        // Sort by tiered score, then daily target as final tiebreaker.
        return candidates.max { lhs, rhs in
            if lhs.engagement != rhs.engagement { return lhs.engagement < rhs.engagement }
            return lhs.target < rhs.target
        }?.seed
    }

    /// Most recent shared workout from a top friend that we'd like to
    /// surface as a `do_friend_workout` slot. We prefer the friend whose
    /// most recent shared split MATCHES the user's `suggestedSplit`
    /// (recovery-aware); among matching candidates we prefer the
    /// recently-engaged friend per PE invariant 25e (a friend who's
    /// active in Fit33 makes the "do Manuel's workout" CTA land with a
    /// live-rival feel instead of a ghost-friend anti-narrative).
    private func friendWorkoutSeed(suggestedSplit: String?) async -> FriendWorkoutSeed? {
        // Use the in-memory feed cache — `ActivityFeedService` keeps the
        // last 20 rows hydrated, and the only freshness sensitive piece
        // here is the friend's split-match. Avoids an extra round trip.
        let activities = ActivityFeedService.shared.activities
        // Filter to "workout_completed" rows with usable metadata.
        let workoutRows: [(activity: FriendActivity, split: String)] = activities.compactMap { act in
            guard act.activityType == "workout_completed",
                  let title = act.metadata.workoutName, !title.isEmpty,
                  let workoutIdStr = act.workoutId,
                  UUID(uuidString: workoutIdStr) != nil else {
                return nil
            }
            let split = Self.inferSplit(muscleGroups: act.metadata.muscleGroups ?? [], title: title)
            return (act, split)
        }
        guard !workoutRows.isEmpty else { return nil }

        // Engagement score per friend — the activity feed only carries
        // userId (no per-challenge today-progress here), so we feed
        // (nil/nil) for the tier-1 real-time signals and rely on tier 2
        // (relationshipScore via FriendRankingService). Falls back to
        // feed-recency when both candidates have no relationshipScore.
        func engagement(_ act: FriendActivity) -> Double {
            FriendRankingService.opponentEngagementScore(
                opponentId: act.userId,
                opponentTodayProgress: nil,
                opponentLastProgressAt: nil
            )
        }

        // Prefer a split-match when the user has a recovery suggestion.
        // Within the matching subset, anchor on the most-engaged friend
        // (relationshipScore-ranked) — falls back to feed order on tie.
        let pool: [(activity: FriendActivity, split: String)] = {
            if let suggested = suggestedSplit, !suggested.isEmpty {
                let matches = workoutRows.filter { $0.split == suggested }
                if !matches.isEmpty { return matches }
            }
            return workoutRows
        }()
        let chosen = pool.max { lhs, rhs in
            engagement(lhs.activity) < engagement(rhs.activity)
        }

        guard let chosen,
              let workoutIdStr = chosen.activity.workoutId,
              let workoutId = UUID(uuidString: workoutIdStr),
              let title = chosen.activity.metadata.workoutName else { return nil }

        return FriendWorkoutSeed(
            friendName: Self.firstName(chosen.activity.displayName),
            workoutId: workoutId,
            title: title,
            split: chosen.split
        )
    }

    /// Heuristic split classifier based on the muscle groups + workout
    /// title. Output is one of the strings in `encodeSplitFamily`'s
    /// codomain so the server can compare directly with `p_suggested_split`.
    private static func inferSplit(muscleGroups: [String], title: String) -> String {
        let lowered = Set(muscleGroups.map { $0.lowercased() })
        let pushHits: Set<String> = ["chest", "shoulders", "triceps"]
        let pullHits: Set<String> = ["back", "biceps", "lats"]
        let legHits:  Set<String> = ["legs", "quads", "hamstrings", "glutes", "calves"]

        let hasPush = !lowered.intersection(pushHits).isEmpty
        let hasPull = !lowered.intersection(pullHits).isEmpty
        let hasLegs = !lowered.intersection(legHits).isEmpty

        if hasPush && !hasPull && !hasLegs { return "push" }
        if hasPull && !hasPush && !hasLegs { return "pull" }
        if hasLegs && !hasPush && !hasPull { return "legs" }
        if hasPush && hasPull && !hasLegs  { return "upper" }
        if hasPush || hasPull || hasLegs   { return "full" }

        let lowercaseTitle = title.lowercased()
        if lowercaseTitle.contains("cardio") || lowercaseTitle.contains("core") {
            return "core_cardio"
        }
        return "full"
    }

    /// Returns the first name segment of a display string ("Paul Smith" → "Paul").
    private static func firstName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
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
    
    /// Multi-signal Day-1 detection. A user is treated as "Day 1" only when
    /// EVERY signal of prior activity is empty. Using only `totalWorkouts == 0`
    /// (the previous gate) caused experienced users to flash beginner quests
    /// on cold start because the cloud profile sync writes `total_workouts`
    /// AFTER `gatherUserContext()` has already captured the stale local value.
    /// Streak / XP / lastWorkoutDate / experienceLevel are populated from
    /// previous sessions' syncs and from the streak-check that runs before
    /// quest fetch, so even when `totalWorkouts` is momentarily 0 the user
    /// can still be reliably identified as established.
    private func isLikelyDay1User(totalWorkouts: Int, workoutStreak: Int) -> Bool {
        guard totalWorkouts == 0, workoutStreak == 0 else { return false }
        let user = UserManager.shared.currentUser
        if (user?.xp ?? 0) > 0 { return false }
        if user?.lastWorkoutDate != nil { return false }
        let level = (user?.experienceLevel ?? "").lowercased()
        if level == "intermediate" || level == "advanced" { return false }
        return true
    }

    /// Fallback goals that are always returned when the server returns empty or errors.
    /// Context-aware: experienced users get real generic quests, beginners get onboarding quests.
    private func defaultGoals() -> [DailyQuest] {
        let totalWorkouts = Int(UserManager.shared.currentUser?.totalWorkouts ?? 0)
        let workoutStreak = Int(UserManager.shared.currentUser?.currentStreak ?? 0)
        if isLikelyDay1User(totalWorkouts: totalWorkouts, workoutStreak: workoutStreak) {
            return [beginnerSocialQuest(), beginnerWorkoutQuest(), beginnerProgramQuest()]
        }
        return experiencedUserFallbackGoals()
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
        // Data invariant 26 — guard `isAuthenticated` before any
        // Supabase read/write/RPC. A persisted `currentUser` can exist
        // while the Supabase session is expired, in which case
        // `auth.uid()` is null server-side and the call would throw.
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("📋 [QUESTS] ⚠️ Not authenticated — skipping fetch", category: .general)
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
        
        // Day 1: show hardcoded beginner quests instead of server quests.
        // Multi-signal gate (see `isLikelyDay1User`): cloud profile sync can
        // race the quest fetch on cold start, leaving `totalWorkouts` at 0
        // momentarily for established users. Falling back to the secondary
        // signals (streak / xp / lastWorkoutDate / experienceLevel) prevents
        // the "advanced user sees Send a Challenge" flash on relaunch.
        if isLikelyDay1User(totalWorkouts: ctx.totalWorkouts, workoutStreak: ctx.workoutStreak) {
            AppLogger.info("📋 [QUESTS] Day 1 — showing beginner goal cards", category: .general)

            // Preserve completion state across re-fetches. Beginner cards have
            // no server-side row, so a `force: true` refresh would otherwise
            // reset `isCompleted` back to false (and re-award XP via the
            // backfill below). Carry forward any completion already in
            // memory or loaded from cache.
            let previouslyCompleted = Set(self.quests.filter(\.isCompleted).map(\.questKey))
            var beginnerQuests = [beginnerSocialQuest(), beginnerWorkoutQuest(), beginnerProgramQuest()]
            for i in beginnerQuests.indices where previouslyCompleted.contains(beginnerQuests[i].questKey) {
                beginnerQuests[i] = markedCompleted(beginnerQuests[i])
            }
            self.quests = beginnerQuests

            // Pre-complete cards for actions taken during onboarding/tutorial
            // (e.g. friend requests sent before the dashboard existed). Safe
            // to call every fetch — completion is idempotent.
            await backfillBeginnerQuestsFromOnboarding()

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
                let p_active_challenge_types: [String]?
                /// Wearable Personalization Phase 4 — true when the
                /// user has any of WHOOP / Oura / Fitbit connected OR
                /// HealthKit authorized. Gates the `has_wearable`
                /// `requires_context` templates added by
                /// `20260509_wearable_quests.sql`.
                let p_has_connected_wearable: Bool
                // ── Smart Adaptive Daily Goals (20260605) ─────────────
                let p_strava_connected: Bool
                let p_whoop_connected: Bool
                let p_oura_connected: Bool
                let p_fitbit_connected: Bool
                /// JSONB hint `{ "dominant": "...", "least": "..." }`.
                /// Empty → server reads from `user_activity_mix`.
                let p_activity_mix: [String: String]
                let p_friend_step_target: Int
                let p_friend_name: String?
                let p_friend_top_workout_id: String?
                let p_friend_top_workout_title: String?
                let p_friend_top_workout_split: String?
                let p_friend_top_workout_matches_recommendation: Bool
                let p_quest_tier: String
                // ── Daily Mission Unification (20260703 — Phase 2) ────
                /// Capacity band from the Daily Brief engine. The
                /// server's Layer 7 (Capacity Band Re-Ranker) reads
                /// this to demote hard-difficulty quests on red days
                /// + elevate PR-flag quests on green days. nil/null
                /// → server falls back to legacy 6-layer behavior.
                let p_capacity_band: String?
                let p_capacity_score: Int?
                /// Top debt the brief surfaced (matches Swift
                /// `DebtKind.rawValue`). Server's Layer 8 (Debt
                /// Booster) force-elevates the matching quest into
                /// slot 2 or 3 when payload meets the threshold.
                let p_top_debt_kind: String?
                /// JSONB: { muscles, days, deficitG, deficitVsPaceG,
                /// deficitL, deficitMl, gap, gapRaw, subKind }.
                let p_top_debt_payload: [String: String]?

                enum CodingKeys: String, CodingKey {
                    case p_user_id, p_timezone, p_has_program, p_has_friends, p_has_challenge
                    case p_step_goal, p_fitness_goal, p_is_subscriber, p_workout_streak
                    case p_total_workouts, p_preferred_time, p_avg_duration
                    case p_has_weight_log, p_hydration_active, p_league_rank
                    case p_active_step_challenge_target
                    case p_suggested_split, p_fatigued_regions
                    case p_active_challenge_types
                    case p_has_connected_wearable
                    case p_strava_connected, p_whoop_connected, p_oura_connected, p_fitbit_connected
                    case p_activity_mix
                    case p_friend_step_target, p_friend_name
                    case p_friend_top_workout_id, p_friend_top_workout_title
                    case p_friend_top_workout_split
                    case p_friend_top_workout_matches_recommendation
                    case p_quest_tier
                    case p_capacity_band, p_capacity_score, p_top_debt_kind, p_top_debt_payload
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
                    if let types = p_active_challenge_types, !types.isEmpty {
                        try container.encode(types, forKey: .p_active_challenge_types)
                    }
                    // Always encode `p_has_connected_wearable` — the
                    // server default is `FALSE` so omitting would
                    // silently drop users from the has_wearable pool
                    // when they HAVE a wearable connected.
                    try container.encode(p_has_connected_wearable, forKey: .p_has_connected_wearable)
                    // Smart Adaptive Daily Goals (20260605). All booleans
                    // and tier are always encoded so the server picks the
                    // right pool. The optional friend / activity-mix
                    // fields are only encoded when they carry signal.
                    try container.encode(p_strava_connected, forKey: .p_strava_connected)
                    try container.encode(p_whoop_connected,  forKey: .p_whoop_connected)
                    try container.encode(p_oura_connected,   forKey: .p_oura_connected)
                    try container.encode(p_fitbit_connected, forKey: .p_fitbit_connected)
                    if !p_activity_mix.isEmpty {
                        try container.encode(p_activity_mix, forKey: .p_activity_mix)
                    }
                    if p_friend_step_target > 0 {
                        try container.encode(p_friend_step_target, forKey: .p_friend_step_target)
                    }
                    if let name = p_friend_name, !name.isEmpty {
                        try container.encode(name, forKey: .p_friend_name)
                    }
                    if let id = p_friend_top_workout_id, !id.isEmpty {
                        try container.encode(id, forKey: .p_friend_top_workout_id)
                    }
                    if let title = p_friend_top_workout_title, !title.isEmpty {
                        try container.encode(title, forKey: .p_friend_top_workout_title)
                    }
                    if let split = p_friend_top_workout_split, !split.isEmpty {
                        try container.encode(split, forKey: .p_friend_top_workout_split)
                    }
                    try container.encode(p_friend_top_workout_matches_recommendation, forKey: .p_friend_top_workout_matches_recommendation)
                    try container.encode(p_quest_tier, forKey: .p_quest_tier)
                    // Daily Mission Unification (20260703 — Phase 2):
                    // brief signals are optional; only encode when
                    // the brief has actually been composed. Server
                    // accepts NULL defaults and falls back to legacy
                    // 6-layer behavior when missing.
                    if let band = p_capacity_band, !band.isEmpty {
                        try container.encode(band, forKey: .p_capacity_band)
                    }
                    if let score = p_capacity_score, score > 0 {
                        try container.encode(score, forKey: .p_capacity_score)
                    }
                    if let debt = p_top_debt_kind, !debt.isEmpty {
                        try container.encode(debt, forKey: .p_top_debt_kind)
                    }
                    if let payload = p_top_debt_payload, !payload.isEmpty {
                        try container.encode(payload, forKey: .p_top_debt_payload)
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
                p_fatigued_regions: ctx.fatiguedRegions.isEmpty ? nil : ctx.fatiguedRegions,
                p_active_challenge_types: ctx.activeChallengeTypes.isEmpty ? nil : ctx.activeChallengeTypes,
                // Wearable Personalization Phase 4 — pass the live
                // wearable-connection state from the main actor. The
                // `wearableQuests` feature flag gates *surfacing* the
                // new quest templates; the param is sent either way so
                // the server can return wearable-context quests as
                // soon as the RPC body migration lands.
                p_has_connected_wearable: AppConfig.FeatureFlags.wearableQuests
                    && (ctx.whoopConnected
                        || ctx.ouraConnected
                        || ctx.fitbitConnected
                        || HealthKitService.shared.isAuthorized),
                // Smart Adaptive Daily Goals (20260605) — separated
                // wearable bools + activity-mix + friend seeds + tier.
                // The kill-switch flag short-circuits the new layers
                // entirely (server still returns a valid slate from
                // the existing predicates).
                p_strava_connected: AppConfig.FeatureFlags.smartAdaptiveQuests && ctx.stravaConnected,
                p_whoop_connected:  AppConfig.FeatureFlags.smartAdaptiveQuests && ctx.whoopConnected,
                p_oura_connected:   AppConfig.FeatureFlags.smartAdaptiveQuests && ctx.ouraConnected,
                p_fitbit_connected: AppConfig.FeatureFlags.smartAdaptiveQuests && ctx.fitbitConnected,
                p_activity_mix: AppConfig.FeatureFlags.smartAdaptiveQuests
                    ? ctx.activityMix28d.rpcHint
                    : [:],
                p_friend_step_target: AppConfig.FeatureFlags.smartAdaptiveQuests
                    ? ctx.friendStepTarget
                    : 0,
                p_friend_name: AppConfig.FeatureFlags.smartAdaptiveQuests
                    ? ctx.friendName
                    : nil,
                p_friend_top_workout_id: AppConfig.FeatureFlags.smartAdaptiveQuests
                    ? ctx.friendTopWorkoutId?.uuidString
                    : nil,
                p_friend_top_workout_title: AppConfig.FeatureFlags.smartAdaptiveQuests
                    ? ctx.friendTopWorkoutTitle
                    : nil,
                p_friend_top_workout_split: AppConfig.FeatureFlags.smartAdaptiveQuests
                    ? ctx.friendTopWorkoutSplit
                    : nil,
                p_friend_top_workout_matches_recommendation: AppConfig.FeatureFlags.smartAdaptiveQuests
                    && ctx.friendTopWorkoutMatchesRecommendation,
                p_quest_tier: AppConfig.FeatureFlags.smartAdaptiveQuests
                    ? ctx.questTier
                    : "free",
                // Daily Mission Unification (20260703 — Phase 2): pull
                // from `DailyBriefStore.shared.brief?.decision` so the
                // server's Layer 7 + Layer 8 see the same Decision the
                // brief headline was built from. When the brief hasn't
                // composed yet (cold launch race), all four are nil
                // and the server falls back to legacy 6-layer logic
                // — exactly the same behavior as before this PR for
                // any user without a brief on hand.
                p_capacity_band:    DailyBriefStore.shared.brief?.decision?.capacityBand.rawValue,
                p_capacity_score:   DailyBriefStore.shared.brief?.decision?.capacityScore,
                p_top_debt_kind:    DailyBriefStore.shared.brief?.decision?.topDebtKind?.rawValue,
                p_top_debt_payload: DailyBriefStore.shared.brief?.decision?.topDebtPayload
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

            // Backfill catch-up. When the RPC just assigned fresh rows (e.g.
            // after a quest-row reset, a new day rollover partway through,
            // or a fresh re-install) the new quests land at 0/1 even though
            // today's workouts / meals / steps may have already happened.
            // Push the existing local state back up so the server flips
            // `is_completed` + awards XP instead of forcing the user to do
            // the thing again. Best-effort; each reportProgress call no-ops
            // if the quest isn't assigned.
            await backfillTodayProgress()

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
                // Route through NetworkErrorClassifier so transient Cloudflare
                // 502/503/504 / -999 cancellations don't create a fingerprint.
                // Real failures (RLS violations, unexpected PostgREST codes) still
                // surface at .error and get triaged by Bug Intelligence.
                // Cluster E (fingerprint 71748b6e): Dashboard `.task`
                // cancellations are the dominant transient here — downgrade
                // to .debug so tab-switches stop generating warnings.
                let classification = NetworkErrorClassifier.log(
                    error,
                    context: "[QUESTS] Failed to fetch",
                    category: .general,
                    transientLevel: .debug
                )
                if case .realError = classification {
                    AppLogger.log("[QUESTS] Error details (raw): \(errorString)", level: .error, category: .general)
                } else {
                    AppLogger.log("[QUESTS] Error details (raw): \(errorString)", level: .debug, category: .general)
                }
            }
            
            if quests.isEmpty {
                AppLogger.info("[QUESTS] Fetch failed with empty goals — activating defaults (\(isStreakFieldError ? "streak_field" : isAuthError ? "auth" : "unknown") cause)", category: .general)
                self.quests = defaultGoals()
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Update Quest Progress

    /// Day-1 onboarding cards (`beginnerSocialQuest()` / `beginnerWorkoutQuest()`
    /// / `beginnerProgramQuest()`) are hardcoded client-side and have NO row
    /// in `user_daily_quests`, so the regular `update_quest_progress` RPC is
    /// a no-op for them. When a user takes an action whose canonical
    /// `QuestKey` matches one of these placeholders, we fall through to a
    /// local-only completion path. Without this map, e.g. sending a friend
    /// request fires `reportProgress(.addFriend)` which logs
    /// "Quest 'add_friend' not active today, skipping" while the
    /// "Add a Friend" beginner card stays at 0/1 forever.
    private static let beginnerEquivalent: [QuestKey: QuestKey] = [
        .addFriend:       .beginnerAddFriend,
        .completeWorkout: .beginnerFirstWorkout,
        .sendChallenge:   .beginnerSendChallenge
    ]

    /// Call this when the user completes an action that might advance a quest.
    /// The function checks if the quest is active today before making the RPC call.
    func reportProgress(questKey: QuestKey, increment: Int = 1) async {
        // Data invariant 26 — guard `isAuthenticated` before the RPC
        // so we don't generate background "not authenticated" errors
        // during the startup auth race.
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Only call RPC if this quest is actually assigned today and not yet done
        guard hasQuest(questKey) else {
            // Day-1 fall-through: the Day-1 beginner equivalent placeholder
            // may be on screen instead of the canonical server-quest row.
            // Flip it locally so the card ticks to ✓ and the user gets XP /
            // league points immediately.
            if let beginnerKey = Self.beginnerEquivalent[questKey],
               hasQuest(beginnerKey) {
                await completeBeginnerQuestLocally(beginnerKey)
                return
            }
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
                    verificationType: old.verificationType,
                    tier: old.tier,
                    doubleXp: old.doubleXp,
                    isCustom: old.isCustom,
                    isReroll: old.isReroll,
                    isBriefInfluenced: old.isBriefInfluenced
                )
                
                // Trigger celebration if quest just completed
                if nowComplete {
                    lastCompletedQuest = quests[idx]
                    showQuestCompletionCelebration = true
                    
                    // Award XP to user profile for quest completion. When
                    // the server-side double-XP flag is set (Pro users via
                    // `claim_double_xp_day`), apply the local 2× match so
                    // the profile XP stays in sync with the server-side
                    // `apply_double_xp_on_complete` trigger.
                    if old.xpReward > 0 {
                        let multiplier: Int32 = (old.doubleXp ?? false) ? 2 : 1
                        UserManager.shared.addXP(Int32(old.xpReward) * multiplier)
                    }
                    
                    // Award league points for quest completion
                    await WeeklyLeagueService.shared.addPoints(source: .challengeTarget)

                    // 2026-04-29 — League Redesign Plan §C1.
                    // Additional +15 league points per quest completion via
                    // the new `.dailyQuestCompleted` source. Stacks ON TOP of
                    // the legacy +25 `.challengeTarget` award (kept for
                    // backwards-compat with existing leaderboards). No
                    // client-side cap — there are at most 3 quests/day, so
                    // the implicit cap is 3 × 15 = +45/day.
                    await WeeklyLeagueService.shared.addPoints(source: .dailyQuestCompleted)
                    
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

    /// Returns a copy of `quest` with completion fields set. Used by the
    /// Day-1 fetch branch to carry completion state across `force: true`
    /// re-fetches without re-awarding XP via `completeBeginnerQuestLocally`.
    private func markedCompleted(_ quest: DailyQuest) -> DailyQuest {
        DailyQuest(
            id: quest.id,
            questKey: quest.questKey,
            title: quest.title,
            description: quest.description,
            icon: quest.icon,
            category: quest.category,
            targetValue: quest.targetValue,
            currentValue: quest.targetValue,
            targetUnit: quest.targetUnit,
            xpReward: quest.xpReward,
            leaguePoints: quest.leaguePoints,
            difficulty: quest.difficulty,
            isCompleted: true,
            completedAt: quest.completedAt ?? ISO8601DateFormatter().string(from: Date()),
            funLabel: quest.funLabel,
            verificationType: quest.verificationType,
            tier: quest.tier,
            doubleXp: quest.doubleXp,
            isCustom: quest.isCustom,
            isReroll: quest.isReroll,
            isBriefInfluenced: quest.isBriefInfluenced
        )
    }

    /// Marks a Day-1 beginner placeholder quest complete in-memory and awards
    /// XP + league points, mirroring the success branch of `reportProgress`.
    /// Used by the `beginnerEquivalent` fall-through above because the
    /// hardcoded beginner cards have no server-side `user_daily_quests` row
    /// and `update_quest_progress` would silently no-op for them.
    ///
    /// `withCelebration` is `false` for backfill paths (e.g.
    /// `backfillBeginnerQuestsFromOnboarding`) where the user took the action
    /// minutes ago during onboarding/tutorial — popping a fullscreen
    /// celebration the moment the dashboard appears would be jarring.
    /// XP / league / bonus credits still happen regardless; only the
    /// celebratory UI overlays are suppressed.
    @MainActor
    private func completeBeginnerQuestLocally(_ questKey: QuestKey, withCelebration: Bool = true) async {
        guard let idx = quests.firstIndex(where: {
            $0.questKey == questKey.rawValue && !$0.isCompleted
        }) else { return }

        let old = quests[idx]
        quests[idx] = DailyQuest(
            id: old.id,
            questKey: old.questKey,
            title: old.title,
            description: old.description,
            icon: old.icon,
            category: old.category,
            targetValue: old.targetValue,
            currentValue: old.targetValue,
            targetUnit: old.targetUnit,
            xpReward: old.xpReward,
            leaguePoints: old.leaguePoints,
            difficulty: old.difficulty,
            isCompleted: true,
            completedAt: ISO8601DateFormatter().string(from: Date()),
            funLabel: old.funLabel,
            verificationType: old.verificationType,
            tier: old.tier,
            doubleXp: old.doubleXp,
            isCustom: old.isCustom,
            isReroll: old.isReroll,
            isBriefInfluenced: old.isBriefInfluenced
        )

        if withCelebration {
            lastCompletedQuest = quests[idx]
            showQuestCompletionCelebration = true
        }

        if old.xpReward > 0 {
            UserManager.shared.addXP(Int32(old.xpReward))
        }

        // Mirror reportProgress's dual-source league award (legacy
        // `.challengeTarget` + `.dailyQuestCompleted`) so the league
        // scoreboard stays consistent regardless of completion path.
        await WeeklyLeagueService.shared.addPoints(source: .challengeTarget)
        await WeeklyLeagueService.shared.addPoints(source: .dailyQuestCompleted)

        // Bonus when all 3 Day-1 cards complete. Beginner quests don't go
        // through the server's `unlock_quest_bonus` trigger, so credit the
        // bonus locally here using the same +50 / +30 amounts the server
        // uses when the regular slate completes.
        if quests.allSatisfy(\.isCompleted) && !allComplete {
            allComplete = true
            bonusXp = 50
            bonusLeaguePoints = 30
            UserManager.shared.addXP(Int32(bonusXp))
            if withCelebration {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    showBonusCelebration = true
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    showBonusCelebration = false
                }
            }
        }

        if withCelebration {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                showQuestCompletionCelebration = false
            }
        }

        cacheQuests()

        #if DEBUG
        AppLogger.info(
            "✅ [QUESTS] Completed beginner '\(questKey.rawValue)' (+\(old.xpReward) XP, +\(old.leaguePoints) league pts) [local\(withCelebration ? "" : ", silent")]",
            category: .general
        )
        #endif
    }

    /// Pre-completes Day-1 beginner cards for actions the user already took
    /// before the quest array existed — most importantly friend requests sent
    /// during the onboarding `addFriends` step or the welcome tutorial.
    ///
    /// Without this, the user would tap "Add" during onboarding (which calls
    /// `reportProgress(.addFriend)` against an empty `quests` array — a silent
    /// no-op), then exit the tutorial only to see the "Add a Friend" card
    /// still at 0/1 on the dashboard. Pre-completing here gives the user a
    /// "preview of completed goals" the moment they land on the dashboard.
    ///
    /// Idempotent: `completeBeginnerQuestLocally` early-returns if the quest
    /// is already complete, so re-running this on every fetch is safe.
    @MainActor
    private func backfillBeginnerQuestsFromOnboarding() async {
        let hasFriendActivity = !FriendService.shared.friends.isEmpty
            || !FriendService.shared.sentRequests.isEmpty
        if hasFriendActivity, hasQuest(.beginnerAddFriend) {
            await completeBeginnerQuestLocally(.beginnerAddFriend, withCelebration: false)
        }
    }

    // MARK: - Backfill (catch-up after quest reassignment)

    /// Walks today's local data sources and replays `reportProgress` for any
    /// quest that's already satisfied by existing state but whose server-side
    /// row is still 0. Safe to call repeatedly — `reportProgress` no-ops when
    /// the quest isn't assigned OR is already complete. The goal here is
    /// specifically the "I did a workout and then my quest reset to 0/1"
    /// scenario, plus meals/water/weight that happened before today's quests
    /// were picked. HealthKit-only data (steps, active minutes, sleep) flows
    /// through the existing observers so we don't duplicate that path here.
    private func backfillTodayProgress() async {
        guard !quests.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // ── Workouts: count today's completed Core Data workouts and replay
        // the same `onWorkoutCompleted` calls the active workout flow makes.
        // Uses the shared view context because this runs on the main actor.
        let ctx = PersistenceController.shared.container.viewContext
        let wRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        wRequest.predicate = NSPredicate(
            format: "isCompleted == true AND date >= %@ AND date < %@",
            today as NSDate,
            (cal.date(byAdding: .day, value: 1, to: today) ?? today) as NSDate
        )
        wRequest.fetchLimit = 10
        let todaysWorkouts = (try? ctx.fetch(wRequest)) ?? []

        if !todaysWorkouts.isEmpty {
            // Replay each workout once so `complete_workout`, `workout_30_min`,
            // `exercise_sets_*`, `early_bird_workout`, and the upper/lower
            // focus quests all tick. `reportProgress` guards against
            // double-tick on already-complete quests.
            for workout in todaysWorkouts {
                let exercises = (workout.exercises?.allObjects as? [WorkoutExercise]) ?? []
                let totalSets = exercises.reduce(0) { total, ex in
                    total + ((ex.sets?.allObjects as? [WorkoutSet])?.filter(\.isCompleted).count ?? 0)
                }
                let durationSeconds = Int(workout.duration)
                await onWorkoutCompleted(durationSeconds: durationSeconds, totalSets: totalSets)

                let trained: Set<String> = Set(
                    exercises.flatMap { $0.safeMuscleGroups.map { $0.lowercased() } }
                )
                if !trained.isEmpty {
                    await onWorkoutWithFocus(bodyParts: trained)
                }
            }
        }

        // ── Meals logged today (live via MealService — already scoped).
        let mealsToday = MealService.shared.todaysMeals
        for meal in mealsToday {
            await onMealLogged(mealType: meal.mealType.rawValue)
        }

        // ── Hydration logged today. `entryCount` is today's glasses total;
        // we pass it as the increment so the server catches up in one call
        // (the RPC caps at target so overshooting is safe).
        let glassesToday = HydrationService.shared.todaySummary?.entryCount ?? 0
        if glassesToday > 0 {
            await onWaterLogged(glasses: glassesToday)
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
            // CRITICAL: `MealType.snacks` (Swift enum) has rawValue **"snacks"**
            // (plural), but this switch was checking only "snack" — the snack
            // quest never fired in production. Audit caught 2026-04-30. Accept
            // both for safety (backend webhooks could send either form).
            case "snack", "snacks":
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

    /// Canonical user daily protein goal in grams. Mirrors the formula used by
    /// `DashboardView+Macros` (`max(100, weightLbs × 0.8)`) so the dashboard
    /// macro card, the Daily Brief's protein deficit, and the
    /// `hit_protein_goal` quest all measure against the same target. Floors
    /// at 100g for very-light users so a 110-lb user isn't told their daily
    /// protein quest completes at 88g (also matches industry-standard
    /// minimum-effective-dose recommendations).
    ///
    /// Add a server-side per-user override on `user_daily_quests.target_value`
    /// in a future migration if we ever want to personalize this number on a
    /// row-by-row basis (e.g. competitive bodybuilders at 1.0g/lb). For now
    /// the entire app reads from this single helper to keep dashboard, brief,
    /// and quest copy in lockstep.
    func computeUserProteinGoal() -> Int {
        let weightLbs = Double(UserManager.shared.currentUser?.weight ?? 150)
        return max(100, Int((weightLbs * 0.8).rounded()))
    }

    /// Call after every meal log with TOTAL protein eaten today. Only flips
    /// the binary `hit_protein_goal` quest to completed once the user has
    /// actually crossed `computeUserProteinGoal()` — never on partial
    /// progress.
    ///
    /// Why the previous behavior was wrong (2026-04-27 — user-reported,
    /// dashboard screenshot showing "Eat 1g protein today / Not yet"):
    /// the server template ships `target_value = 1, target_unit = 'goal'`
    /// which is a binary completion stamp. The previous body of this method
    /// reported a delta in raw GRAMS (`needed = totalGrams - currentValue`)
    /// to the server, so the very first meal with any protein bumped
    /// `current_value` past 1 and the quest completed — meaning a 20g eggs
    /// breakfast finished a "Hit your daily protein goal" `difficulty=hard`
    /// quest. Quest description compounded the bug by interpolating
    /// `quest.targetValue` (= 1) into the copy ("Eat 1g protein today"),
    /// telling the user the threshold was 1g.
    ///
    /// New behavior: gate the binary completion on the real-world local
    /// threshold. The mechanic is now consistent with `hit_step_goal` (line
    /// `lastReportedSteps < HealthKitManager.shared.stepGoal && todaySteps
    /// >= HealthKitManager.shared.stepGoal` in `reportLiveProgress`).
    /// `current_value` stays at 0 until goal is hit, then ticks to 1.
    func onProteinProgress(totalGrams: Int) async {
        guard hasQuest(.hitProteinGoal) else { return }
        let goal = computeUserProteinGoal()
        guard totalGrams >= goal else { return }
        // De-dupe: don't re-fire for users who already completed today.
        if let idx = quests.firstIndex(where: { $0.questKey == QuestKey.hitProteinGoal.rawValue }),
           quests[idx].isCompleted {
            return
        }
        await onProteinGoalHit()
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
        // No-op as of migration 20260611. The `sleep_7_hours` and
        // `sleep_8h_wearable` templates were retired (soft-disabled,
        // is_active = FALSE) because their pass/fail outcome is locked-in
        // by last night's sleep before the user can take any action today
        // — see PE invariant 19d. The hook is kept (vs. deleted) so the
        // call sites in HealthDataService / sleep-sync paths don't need
        // to be untangled; if a future actionable sleep quest lands, this
        // is its natural attach point.
        _ = hours
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

    // MARK: - Smart Adaptive Daily Goals: New Hooks
    //
    // Fire-and-forget verifier hooks for the integration-driven quest
    // families introduced in 20260604 (Strava PRs, wearable activations,
    // friend social actions). Each hook is safe to call repeatedly — the
    // server-side verification RPC walks today's user_daily_quests rows
    // and only flips quests that were actually achieved.

    /// Call from `StravaService.syncActivities` after activities were
    /// imported. Triggers `verify_strava_quests_for_today` so PR / outdoor
    /// quests flip without the user opening the daily-goals widget.
    /// Cardio Redesign Phase 1 — internally delegates to the more general
    /// `onCardioActivityImported(source:)` since the verifier RPC was
    /// widened (migration 186) to accept both `'strava'` and `'fit33'`
    /// sources.
    func onStravaActivityImported() async {
        await onCardioActivityImported(source: "strava")
    }

    /// Call from any cardio-save call site (native `record_cardio_workout`
    /// RPC return path, Strava webhook arrival, HK ambient-cardio sync).
    /// Triggers `verify_strava_quests_for_today` (now widened to accept
    /// both `'strava'` and `'fit33'` sources per migration 186) so PR /
    /// outdoor / Z2 / walk-1km quests flip immediately without waiting for
    /// the daily-goals widget to refresh on next foreground.
    ///
    /// `source` is informational (logged for triage); the verifier RPC
    /// itself doesn't filter by source — it walks today's
    /// `user_daily_quests` for the caller and ticks each one whose
    /// canonical detector matches.
    func onCardioActivityImported(source: String = "fit33") async {
        // Data invariant 26 — auth gate before RPC.
        guard SupabaseManager.shared.isAuthenticated,
              SupabaseManager.shared.currentUser?.id != nil else { return }
        guard AppConfig.FeatureFlags.smartAdaptiveQuests else { return }

        // Skip the round-trip when the user has zero cardio-context
        // quests assigned today. Walks both Strava-PR keys + the new
        // native cardio keys (walk_1km / cardio_minutes_20 /
        // zone_2_minutes_20 — added 2026-04-25 in #20260610).
        let cardioKeys: Set<String> = [
            QuestKey.beatYour5kPR.rawValue,
            QuestKey.negativeSplitRun.rawValue,
            QuestKey.runOutside8km.rawValue,
            QuestKey.cycleOutside30km.rawValue,
            QuestKey.completeStravaSegment.rawValue,
            "run_outside_3km", "run_outside_5km",
            "cycle_outside_15km",
            "walk_1km", "cardio_minutes_20", "zone_2_minutes_20",
            "active_recovery_logged", "walk_when_red", "evening_wind_down"
        ]
        guard quests.contains(where: { cardioKeys.contains($0.questKey) && !$0.isCompleted }) else {
            return
        }

        do {
            _ = try await SupabaseManager.shared.supabaseClient
                .rpc("verify_strava_quests_for_today", params: [
                    "p_timezone": TimeZone.current.identifier
                ])
                .execute()
            await fetchDailyQuests(force: true)
            #if DEBUG
            AppLogger.debug(
                "✅ [QUESTS] Verified cardio quests after \(source) import",
                category: .general
            )
            #endif
        } catch {
            #if DEBUG
            AppLogger.warning(
                "⚠️ [QUESTS] verify_strava_quests_for_today failed (source=\(source)): \(error)",
                category: .general
            )
            #endif
        }
    }

    /// Call from `ReadinessService.recompute` after a fresh band/score is
    /// committed. Triggers `verify_wearable_quests_for_today` for sleep /
    /// recovery / strain / walk-when-red quests.
    func onReadinessRecomputed() async {
        // Data invariant 26 — auth gate before RPC.
        guard SupabaseManager.shared.isAuthenticated,
              SupabaseManager.shared.currentUser?.id != nil else { return }
        guard AppConfig.FeatureFlags.smartAdaptiveQuests else { return }

        let wearableKeys: Set<String> = [
            QuestKey.matchYesterdayStrain.rawValue,
            QuestKey.walkWhenRed.rawValue,
            "sleep_8h_wearable", "recovery_above_67",
            "hrv_above_baseline", "rhr_in_healthy_range",
            "respect_red_recovery"
        ]
        guard quests.contains(where: { wearableKeys.contains($0.questKey) && !$0.isCompleted }) else {
            return
        }

        do {
            _ = try await SupabaseManager.shared.supabaseClient
                .rpc("verify_wearable_quests_for_today", params: [
                    "p_timezone": TimeZone.current.identifier
                ])
                .execute()
            await fetchDailyQuests(force: true)
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [QUESTS] verify_wearable_quests_for_today failed: \(error)", category: .general)
            #endif
        }
    }

    /// Call when the user finishes a workout that was shared by a friend.
    /// Powers the `do_friend_workout` quest. We require a workout_id so
    /// the server-side check (matching the friend's seed) can disambiguate
    /// — if the user just did "any" workout, the existing `complete_workout`
    /// quest covers it.
    func onSharedWorkoutCompleted(originWorkoutId: UUID) async {
        guard hasQuest(.doFriendWorkout) else { return }
        await reportProgress(questKey: .doFriendWorkout)
    }

    /// Call when the user comments on a friend's activity-feed entry.
    func onFriendWorkoutComment() async {
        await reportProgress(questKey: .commentOnFriendsWorkout)
    }

    /// Call when a friend reaction is added (≥3 across the day).
    func onFriendReactionSent() async {
        await reportProgress(questKey: .reactTo3Workouts)
        await reportProgress(questKey: .reactToWorkout)
    }

    /// Call when a 1v1 challenge is created with a top friend.
    func onTopFriendChallengeStarted() async {
        await reportProgress(questKey: .start1v1WithTopFriend)
        await reportProgress(questKey: .start1v1Challenge)
    }

    // MARK: - Smart Adaptive Daily Goals: Pro Monetization

    /// Reroll one of today's quest slots for a fresh candidate. Free users
    /// get 1/day, Pro 5/day. Returns a structured result so the UI can
    /// distinguish "out of rerolls" from "no eligible swap".
    struct RerollOutcome {
        let success: Bool
        let reason: String?
        let newQuestKey: String?
        let remaining: Int
        let isPro: Bool
    }

    func reroll(questId: UUID) async -> RerollOutcome {
        // Data invariant 26 — guard `isAuthenticated`, not just
        // `currentUser`. A persisted user with an expired session
        // would otherwise hit `auth.uid()` null server-side.
        guard SupabaseManager.shared.isAuthenticated,
              SupabaseManager.shared.currentUser?.id != nil else {
            return RerollOutcome(success: false, reason: "not_authenticated",
                                 newQuestKey: nil, remaining: 0, isPro: false)
        }

        struct RerollResponse: Decodable {
            let success: Bool
            let reason: String?
            let newQuestKey: String?
            let remaining: Int?
            let isPro: Bool?
            let used: Int?
            let limit: Int?
            enum CodingKeys: String, CodingKey {
                case success, reason
                case newQuestKey = "new_quest_key"
                case remaining
                case isPro = "is_pro"
                case used, limit
            }
        }
        struct Params: Encodable {
            let p_quest_id: String
            let p_timezone: String
            let p_is_pro: Bool
        }

        let isPro = PremiumManager.shared.isPremiumUser
        do {
            let result: RerollResponse = try await SupabaseManager.shared.supabaseClient
                .rpc("reroll_daily_quest", params: Params(
                    p_quest_id: questId.uuidString,
                    p_timezone: TimeZone.current.identifier,
                    p_is_pro: isPro
                ))
                .execute()
                .value

            // Pull the updated row back so the UI animates to the new
            // title/description without a stale cache moment.
            if result.success {
                await fetchDailyQuests(force: true)
            }

            return RerollOutcome(
                success: result.success,
                reason: result.reason,
                newQuestKey: result.newQuestKey,
                remaining: result.remaining ?? 0,
                isPro: result.isPro ?? isPro
            )
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [QUESTS] reroll_daily_quest failed: \(error)", category: .general)
            #endif
            return RerollOutcome(success: false, reason: error.localizedDescription,
                                 newQuestKey: nil, remaining: 0, isPro: isPro)
        }
    }

    /// Stamp today's quest rows with `double_xp = TRUE` (Pro 1/week).
    /// The `apply_double_xp_on_complete` server trigger awards the bonus
    /// XP at completion time.
    func claimDoubleXpDay() async -> (success: Bool, reason: String?) {
        // Data invariant 26 — auth gate before RPC.
        guard SupabaseManager.shared.isAuthenticated else {
            return (false, "not_authenticated")
        }
        guard PremiumManager.shared.isPremiumUser else {
            return (false, "pro_required")
        }

        struct Result: Decodable {
            let success: Bool
            let reason: String?
        }
        struct Params: Encodable {
            let p_date: String?
            let p_is_pro: Bool
        }

        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current

            let result: Result = try await SupabaseManager.shared.supabaseClient
                .rpc("claim_double_xp_day", params: Params(
                    p_date: formatter.string(from: Date()),
                    p_is_pro: true
                ))
                .execute()
                .value

            if result.success {
                await fetchDailyQuests(force: true)
            }
            return (result.success, result.reason)
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [QUESTS] claim_double_xp_day failed: \(error)", category: .general)
            #endif
            return (false, error.localizedDescription)
        }
    }

    /// Pro-only custom quest. Capped at 25 XP / 15 LP server-side; manual
    /// verification only — the user marks it complete by calling
    /// `reportProgress(questKey:)` with the returned key.
    func submitCustomQuest(title: String, targetValue: Int, targetUnit: String) async -> (success: Bool, reason: String?) {
        // Data invariant 26 — auth gate before RPC.
        guard SupabaseManager.shared.isAuthenticated else {
            return (false, "not_authenticated")
        }
        guard PremiumManager.shared.isPremiumUser else {
            return (false, "pro_required")
        }

        struct Result: Decodable {
            let success: Bool
            let reason: String?
        }
        struct Params: Encodable {
            let p_title: String
            let p_target_value: Int
            let p_target_unit: String
            let p_is_pro: Bool
            let p_timezone: String
        }

        do {
            let result: Result = try await SupabaseManager.shared.supabaseClient
                .rpc("submit_custom_quest", params: Params(
                    p_title: title,
                    p_target_value: targetValue,
                    p_target_unit: targetUnit,
                    p_is_pro: true,
                    p_timezone: TimeZone.current.identifier
                ))
                .execute()
                .value

            if result.success {
                await fetchDailyQuests(force: true)
            }
            return (result.success, result.reason)
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [QUESTS] submit_custom_quest failed: \(error)", category: .general)
            #endif
            return (false, error.localizedDescription)
        }
    }

    /// Pro-only override that clears a user-level skip-streak suppression
    /// for a category (e.g. user wants to re-engage with `nutrition`
    /// after the system suppressed it).
    func unsuppressCategory(_ category: String) async -> Bool {
        // Data invariant 26 — auth gate before RPC.
        guard SupabaseManager.shared.isAuthenticated else { return false }
        guard PremiumManager.shared.isPremiumUser else { return false }
        struct Result: Decodable { let success: Bool }
        struct Params: Encodable { let p_category: String; let p_is_pro: Bool }
        do {
            let result: Result = try await SupabaseManager.shared.supabaseClient
                .rpc("unsuppress_quest_category", params: Params(
                    p_category: category, p_is_pro: true
                ))
                .execute()
                .value
            return result.success
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [QUESTS] unsuppress_quest_category failed: \(error)", category: .general)
            #endif
            return false
        }
    }

    /// Daily Goals Insights toggle (migration 20260702). Pro-only.
    /// `enabled = true`  → clears `suppressed_until` (mirrors `unsuppressCategory`).
    /// `enabled = false` → writes the forever-sentinel so `get_daily_quests` v3
    /// excludes the category indefinitely. Refreshes the slate on success
    /// so the user sees the toggle take effect immediately.
    func setCategoryEnabled(_ category: String, enabled: Bool) async -> Bool {
        // Data invariant 26 — auth gate before RPC.
        guard SupabaseManager.shared.isAuthenticated else { return false }
        guard PremiumManager.shared.isPremiumUser else { return false }
        struct Result: Decodable { let success: Bool }
        struct Params: Encodable {
            let p_category: String
            let p_enabled: Bool
            let p_is_pro: Bool
        }
        do {
            let result: Result = try await SupabaseManager.shared.supabaseClient
                .rpc("set_quest_category_enabled", params: Params(
                    p_category: category,
                    p_enabled: enabled,
                    p_is_pro: true
                ))
                .execute()
                .value
            if result.success {
                await fetchDailyQuests(force: true)
            }
            return result.success
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [QUESTS] set_quest_category_enabled failed: \(error)", category: .general)
            #endif
            return false
        }
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

        DailyGoalsWidgetBridge.publish(
            quests: quests,
            allComplete: allComplete,
            bonusXp: bonusXp
        )
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

        // Mirror the boot-time slate to the App Group so the home-screen
        // widget paints real goals on first launch — `cacheQuests` only
        // fires after a successful server fetch.
        DailyGoalsWidgetBridge.publish(
            quests: quests,
            allComplete: allComplete,
            bonusXp: bonusXp
        )
    }
}

// MARK: - QuestEmojiResolver
//
// Smart, content-aware emoji selection for daily quests. Replaces the original
// 7-emoji-per-category mapping with a multi-layer resolver so cards feel alive
// (a "Heart Health" quest gets ❤️, a "Strawberry Smoothie" quest gets 🍓, a
// "Drink Water" quest gets 💧 — instead of every nutrition quest being 🥗).
//
// Resolution order (first hit wins):
//   1. byQuestKey       — curated emoji per canonical quest_key
//   2. keywordTable     — priority-ordered keyword scan of title+description+funLabel
//   3. leadingFunEmoji  — first character of fun_label if it's an emoji
//   4. categoryFallback — category bucket (workout/nutrition/social/...)
//   5. ⭐               — generic default
//
// MIRROR: `RunningActivityWidget/QuestEmojiResolver.swift` keeps an identical
// table for the home-screen widget. When you add/edit an entry here, mirror it
// there too so widget cards match in-app cards.

enum QuestEmojiResolver {
    static func resolve(
        questKey: String,
        title: String,
        description: String,
        category: String,
        funLabel: String? = nil
    ) -> String {
        // (1) Exact quest_key — most-curated, beats any keyword heuristic.
        if let exact = byQuestKey[questKey.lowercased()] {
            return exact
        }

        // (2) Keyword scan — order matters; specific entries are listed first.
        let haystack = "\(title) \(description) \(funLabel ?? "")".lowercased()
        for (keyword, emoji) in keywordTable where haystack.contains(keyword) {
            return emoji
        }

        // (3) Leading emoji from fun_label (server-curated shortcut).
        if let funLabel,
           let first = funLabel.trimmingCharacters(in: .whitespaces).first,
           first.isLikelyEmoji {
            return String(first)
        }

        // (4) Category bucket fallback.
        if let bucket = categoryFallback[category.lowercased()] {
            return bucket
        }

        return "⭐"
    }

    // MARK: Quest-key (exact) table
    //
    // Cover every canonical `QuestKey` enum case + every server-seeded
    // template key from `quest_templates`. Server-side rerolled / friend-named
    // variants reuse the base key so this still hits.
    private static let byQuestKey: [String: String] = [
        // Workout
        "complete_workout":         "💪",
        "complete_program_day":     "📋",
        "complete_2_workouts":      "🏋️",
        "workout_30_min":           "⏱️",
        "exercise_sets_10":         "🎯",
        "exercise_sets_15":         "🎯",
        "exercise_sets_20":         "🎯",
        "exercise_sets_25":         "🎯",
        "try_new_exercise":         "✨",
        "upper_body_workout":       "🦾",
        "lower_body_workout":       "🦵",
        "stretch_session":          "🧘",
        "beat_volume_pr":           "🏆",
        "beat_personal_record":     "🏆",
        "maintain_streak":          "🔥",

        // Nutrition
        "log_breakfast":            "🥣",
        "log_lunch":                "🥗",
        "log_dinner":               "🍽️",
        "log_3_meals":              "🍱",
        "log_snack":                "🍎",
        "log_meal":                 "🍽️",
        "log_water":                "💧",
        "log_water_3":              "💧",
        "log_water_8":              "🚰",
        "hit_protein_goal":         "🥩",
        "log_high_protein_meal":    "🍗",
        "log_all_macros":           "📋",
        "hydration_before_noon":    "💧",

        // Steps & Movement
        "walk_3k_steps":            "🚶",
        "walk_5k_steps":            "🚶‍♂️",
        "walk_7500_steps":          "🥾",
        "walk_10k_steps":           "🏃",
        "hit_step_goal":            "👟",
        "active_minutes_30":        "⏱️",
        "burn_300_calories":        "🔥",
        "sleep_7_hours":            "😴",

        // Social
        "send_challenge":           "⚔️",
        "start_1v1_challenge":      "⚔️",
        "start_1v1_with_top_friend":"⚔️",
        "start_first_challenge":    "🚩",
        "react_to_workout":         "👏",
        "react_to_3_workouts":      "👏",
        "comment_on_friends_workout":"💬",
        "do_friend_workout":        "👯",
        "invite_friend":            "💌",
        "add_friend":               "🤝",
        "beat_friend_steps":        "🥾",
        "league_3_workouts":        "🏆",
        "top_3_league":             "🥇",

        // Tracking / consistency
        "log_weight":               "⚖️",
        "weekly_weigh_in":          "⚖️",
        "check_progress":           "📊",
        "log_cardio":               "❤️",

        // Wildcard / fun
        "perfect_day":              "🌟",
        "early_bird_workout":       "🌅",
        "share_workout":            "📣",
        "favorite_a_workout":       "⭐",

        // Reward
        "watch_ads":                "📺",

        // Strava / outdoor
        "beat_your_5k_pr":          "🏁",
        "negative_split_run":       "📈",
        "run_outside_8km":          "🛣️",
        "cycle_outside_30km":       "🚴",
        "complete_strava_segment":  "📍",

        // Wearable
        "match_yesterday_strain":   "⚡",
        "walk_when_red":            "🟥",

        // Day-1 beginner pack
        "beginner_sync_contacts":   "📇",
        "beginner_add_friend":      "🤝",
        "beginner_send_challenge":  "🚩",
        "beginner_first_workout":   "🎬",
        "beginner_explore_program": "📚"
    ]

    // MARK: Keyword priority table
    //
    // Tuples of `(substring, emoji)` scanned in order; first match wins.
    // Place SPECIFIC entries before GENERIC ones (e.g. "heart health" before
    // "heart", "strawberry" before "berry", "bench press" before "press").
    // All keys lowercased; the haystack is title+description+funLabel.
    private static let keywordTable: [(String, String)] = [
        // ── Health identity ──────────────────────────────────────────────
        ("heart health",     "❤️"),
        ("heart rate",       "❤️"),
        ("cardiovascular",   "❤️"),
        ("blood pressure",   "🩺"),
        ("hrv",              "💓"),
        ("resting hr",       "💓"),
        ("vo2",              "🫁"),
        ("breath",           "🫁"),

        // ── Specific fruits ──────────────────────────────────────────────
        ("strawberr",        "🍓"),
        ("blueberr",         "🫐"),
        ("raspberr",         "🍓"),
        ("blackberr",        "🫐"),
        ("watermelon",       "🍉"),
        ("pineapple",        "🍍"),
        ("avocado",          "🥑"),
        ("banana",           "🍌"),
        ("mango",             "🥭"),
        ("kiwi",             "🥝"),
        ("coconut",          "🥥"),
        ("peach",            "🍑"),
        ("pear",             "🍐"),
        ("cherry",           "🍒"),
        ("lemon",            "🍋"),
        ("orange juice",     "🍊"),
        ("grape",            "🍇"),
        ("apple",            "🍎"),
        ("berry", "🫐"), ("berries", "🫐"),
        ("fruit",            "🍇"),

        // ── Veggies ──────────────────────────────────────────────────────
        ("broccoli",         "🥦"),
        ("carrot",           "🥕"),
        ("tomato",           "🍅"),
        ("corn",             "🌽"),
        ("bell pepper",      "🫑"),
        ("onion",            "🧅"),
        ("garlic",           "🧄"),
        ("potato",           "🥔"),
        ("mushroom",         "🍄"),
        ("lettuce",          "🥬"),
        ("greens",           "🥬"),
        ("kale",             "🥬"),
        ("spinach",          "🥬"),
        ("salad",            "🥗"),

        // ── Protein-foods ────────────────────────────────────────────────
        ("scrambled",        "🍳"),
        ("omelet",           "🍳"),
        ("egg",              "🥚"),
        ("chicken",          "🍗"),
        ("turkey",           "🦃"),
        ("steak",            "🥩"),
        ("beef",             "🥩"),
        ("pork",             "🥓"),
        ("bacon",            "🥓"),
        ("salmon",           "🐟"),
        ("tuna",             "🐟"),
        ("fish",             "🐟"),
        ("shrimp",           "🦐"),
        ("tofu",             "🌱"),
        ("almond",           "🥜"),
        ("peanut",           "🥜"),
        ("nuts",             "🥜"),
        ("yogurt",           "🥛"),
        ("cottage cheese",   "🧀"),
        ("cheese",           "🧀"),
        ("milk",             "🥛"),
        ("protein shake",    "🥤"),
        ("shake",            "🥤"),
        ("smoothie",         "🥤"),
        ("protein",          "🥩"),

        // ── Carbs / breakfast ────────────────────────────────────────────
        ("cereal",           "🥣"),
        ("oatmeal",          "🥣"),
        ("oats",             "🥣"),
        ("porridge",         "🥣"),
        ("granola",          "🥣"),
        ("pancake",          "🥞"),
        ("waffle",           "🧇"),
        ("bagel",            "🥯"),
        ("toast",            "🍞"),
        ("bread",            "🍞"),
        ("croissant",        "🥐"),
        ("pizza",            "🍕"),
        ("burger",           "🍔"),
        ("sandwich",         "🥪"),
        ("burrito",          "🌯"),
        ("taco",             "🌮"),
        ("sushi",            "🍣"),
        ("rice",             "🍚"),
        ("ramen",            "🍜"),
        ("noodle",           "🍜"),
        ("pasta",            "🍝"),
        ("dessert",          "🍰"),
        ("ice cream",        "🍦"),

        // ── Drinks ───────────────────────────────────────────────────────
        ("water",            "💧"),
        ("hydrat",           "💧"),
        ("glass",            "💧"),
        ("coffee",           "☕"),
        ("espresso",         "☕"),
        ("matcha",           "🍵"),
        ("tea",              "🍵"),
        ("juice",            "🧃"),
        ("beer",             "🍺"),
        ("wine",             "🍷"),

        // ── Meal types ───────────────────────────────────────────────────
        ("breakfast",        "🥣"),
        ("brunch",           "🍳"),
        ("lunch",            "🥗"),
        ("dinner",           "🍽️"),
        ("supper",           "🍽️"),
        ("snack",            "🍎"),
        ("3 meals",          "🍱"),
        ("three meals",      "🍱"),
        ("meal prep",        "🍱"),
        ("macro",            "📋"),
        ("calorie",          "🔥"),
        ("calories",         "🔥"),
        ("fasting",          "⏳"),
        ("fast ",            "⏳"),

        // ── Specific lifts / exercises ───────────────────────────────────
        ("deadlift",         "🏋️"),
        ("bench press",      "🏋️"),
        ("squat",            "🦵"),
        ("pushup",           "💪"),
        ("push-up",          "💪"),
        ("push up",          "💪"),
        ("pullup",           "🤸"),
        ("pull-up",          "🤸"),
        ("pull up",          "🤸"),
        ("plank",            "🧍"),
        ("burpee",           "🤸"),
        ("lunge",            "🦵"),
        ("curl",             "💪"),
        ("row ",             "🚣"),
        ("rowing",           "🚣"),
        ("press",            "🏋️"),
        ("abs",              "🧍"),
        ("core",             "🧍"),
        ("leg day",          "🦵"),
        ("leg ",             "🦵"),
        ("arm day",          "💪"),
        ("arm ",             "💪"),
        ("back day",         "🏋️"),
        ("chest",            "🏋️"),
        ("shoulder",         "🏋️"),
        ("glute",            "🍑"),
        ("calf",             "🦵"),
        ("calves",           "🦵"),

        // ── Studio / class formats ───────────────────────────────────────
        ("yoga",             "🧘‍♀️"),
        ("pilates",          "🧘‍♀️"),
        ("meditat",          "🧘‍♂️"),
        ("mindful",          "🧘‍♂️"),
        ("stretch",          "🧘"),
        ("flexibility",      "🧘"),
        ("mobility",         "🧘"),
        ("boxing",           "🥊"),
        ("kickbox",          "🥊"),
        ("punch",            "🥊"),
        ("martial",          "🥋"),
        ("karate",           "🥋"),

        // ── Sports ───────────────────────────────────────────────────────
        ("basketball",       "🏀"),
        ("soccer",           "⚽"),
        ("football",         "🏈"),
        ("baseball",         "⚾"),
        ("tennis",           "🎾"),
        ("golf",             "⛳"),
        ("ping pong",        "🏓"),
        ("table tennis",     "🏓"),
        ("volleyball",       "🏐"),
        ("frisbee",          "🥏"),
        ("ski",              "🎿"),
        ("snowboard",        "🏂"),
        ("skate",            "⛸️"),
        ("surf",             "🏄"),
        ("climb",            "🧗"),
        ("boulder",          "🧗"),

        // ── Cardio ───────────────────────────────────────────────────────
        ("marathon",         "🏃"),
        ("5k",               "🏁"),
        ("10k run",          "🏁"),
        ("sprint",           "💨"),
        ("jog",              "🏃"),
        ("run ",             "🏃"),
        ("running",          "🏃"),
        ("hike",             "🥾"),
        ("trail",            "🥾"),
        ("cycle",            "🚴"),
        ("biking",           "🚴"),
        ("bike ride",        "🚴"),
        ("ride",             "🚴"),
        ("spin class",       "🚴"),
        ("swim",             "🏊"),
        ("pool",             "🏊"),
        ("cardio",           "❤️"),

        // ── Health metrics ───────────────────────────────────────────────
        ("sleep",            "😴"),
        ("bedtime",          "😴"),
        ("rest day",         "🛌"),
        ("recovery",         "🛌"),
        ("recover",          "🛌"),
        ("strain",           "⚡"),
        ("active min",       "⏱️"),
        ("minutes",          "⏱️"),
        ("duration",         "⏱️"),
        ("burn",             "🔥"),
        ("scale",            "⚖️"),
        ("weigh",            "⚖️"),
        ("weight in",        "⚖️"),

        // ── Time of day ──────────────────────────────────────────────────
        ("early bird",       "🌅"),
        ("sunrise",          "🌅"),
        ("morning",          "🌅"),
        ("am workout",       "🌅"),
        ("evening",          "🌇"),
        ("sunset",           "🌇"),
        ("night",            "🌙"),
        ("late",             "🌙"),
        ("noon",             "☀️"),
        ("afternoon",        "☀️"),

        // ── Streaks / records / leaderboard ──────────────────────────────
        ("streak",           "🔥"),
        ("personal record",  "🏆"),
        ("personal best",    "🏆"),
        (" pr ",             "🏆"),
        ("beat your",        "🏆"),
        ("trophy",           "🏆"),
        ("first place",      "🥇"),
        ("1st",              "🥇"),
        ("top 3",            "🥇"),
        ("leaderboard",      "🥇"),
        ("rank",             "🥇"),
        ("league",           "🏆"),

        // ── Social ───────────────────────────────────────────────────────
        ("1v1",              "⚔️"),
        ("duel",             "⚔️"),
        ("challenge",        "⚔️"),
        ("rival",            "😎"),
        ("hype",             "👏"),
        ("cheer",            "📣"),
        ("clap",             "👏"),
        ("applaud",          "👏"),
        ("react",            "👏"),
        ("comment",          "💬"),
        ("invite",           "💌"),
        ("share",            "📣"),
        ("crew",             "👯"),
        ("squad",            "👯"),
        ("group",            "👯"),
        ("contact",          "📇"),
        ("buddy",            "🤝"),
        ("friend",           "🤝"),

        // ── Tracking / progress ──────────────────────────────────────────
        ("dashboard",        "📊"),
        ("progress",         "📊"),
        ("track",            "📊"),
        ("journal",          "📓"),
        ("log",              "📝"),
        ("photo",            "📸"),
        ("selfie",           "📸"),

        // ── Wildcard / fun ───────────────────────────────────────────────
        ("perfect",          "🌟"),
        ("explore",          "🧭"),
        ("discover",         "🧭"),
        ("favorite",         "⭐"),
        ("rainbow",          "🌈"),
        ("treasure",         "💰"),
        ("rocket",           "🚀"),
        ("launch",           "🚀"),
        ("celebration",      "🎉"),
        ("party",            "🎉"),
        ("magic",            "🪄"),
        ("lucky",            "🍀"),
        ("luck",             "🍀"),
        ("secret",           "🤫"),

        // ── Reward / monetization ────────────────────────────────────────
        ("watch ad",         "📺"),
        ("ads",              "📺"),
        ("video",            "📺"),
        ("bonus",            "🎁"),
        ("reward",           "🎁"),
        ("gift",             "🎁"),
        ("coin",             "🪙"),
        ("token",            "🪙"),
        ("diamond",          "💎"),
        ("premium",          "💎"),

        // ── Environment ──────────────────────────────────────────────────
        ("outdoor",          "🌳"),
        ("outside",          "🌳"),
        ("park",             "🌳"),
        ("indoor",           "🏠"),
        ("home workout",     "🏠"),
        ("gym",              "🏋️"),
        ("segment",          "📍"),
        ("mountain",         "🏔️"),
        ("summit",           "🏔️"),

        // ── Beginner ─────────────────────────────────────────────────────
        ("first workout",    "🎬"),
        ("first time",       "🎬"),
        ("welcome",          "👋"),
        ("beginner",         "🎬"),

        // ── Generic exercise verbs (lowest-priority before category) ─────
        ("workout",          "💪"),
        ("exercise",         "💪"),
        ("training",         "💪"),
        ("lift",             "🏋️"),
        ("sets",             "🎯"),
        ("reps",             "🎯"),
        ("walk",             "🚶"),
        ("step",             "👟"),
        ("nutrition",        "🥗"),
        ("meal",             "🍽️")
    ]

    // MARK: Category fallback
    private static let categoryFallback: [String: String] = [
        "workout":   "💪",
        "nutrition": "🥗",
        "social":    "👥",
        "steps":     "👟",
        "tracking":  "📊",
        "wildcard":  "🌟",
        "reward":    "🎁",
        "recovery":  "🛌",
        "wellness":  "🧘"
    ]
}

private extension Character {
    /// Best-effort emoji check — passes for grapheme clusters whose first
    /// scalar is in the emoji range. Avoids misclassifying plain ASCII (e.g.
    /// the leading "J" in "Just show up") as an emoji.
    var isLikelyEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && scalar.value > 0x238C
    }
}
