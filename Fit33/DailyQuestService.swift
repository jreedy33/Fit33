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
    
    // MARK: - Legacy keys (for backwards compat with existing quests)
    case logMeal = "log_meal"
    case logWater = "log_water"
    case exerciseSets10 = "exercise_sets_10"
    case exerciseSets20 = "exercise_sets_20"
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
    
    /// Collects current user context for personalized quest selection
    private func gatherUserContext() -> (hasProgram: Bool, hasFriends: Bool, hasChallenge: Bool, stepGoal: Int, fitnessGoal: String) {
        // Check for active program (cloud or generated)
        let hasCloudProgram = CloudProgramService.shared.activeProgram != nil
        let hasGeneratedProgram = GeneratedProgramService.shared.activeProgram != nil
        let hasSmartProgram = SmartProgramEngine.shared.userPrograms.contains { !$0.isCompleted }
        let hasProgram = hasCloudProgram || hasGeneratedProgram || hasSmartProgram
        
        // Check for friends
        let hasFriends = !FriendService.shared.friends.isEmpty
        
        // Check for active challenges (1v1 or group)
        let hasChallenge = !ChallengeService.shared.activeChallenges.isEmpty || 
                           !ChallengeService.shared.activeGroupChallenges.isEmpty
        
        // Step goal
        let stepGoal = HealthKitManager.shared.stepGoal
        
        // Fitness goal from user profile
        let fitnessGoal = UserManager.shared.currentUser?.fitnessGoal ?? "general"
        
        return (hasProgram, hasFriends, hasChallenge, stepGoal, fitnessGoal)
    }
    
    // MARK: - Fetch Daily Quests
    
    func fetchDailyQuests(force: Bool = false) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("📋 [QUESTS] ⚠️ No currentUser — skipping fetch")
            return
        }
        
        // Throttle
        if !force, let cacheDate = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
           Date().timeIntervalSince(cacheDate) < cacheDuration,
           !quests.isEmpty {
            print("📋 [QUESTS] Throttled — using cache (\(quests.count) quests)")
            return
        }
        
        print("📋 [QUESTS] Fetching daily quests for user \(userId.uuidString.prefix(8))...")
        isLoading = true
        error = nil
        
        // Gather user context for personalized quest selection
        let ctx = gatherUserContext()
        
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
            }
            
            let params = GetDailyQuestsParams(
                p_user_id: userId.uuidString,
                p_timezone: TimeZone.current.identifier,
                p_has_program: ctx.hasProgram,
                p_has_friends: ctx.hasFriends,
                p_has_challenge: ctx.hasChallenge,
                p_step_goal: ctx.stepGoal,
                p_fitness_goal: ctx.fitnessGoal,
                p_is_subscriber: PremiumManager.shared.isPremiumUser
            )
            
            let response: DailyQuestsResponse = try await SupabaseManager.shared.supabaseClient
                .rpc("get_daily_quests", params: params)
                .execute()
                .value
            
            self.quests = response.quests ?? []
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
            print("📋 [QUESTS] Fetched \(quests.count) quests (\(completed)/\(quests.count) done), streak: \(response.streak), profile: \(response.difficultyProfile ?? "?")")
            for q in quests {
                print("   → \(q.questKey): \"\(q.title)\" [\(q.difficulty)] \(q.isCompleted ? "✅" : "⬜")")
            }
            #endif
            
            // If the watch_ads quest is active and not completed, preload a rewarded ad
            if hasQuest(.watchAds) {
                AdManager.shared.prepareRewardedAd()
            }
            
        } catch {
            self.error = error.localizedDescription
            print("❌ [QUESTS] Failed to fetch: \(error)")
            print("❌ [QUESTS] Error details: \(error.localizedDescription)")
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
            print("📋 [QUESTS] Quest '\(questKey.rawValue)' not active today, skipping")
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
                print("📋 [QUESTS] Progress update returned false: \(result.reason ?? "unknown")")
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
                    print("✅ [QUESTS] Completed '\(questKey.rawValue)' (+\(old.xpReward) XP, +\(old.leaguePoints) league pts)")
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
                    print("🎉 [QUESTS] ALL QUESTS COMPLETE! Bonus: +\(bonusXp) XP, +\(bonusLeaguePoints) league pts")
                    #endif
                }
                
                cacheQuests()
            }
            
        } catch {
            #if DEBUG
            print("⚠️ [QUESTS] Failed to update progress: \(error)")
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
    
    /// Call when a workout targets specific body parts
    func onWorkoutWithFocus(bodyParts: Set<String>) async {
        let upperBodyParts: Set<String> = ["chest", "back", "shoulders", "arms", "biceps", "triceps"]
        let lowerBodyParts: Set<String> = ["legs", "quads", "hamstrings", "glutes", "calves"]
        
        let isUpperBody = !bodyParts.intersection(upperBodyParts).isEmpty
        let isLowerBody = !bodyParts.intersection(lowerBodyParts).isEmpty
        
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
    
    /// Call when step count updates (pass total steps for today)
    func onStepsUpdated(todaySteps: Int) async {
        let delta = todaySteps - lastReportedSteps
        guard delta > 0 else { return }
        
        if todaySteps >= 3000 {
            await reportProgress(questKey: .walk3kSteps, increment: delta)
        }
        if todaySteps >= 5000 {
            await reportProgress(questKey: .walk5kSteps, increment: delta)
        }
        if todaySteps >= 7500 {
            await reportProgress(questKey: .walk7500Steps, increment: delta)
        }
        if todaySteps >= 10000 {
            await reportProgress(questKey: .walk10kSteps, increment: delta)
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
            return
        }
        
        // Only load cache if it's from today
        let today = Calendar.current.startOfDay(for: Date())
        if let cacheDate = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
           Calendar.current.isDate(cacheDate, inSameDayAs: today) {
            self.quests = cached.quests ?? []
            self.allComplete = cached.allComplete
            self.bonusXp = cached.bonusXp
            self.bonusLeaguePoints = cached.bonusLeaguePoints
            self.questStreak = cached.streak
            self.longestStreak = cached.longestStreak
            self.totalCompleted = cached.totalCompleted
            self.difficultyProfile = cached.difficultyProfile
        }
    }
}
