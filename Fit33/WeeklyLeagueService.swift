//
//  WeeklyLeagueService.swift
//  Fit33
//
//  Weekly League System — Duolingo-style competitive leagues
//  Users are grouped into pools of ~30 and compete weekly for points.
//  Top performers get promoted; bottom performers get relegated.
//  Resets every Monday morning.
//

import Foundation
import SwiftUI
import Combine

// MARK: - League Models

struct LeagueStanding: Codable {
    let groupId: UUID
    let tierRank: Int
    let tierName: String
    let tierEmoji: String
    let tierColor: String
    let promotionCount: Int
    let relegationCount: Int
    let weekStart: String
    let daysRemaining: Int
    let myPoints: Int
    let myRank: Int
    let groupSize: Int
    let leaderboard: [LeagueEntry]

    // 2026-04-29 — League Redesign Plan §A2 + §A3 + §A4 + §C3.
    // Surfaced by `get_or_join_weekly_league` after migration #147
    // (`20260716_league_sprint2_stakes.sql`). All optional so old clients
    // keep decoding the response and a fresh placement that hasn't yet
    // accumulated streak/shield state still parses.
    let pendingLeaguePoints: Int?
    let shieldAvailable: Bool?
    let top3Streak: Int?
    let crownUntil: String?
    /// Peak Day Bonus weekday (ISO 1=Mon..7=Sun). League Points earned on
    /// this weekday count 3×. Refreshed every Monday rollup. NULL until
    /// the user has been placed at least once after migration #148.
    /// League Redesign Plan §A5.
    let peakDay: Int?

    var friendsInLeague: Int {
        leaderboard.filter { $0.isFriend == true && !$0.isCurrentUser }.count
    }
    
    var connectionsInLeague: Int {
        leaderboard.filter {
            !$0.isCurrentUser && ($0.isFriend == true || ($0.mutualFriendCount ?? 0) > 0)
        }.count
    }
    
    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case tierRank = "tier_rank"
        case tierName = "tier_name"
        case tierEmoji = "tier_emoji"
        case tierColor = "tier_color"
        case promotionCount = "promotion_count"
        case relegationCount = "relegation_count"
        case weekStart = "week_start"
        case daysRemaining = "days_remaining"
        case myPoints = "my_points"
        case myRank = "my_rank"
        case groupSize = "group_size"
        case leaderboard
        case pendingLeaguePoints = "pending_league_points"
        case shieldAvailable = "shield_available"
        case top3Streak = "top3_streak"
        case crownUntil = "crown_until"
        case peakDay = "peak_day"
    }

    /// Is today the user's Peak Day? Returns false when `peakDay` is nil
    /// (legacy users until next placement). League Redesign Plan §A5.
    var isPeakDayToday: Bool {
        guard let peakDay else { return false }
        let calendar = Calendar(identifier: .iso8601)
        let weekday = calendar.component(.weekday, from: Date())
        // Apple uses Sunday=1..Saturday=7. ISO uses Monday=1..Sunday=7.
        let isoWeekday = (weekday == 1) ? 7 : (weekday - 1)
        return isoWeekday == peakDay
    }

    /// Display name for the user's Peak Day (e.g. "Wednesday").
    var peakDayName: String? {
        guard let peakDay, peakDay >= 1, peakDay <= 7 else { return nil }
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return names[peakDay - 1]
    }

    /// Whether the user currently holds the Crown of the Week (rank-1
    /// finisher last Monday rollup, valid for 7 days). Drives the gold
    /// ring around the welcome-widget badge and the small `crown.fill`
    /// flair on profile cards. Plan §A2.
    var hasActiveCrown: Bool {
        guard let crownUntil, !crownUntil.isEmpty else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let expiry = formatter.date(from: crownUntil) {
            return expiry > Date()
        }
        formatter.formatOptions = [.withInternetDateTime]
        return (formatter.date(from: crownUntil) ?? Date.distantPast) > Date()
    }
    
    /// SwiftUI color for the current tier
    var tierSwiftUIColor: Color {
        switch tierRank {
        case 1: return .orange           // Bronze
        case 2: return .gray             // Silver
        case 3: return .yellow           // Gold
        case 4: return Color(red: 0.66, green: 0.66, blue: 0.78) // Platinum
        case 5: return .cyan             // Diamond
        case 6: return Color(red: 1.0, green: 0.42, blue: 0.21)  // Elite
        case 7: return Color(red: 0.11, green: 0.63, blue: 0.95) // Verified (Twitter blue)
        default: return .blue
        }
    }
    
    /// Gradient colors for the current tier
    var tierGradient: [Color] {
        switch tierRank {
        case 1: return [.orange, Color(red: 0.8, green: 0.5, blue: 0.2)]     // Bronze
        case 2: return [.gray, Color(white: 0.85)]                             // Silver
        case 3: return [.yellow, .orange]                                       // Gold
        case 4: return [Color(red: 0.66, green: 0.66, blue: 0.78), .purple]   // Platinum
        case 5: return [.cyan, .blue]                                           // Diamond
        case 6: return [Color(red: 1.0, green: 0.42, blue: 0.21), .red]       // Elite
        case 7: return [Color(red: 0.11, green: 0.63, blue: 0.95), Color(red: 0.0, green: 0.45, blue: 0.85)] // Verified
        default: return [.blue, .cyan]
        }
    }
    
    /// Whether the user is in the promotion zone
    var isInPromotionZone: Bool {
        promotionCount > 0 && myRank <= promotionCount
    }
    
    /// Whether the user is in the relegation zone
    var isInRelegationZone: Bool {
        relegationCount > 0 && myRank > (groupSize - relegationCount)
    }
    
    /// Next tier name (for promotion display)
    var nextTierName: String? {
        switch tierRank {
        case 1: return "Silver"
        case 2: return "Gold"
        case 3: return "Platinum"
        case 4: return "Diamond"
        case 5: return "Elite"
        case 6: return "Verified"
        default: return nil
        }
    }
    
    /// Previous tier name (for relegation display)
    var prevTierName: String? {
        switch tierRank {
        case 2: return "Bronze"
        case 3: return "Silver"
        case 4: return "Gold"
        case 5: return "Platinum"
        case 6: return "Diamond"
        case 7: return "Elite"
        default: return nil
        }
    }
}

