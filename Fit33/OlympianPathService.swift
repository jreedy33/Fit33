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
        if !force, lastSyncedPoolYear == year, !goals.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 1. Resolve archetype from current user profile + connection signals
        let resolvedArchetype = resolveCurrentArchetype()

        // 2. Ask the server for the user's 33 (idempotent)
        guard let response = await assignPath(year: year, archetype: resolvedArchetype) else {
            AppLogger.warning("OlympianPathService: assign_olympian_path returned nil (year=\(year))", category: .general)
            // lastLoadError is already populated by `assignPath`'s catch
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

        // 4. Retroactively sync counters / mirrors so Path reflects historical work
        await BadgeService.shared.resyncOlympianProgressFromLocalTotals()

        // 5. Canonical achievement rows + progress for rebuild
        await BadgeService.shared.fetchAchievements()

        // 6. Fetch this user's stackable badges
        await fetchSeasonBadges()

        // 7. Build the 33-goal view
        rebuildGoals(from: response.assignments)
        lastSyncedPoolYear = poolYear
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
        } catch {
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
        do {
            let response: [OlympianSeasonBadge] = try await SupabaseManager.shared.supabaseClient
                .from("user_olympian_seasons")
                .select("season_year, archetype, completed_at")
                .order("season_year", ascending: false)
                .execute()
                .value
            self.seasonBadges = response
        } catch {
            AppLogger.error("fetchSeasonBadges failed: \(error.localizedDescription)", category: .general)
        }
    }

    private func rebuildGoals(from assignments: [OlympianAssignmentDTO]) {
        let cache = Dictionary(uniqueKeysWithValues:
            BadgeService.shared.achievements.map { ($0.achievementKey, $0) }
        )

        // Distinguish "RPC returned nothing" (server bug / migration mid-fail)
        // from "RPC returned 33 but local achievement cache is missing those
        // rows" (BadgeService.fetchAchievements race / category filter regression).
        // Both produce a blank UI but need different fixes, so we surface them.
        let missingKeys: [String] = assignments
            .map(\.achievementKey)
            .filter { cache[$0] == nil }

        if assignments.isEmpty {
            self.lastLoadError = "Server returned 0 goals. Migration may not be fully applied — check seed pool."
            AppLogger.warning(
                "OlympianPathService.rebuildGoals: 0 assignments returned from server",
                category: .general
            )
        } else if missingKeys.count == assignments.count {
            self.lastLoadError = "Goals assigned but achievement rows missing from local cache. Try Force Quit + reopen."
            AppLogger.warning(
                "OlympianPathService.rebuildGoals: assignments=\(assignments.count) but cache lacks all keys (sample: \(missingKeys.prefix(3).joined(separator: ", ")))",
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
