import SwiftUI
import Combine

// MARK: - Achievement Model

struct AchievementItem: Codable, Identifiable {
    let achievementKey: String
    let title: String
    let description: String
    let icon: String
    let category: String
    let threshold: Int
    let xpReward: Int
    let rarity: String
    let progress: Int
    let unlockedAt: String?
    let sortOrder: Int
    
    var id: String { achievementKey }
    var isUnlocked: Bool { unlockedAt != nil }
    var progressPercent: Double {
        guard threshold > 0 else { return 0 }
        return min(1.0, Double(progress) / Double(threshold))
    }
    
    var rarityColor: Color {
        switch rarity {
        case "common": return .gray
        case "uncommon": return .green
        case "rare": return .blue
        case "epic": return .purple
        case "legendary": return .orange
        default: return .gray
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case achievementKey = "achievement_key"
        case title, description, icon, category, threshold
        case xpReward = "xp_reward"
        case rarity, progress
        case unlockedAt = "unlocked_at"
        case sortOrder = "sort_order"
    }
}

struct UnlockResult: Codable {
    let unlocked: Bool
    let achievementTitle: String?
    let achievementIcon: String?
    let achievementRarity: String?
    let xpReward: Int?
    
    enum CodingKeys: String, CodingKey {
        case unlocked
        case achievementTitle = "achievement_title"
        case achievementIcon = "achievement_icon"
        case achievementRarity = "achievement_rarity"
        case xpReward = "xp_reward"
    }
}

// MARK: - Badge Service (Supabase-backed achievements)

class BadgeService: ObservableObject {
    static let shared = BadgeService()
    
    @Published var achievements: [AchievementItem] = []
    @Published var showUnlockToast = false
    @Published var lastUnlockedAchievement: AchievementItem?
    
    var unlockedCount: Int { achievements.filter(\.isUnlocked).count }
    var totalCount: Int { achievements.count }
    
    private init() {}
    
    // MARK: - Fetch
    
    func fetchAchievements(forUserId userId: UUID? = nil) async {
        do {
            var params: [String: String] = [:]
            if let userId = userId {
                params["p_user_id"] = userId.uuidString
            }
            
            let result: [AchievementItem] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_user_achievements", params: params)
                .execute()
                .value
            
            await MainActor.run {
                self.achievements = result
            }
        } catch {
            AppLogger.error("Failed to fetch achievements: \(error.localizedDescription)", category: .general)
        }
    }
    
    // MARK: - Unlock Check
    