struct LeagueEntry: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let points: Int
    let workoutsCompleted: Int?
    let rank: Int
    let isCurrentUser: Bool
    let isFriend: Bool?
    let mutualFriendCount: Int?
    let isVerified: Bool?
    let isGoldVerified: Bool?
    // 2026-04-29 — League Redesign Plan §A2.
    // Set by `get_or_join_weekly_league` after migration #147 — true iff the
    // member's `user_league_tier.crown_until > now()`. Drives the gold ring
    // around the leaderboard avatar for the current Crown of the Week.
    let hasCrown: Bool?

    var id: UUID { userId }
    
    var displayName: String {
        if let name = name, !name.isEmpty { return name }
        if let username = username, !username.isEmpty { return "@\(username)" }
        return "Athlete"
    }
    
    var firstName: String {
        displayName.components(separatedBy: " ").first ?? displayName
    }
    
    var initials: String {
        let parts = displayName.components(separatedBy: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
    
    /// Whether this person is a social connection (friend or friend-of-friend)
    var isConnection: Bool {
        isFriend == true || (mutualFriendCount ?? 0) > 0
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case username
        case profilePhotoUrl = "profile_photo_url"
        case points
        case workoutsCompleted = "workouts_completed"
        case rank
        case isCurrentUser = "is_current_user"
        case isFriend = "is_friend"
        case mutualFriendCount = "mutual_friend_count"
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
        case hasCrown = "has_crown"
    }
}

struct LeagueHistoryEntry: Codable, Identifiable {
    let weekStart: String
    let tierName: String
    let tierRank: Int
    let finalRank: Int
    let finalPoints: Int
    let groupSize: Int
    let wasPromoted: Bool
    let wasRelegated: Bool
    // 2026-04-29 — League Redesign Plan §A2 + §A3 + §A4.
    // Per-row flags written by the rollup so the iOS celebration overlay
    // can route to the right `TierPromotionEvent.Variant` without
    // re-running the rollup logic. All optional — old history rows
    // pre-dating migration #147 lack these columns.
    let wasStandOut: Bool?
    let wasCrown: Bool?
    let wasShielded: Bool?
    let wasBounceback: Bool?

    var id: String { weekStart }

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case tierName = "tier_name"
        case tierRank = "tier_rank"
        case finalRank = "final_rank"
        case finalPoints = "final_points"
        case groupSize = "group_size"
        case wasPromoted = "was_promoted"
        case wasRelegated = "was_relegated"
        case wasStandOut = "was_stand_out"
        case wasCrown = "was_crown"
        case wasShielded = "was_shielded"
        case wasBounceback = "was_bounceback"
    }
}

// MARK: - Tier Promotion Event
//
// 2026-04-29 — League Redesign Plan §B2. The single celebration trigger that
// replaces the legacy XP-100-boundary `LevelUpCelebrationOverlay`. Variants
// gate which overlay copy / animation to show; the Sprint 1 deliverable is
// `.standard` only — Sprint 2 wires `.standOut`, `.crown`, `.bounceback`, and
// the (informational, not celebratory) `.shieldBurned` banner. The overlay
// reads everything it needs off this struct so the celebration surface stays
// pure and the trigger logic stays in WeeklyLeagueService.

