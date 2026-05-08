//
//  OlympianPathService.swift
//  Fit33
//
//  "Path to 33" — Annual Olympian Track.
//
//  This service is a THIN view layer on top of `BadgeService`. It does NOT
//  own its own progress engine; every Olympian goal is a row in `achievements`
//  with `category='olympian_path'`, and progress is incremented by the same
//  `unlock_achievement` RPC the rest of the achievement system uses.
//
//  Lifecycle:
//   1. App boot or sign-in → `loadCurrentSeason()` resolves the user's
//      archetype from `user_profiles.fitness_goal` and calls the idempotent
//      `assign_olympian_path(p_year, p_archetype)` RPC. The RPC seeds 33
//      personalized rows in `user_olympian_assignments` on first call and
//      returns the existing 33 on every call thereafter (frozen for the year).
//   2. `BadgeService.fetchAchievements()` populates the canonical progress
//      data (progress + unlocked_at) for every row. `OlympianPathService`
//      joins the assignments to the achievements list and exposes the 33 as
//      `goals: [OlympianGoal]` ordered 1..33.
//   3. Whenever `BadgeService.lastUnlockedAchievement` fires, the service
//      refreshes if the unlocked key is one of the 33.
//   4. When the user has unlocked all 33, the server's
//      `complete_olympian_season_if_done(p_year)` RPC mints a row in
//      `user_olympian_seasons`. The service watches for the new row and
//      surfaces a `pendingSeasonCompletion` event for `ContentView` to
//      drive the celebration overlay.

import Foundation
import Combine
import SwiftUI

// MARK: - Archetype

/// Onboarding-derived path archetype. Frozen at first assignment for the
/// season so the 33 stay stable even if the user's `fitness_goal` changes
/// mid-year.
enum OlympianArchetype: String, Codable, CaseIterable {
    case strength
    case endurance
    case weightLoss
    case general
    case athletic

    var displayName: String {
        switch self {
        case .strength:   return "Strength Path"
        case .endurance:  return "Endurance Path"
        case .weightLoss: return "Weight-Loss Path"
        case .general:    return "Balanced Path"
        case .athletic:   return "Athletic Path"
        }
    }

    var icon: String {
        switch self {
        case .strength:   return "dumbbell.fill"
        case .endurance:  return "figure.run"
        case .weightLoss: return "scalemass.fill"
        case .general:    return "leaf.fill"
        case .athletic:   return "bolt.heart.fill"
        }
    }

    /// Light visual flavor used on profile chips and detail header.
    /// Intentionally distinct from league tier colors so the two systems
    /// don't collide.
    var accent: Color {
        switch self {
        case .strength:   return Color(red: 0.95, green: 0.45, blue: 0.25)
        case .endurance:  return Color(red: 0.20, green: 0.78, blue: 0.55)
        case .weightLoss: return Color(red: 0.40, green: 0.65, blue: 0.95)
        case .general:    return Color(red: 0.60, green: 0.55, blue: 0.95)
        case .athletic:   return Color(red: 0.95, green: 0.30, blue: 0.55)
        }
    }

    /// Map an onboarding `fitness_goal` raw string + connection signals
    /// to an archetype. Mirrors the substring logic in
    /// `cardio_goal_bias_score` (SQL) and `GoalFamily.init(rawGoal:)` so
    /// the two server/client surfaces stay aligned.
    ///
    /// Connection signals are secondary tie-breakers:
    ///  * Strava + WHOOP both connected → `.athletic`
    ///  * Strava connected and goal is ambiguous → bias toward `.endurance`
    static func resolve(
        fitnessGoal: String?,
        stravaConnected: Bool = false,
        whoopConnected: Bool = false
    ) -> OlympianArchetype {
        let goal = (fitnessGoal ?? "").lowercased()

        // Athletic = both wearables connected, regardless of goal text
        if stravaConnected && whoopConnected {
            return .athletic
        }

        if goal.contains("muscle") || goal.contains("bulk")
            || goal.contains("strong") || goal.contains("power") {
            return .strength
        }

        if goal.contains("endurance") || goal.contains("cardio")
            || goal.contains("marathon") || goal.contains("5k") || goal.contains("10k")
            || goal.contains("run") || goal.contains("cycle") {
            return .endurance
        }

        if goal.contains("lean") || goal.contains("lose") || goal.contains("fat")
            || goal.contains("cut") || goal.contains("tone") {
            return .weightLoss
        }

        // Strava-only with no clear goal text leans endurance
        if stravaConnected {
            return .endurance
        }

        return .general
    }
}

// MARK: - DTOs

/// One assignment row, decoded from `assign_olympian_path` jsonb.
private struct OlympianAssignmentDTO: Decodable {
    let goalNumber: Int
    let goalTier: Int
    let achievementKey: String
    let archetype: String

    enum CodingKeys: String, CodingKey {
        case goalNumber = "goal_number"
        case goalTier = "goal_tier"
        case achievementKey = "achievement_key"
        case archetype
    }
}

/// `assign_olympian_path` envelope. Decodes `pool_year` and epoch fields
/// flexibly (PostgREST / jsonb may surface `Int` or `Double`).
private struct AssignPathResponseDTO: Decodable {
    let created: Bool
    let archetype: String?
    let assignments: [OlympianAssignmentDTO]
    let poolYear: Int?
    let pathStartedAtEpoch: Double?
    let pathEndsAtEpoch: Double?