    @discardableResult
    func checkAndUnlock(key: String, progress: Int = 1) async -> Bool {
        do {
            struct UnlockParams: Encodable {
                let p_achievement_key: String
                let p_progress: Int
            }
            
            let results: [UnlockResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("unlock_achievement", params: UnlockParams(
                    p_achievement_key: key,
                    p_progress: progress
                ))
                .execute()
                .value
            return await handleUnlockResult(results: results, key: key)
        } catch {
            AppLogger.error("Failed to check achievement \(key): \(error.localizedDescription)", category: .general)
            return false
        }
    }

    /// Additive variant — calls `increment_achievement_progress` server-side.
    /// Use this when the iOS only sees event deltas (reactions sent, meals
    /// logged, etc.) and doesn't have a stable lifetime counter to pass to
    /// `checkAndUnlock`.
    @discardableResult
    func incrementAndUnlock(key: String, by delta: Int = 1) async -> Bool {
        guard delta > 0 else { return false }
        do {
            struct IncParams: Encodable {
                let p_achievement_key: String
                let p_delta: Int
            }

            let results: [UnlockResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("increment_achievement_progress", params: IncParams(
                    p_achievement_key: key,
                    p_delta: delta
                ))
                .execute()
                .value
            return await handleUnlockResult(results: results, key: key)
        } catch {
            AppLogger.error("Failed to increment achievement \(key): \(error.localizedDescription)", category: .general)
            return false
        }
    }

    /// Shared post-RPC handling for both `checkAndUnlock` and
    /// `incrementAndUnlock` — XP credit, toast cache, and refresh.
    private func handleUnlockResult(results: [UnlockResult], key: String) async -> Bool {
        guard let result = results.first, result.unlocked else { return false }

        if let xp = result.xpReward, xp > 0 {
            await MainActor.run {
                UserManager.shared.addXP(Int32(xp))
            }
        }

        await MainActor.run {
            if let match = self.achievements.first(where: { $0.achievementKey == key }) {
                self.lastUnlockedAchievement = match
            } else if let title = result.achievementTitle {
                self.lastUnlockedAchievement = AchievementItem(
                    achievementKey: key,
                    title: title,
                    description: "",
                    icon: result.achievementIcon ?? "star.fill",
                    category: "special",
                    threshold: 1,
                    xpReward: result.xpReward ?? 0,
                    rarity: result.achievementRarity ?? "common",
                    progress: 1,
                    unlockedAt: ISO8601DateFormatter().string(from: Date()),
                    sortOrder: 0
                )
            }
            self.showUnlockToast = true
        }

        await fetchAchievements()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            self.showUnlockToast = false
        }

        return true
    }
    
    // MARK: - Convenience Checkers
    //
    // 2026-05-04 — Olympian Path: every convenience helper now fans out to
    // the matching `olympian_<currentYear>_*` mirror keys so the same event
    // (workout, friend, PR, etc.) progresses both the legacy badge AND the
    // user's personalized 33-goal path. Mirror keys are no-ops when the
    // user's archetype path doesn't include them; the server short-circuits
    // unknown keys.

    private static var olympianYearPrefix: String {
        "olympian_\(Calendar.current.component(.year, from: Date()))"
    }

    func onWorkoutCompleted(totalWorkouts: Int) async {
        await checkAndUnlock(key: "first_workout", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_10", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_50", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_100", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_500", progress: totalWorkouts)

        // Olympian Path mirrors (universal + per-archetype workout counters)
        let p = Self.olympianYearPrefix
        await checkAndUnlock(key: "\(p)_first_workout",   progress: totalWorkouts)
        await checkAndUnlock(key: "\(p)_workouts_100",    progress: totalWorkouts)
        // Strength path mirrors (silent no-op for non-strength users)
        await checkAndUnlock(key: "\(p)_str_first_lift",  progress: totalWorkouts)
        await checkAndUnlock(key: "\(p)_str_workouts_5",  progress: totalWorkouts)
        await checkAndUnlock(key: "\(p)_str_workouts_25", progress: totalWorkouts)
        await checkAndUnlock(key: "\(p)_str_workouts_50", progress: totalWorkouts)
        await checkAndUnlock(key: "\(p)_str_workouts_75", progress: totalWorkouts)
        await checkAndUnlock(key: "\(p)_str_workouts_150",progress: totalWorkouts)

        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 {
            await checkAndUnlock(key: "early_bird")
        }
        if hour >= 22 {
            await checkAndUnlock(key: "night_owl")
        }
    }
    
    func onStreakUpdated(streak: Int) async {
        await checkAndUnlock(key: "streak_7", progress: streak)
        await checkAndUnlock(key: "streak_14", progress: streak)
        await checkAndUnlock(key: "streak_30", progress: streak)
        await checkAndUnlock(key: "streak_60", progress: streak)
        await checkAndUnlock(key: "streak_100", progress: streak)

        let p = Self.olympianYearPrefix
        await checkAndUnlock(key: "\(p)_streak_7",   progress: streak)
        await checkAndUnlock(key: "\(p)_streak_14",  progress: streak)
        await checkAndUnlock(key: "\(p)_streak_30",  progress: streak)
        await checkAndUnlock(key: "\(p)_streak_60",  progress: streak)
        await checkAndUnlock(key: "\(p)_streak_100", progress: streak)
    }
    
    func onFriendAdded(totalFriends: Int) async {
        await checkAndUnlock(key: "first_friend", progress: totalFriends)
        await checkAndUnlock(key: "friends_10", progress: totalFriends)

        let p = Self.olympianYearPrefix
        await checkAndUnlock(key: "\(p)_first_friend",  progress: totalFriends)
        await checkAndUnlock(key: "\(p)_str_friends_10", progress: totalFriends)
        await checkAndUnlock(key: "\(p)_end_friends_10", progress: totalFriends)
    }
    
    func onChallengeWon(totalWins: Int) async {
        await checkAndUnlock(key: "first_challenge_won", progress: totalWins)
        await checkAndUnlock(key: "challenges_won_10", progress: totalWins)

        let p = Self.olympianYearPrefix
        await checkAndUnlock(key: "\(p)_won_challenge", progress: totalWins)
    }
    
    func onMealLogged(totalMeals: Int) async {
        await checkAndUnlock(key: "first_meal_logged", progress: totalMeals)
        await checkAndUnlock(key: "meals_logged_100", progress: totalMeals)

        let p = Self.olympianYearPrefix
        await checkAndUnlock(key: "\(p)_first_meal", progress: totalMeals)
        await checkAndUnlock(key: "\(p)_wl_meals_5",   progress: totalMeals)
        await checkAndUnlock(key: "\(p)_wl_meals_30",  progress: totalMeals)
        await checkAndUnlock(key: "\(p)_wl_meals_50",  progress: totalMeals)
        await checkAndUnlock(key: "\(p)_wl_meals_100", progress: totalMeals)
        await checkAndUnlock(key: "\(p)_wl_meals_200", progress: totalMeals)
    }
    
    func onWorkoutShared() async {
        await checkAndUnlock(key: "first_workout_shared")

        let p = Self.olympianYearPrefix
        await checkAndUnlock(key: "\(p)_send_challenge")
    }
    
    /// Increment-style: server adds `delta` to lifetime reactions count.
    /// Use when iOS only sees the per-reaction event (no lifetime counter).
    func onReactionSent(delta: Int = 1) async {
        await incrementAndUnlock(key: "reactions_sent_50", by: delta)

        let p = Self.olympianYearPrefix
        await incrementAndUnlock(key: "\(p)_react_25",         by: delta)
        await incrementAndUnlock(key: "\(p)_str_react_friend", by: delta)
        await incrementAndUnlock(key: "\(p)_end_react_friend", by: delta)
        await incrementAndUnlock(key: "\(p)_str_react_50",     by: delta)
        await incrementAndUnlock(key: "\(p)_end_react_50",     by: delta)
    }
    
    func onPersonalRecord(totalPRs: Int = 1) async {
        await checkAndUnlock(key: "first_pr", progress: totalPRs)

        let p = Self.olympianYearPrefix
        await checkAndUnlock(key: "\(p)_first_pr",   progress: totalPRs)
        await checkAndUnlock(key: "\(p)_str_pr_5",   progress: totalPRs)
        await checkAndUnlock(key: "\(p)_str_pr_10",  progress: totalPRs)
        await checkAndUnlock(key: "\(p)_str_pr_20",  progress: totalPRs)
    }

    // MARK: - Weekly League — Tier + Milestone unlock hooks
    //
    // 2026-04-29 — League Redesign Plan §B1 + Sprint 3 polish.
    // The achievements ladder reflowed from 50-level to 7-tier + 5-milestone
    // in `WorkoutProgressView`. These two methods are the unlock pipeline:
    // `WeeklyLeagueService.detectAndQueueTierPromotion` calls them when a
    // promotion or league moment fires, so the achievement unlock toast
    // appears alongside the `TierPromotionOverlay`. Achievement keys
    // (e.g. `tier_2`, `milestone_first_crown`) are server-seeded; this
    // method silently no-ops when a key has no row, so hot-path Swift
    // code is safe to call before the seed migration ships.

    /// Unlocks the tier achievement for the rank the user just reached.
    /// Idempotent — `checkAndUnlock` short-circuits when the achievement
    /// is already unlocked.
    func onTierAchieved(tierRank: Int) async {
        guard tierRank >= 1, tierRank <= 7 else { return }
        await checkAndUnlock(key: "tier_\(tierRank)")
    }

    /// Unlocks a league milestone achievement keyed by the milestone id.
    /// Recognized keys: `milestone_first_crown`, `milestone_stand_out`,
    /// `milestone_bounceback`, `milestone_shield_burned`, `milestone_verified`.
    /// Caller is responsible for the variant → key mapping.
    func onLeagueMilestone(key: String) async {
        guard key.hasPrefix("milestone_") else { return }
        await checkAndUnlock(key: key)
    }
}