struct TierPromotionEvent: Equatable {
    enum Variant: String, Equatable {
        case standard               // simple promotion (Bronze → Silver, etc.)
        case standOut               // 3-week top-3 streak → skip-tier (Sprint 2)
        case crown                  // rank-1 last week (Sprint 2)
        case bounceback             // promoted the week after a relegation (Sprint 2)
        case shieldBurned           // first-strike shield used (informational, not celebratory) (Sprint 2)
    }

    let variant: Variant
    /// The tier rank the user was promoted INTO (e.g. 2 = Silver).
    let newTierRank: Int
    /// Display name for the destination tier (e.g. "Silver").
    let newTierName: String
    /// Skipped-tier name when `variant == .standOut`. Nil for other variants.
    let skippedTierName: String?
}

// MARK: - League Points Configuration

enum LeaguePointSource: String {
    // Existing 5 sources
    case workout = "workout"
    case challengeTarget = "challenge_target"
    case personalRecord = "personal_record"
    case mealLogged = "meal_logged"
    case dailyLogin = "daily_login"

    // 2026-04-29 — League Redesign Plan §C1.
    // 7 new fitness-aligned sources expand the task taxonomy from 5 → 12.
    // Each is paired with a per-day or per-week cap enforced both
    // client-side here (`dailyCap` / `weeklyCap` / `lifetimeCap`) and
    // server-side in the `add_league_points` RPC (Sprint 3 §sprint3-caps-enforcement).
    // Streak milestones are point-tiered: caller decides 7d/30d/100d.
    case streakMilestone7 = "streak_milestone_7"
    case streakMilestone30 = "streak_milestone_30"
    case streakMilestone100 = "streak_milestone_100"
    case dailyQuestCompleted = "daily_quest_completed"
    case cardioSession = "cardio_session"
    case bodyWeightLogged = "body_weight_logged"
    case newExerciseTried = "new_exercise_tried"
    case friendKudosGiven = "friend_kudos_given"
    case workoutSharedWithFriend = "workout_shared_with_friend"

    var points: Int {
        switch self {
        // Existing
        case .workout: return 50
        case .challengeTarget: return 25
        case .personalRecord: return 30
        case .mealLogged: return 10
        case .dailyLogin: return 5
        // New
        case .streakMilestone7: return 50
        case .streakMilestone30: return 100
        case .streakMilestone100: return 200
        case .dailyQuestCompleted: return 15
        case .cardioSession: return 50
        case .bodyWeightLogged: return 5
        case .newExerciseTried: return 10
        case .friendKudosGiven: return 2
        case .workoutSharedWithFriend: return 15
        }
    }

    var displayName: String {
        switch self {
        case .workout: return "Workout"
        case .challengeTarget: return "Challenge"
        case .personalRecord: return "PR"
        case .mealLogged: return "Meal"
        case .dailyLogin: return "Login"
        case .streakMilestone7: return "7-day streak"
        case .streakMilestone30: return "30-day streak"
        case .streakMilestone100: return "100-day streak"
        case .dailyQuestCompleted: return "Quest"
        case .cardioSession: return "Cardio"
        case .bodyWeightLogged: return "Weigh-in"
        case .newExerciseTried: return "New exercise"
        case .friendKudosGiven: return "Kudos"
        case .workoutSharedWithFriend: return "Shared workout"
        }
    }

    /// Soft client-side daily cap. `nil` = uncapped client-side (server still
    /// enforces a hard cap per Sprint 3 §sprint3-caps-enforcement).
    /// Used by `WeeklyLeagueService.shouldAwardPoints(source:)` to short-circuit
    /// before round-tripping to Supabase. Per-source values from the plan §C1.
    var dailyCap: Int? {
        switch self {
        case .mealLogged: return 3
        case .dailyLogin: return 1
        case .bodyWeightLogged: return 1
        case .friendKudosGiven: return 5
        default: return nil
        }
    }

    /// Soft client-side weekly cap.
    var weeklyCap: Int? {
        switch self {
        case .personalRecord: return nil          // 1×/exercise/wk — keyed cap, handled at PR site
        case .workoutSharedWithFriend: return 3
        default: return nil
        }
    }

