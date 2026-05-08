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

/// Phase 5.D — one row of `batch_check_achievements` server output.
/// `justUnlocked == true` is the trigger to fan out a celebration toast +
/// XP credit (the per-key `unlock_achievement` shape lives in `UnlockResult`
/// above; this one carries the extra columns the batch RPC returns so we
/// don't lose progress / unlocked_at fidelity at the seam).
struct BatchAchievementRow: Decodable {
    let achievementKey: String
    let progressValue: Int
    let isUnlocked: Bool
    let unlockedAt: String?
    let justUnlocked: Bool
    let achievementTitle: String?
    let achievementIcon: String?
    let achievementRarity: String?
    let xpReward: Int?

    enum CodingKeys: String, CodingKey {
        case achievementKey = "achievement_key"
        case progressValue = "progress_value"
        case isUnlocked = "is_unlocked"
        case unlockedAt = "unlocked_at"
        case justUnlocked = "just_unlocked"
        case achievementTitle = "achievement_title"
        case achievementIcon = "achievement_icon"
        case achievementRarity = "achievement_rarity"
        case xpReward = "xp_reward"
    }

    /// Project this batch row onto the canonical single-RPC `UnlockResult`
    /// shape so the post-unlock fan-out (`handleUnlockResult`) can run
    /// unchanged regardless of which RPC variant produced the row.
    var asUnlockResult: UnlockResult {
        UnlockResult(
            unlocked: justUnlocked,
            achievementTitle: achievementTitle,
            achievementIcon: achievementIcon,
            achievementRarity: achievementRarity,
            xpReward: xpReward
        )
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

    /// When > 0, `checkAndUnlock` / `incrementAndUnlock` skip per-call
    /// `fetchAchievements`, unlock toasts, and `lastUnlockedAchievement`
    /// fan-out — used by `resyncOlympianProgressFromLocalTotals()` so a
    /// first-open backfill doesn't spam 20+ celebration toasts.
    private var achievementSyncBatchDepth: Int = 0
    
    private init() {}
    
    // MARK: - Fetch
    
    /// Fetch the canonical achievements row set into `self.achievements`.
    ///
    /// `transientLevel` controls the log level for transient/cancellation
    /// errors classified by `NetworkErrorClassifier` (default `.warning`,
    /// matching today's QP invariant 25a behavior). Phase 6 OlympianPath
    /// integration passes `.debug` on the first attempt (knows it will
    /// retry, so a single transient cancellation isn't worth a warning)
    /// and `.warning` for the retry attempt. All non-transient errors
    /// (real network / RLS / decode failures) still log at their
    /// classifier-determined level regardless of this parameter.
    func fetchAchievements(
        forUserId userId: UUID? = nil,
        transientLevel: AppLogger.Level = .warning
    ) async {
        let startedAt = Date()
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
            // QP invariant 25a: route through NetworkErrorClassifier so
            // CancellationError (tab switch / dashboard re-render mid-fetch)
            // and transient 401s classify as `.transientNetwork` (warning,
            // no fingerprint) instead of manufacturing a bug-intel
            // fingerprint per occurrence. Closes `878468de` (28 occ × 3 users).
            //
            // Phase 6 OlympianPath: when `transientLevel` is `.debug`, the
            // OlympianPath atomic gate has already committed to a retry
            // pass — silencing the first-attempt cancellation to .debug
            // matches the prompt's step-5 routing while keeping any
            // retry-fail visible at .warning.
            NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch achievements",
                category: .general,
                transientLevel: transientLevel,
                op: PerformanceSignposts.Op.achievementFetch.rawValue,
                endpoint: "rpc/get_user_achievements",
                startedAt: startedAt,
                userId: userId ?? SupabaseManager.shared.currentUser?.id
            )
        }
    }
    
    // MARK: - Unlock Check
    
    @discardableResult
    func checkAndUnlock(key: String, progress: Int = 1) async -> Bool {
        let startedAt = Date()
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
            let unlocked = await handleUnlockResult(results: results, key: key)
            if achievementSyncBatchDepth == 0 {
                await fetchAchievements()
            }
            return unlocked
        } catch {
            // QP invariant 25a: every fanout `onWorkoutCompleted` /
            // `onMealLogged` / etc. invokes `checkAndUnlock` for ~10–20
            // achievement keys in parallel. When the user navigates
            // (tab switch on Dashboard return after workout finish),
            // every in-flight RPC throws `CancellationError` → bare
            // `AppLogger.error` previously fired a fingerprint per key.
            // Closes `40779673`/`5c5d0f3c`/`43add712`/`a7b890fd`/
            // `3840b05d`/`a5e13a94`/`dfb5892d`/`8a3fbd08` cluster (357+
            // occurrences across 4 users on build 1.39 (68)).
            NetworkErrorClassifier.log(
                error,
                context: "Failed to check achievement \(key)",
                category: .general,
                op: PerformanceSignposts.Op.achievementCheck.rawValue,
                endpoint: "rpc/unlock_achievement",
                startedAt: startedAt,
                userId: SupabaseManager.shared.currentUser?.id
            )
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
        let startedAt = Date()
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
            let unlocked = await handleUnlockResult(results: results, key: key)
            if achievementSyncBatchDepth == 0 {
                await fetchAchievements()
            }
            return unlocked
        } catch {
            // Same routing rationale as `checkAndUnlock` above. Companion
            // call site for additive-delta achievement progress.
            NetworkErrorClassifier.log(
                error,
                context: "Failed to increment achievement \(key)",
                category: .general,
                op: PerformanceSignposts.Op.achievementIncrement.rawValue,
                endpoint: "rpc/increment_achievement_progress",
                startedAt: startedAt,
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }

    /// Shared post-RPC handling for both `checkAndUnlock` and
    /// `incrementAndUnlock` — XP credit, toast cache (unless batched).
    private func handleUnlockResult(results: [UnlockResult], key: String) async -> Bool {
        guard let result = results.first, result.unlocked else { return false }

        if let xp = result.xpReward, xp > 0 {
            await MainActor.run {
                UserManager.shared.addXP(Int32(xp))
            }
        }

        let silentBatch = achievementSyncBatchDepth > 0
        if !silentBatch {
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

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                self.showUnlockToast = false
            }
        }

        return true
    }
    
    // MARK: - Batch Coalescer (Phase 5.D)
    //
    // 2026-05-07 — `PerfFlags.phase5BatchAchievements` collapses N parallel
    // `unlock_achievement` RPCs into a single `batch_check_achievements`
    // round-trip. Every per-event helper below (`onWorkoutCompleted`,
    // `onStreakUpdated`, etc.) routes through `batchCheckAndUnlock` so the
    // flag flips the entire surface in one place. When the flag is OFF, we
    // fall back to the existing per-key serial fan-out for behavioral
    // parity (and as the rollback path).
    //
    // Side-effect parity is enforced server-side: see
    // `supabase/20260507_batch_check_achievements.sql` — the per-key LOOP
    // body replicates the GREATEST-upsert + unlocked_at stamp + xp_reward
    // award + tail-call to `complete_olympian_season_if_done` exactly as
    // `unlock_achievement` does today.

    /// Issues a single `batch_check_achievements` RPC for the supplied
    /// `(key, progress)` pairs. Falls back to the per-key serial fan-out
    /// when `PerfFlags.phase5BatchAchievements` is OFF. Returns the count
    /// of achievements that newly unlocked on this call (mirrors the
    /// per-key path's `Bool` return summed across all keys).
    @discardableResult
    private func batchCheckAndUnlock(_ pairs: [(key: String, progress: Int)]) async -> Int {
        guard !pairs.isEmpty else { return 0 }

        if !PerfFlags.phase5BatchAchievements {
            // Off-flag fallback: preserve today's serial fan-out exactly.
            // `checkAndUnlock` itself triggers `fetchAchievements()` per call
            // (when depth=0), so the off-flag path matches pre-Phase-5.D
            // behavior bit-for-bit.
            var unlocked = 0
            for pair in pairs {
                if await checkAndUnlock(key: pair.key, progress: pair.progress) {
                    unlocked += 1
                }
            }
            return unlocked
        }

        let startedAt = Date()
        do {
            struct BatchParams: Encodable {
                let p_achievement_keys: [String]
                let p_progress_values: [Int]
            }

            let rows: [BatchAchievementRow] = try await SupabaseManager.shared.supabaseClient
                .rpc("batch_check_achievements", params: BatchParams(
                    p_achievement_keys: pairs.map(\.key),
                    p_progress_values: pairs.map(\.progress)
                ))
                .execute()
                .value

            var unlocked = 0
            for row in rows where row.justUnlocked {
                // Reuse the canonical post-unlock side-effect cascade
                // (XP credit on the iOS side + toast cache + lastUnlocked
                // observable). The server already wrote the XP delta; the
                // local `UserManager.addXP` call is the iOS-side mirror
                // that updates the in-memory profile + Core Data row.
                if await handleUnlockResult(results: [row.asUnlockResult], key: row.achievementKey) {
                    unlocked += 1
                }
            }

            // Single end-of-batch refetch matches the per-key path's
            // `await fetchAchievements()` post-condition (depth>0 callers
            // suppress; depth=0 callers see the latest server state).
            if achievementSyncBatchDepth == 0 {
                await fetchAchievements()
            }
            return unlocked
        } catch {
            // QP invariant 25a: route batch failures through the same
            // classifier as the per-key path so a tab-switch
            // CancellationError or transient 401 stays at `.warning`
            // (no fingerprint) instead of manufacturing one. The whole
            // point of Phase 5.D is to STOP these warnings appearing
            // 24× per cold start by collapsing the fan-out — this
            // catch is the safety net for the single batch call.
            NetworkErrorClassifier.log(
                error,
                context: "Failed to batch check \(pairs.count) achievements",
                category: .general,
                op: PerformanceSignposts.Op.achievementCheck.rawValue,
                endpoint: "rpc/batch_check_achievements",
                startedAt: startedAt,
                userId: SupabaseManager.shared.currentUser?.id
            )
            return 0
        }
    }

    // MARK: - Convenience Checkers
    //
    // 2026-05-04 — Olympian Path: every convenience helper now fans out to
    // the matching `olympian_<currentYear>_*` mirror keys so the same event
    // (workout, friend, PR, etc.) progresses both the legacy badge AND the
    // user's personalized 33-goal path. Mirror keys are no-ops when the
    // user's archetype path doesn't include them; the server short-circuits
    // unknown keys.
    //
    // 2026-05-07 — Each helper builds a `[(key, progress)]` array and hands
    // it to `batchCheckAndUnlock`. With `PerfFlags.phase5BatchAchievements`
    // ON, the helper makes ONE round-trip per call; OFF, it falls back to
    // the original per-key serial fan-out.

    /// Mirrors use `olympian_<poolYear>_…` keys seeded in Postgres. Pool year
    /// comes from `assign_olympian_path` (stored in UserDefaults by
    /// `OlympianPathService`) so it stays aligned with the active achievement
    /// pool; falls back to the calendar year before the first path load.
    private static func olympianMirrorPrefix() -> String {
        let stored = UserDefaults.standard.integer(forKey: OlympianPathService.mirrorPoolYearDefaultsKey)
        let calYear = Calendar.current.component(.year, from: Date())
        let y = stored > 0 ? stored : calYear
        return "olympian_\(y)"
    }

    func onWorkoutCompleted(totalWorkouts: Int) async {
        let p = Self.olympianMirrorPrefix()
        var pairs: [(key: String, progress: Int)] = [
            ("first_workout",          totalWorkouts),
            ("workouts_10",            totalWorkouts),
            ("workouts_50",            totalWorkouts),
            ("workouts_100",           totalWorkouts),
            ("workouts_500",           totalWorkouts),
            // Olympian Path mirrors (universal + per-archetype workout counters)
            ("\(p)_first_workout",     totalWorkouts),
            ("\(p)_workouts_100",      totalWorkouts),
            // Strength path mirrors (silent no-op for non-strength users)
            ("\(p)_str_first_lift",    totalWorkouts),
            ("\(p)_str_workouts_5",    totalWorkouts),
            ("\(p)_str_workouts_25",   totalWorkouts),
            ("\(p)_str_workouts_50",   totalWorkouts),
            ("\(p)_str_workouts_75",   totalWorkouts),
            ("\(p)_str_workouts_150",  totalWorkouts),
        ]

        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 { pairs.append(("early_bird", 1)) }
        if hour >= 22 { pairs.append(("night_owl", 1)) }

        await batchCheckAndUnlock(pairs)
    }
    
    func onStreakUpdated(streak: Int) async {
        let p = Self.olympianMirrorPrefix()
        await batchCheckAndUnlock([
            ("streak_7",         streak),
            ("streak_14",        streak),
            ("streak_30",        streak),
            ("streak_60",        streak),
            ("streak_100",       streak),
            ("\(p)_streak_7",    streak),
            ("\(p)_streak_14",   streak),
            ("\(p)_streak_30",   streak),
            ("\(p)_streak_60",   streak),
            ("\(p)_streak_100",  streak),
        ])
    }
    
    func onFriendAdded(totalFriends: Int) async {
        let p = Self.olympianMirrorPrefix()
        await batchCheckAndUnlock([
            ("first_friend",         totalFriends),
            ("friends_10",           totalFriends),
            ("\(p)_first_friend",    totalFriends),
            ("\(p)_str_friends_10",  totalFriends),
            ("\(p)_end_friends_10",  totalFriends),
        ])
    }
    
    func onChallengeWon(totalWins: Int) async {
        let p = Self.olympianMirrorPrefix()
        await batchCheckAndUnlock([
            ("first_challenge_won",  totalWins),
            ("challenges_won_10",    totalWins),
            ("\(p)_won_challenge",   totalWins),
        ])
    }
    
    func onMealLogged(totalMeals: Int) async {
        let p = Self.olympianMirrorPrefix()
        await batchCheckAndUnlock([
            ("first_meal_logged",   totalMeals),
            ("meals_logged_100",    totalMeals),
            ("\(p)_first_meal",     totalMeals),
            ("\(p)_wl_meals_5",     totalMeals),
            ("\(p)_wl_meals_30",    totalMeals),
            ("\(p)_wl_meals_50",    totalMeals),
            ("\(p)_wl_meals_100",   totalMeals),
            ("\(p)_wl_meals_200",   totalMeals),
        ])
    }
    
    func onWorkoutShared() async {
        let p = Self.olympianMirrorPrefix()
        await batchCheckAndUnlock([
            ("first_workout_shared", 1),
            ("\(p)_send_challenge",  1),
        ])
    }
    
    /// Increment-style: server adds `delta` to lifetime reactions count.
    /// Use when iOS only sees the per-reaction event (no lifetime counter).
    func onReactionSent(delta: Int = 1) async {
        await incrementAndUnlock(key: "reactions_sent_50", by: delta)

        let p = Self.olympianMirrorPrefix()
        await incrementAndUnlock(key: "\(p)_react_25",         by: delta)
        await incrementAndUnlock(key: "\(p)_str_react_friend", by: delta)
        await incrementAndUnlock(key: "\(p)_end_react_friend", by: delta)
        await incrementAndUnlock(key: "\(p)_str_react_50",     by: delta)
        await incrementAndUnlock(key: "\(p)_end_react_50",     by: delta)
    }
    
    func onPersonalRecord(totalPRs: Int = 1) async {
        let p = Self.olympianMirrorPrefix()
        await batchCheckAndUnlock([
            ("first_pr",         totalPRs),
            ("\(p)_first_pr",    totalPRs),
            ("\(p)_str_pr_5",    totalPRs),
            ("\(p)_str_pr_10",   totalPRs),
            ("\(p)_str_pr_20",   totalPRs),
        ])
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

    // MARK: - Olympian Path — one-shot local backfill (silent)

    /// Replays lifetime counters from Core Data + in-memory services through
    /// the same unlock hooks as live events so Path-to-33 goals reflect what
    /// the user already accomplished before the feature shipped. Suppresses
    /// unlock toasts while batching; always ends with a single
    /// `fetchAchievements()`.
    ///
    /// `transientLevel` is forwarded to the tail `fetchAchievements()` call
    /// only — Phase 6 OlympianPath passes `.debug` so a cancelled cold-start
    /// fetch doesn't fingerprint a warning the gate is about to retry away.
    /// Defaults to `.warning` to preserve QP-25a behavior for every
    /// non-Phase-6 caller.
    @MainActor
    func resyncOlympianProgressFromLocalTotals(transientLevel: AppLogger.Level = .warning) async {
        achievementSyncBatchDepth += 1
        defer { achievementSyncBatchDepth -= 1 }

        guard let user = UserManager.shared.currentUser else { return }

        let workouts = Int(user.totalWorkouts)
        let streak = Int(user.currentStreak)
        let friends = FriendService.shared.friends.count
        let meals = MealService.shared.lifetimeMealEntryCount()
        let prApprox = max(1, ExerciseHistoryService.shared.personalRecordsCache.count)

        await onWorkoutCompleted(totalWorkouts: workouts)
        await onStreakUpdated(streak: streak)
        await onFriendAdded(totalFriends: friends)
        await onMealLogged(totalMeals: meals)
        await onPersonalRecord(totalPRs: prApprox)

        let leagueRank = WeeklyLeagueService.shared.standing?.tierRank ?? 0
        if leagueRank > 0 {
            let p = Self.olympianMirrorPrefix()
            var leaguePairs: [(key: String, progress: Int)] = [
                ("\(p)_tier_gold",          leagueRank),
                ("\(p)_tier_diamond",       leagueRank),
                ("\(p)_str_tier_platinum",  leagueRank),
                ("\(p)_end_tier_platinum",  leagueRank),
            ]
            // `tier_<n>` keys mirror `onTierAchieved(tierRank:)` exactly —
            // server-side `unlock_achievement` short-circuits unknown keys
            // and `tier_<n>` outside 1..7 is bounds-checked per
            // `onTierAchieved` contract (range gate handled here too).
            for t in 1...leagueRank where t <= 7 {
                leaguePairs.append(("tier_\(t)", 1))
            }
            await batchCheckAndUnlock(leaguePairs)
        }

        if StravaService.shared.isConnected {
            let p = Self.olympianMirrorPrefix()
            await batchCheckAndUnlock([("\(p)_end_connect", 1)])
        }

        // Phase 6 OlympianPath: tail fetch level overridable so a cancelled
        // cold-start fetch (the gate is about to retry) doesn't fingerprint
        // a warning. Default `.warning` preserves QP-25a for every other caller.
        await fetchAchievements(transientLevel: transientLevel)
    }
}