    enum CodingKeys: String, CodingKey {
        case created, archetype, assignments
        case poolYear = "pool_year"
        case pathStartedAtEpoch = "path_started_at_epoch"
        case pathEndsAtEpoch = "path_ends_at_epoch"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        created = try c.decode(Bool.self, forKey: .created)
        archetype = try c.decodeIfPresent(String.self, forKey: .archetype)
        assignments = try c.decode([OlympianAssignmentDTO].self, forKey: .assignments)

        if let py = try? c.decode(Int.self, forKey: .poolYear) {
            poolYear = py
        } else if let d = try? c.decode(Double.self, forKey: .poolYear) {
            poolYear = Int(d)
        } else {
            poolYear = nil
        }

        pathStartedAtEpoch = Self.decodeFlexibleEpoch(c, key: .pathStartedAtEpoch)
        pathEndsAtEpoch = Self.decodeFlexibleEpoch(c, key: .pathEndsAtEpoch)
    }

    private static func decodeFlexibleEpoch(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        guard c.contains(key) else { return nil }
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decode(String.self, forKey: key), let d = Double(s) { return d }
        return nil
    }
}

/// One row in `user_olympian_seasons` (stackable badge).
struct OlympianSeasonBadge: Identifiable, Decodable, Hashable {
    let seasonYear: Int
    let archetype: String
    let completedAt: String

    var id: Int { seasonYear }

    var resolvedArchetype: OlympianArchetype {
        OlympianArchetype(rawValue: archetype) ?? .general
    }

    enum CodingKeys: String, CodingKey {
        case seasonYear = "season_year"
        case archetype
        case completedAt = "completed_at"
    }
}

// MARK: - Share bridge

/// Bridge type used by the celebration overlay's "Share" button AND the
/// year-end recap card. Lives next to `OlympianSeasonBadge` (the value it
/// wraps) so both `OlympianCelebrationOverlay` and `OlympianPathView` see it
/// without a cross-file dependency. Reuses the cross-app `ShareSheet`
/// (`DevSessionLogsView.swift`) which wraps `UIActivityViewController` —
/// a separate share-card composition is out of scope.
struct OlympianShareItem: Identifiable {
    let badge: OlympianSeasonBadge
    var id: Int { badge.seasonYear }

    var shareText: String {
        let archetypeName = badge.resolvedArchetype.displayName
        return """
        I just hit Olympian \(badge.seasonYear) on Fit33 — all 33 personalized goals on the \(archetypeName) complete. \
        Path to 33. Locked in. 👑
        """
    }
}

// MARK: - Goal model (UI-facing)

/// One of the user's 33 goals, populated by joining
/// `user_olympian_assignments` to `BadgeService.achievements`.
struct OlympianGoal: Identifiable, Hashable {
    let goalNumber: Int        // 1..33
    let tier: Int              // 1..5
    let achievementKey: String
    let title: String
    let description: String
    let icon: String
    let rarity: String
    let threshold: Int
    let progress: Int
    let xpReward: Int
    let unlocked: Bool

    var id: Int { goalNumber }

    var progressPercent: Double {
        guard threshold > 0 else { return unlocked ? 1.0 : 0.0 }
        return min(1.0, Double(progress) / Double(threshold))
    }

    /// Tier blues for Path UI — single coherent gradient-blue family (Tier 1
    /// light → Tier 5 deep). Distinct from league tier colors.
    var tierColor: Color {
        OlympianPathBluePalette.color(for: tier)
    }
}

// MARK: - Path visual palette (gradient blue)

enum OlympianPathBluePalette {
    static func color(for tier: Int) -> Color {
        switch tier {
        case 1: return Color(red: 0.62, green: 0.82, blue: 1.00) // ice
        case 2: return Color(red: 0.42, green: 0.68, blue: 0.98) // sky
        case 3: return Color(red: 0.26, green: 0.52, blue: 0.95) // cobalt
        case 4: return Color(red: 0.14, green: 0.36, blue: 0.88) // royal
        case 5: return Color(red: 0.06, green: 0.22, blue: 0.72) // deep / finale
        default: return Color(red: 0.45, green: 0.65, blue: 0.95)
        }
    }

    /// Angular gradient stops for the header ring (all blues).
    static let ringAngularColors: [Color] = [
        Color(red: 0.62, green: 0.82, blue: 1.00),
        Color(red: 0.42, green: 0.68, blue: 0.98),
        Color(red: 0.26, green: 0.52, blue: 0.95),
        Color(red: 0.14, green: 0.36, blue: 0.88),
        Color(red: 0.06, green: 0.22, blue: 0.72),
        Color(red: 0.62, green: 0.82, blue: 1.00)
    ]
}

// MARK: - Service

@MainActor
final class OlympianPathService: ObservableObject {
    static let shared = OlympianPathService()

    /// UserDefaults — Olympian mirror keys `olympian_<year>_…` in `BadgeService`
    /// must match the pool seeded in Postgres. Written from `assign_olympian_path`.
    static let mirrorPoolYearDefaultsKey = "olympian_mirror_pool_year"

    /// Active season year for RPC `p_year` (matches seeded `achievements.season_year`).
    static var currentSeasonYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// 33 ordered goals for the current season. Empty until first load.
    @Published private(set) var goals: [OlympianGoal] = []

    /// Stackable badges for past seasons (read-only view of `user_olympian_seasons`).
    @Published private(set) var seasonBadges: [OlympianSeasonBadge] = []