    /// One-time-per-key lifetime cap. Used for the streak milestones (each
    /// streak threshold awards once per user) and "tried new exercise"
    /// (1× per exercise lifetime — handled at trigger site by checking
    /// per-exercise history). Returns the per-key bucket label so callers
    /// can build a stable dedup key (e.g. "streak_30").
    var lifetimeKey: String? {
        switch self {
        case .streakMilestone7: return "streak_7"
        case .streakMilestone30: return "streak_30"
        case .streakMilestone100: return "streak_100"
        case .newExerciseTried: return "new_exercise"  // suffix with exerciseId at trigger site
        default: return nil
        }
    }
}

// MARK: - Weekly League Service

@MainActor
class WeeklyLeagueService: ObservableObject {
    static let shared = WeeklyLeagueService()
    
    // MARK: - Published State
    @Published var standing: LeagueStanding?
    @Published var history: [LeagueHistoryEntry] = []
    @Published var isLoading = false
    @Published var hasJoined = false
    @Published var notPlaced = false
    @Published var notPlacedTierName: String?
    /// Tier rank (1-7) the unplaced user will land in next Monday.
    /// Populated from the same `not_placed` JSON branch as `notPlacedTierName`.
    /// Added 2026-04-29 (League Redesign Plan §B1) so achievement / dashboard
    /// surfaces can render the user's pending tier identity without inferring
    /// it from a string lookup.
    @Published var notPlacedTierRank: Int?
    @Published var notPlacedNextWeek: String?
    @Published var error: String?

    /// Pending tier-promotion celebration event. Set when `fetchOrJoinLeague`
    /// detects the server-side `current_tier` increased relative to the
    /// last-seen value persisted in UserDefaults — i.e. a Monday rollup
    /// promotion. ContentView watches this @Published and shows
    /// `TierPromotionOverlay` when non-nil. The overlay's onDismiss handler
    /// must reset this back to `nil`.
    /// Added 2026-04-29 (League Redesign Plan §B2).
    @Published var pendingTierPromotion: TierPromotionEvent?

    // MARK: - Cache
    private let standingCacheKey = "fit33_league_standing"
    private let standingCacheDateKey = "fit33_league_cache_date"
    private let dailyLoginKey = "fit33_league_daily_login"
    /// UserDefaults key tracking the highest tier rank we've already
    /// celebrated for this user. Bumped after each promotion overlay so
    /// re-fetches on the same week never re-fire the celebration.
    /// Added 2026-04-29 (League Redesign Plan §B2).
    private let lastSeenTierRankKey = "fit33_league_last_seen_tier_rank"
    private let cacheDuration: TimeInterval = 120 // 2 minutes
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        if !PrivacySettingsManager.shared.hideFromWeeklyLeague {
            loadCachedStanding()
        }
        
        PrivacySettingsManager.shared.$hideFromWeeklyLeague
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidden in
                guard let self else { return }
                if hidden {
                    self.standing = nil
                    self.hasJoined = false
                    UserDefaults.standard.removeObject(forKey: self.standingCacheKey)
                    UserDefaults.standard.removeObject(forKey: self.standingCacheDateKey)
                    AppLogger.debug("🏆 [LEAGUE] Cleared league data — user enabled privacy hide", category: .social)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Fetch / Join League
    
    /// Main entry point: get or create the user's league membership for this week.
    /// Lazily processes past weeks (promotions/relegations) on the server.
    func fetchOrJoinLeague(force: Bool = false) async {
        guard !PrivacySettingsManager.shared.hideFromWeeklyLeague else {
            self.standing = nil
            self.hasJoined = false
            AppLogger.debug("[PRIVACY] Skipping league join — user has weekly league hidden", category: .social)
            return
        }
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        if !force, let cacheDate = UserDefaults.standard.object(forKey: standingCacheDateKey) as? Date,
           Date().timeIntervalSince(cacheDate) < cacheDuration,
           standing != nil {
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let response = try await SupabaseManager.shared.supabaseClient
                .rpc("get_or_join_weekly_league", params: ["p_user_id": userId.uuidString])
                .execute()
            
            if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] {
                if json["hidden"] as? Bool == true {
                    self.standing = nil
                    self.hasJoined = false
                    self.notPlaced = false
                    AppLogger.debug("🏆 [LEAGUE] Server returned hidden=true — user is hidden from league", category: .social)
                    isLoading = false
                    return
                }
                
                if json["not_placed"] as? Bool == true {
                    self.standing = nil
                    self.hasJoined = false
                    self.notPlaced = true
                    self.notPlacedTierName = json["tier_name"] as? String
                    self.notPlacedTierRank = json["tier_rank"] as? Int
                    self.notPlacedNextWeek = json["next_week_start"] as? String
                    AppLogger.debug("🏆 [LEAGUE] Not placed this week — roster locked. Next week: \(self.notPlacedNextWeek ?? "?")", category: .social)
                    isLoading = false
                    return
                }
            }
            
            let result = try JSONDecoder().decode(LeagueStanding.self, from: response.data)
            
            self.standing = result
            self.hasJoined = true
            self.notPlaced = false
            self.notPlacedTierName = nil
            self.notPlacedTierRank = nil
            self.notPlacedNextWeek = nil
            cacheStanding(result)

            // 2026-04-29 — League Redesign Plan §B2.
            // Detect tier promotion vs the last-seen rank we've celebrated.
            // First-ever placement (no stored value) does NOT fire — there's
            // no "from" tier to celebrate. Only an actual increase fires
            // (rollup is the only path that increases `current_tier`).
            //
            // Sprint 2 (Plan §A2/A3/A4): the variant routing reads
            // `was_stand_out` / `was_crown` / `was_bounceback` /
            // `was_shielded` from the latest history row, so we proactively
            // refresh history first when there's any chance the rank
            // changed. Cheap — `get_league_history` is paginated and
            // cached.
            await fetchHistory()
            detectAndQueueTierPromotion(newRank: result.tierRank, newName: result.tierName)

            #if DEBUG
            AppLogger.debug("🏆 [LEAGUE] Joined/fetched league: \(result.tierName) league, rank #\(result.myRank)/\(result.groupSize), \(result.myPoints) pts", category: .social)
            #endif

            await awardDailyLoginPoints()
            
        } catch is CancellationError {
            AppLogger.debug("🔕 [LEAGUE] League fetch cancelled (tab switch)", category: .social)
        } catch let urlError as URLError where urlError.code == .cancelled {
            AppLogger.debug("🔕 [LEAGUE] League fetch cancelled (tab switch)", category: .social)
        } catch {
            self.error = error.localizedDescription
            #if DEBUG
            AppLogger.error("❌ [LEAGUE] Failed to fetch league: \(error)", category: .social)
            #endif
        }
        
        isLoading = false
    }

    // MARK: - Tier Promotion Detection (League Redesign Plan §B2)

    /// Compares the just-fetched tier rank against the last-celebrated rank
    /// stored in UserDefaults. Fires `pendingTierPromotion` exactly once per
    /// rank increase so the overlay shows on the first fetch after a Monday
    /// rollup and never again until the next promotion. First-ever placement
    /// (no stored rank) seeds the baseline silently — there is no "from"
    /// tier to celebrate.
    private func detectAndQueueTierPromotion(newRank: Int, newName: String) {
        let defaults = UserDefaults.standard
        let storedAny = defaults.object(forKey: lastSeenTierRankKey)

        // First-ever fetch — seed the baseline, no celebration.
        guard let stored = storedAny as? Int else {
            defaults.set(newRank, forKey: lastSeenTierRankKey)
            return
        }

        if newRank > stored {
            // Bumped — rollup promoted us. 2026-04-29 Sprint 2 (League
            // Redesign Plan §A2/A3/A4) refines the variant from server-
            // written history flags so the overlay routes to the right
            // copy. Latest history row holds `was_stand_out`,
            // `was_crown`, `was_bounceback`, `was_shielded`. Order
            // matters: Stand-Out > Bounceback > Crown > standard.
            let latest = self.history.first
            let variant: TierPromotionEvent.Variant
            let skipped: String?

            if (latest?.wasStandOut ?? false) && (newRank - stored) >= 2 {
                variant = .standOut
                let skippedRank = newRank - 1
                skipped = Self.tierName(forRank: skippedRank)
            } else if latest?.wasBounceback ?? false {
                variant = .bounceback
                skipped = nil
            } else if latest?.wasCrown ?? false {
                // Hit a crown last week AND promoted this week — favour
                // Crown so the user gets the prestige cue (the tier-up
                // is implied by `newTierName`).
                variant = .crown
                skipped = nil
            } else {
                variant = .standard
                skipped = nil
            }

            self.pendingTierPromotion = TierPromotionEvent(
                variant: variant,
                newTierRank: newRank,
                newTierName: newName,
                skippedTierName: skipped
            )
            defaults.set(newRank, forKey: lastSeenTierRankKey)
            HapticManager.notification(.success)

            // 2026-04-29 — Sprint 3 polish (League Redesign Plan §B1).
            // Fire the achievement unlock pipeline alongside the overlay so
            // the user sees the tier-promotion celebration AND the
            // achievement unlock toast. Milestone keys map 1:1 with the
            // celebration variants. No-op silently if the achievement row
            // isn't seeded yet.
            Task {
                await BadgeService.shared.onTierAchieved(tierRank: newRank)
                switch variant {
                case .crown:
                    await BadgeService.shared.onLeagueMilestone(key: "milestone_first_crown")
                case .standOut:
                    await BadgeService.shared.onLeagueMilestone(key: "milestone_stand_out")
                case .bounceback:
                    await BadgeService.shared.onLeagueMilestone(key: "milestone_bounceback")
                case .standard, .shieldBurned:
                    break
                }
                if newRank == 7 {
                    await BadgeService.shared.onLeagueMilestone(key: "milestone_verified")
                }
            }
            return
        }

        if newRank == stored {
            // Tier didn't change but a shield burned last rollup —
            // surface the informational "shield burned" overlay once.
            // Idempotent: marker key flips on first display so repeat
            // fetches in the same week stay silent.
            if let latest = self.history.first,
               latest.wasShielded == true {
                let shieldShownKey = "fit33_league_shield_shown_for_\(latest.weekStart)"
                if !defaults.bool(forKey: shieldShownKey) {
                    self.pendingTierPromotion = TierPromotionEvent(
                        variant: .shieldBurned,
                        newTierRank: newRank,
                        newTierName: newName,
                        skippedTierName: nil
                    )
                    defaults.set(true, forKey: shieldShownKey)
                    HapticManager.notification(.warning)

                    // Award the milestone achievement so a shielded user
                    // gets a small "your shield burned for the first
                    // time" pat on the back. Idempotent — the achievement
                    // unlock check short-circuits on repeats.
                    Task {
                        await BadgeService.shared.onLeagueMilestone(key: "milestone_shield_burned")
                    }
                }
            }
            return
        }

        // Tier dropped (relegation) — bring the cached value down so a future
        // re-promotion fires the Bounceback celebration on the very next
        // rollup. The server already sets `was_bounceback` on next week's
        // history row when this week's row was relegated AND next week's
        // promoted; this client side just keeps the cache honest.
        if newRank < stored {
            defaults.set(newRank, forKey: lastSeenTierRankKey)
        }
    }