    /// Resolved archetype for the current season (frozen at assignment).
    @Published private(set) var archetype: OlympianArchetype = .general

    /// Personal Path clock — set from `assign_olympian_path` (epoch fields).
    /// `nil` until the server returns window data (migration `20260505`).
    @Published private(set) var pathStartedAt: Date?
    @Published private(set) var pathEndsAt: Date?

    /// Highest tier (1..5) the user has fully cleared. 0 if no tier complete.
    @Published private(set) var highestClearedTier: Int = 0

    /// Loading state — `true` while `loadCurrentSeason()` is in flight.
    @Published private(set) var isLoading: Bool = false

    /// Last load failure surfaced to the empty-state card. Populated when
    /// `assign_olympian_path` throws (most often: migration not deployed
    /// yet, RLS misconfig, or assignment-short EXCEPTION) so the user
    /// sees the actual server message instead of a silent blank page.
    /// Cleared on successful load.
    @Published private(set) var lastLoadError: String?

    /// Set when the current season was just minted (33/33 unlocked); the
    /// celebration overlay reads + clears this. Drives
    /// `OlympianCelebrationOverlay` in the same way `pendingTierPromotion`
    /// drives `TierPromotionOverlay`.
    @Published var pendingSeasonCompletion: OlympianSeasonBadge?

    private var cancellables = Set<AnyCancellable>()
    private var lastSyncedPoolYear: Int?

    // MARK: - Snappiness Overhaul Phase 1.2 — 60s TTL cache
    //
    // `loadCurrentSeason()` was being invoked 50+ times during cold start
    // because multiple SwiftUI view-tree branches (`ProfileView`,
    // `OlympianPathView`, dashboard wrappers) each kicked it from
    // `.task` / `.onAppear`. Even though the function short-circuits on
    // `lastSyncedPoolYear == year && !goals.isEmpty`, the FIRST burst of
    // 50 callers can fire before the first one completes, so each one
    // hit the `assign_olympian_path` RPC. The TTL gates the entry point
    // so a successful fetch within the last 60s short-circuits before
    // any work is done. Invalidation hooks on the relevant
    // `NotificationCenter` events (workout completed, meal logged, etc.)
    // ensure the cache never serves stale data after a user action that
    // would have changed Olympian progress.
    //
    // All TTL behavior is gated by `PerfFlags.phase1BodyChurn` — when
    // OFF the function behaves byte-for-byte as it did pre-overhaul.
    private var lastFetchedAt: Date?
    private var cachedSeason: AssignPathResponseDTO?
    private var notificationTokens: [NSObjectProtocol] = []
    private static let cacheTTL: TimeInterval = 60

    // Snappiness Overhaul Phase 1.2 (extension, 2026-05-07) — parallel TTL
    // cache for `fetchSeasonBadges()`. Phase 1.2 added a 60s TTL to
    // `loadCurrentSeason()` but `fetchSeasonBadges()` was a separate code
    // path that did NOT short-circuit, so any caller who raced past the
    // outer `loadCurrentSeason` TTL check (multiple parallel cold-start
    // callers before `lastFetchedAt` was populated) re-fetched badges
    // unconditionally. Cancellations of those races fingerprinted as
    // `❌ fetchSeasonBadges failed: cancelled` (logged at .error pre-fix).
    //
    // Independent endpoint determination: `fetchSeasonBadges()` queries
    // `user_olympian_seasons` (past completed seasons). The
    // `assign_olympian_path` response only carries the CURRENT-year
    // assignments; past seasons are NOT derivable from the cached DTO.
    // Hence we add a parallel TTL cache (same 60s window) instead of
    // computing from `cachedSeason`.
    //
    // All TTL behavior gated by `PerfFlags.phase1BodyChurn` — flag OFF
    // restores byte-identical pre-overhaul behavior. Invalidation reuses
    // the existing `registerCacheInvalidationObservers()` infrastructure
    // (the invalidate closure clears BOTH `lastFetchedAt` and
    // `cachedBadgesAt`) — no duplicate notification observer wiring.
    private var cachedBadgesAt: Date?

    private init() {
        // Listen to the global achievement-unlock toast and refresh when one
        // of the 33 unlocks. We don't refresh on EVERY unlock because most
        // unlocks (legacy badges) aren't part of the path.
        BadgeService.shared.$lastUnlockedAchievement
            .compactMap { $0 }
            .sink { [weak self] item in
                guard let self else { return }
                Task { @MainActor in
                    if self.goals.contains(where: { $0.achievementKey == item.achievementKey }) {
                        await self.refreshFromCachedAchievements()
                    }
                }
            }
            .store(in: &cancellables)

        // Snappiness Overhaul Phase 1.2 — register cache-invalidation
        // observers behind the flag. Each `addObserver` returns a token
        // we hold in `notificationTokens` so `deinit` can clean up.
        // NOTE: as of 2026-05-07, NONE of the 5 spec'd notification
        // names are emitted anywhere in the codebase. We leave FIXMEs
        // for each so a future PR that wires them up only needs to
        // un-skip the registration. The 60s TTL is the floor in the
        // meantime — invalidation just makes it tighter.
        if PerfFlags.phase1BodyChurn {
            registerCacheInvalidationObservers()
        }
    }