    /// Cheap reverse-lookup for the canonical tier name by rank. Used by
    /// `detectAndQueueTierPromotion` to derive the skipped-tier label
    /// for Stand-Out variants without a server round-trip. Mirrors the
    /// `league_tiers.name` seed values.
    private static func tierName(forRank rank: Int) -> String? {
        switch rank {
        case 1: return "Bronze"
        case 2: return "Silver"
        case 3: return "Gold"
        case 4: return "Platinum"
        case 5: return "Diamond"
        case 6: return "Elite"
        case 7: return "Verified"
        default: return nil
        }
    }

    /// Clear the pending tier-promotion event after the overlay dismisses.
    /// Public so the overlay's `onDismiss` closure (in `ContentView`) can
    /// reset the trigger. Safe to call when no event is pending — no-op.
    func clearPendingTierPromotion() {
        self.pendingTierPromotion = nil
    }

    // MARK: - Client-side caps (League Redesign Plan §C2)
    //
    // Soft client-side dedup so the network round-trip is skipped when the
    // user is already over their per-day / per-week / lifetime cap for a
    // source. Server-side enforcement is the source of truth (Sprint 3
    // §sprint3-caps-enforcement) — this helper just prevents the obvious
    // "tap kudos 200 times" client-side junk traffic.
    //
    // Storage: UserDefaults JSON dict `{ "<source>:<bucket>:<dateKey>": count }`.
    // The bucket discriminator distinguishes daily / weekly / lifetime
    // counters; the date key is `yyyy-MM-dd` for daily and the ISO week
    // start (Mon) for weekly. Lifetime uses a stable bucket key (no date).
    // For per-key lifetime sources (`.newExerciseTried`) the caller passes
    // an `attribution` string (the exercise id) that's appended to the key.