    deinit {
        // Snappiness Overhaul Phase 1.2 — clean up any observers we
        // registered. The block-API tokens are removed individually
        // (NOT `removeObserver(self)` which only cleans selector-API
        // registrations). Singleton in practice never deallocs, but
        // defense-in-depth + matches the existing pattern in
        // `PerformanceOptimizations.swift`.
        let center = NotificationCenter.default
        for token in notificationTokens {
            center.removeObserver(token)
        }
    }

    /// Wires the 5 spec'd cache-invalidation events. Each invalidation
    /// just nils `lastFetchedAt`; the next `loadCurrentSeason()` call
    /// will hit the network. Skipped entries leave a FIXME so a future
    /// PR can wire them up by simply un-commenting.
    private func registerCacheInvalidationObservers() {
        let center = NotificationCenter.default
        let invalidate: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                // Phase 1.2 — invalidate BOTH the season TTL and the badges
                // TTL when a user action that could affect Olympian progress
                // fires. We invalidate both off the same notification set so
                // we never have to add a parallel observer chain.
                self?.lastFetchedAt = nil
                self?.cachedBadgesAt = nil
                AppLogger.debug(
                    "OlympianPathService: TTL cache (season + badges) invalidated by notification",
                    category: .general
                )
            }
        }

        // FIXME: notification not yet emitted by UserManager — once
        // `UserManager.workoutCompleted` Notification.Name is added, register here:
        // notificationTokens.append(center.addObserver(
        //     forName: Notification.Name("UserManager.workoutCompleted"),
        //     object: nil, queue: .main, using: invalidate))

        // FIXME: notification not yet emitted by MealService — once
        // `MealService.mealLogged` Notification.Name is added, register here:
        // notificationTokens.append(center.addObserver(
        //     forName: Notification.Name("MealService.mealLogged"),
        //     object: nil, queue: .main, using: invalidate))

        // FIXME: notification not yet emitted by FriendService — once
        // `FriendService.friendAdded` Notification.Name is added, register here:
        // notificationTokens.append(center.addObserver(
        //     forName: Notification.Name("FriendService.friendAdded"),
        //     object: nil, queue: .main, using: invalidate))

        // FIXME: notification not yet emitted by ExerciseHistoryService — once
        // `ExerciseHistoryService.personalRecord` Notification.Name is added, register here:
        // notificationTokens.append(center.addObserver(
        //     forName: Notification.Name("ExerciseHistoryService.personalRecord"),
        //     object: nil, queue: .main, using: invalidate))

        // FIXME: notification not yet emitted by AchievementService — once
        // `AchievementService.achievementUnlocked` Notification.Name is added, register here:
        // notificationTokens.append(center.addObserver(
        //     forName: Notification.Name("AchievementService.achievementUnlocked"),
        //     object: nil, queue: .main, using: invalidate))

        // Reference `invalidate` so the closure isn't elided by the
        // compiler before the FIXMEs are wired up. (Cheap, single
        // assignment; the closure itself is not invoked here.)
        _ = invalidate
        _ = center
    }

    // MARK: - Computed

    /// (completedCount, totalCount). Total is always 33 once loaded.
    var progress: (completed: Int, total: Int) {
        (goals.filter(\.unlocked).count, max(goals.count, 33))
    }

    /// The next not-yet-unlocked goal in numerical order, or nil if all done.
    var nextGoal: OlympianGoal? {
        goals.first(where: { !$0.unlocked })
    }

    /// Whether the user has completed all 33 for the current season.
    var seasonComplete: Bool {
        goals.count == 33 && goals.allSatisfy(\.unlocked)
    }

    /// Calendar day index within the personal 365-day Path (1…365).
    var currentDayOfPath: Int {
        guard let start = pathStartedAt else { return 1 }
        let cal = Calendar.current
        let raw = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: Date())).day ?? 0
        return min(365, max(1, raw + 1))
    }

    /// Whole days remaining until `pathEndsAt` (0 after the window passes).
    var daysRemainingOnPath: Int {
        guard let end = pathEndsAt else {
            return max(0, 365 - (currentDayOfPath - 1))
        }
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: end)).day ?? 0
        return max(0, d)
    }

    /// Single-line subtitle for navigation + header (365-day cadence).
    var path365Subtitle: String {
        if pathStartedAt != nil {
            return "Day \(currentDayOfPath) of 365 · \(daysRemainingOnPath) days left"
        }
        return "Your personalized 365-day Path"
    }

    // MARK: - Load

    /// Resolves archetype, calls `assign_olympian_path`, fetches achievement
    /// progress, and rebuilds the 33-goal list. Idempotent — calling more
    /// than once a session is cheap (server short-circuits when assignments
    /// already exist).
    func loadCurrentSeason(force: Bool = false) async {
        let year = Self.currentSeasonYear

        // Snappiness Overhaul Phase 1.2 — 60s TTL short-circuit.
        // Sits ABOVE the existing `lastSyncedPoolYear` check so a burst
        // of 50 cold-start callers all return immediately on the first
        // post-fetch frame instead of each spinning up an RPC. `force:
        // true` callers (manual pull-to-refresh, post-completion
        // recompute) bypass the TTL — they explicitly asked for fresh
        // data. With the flag OFF, this whole block is skipped and the
        // function behaves byte-for-byte as it did pre-overhaul.
        if PerfFlags.phase1BodyChurn,
           !force,
           let lastFetched = lastFetchedAt,
           cachedSeason != nil,
           Date().timeIntervalSince(lastFetched) < Self.cacheTTL {
            AppLogger.debug(
                "OlympianPathService: TTL cache hit (age=\(Int(Date().timeIntervalSince(lastFetched)))s, year=\(year))",
                category: .general
            )
            return
        }

        if !force, lastSyncedPoolYear == year, !goals.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 1. Resolve archetype from current user profile + connection signals
        let resolvedArchetype = resolveCurrentArchetype()

        // 2. Ask the server for the user's 33 (idempotent)
        guard let response = await assignPath(year: year, archetype: resolvedArchetype) else {
            // If `lastLoadError` is empty here, `assignPath` returned nil for a
            // benign reason (transient task cancellation). Don't warn — the
            // next foreground refresh / pull-to-refresh will retry. Only the
            // real-error branch populates `lastLoadError`.
            if lastLoadError != nil {
                AppLogger.warning("OlympianPathService: assign_olympian_path returned nil (year=\(year))", category: .general)
            }
            return
        }

        // Server responded — clear any prior error before continuing
        lastLoadError = nil

        // 2b. Mirror pool year + 365-day window (optional until migration ships)
        let poolYear = response.poolYear ?? year
        UserDefaults.standard.set(poolYear, forKey: Self.mirrorPoolYearDefaultsKey)
        if let ep = response.pathStartedAtEpoch {
            pathStartedAt = Date(timeIntervalSince1970: ep)
        }
        if let ee = response.pathEndsAtEpoch {
            pathEndsAt = Date(timeIntervalSince1970: ee)
        }

        // 3. Use the SERVER-provided archetype (frozen at first assignment)
        if let serverArch = response.archetype.flatMap(OlympianArchetype.init(rawValue:)) {
            archetype = serverArch
        } else {
            archetype = resolvedArchetype
        }

        // 4. Retroactively sync counters / mirrors so Path reflects historical work.
        //
        // Phase 6 (atomic-goals): when ON, the resync's tail `fetchAchievements`
        // logs cancellations at `.debug` (the gate is about to retry, so the
        // first-attempt cancellation isn't worth a warning). When OFF we keep
        // the default `.warning` to preserve byte-identical pre-Phase-6 behavior.
        if PerfFlags.phase6OlympianGoalsAtomic {
            await BadgeService.shared.resyncOlympianProgressFromLocalTotals(transientLevel: .debug)
        } else {
            await BadgeService.shared.resyncOlympianProgressFromLocalTotals()
        }

        // 5 + 6 + 7. Canonical achievement rows + badges + atomic rebuild.
        //
        // Pre-Phase-6 ordering (flag OFF) was:
        //   await BadgeService.shared.fetchAchievements()   // step 5 (duplicate of resync's tail)
        //   await fetchSeasonBadges()                       // step 6
        //   rebuildGoals(from: response.assignments)        // step 7 — reads BadgeService.achievements
        //
        // The race: `get_user_achievements` is cancellable (parent SwiftUI
        // `.task` teardown / superseded fetch). When cancelled, the cache
        // stays empty; rebuildGoals's `compactMap` against an empty cache
        // yields `goals=[]` → all 33 paths render blank. Phase 1.2's TTL
        // cache then HITS for 60s, so the empty state persists.
        //
        // Phase 6 fix: gate `rebuildGoals` on a populated achievements
        // cache. If the resync's tail fetch left the cache empty, schedule
        // exactly ONE retry after 350ms BEFORE rebuilding. If the retry
        // also fails, surface `.olympianGoalsStale` + a single `.warning`
        // log instead of writing fake-empty goals.
        var phase6RetryFailed = false
        if PerfFlags.phase6OlympianGoalsAtomic {
            let cacheState = await ensureAchievementsPopulatedWithRetry()

            // Step 6 — badges (independent endpoint; race-safe).
            await fetchSeasonBadges()

            switch cacheState {
            case .populatedNoRetryNeeded, .populatedAfterRetry:
                rebuildGoals(
                    from: response.assignments,
                    afterRetry: cacheState == .populatedAfterRetry
                )
            case .emptyAfterRetry:
                // Single retry already fired and the cache is STILL empty.
                // Don't blank the existing goals — preserve last known state
                // and surface a stale notification so views can present a
                // "tap to refresh" affordance instead of fake-empty progress.
                AppLogger.warning(
                    "OlympianPathService.rebuildGoals: achievements cache permanently empty after retry (assignments=\(response.assignments.count))",
                    category: .general
                )
                self.lastLoadError = "Couldn't load goals — tap to refresh"
                NotificationCenter.default.post(
                    name: .olympianGoalsStale,
                    object: nil,
                    userInfo: ["assignmentCount": response.assignments.count]
                )
                phase6RetryFailed = true
            }
        } else {
            // Pre-Phase-6 path — byte-identical to original.
            await BadgeService.shared.fetchAchievements()
            await fetchSeasonBadges()
            rebuildGoals(from: response.assignments)
        }

        // Phase 6 — when the gate's retry left the cache permanently empty,
        // SKIP populating `lastSyncedPoolYear` AND the Phase 1.2 TTL cache
        // markers. Otherwise the next `loadCurrentSeason()` call (e.g. the
        // user tapping "refresh" on the stale-state card) would hit either
        // the TTL short-circuit (60s lockout) or the `lastSyncedPoolYear ==
        // year && !goals.isEmpty` early-return — preventing recovery.
        // Leaving these unwritten means the next call goes full-fetch,
        // which is exactly what the stale-state UX expects.
        if !phase6RetryFailed {
            lastSyncedPoolYear = poolYear

            // Snappiness Overhaul Phase 1.2 — populate the TTL cache markers
            // ONLY when the new path is enabled, so flag-OFF behavior stays
            // byte-identical (no extra writes, no behavioral drift).
            if PerfFlags.phase1BodyChurn {
                lastFetchedAt = Date()
                cachedSeason = response
            }
        }
    }

    /// Refresh the goal list from the cached achievements (no network round
    /// trip if the cache is fresh enough). Triggers when one of the 33
    /// unlocks via the BadgeService toast.
    func refreshFromCachedAchievements() async {
        let year = Self.currentSeasonYear
        guard let response = await assignPath(year: year, archetype: archetype) else { return }
        if let ep = response.pathStartedAtEpoch {
            pathStartedAt = Date(timeIntervalSince1970: ep)
        }
        if let ee = response.pathEndsAtEpoch {
            pathEndsAt = Date(timeIntervalSince1970: ee)
        }
        if let py = response.poolYear {
            UserDefaults.standard.set(py, forKey: Self.mirrorPoolYearDefaultsKey)
        }
        await BadgeService.shared.fetchAchievements()
        rebuildGoals(from: response.assignments)
        await maybeTriggerCelebration()
    }

    // MARK: - Helpers (private)

    private func resolveCurrentArchetype() -> OlympianArchetype {
        let goal = UserManager.shared.currentUser?.fitnessGoal

        // Best-effort connection signals (matches DailyQuestService context).
        // Server-side `assign_olympian_path` is idempotent so a wrong-on-first-
        // call signal doesn't permanently misroute the user; the assignment
        // freezes only after the first successful call.
        let strava = StravaService.shared.isConnected
        let whoop  = WhoopService.shared.isConnected

        return OlympianArchetype.resolve(
            fitnessGoal: goal,
            stravaConnected: strava,
            whoopConnected: whoop
        )
    }

    private func assignPath(year: Int, archetype: OlympianArchetype) async -> AssignPathResponseDTO? {
        struct Params: Encodable {
            let p_year: Int
            let p_archetype: String
        }
        do {
            let response: AssignPathResponseDTO = try await SupabaseManager.shared.supabaseClient
                .rpc("assign_olympian_path", params: Params(
                    p_year: year,
                    p_archetype: archetype.rawValue
                ))
                .execute()
                .value
            return response
        } catch is CancellationError {
            // Transient — typically the parent SwiftUI `.task` was torn down
            // (scenePhase blip during cold start, view going away). NOT a
            // real failure: we leave `lastLoadError` empty so the empty-state
            // card stays clean and the next foreground refresh retries.
            AppLogger.debug(
                "assign_olympian_path cancelled (transient task teardown) — no error surfaced",
                category: .general
            )
            return nil
        } catch {
            // URLError.cancelled is the same story (network task cancelled when
            // SwiftUI tore down the parent task). Don't log as `error` and
            // don't surface to the empty-state card.
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                AppLogger.debug(
                    "assign_olympian_path URL cancelled (transient task teardown)",
                    category: .general
                )
                return nil
            }
            // Surface the real Postgres / network error to the user-facing
            // empty state. Common cases worth distinguishing:
            //   • PGRST202 / "function … does not exist" → migration not
            //     deployed; retry won't help until SQL runs.
            //   • "Olympian assignment short" → seed pool incomplete; the
            //     ALTER TABLE / INSERT INTO achievements step partially
            //     failed mid-migration.
            //   • 401 / 403 → auth state / RLS regression.
            // Stripped of the "PostgrestError(...)" wrapper noise so the
            // copy fits the empty-state card cleanly.
            let raw = error.localizedDescription
            let cleaned: String = {
                if let range = raw.range(of: #"message: "(.*?)""#, options: .regularExpression) {
                    let extracted = String(raw[range])
                        .replacingOccurrences(of: #"message: ""#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return extracted.isEmpty ? raw : extracted
                }
                return raw
            }()
            self.lastLoadError = cleaned
            AppLogger.error(
                "assign_olympian_path failed: \(raw)",
                category: .general
            )
            return nil
        }
    }

    private func fetchSeasonBadges() async {
        // Snappiness Overhaul Phase 1.2 (extension, 2026-05-07) — TTL
        // short-circuit. Mirrors the `loadCurrentSeason()` 60s gate.
        // Independent endpoint (queries `user_olympian_seasons`, NOT
        // derivable from the `assign_olympian_path` DTO), so we cannot
        // skip the network entirely on a `cachedSeason` hit; we cache the
        // badges fetch separately. Invalidation reuses the existing
        // `registerCacheInvalidationObservers()` infrastructure — the
        // invalidate closure clears both `lastFetchedAt` AND
        // `cachedBadgesAt` so a future `MealService.mealLogged` /
        // `AchievementService.achievementUnlocked` notification (when the
        // FIXMEs in `registerCacheInvalidationObservers` are wired) re-pulls
        // both. With the flag OFF this whole block is skipped — byte-for-
        // byte pre-overhaul behavior.
        if PerfFlags.phase1BodyChurn,
           let last = cachedBadgesAt,
           Date().timeIntervalSince(last) < Self.cacheTTL {
            AppLogger.debug(
                "OlympianPathService: badges TTL cache hit (age=\(Int(Date().timeIntervalSince(last)))s)",
                category: .general
            )
            return
        }

        do {
            let response: [OlympianSeasonBadge] = try await SupabaseManager.shared.supabaseClient
                .from("user_olympian_seasons")
                .select("season_year, archetype, completed_at")
                .order("season_year", ascending: false)
                .execute()
                .value
            self.seasonBadges = response

            if PerfFlags.phase1BodyChurn {
                cachedBadgesAt = Date()
            }
        } catch is CancellationError {
            // Transient — typically the parent SwiftUI `.task` was torn down
            // (scenePhase blip during cold start, view going away). Same
            // story as `assignPath` cancellation handling above; demote to
            // .debug so it doesn't fingerprint as a real error and contribute
            // to bug-intel noise.
            AppLogger.debug(
                "fetchSeasonBadges cancelled (transient task teardown) — no error surfaced",
                category: .general
            )
        } catch {
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                AppLogger.debug(
                    "fetchSeasonBadges URL cancelled (transient task teardown)",
                    category: .general
                )
                return
            }
            AppLogger.error("fetchSeasonBadges failed: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Phase 6 — Atomic goals gate (achievements-cache retry)

    /// Result of the Phase 6 atomic gate. Tells `loadCurrentSeason` whether
    /// the achievements cache was populated immediately, populated after a
    /// single retry, or remained empty after the retry — so the caller can
    /// pick between rebuildGoals / rebuildGoals(afterRetry:) / posting
    /// `.olympianGoalsStale`.
    private enum AchievementsCacheState {
        case populatedNoRetryNeeded
        case populatedAfterRetry
        case emptyAfterRetry
    }

    /// Phase 6 — guarantee the achievements cache is populated before
    /// rebuildGoals fires. Called from `loadCurrentSeason` AFTER
    /// `resyncOlympianProgressFromLocalTotals` (whose tail
    /// `fetchAchievements` is the first attempt).
    ///
    /// Behavior:
    ///   • Cache populated → return `.populatedNoRetryNeeded` (no retry, no log).
    ///   • Cache empty → log a `.debug` line, sleep 350ms, retry exactly once
    ///     with `transientLevel: .warning` so a SECOND cancellation is
    ///     surfaced (single warning per cold-start race instead of zero).
    ///   • If still empty after retry → return `.emptyAfterRetry`; the
    ///     caller posts `.olympianGoalsStale` and writes a single `.warning`.
    ///
    /// The 350ms backoff is intentional — immediate retry would just spam
    /// during real cancellation cascades (rapid scenePhase blips, dashboard
    /// transition tear-downs), and longer backoffs delay Path UI render
    /// past the user's first dashboard view. 350ms is the empirical sweet
    /// spot from `[bg-init] CloudSync` waterfall measurements: long enough
    /// for the supersession storm to settle, short enough to land within
    /// the user's first frame budget.
    private func ensureAchievementsPopulatedWithRetry() async -> AchievementsCacheState {
        if !BadgeService.shared.achievements.isEmpty {
            return .populatedNoRetryNeeded
        }

        AppLogger.debug(
            "OlympianPathService: achievements cache empty after initial fetch (probable cancellation), scheduling single retry in 350ms",
            category: .general
        )

        try? await Task.sleep(nanoseconds: 350_000_000)

        // Retry — this attempt's transient cancellation IS visible (`.warning`)
        // because we won't retry again. Real / non-transient errors still
        // log at `.error` via the classifier regardless of transientLevel.
        await BadgeService.shared.fetchAchievements(transientLevel: .warning)

        return BadgeService.shared.achievements.isEmpty ? .emptyAfterRetry : .populatedAfterRetry
    }

    private func rebuildGoals(from assignments: [OlympianAssignmentDTO], afterRetry: Bool = false) {
        let cache = Dictionary(uniqueKeysWithValues:
            BadgeService.shared.achievements.map { ($0.achievementKey, $0) }
        )

        // Distinguish three failure modes — Phase 6 tiered diagnostics:
        //  (a) RPC returned nothing — server bug / migration mid-fail.
        //      Always a `.warning`.
        //  (b) Cache is COMPLETELY EMPTY — race symptom (cancellation).
        //      Under phase 6 ON the gate prevents this branch firing
        //      (caller posts `.olympianGoalsStale` instead). Under phase 6
        //      OFF (or any rebuildGoals call from a path that bypassed the
        //      gate) we fall through to the legacy warning.
        //  (c) Cache populated but ALL assignment keys are missing — real
        //      data integrity issue (seed migration didn't run for this
        //      user, achievement keys drifted between server + iOS, etc.).
        //      Always a `.warning` and never silenced — this is the
        //      legitimate alarm the prompt asks us to keep loud.
        //  (d) Cache populated, partial mismatch — render what we have +
        //      `.warning` so the missing slice is visible without blanking
        //      the rest of the path.
        let missingKeys: [String] = assignments
            .map(\.achievementKey)
            .filter { cache[$0] == nil }

        let cacheIsCompletelyEmpty = BadgeService.shared.achievements.isEmpty

        if assignments.isEmpty {
            self.lastLoadError = "Server returned 0 goals. Migration may not be fully applied — check seed pool."
            AppLogger.warning(
                "OlympianPathService.rebuildGoals: 0 assignments returned from server",
                category: .general
            )
        } else if missingKeys.count == assignments.count && cacheIsCompletelyEmpty {
            // Race-symptom branch. Phase 6 gate should keep us out of here,
            // but if a caller bypassed the gate (flag OFF, future path), fall
            // back to the original message so behavior is preserved.
            if PerfFlags.phase6OlympianGoalsAtomic && afterRetry {
                // Defensive — phase6 ON path lands here only if the caller
                // did NOT route through `.emptyAfterRetry` (shouldn't happen
                // today; future-proofing). Treat as the post-retry permanent
                // failure case.
                self.lastLoadError = "Couldn't load goals — tap to refresh"
                AppLogger.warning(
                    "OlympianPathService.rebuildGoals: achievements cache permanently empty after retry (assignments=\(assignments.count))",
                    category: .general
                )
            } else if PerfFlags.phase6OlympianGoalsAtomic {
                // Phase 6 ON, retry not yet fired — this should never trip
                // because `loadCurrentSeason` gates ahead of us. Demote to
                // `.debug` so the (impossible-by-construction) trip doesn't
                // fingerprint a warning. Don't overwrite `self.goals` with
                // an empty array — preserve last-known state so any prior
                // render survives until the gate's retry completes.
                AppLogger.debug(
                    "OlympianPathService.rebuildGoals: deferring — achievements cache empty, retry scheduled (assignments=\(assignments.count))",
                    category: .general
                )
                return
            } else {
                // Phase 6 OFF — legacy path. Preserve byte-identical original
                // warning so 1.39 and earlier behavior is unchanged.
                self.lastLoadError = "Goals assigned but achievement rows missing from local cache. Try Force Quit + reopen."
                AppLogger.warning(
                    "OlympianPathService.rebuildGoals: assignments=\(assignments.count) but cache lacks all keys (sample: \(missingKeys.prefix(3).joined(separator: ", ")))",
                    category: .general
                )
            }
        } else if missingKeys.count == assignments.count {
            // Cache has rows but NONE match the assigned keys — this is a
            // legitimate data-integrity warning (NOT a race), kept loud per
            // the prompt's step 3.
            self.lastLoadError = "Goals assigned but achievement rows missing from local cache. Try Force Quit + reopen."
            AppLogger.warning(
                "OlympianPathService.rebuildGoals: assignments=\(assignments.count) but cache lacks all keys (sample: \(missingKeys.prefix(3).joined(separator: ", "))) — data integrity, not race",
                category: .general
            )
        } else if !missingKeys.isEmpty {
            // Partial mismatch — surface as a warning, but still render what we have.
            AppLogger.warning(
                "OlympianPathService.rebuildGoals: \(missingKeys.count) of \(assignments.count) keys missing from cache (sample: \(missingKeys.prefix(3).joined(separator: ", ")))",
                category: .general
            )
        }

        let mapped: [OlympianGoal] = assignments.compactMap { a in
            guard let row = cache[a.achievementKey] else { return nil }
            return OlympianGoal(
                goalNumber: a.goalNumber,
                tier: a.goalTier,
                achievementKey: a.achievementKey,
                title: row.title,
                description: row.description,
                icon: row.icon,
                rarity: row.rarity,
                threshold: row.threshold,
                progress: row.progress,
                xpReward: row.xpReward,
                unlocked: row.isUnlocked
            )
        }

        let ordered = mapped.sorted { $0.goalNumber < $1.goalNumber }
        self.goals = ordered

        // Highest fully-cleared tier
        var highest = 0
        for tier in 1...5 {
            let tierGoals = ordered.filter { $0.tier == tier }
            if !tierGoals.isEmpty, tierGoals.allSatisfy(\.unlocked) {
                highest = tier
            } else {
                break // tiers are progressive — stop at first incomplete
            }
        }
        self.highestClearedTier = highest
    }

    /// If the season just completed but no badge has been minted client-side,
    /// query the server (which mints atomically on the unlock side via
    /// `complete_olympian_season_if_done`) and surface a celebration event.
    private func maybeTriggerCelebration() async {
        guard seasonComplete else { return }
        let year = Self.currentSeasonYear
        // Check if we already have a badge for this year cached
        if seasonBadges.contains(where: { $0.seasonYear == year }) { return }

        // Re-fetch (server should have minted via unlock_achievement tail)
        await fetchSeasonBadges()
        if let mintedBadge = seasonBadges.first(where: { $0.seasonYear == year }),
           pendingSeasonCompletion == nil {
            pendingSeasonCompletion = mintedBadge
        }
    }

    func clearPendingCompletion() {
        pendingSeasonCompletion = nil
    }
}

// MARK: - Phase 6 — Goals-stale notification

extension Notification.Name {
    /// Phase 6 (`PerfFlags.phase6OlympianGoalsAtomic`) — Posted by
    /// `OlympianPathService.loadCurrentSeason` when the achievements cache
    /// stayed empty after the gate's single retry pass. Views observing
    /// this can show a "tap to refresh" stale state instead of fake-empty
    /// progress (the pre-Phase-6 race default that fingerprinted the
    /// 1.39 (70) blank-goals report).
    ///
    /// `userInfo["assignmentCount"]` carries the number of path
    /// assignments the server returned — if this is 33 (the canonical
    /// pool size), the failure is purely on the achievements-fetch leg
    /// and a manual refresh is the right user affordance.
    static let olympianGoalsStale = Notification.Name("OlympianPathService.olympianGoalsStale")
}