    private static let capLedgerKey = "fit33_league_point_cap_ledger_v1"
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let weekKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = .current
        f.dateFormat = "yyyy-'W'ww"
        return f
    }()

    /// Returns true if the source has remaining client-side cap budget for
    /// the user *right now*. Increments the ledger when it returns true so
    /// repeated calls from the same trigger respect the cap. Pass an
    /// `attribution` string for per-key lifetime sources (e.g. exercise id
    /// for `.newExerciseTried`); pass `nil` for date-bucketed caps.
    func canAwardPoints(source: LeaguePointSource, attribution: String? = nil) -> Bool {
        let defaults = UserDefaults.standard
        var ledger = (defaults.dictionary(forKey: Self.capLedgerKey) as? [String: Int]) ?? [:]
        let now = Date()

        // Lifetime sources (streak milestones, new-exercise) — once per key.
        if let lifetimeBase = source.lifetimeKey {
            let key: String
            if let attribution {
                key = "\(source.rawValue):lifetime:\(lifetimeBase):\(attribution)"
            } else {
                key = "\(source.rawValue):lifetime:\(lifetimeBase)"
            }
            if (ledger[key] ?? 0) >= 1 {
                return false
            }
            ledger[key] = 1
            defaults.set(ledger, forKey: Self.capLedgerKey)
            return true
        }

        // Daily-capped sources.
        if let cap = source.dailyCap {
            let key = "\(source.rawValue):daily:\(Self.dayKeyFormatter.string(from: now))"
            let current = ledger[key] ?? 0
            if current >= cap { return false }
            ledger[key] = current + 1
            defaults.set(ledger, forKey: Self.capLedgerKey)
            return true
        }

        // Weekly-capped sources.
        if let cap = source.weeklyCap {
            let key = "\(source.rawValue):weekly:\(Self.weekKeyFormatter.string(from: now))"
            let current = ledger[key] ?? 0
            if current >= cap { return false }
            ledger[key] = current + 1
            defaults.set(ledger, forKey: Self.capLedgerKey)
            return true
        }

        return true
    }

    // MARK: - Add Points
    
    /// Add points for a specific activity. Call from workout completion, PR detection, etc.
    func addPoints(source: LeaguePointSource) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        guard hasJoined else { return } // Don't add points if user hasn't joined league yet
        
        do {
            struct PointsResult: Decodable {
                let success: Bool
                let new_points: Int?
                let points_added: Int?
            }
            
            let result: PointsResult = try await SupabaseManager.shared.supabaseClient
                .rpc("add_league_points", params: [
                    "p_user_id": userId.uuidString,
                    "p_points": "\(source.points)",
                    "p_source": source.rawValue
                ])
                .execute()
                .value
            
            if result.success, let newPoints = result.new_points {
                // Update local state immediately
                if var current = standing {
                    // Re-sort leaderboard with new points
                    var updatedLeaderboard = current.leaderboard
                    if let idx = updatedLeaderboard.firstIndex(where: { $0.isCurrentUser }) {
                        let old = updatedLeaderboard[idx]
                        updatedLeaderboard[idx] = LeagueEntry(
                            userId: old.userId,
                            name: old.name,
                            username: old.username,
                            profilePhotoUrl: old.profilePhotoUrl,
                            points: newPoints,
                            workoutsCompleted: (old.workoutsCompleted ?? 0) + (source == .workout ? 1 : 0),
                            rank: old.rank,
                            isCurrentUser: true,
                            isFriend: old.isFriend,
                            mutualFriendCount: old.mutualFriendCount,
                            isVerified: old.isVerified,
                            isGoldVerified: old.isGoldVerified,
                            hasCrown: old.hasCrown
                        )
                    }
                    // Note: rank may change — do a full refresh next time.
                    // 2026-04-29 — League Redesign Plan §A2 + §A3 + §A4 + §C3.
                    // Carry the Sprint 2 fields forward unchanged on the
                    // optimistic update — the next full fetch will re-pull
                    // them from the server with the source-of-truth values.
                    self.standing = LeagueStanding(
                        groupId: current.groupId,
                        tierRank: current.tierRank,
                        tierName: current.tierName,
                        tierEmoji: current.tierEmoji,
                        tierColor: current.tierColor,
                        promotionCount: current.promotionCount,
                        relegationCount: current.relegationCount,
                        weekStart: current.weekStart,
                        daysRemaining: current.daysRemaining,
                        myPoints: newPoints,
                        myRank: current.myRank,
                        groupSize: current.groupSize,
                        leaderboard: updatedLeaderboard,
                        pendingLeaguePoints: current.pendingLeaguePoints,
                        shieldAvailable: current.shieldAvailable,
                        top3Streak: current.top3Streak,
                        crownUntil: current.crownUntil,
                        peakDay: current.peakDay
                    )
                }
                
                #if DEBUG
                AppLogger.debug("🏆 [LEAGUE] +\(source.points) pts (\(source.displayName)) → \(newPoints) total", category: .social)
                #endif
            }
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [LEAGUE] Failed to add points: \(error)", category: .social)
            #endif
        }
    }
    
    // MARK: - Fetch Full Leaderboard
    
    /// Get the full leaderboard for the current group (used in detail view)
    func fetchFullLeaderboard() async {
        guard !PrivacySettingsManager.shared.hideFromWeeklyLeague else {
            self.standing = nil
            self.hasJoined = false
            return
        }
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            // Bug-intel fingerprint eb6ce765: previously this early-return was
            // silent and the detail view rendered a black empty ScrollView.
            // Surface the reason so the UI can show a real error state.
            self.error = "Sign in to view the full leaderboard."
            return
        }
        guard let groupId = standing?.groupId else {
            self.error = "No league assignment yet — check back when this week's placements finish."
            return
        }

        isLoading = true
        self.error = nil

        do {
            let result: LeagueStanding = try await SupabaseManager.shared.supabaseClient
                .rpc("get_league_leaderboard", params: [
                    "p_user_id": userId.uuidString,
                    "p_group_id": groupId.uuidString
                ])
                .execute()
                .value

            self.standing = result
            self.error = nil
            cacheStanding(result)

        } catch is CancellationError {
            AppLogger.debug("🔕 [LEAGUE] Leaderboard fetch cancelled (tab switch)", category: .social)
        } catch let urlError as URLError where urlError.code == .cancelled {
            AppLogger.debug("🔕 [LEAGUE] Leaderboard fetch cancelled (tab switch)", category: .social)
        } catch {
            self.error = "Couldn't load the leaderboard. Check your connection and try again."
            #if DEBUG
            AppLogger.error("❌ [LEAGUE] Failed to fetch leaderboard: \(error)", category: .social)
            #endif
        }

        isLoading = false
    }
    
    // MARK: - Fetch History
    
    func fetchHistory() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            let result: [LeagueHistoryEntry] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_league_history", params: ["p_user_id": userId.uuidString])
                .execute()
                .value
            
            self.history = result
            
        } catch {
            #if DEBUG
            AppLogger.error("❌ [LEAGUE] Failed to fetch history: \(error)", category: .social)
            #endif
        }
    }
    
    // MARK: - Daily Login Points
    
    private func awardDailyLoginPoints() async {
        let today = Calendar.current.startOfDay(for: Date())
        let lastLogin = UserDefaults.standard.object(forKey: dailyLoginKey) as? Date
        
        if let lastLogin = lastLogin, Calendar.current.isDate(lastLogin, inSameDayAs: today) {
            return // Already awarded today
        }
        
        // Award login points
        await addPoints(source: .dailyLogin)
        UserDefaults.standard.set(today, forKey: dailyLoginKey)
        
        #if DEBUG
        AppLogger.debug("🏆 [LEAGUE] Daily login bonus awarded (+5 pts)", category: .social)
        #endif
    }
    
    // MARK: - Hide / Unhide League Users
    
    @Published var hiddenUserIds: Set<UUID> = []
    
    func hideUser(_ userId: UUID) async {
        hiddenUserIds.insert(userId)
        
        if let current = standing {
            let filtered = current.leaderboard.filter { $0.userId != userId }
            self.standing = LeagueStanding(
                groupId: current.groupId,
                tierRank: current.tierRank,
                tierName: current.tierName,
                tierEmoji: current.tierEmoji,
                tierColor: current.tierColor,
                promotionCount: current.promotionCount,
                relegationCount: current.relegationCount,
                weekStart: current.weekStart,
                daysRemaining: current.daysRemaining,
                myPoints: current.myPoints,
                myRank: current.myRank,
                groupSize: current.groupSize,
                leaderboard: filtered,
                pendingLeaguePoints: current.pendingLeaguePoints,
                shieldAvailable: current.shieldAvailable,
                top3Streak: current.top3Streak,
                crownUntil: current.crownUntil,
                peakDay: current.peakDay
            )
        }
        
        do {
            struct HideResult: Decodable { let success: Bool }
            let _: HideResult = try await SupabaseManager.shared.supabaseClient
                .rpc("hide_league_user", params: ["p_hidden_user_id": userId.uuidString])
                .execute()
                .value
        } catch {
            AppLogger.warning("Failed to hide league user: \(error)", category: .social)
        }
    }
    
    func unhideUser(_ userId: UUID) async {
        hiddenUserIds.remove(userId)
        
        do {
            struct UnhideResult: Decodable { let success: Bool }
            let _: UnhideResult = try await SupabaseManager.shared.supabaseClient
                .rpc("unhide_league_user", params: ["p_hidden_user_id": userId.uuidString])
                .execute()
                .value
            
            await fetchFullLeaderboard()
        } catch {
            AppLogger.warning("Failed to unhide league user: \(error)", category: .social)
        }
    }
    
    // MARK: - Cache
    
    private func cacheStanding(_ standing: LeagueStanding) {
        if let data = try? JSONEncoder().encode(standing) {
            UserDefaults.standard.set(data, forKey: standingCacheKey)
            UserDefaults.standard.set(Date(), forKey: standingCacheDateKey)
        }
    }
    
    private func loadCachedStanding() {
        guard let data = UserDefaults.standard.data(forKey: standingCacheKey),
              let cached = try? JSONDecoder().decode(LeagueStanding.self, from: data) else {
            return
        }
        self.standing = cached
        self.hasJoined = true
    }
}
