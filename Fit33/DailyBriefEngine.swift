//
//  DailyBriefEngine.swift
//  Fit33
//
//  Daily Brief — fused multi-source welcome insight.
//
//  Replaces the 10-priority cascade in `AdvancedIntelligenceService
//  .getPersonalizedRecommendation` with a composition rule:
//
//      brief = capacity_facet  ×  compatible_debt_facet
//                              ×  goal_facet
//                              ×  optional_booster
//
//  Each facet emits a `FacetSignal { urgency, trace, payload }`. The
//  engine picks the highest-urgency Capacity (always present), the
//  highest-urgency Debt that's COMPATIBLE with that Capacity (red
//  recovery vetoes "go do legs"; green vetoes "rest day"), shapes
//  verbs from the user's `fitnessGoal`, and surfaces a Booster when
//  the chosen action also closes a quest or challenge gap.
//
//  Sources fused (read-only — never sync):
//    * Wearables → `ReadinessService.todayReadiness` (.green/.yellow/
//      .red + score), `WhoopService.todayStrain`, `WhoopService
//      .currentRecoveryLevel`, `OuraService.todayReadiness`.
//    * Workouts → `WorkoutSuggestionEngine.getMuscleRecoveryStatesAsync`
//      (Core Data, off main thread), `User.fitnessGoal`.
//    * Quests → `DailyQuestService.shared.quests` for live "close the
//      gap" detection.
//    * Nutrition → `MealService.shared.todaysMeals` vs goals from
//      `User`.
//    * Hydration → `HydrationService.shared.todayTotal/todayProgress`
//      vs `recommendedGoalMl`.
//    * Activity → `HealthKitService.shared.todaySteps /
//      todayActiveMinutes / todayCalories`.
//    * Competition → `ChallengeService.shared.activeChallenges` (top
//      1v1 with biggest gap and ≤2 days remaining).
//    * Streak → `UserManager.shared.currentUser.currentStreak`.
//    * Correlations → `PersonalizedInsightsService.shared
//      .activeInsights` for the rotating sub-line (gated by
//      `AppConfig.FeatureFlags.personalizedInsightsV2`).
//
//  Output → `DailyBrief` rendered by `WelcomeBriefRow` inside
//  `DashboardWelcomeBriefWrapper` (PE invariant 9 — widget isolation).
//
//  Threading:
//    * `@MainActor` because every published service we read is
//      `@MainActor`. Heavy Core Data muscle-debt read is delegated to
//      `WorkoutSuggestionEngine` which has its own `bgContext`.
//    * `compose(...)` runs facet reads in parallel via `async let`.
//

import Foundation
import SwiftUI

// MARK: - Public types

/// Capacity band derived from blended readiness. `unknown` only for
/// users with zero wearables connected — engine still picks a brief,
/// but uses templates that never reference recovery copy.
enum CapacityBand: String, Codable {
    case green, yellow, red, unknown

    init(readiness: DailyReadinessSnapshot) {
        guard readiness.hasWearableSignal else { self = .unknown; return }
        switch readiness.band {
        case .green: self = .green
        case .yellow: self = .yellow
        case .red: self = .red
        }
    }
}

/// Maps `User.fitnessGoal` Core Data string to a small canonical set
/// the templates can pivot on. Strings come from onboarding so we
/// match by case-insensitive substring rather than exact equality.
enum GoalFamily: String, Codable {
    case buildMuscle, loseFat, endurance, generalFitness

    init(rawGoal: String?) {
        let s = (rawGoal ?? "").lowercased()
        if s.contains("build") || s.contains("gain") || s.contains("muscle") {
            self = .buildMuscle
        } else if s.contains("lose") || s.contains("loss") || s.contains("lean") || s.contains("fat") {
            self = .loseFat
        } else if s.contains("endurance") || s.contains("cardio") {
            self = .endurance
        } else {
            self = .generalFitness
        }
    }
}

/// What's the user behind on? Templates key off (band, debt, goal).
enum DebtKind: String, Codable {
    case muscleGroup        // "chest + triceps are 5 days overdue"
    case proteinDeficit     // "30g protein behind"
    case hydrationDeficit   // "1.2L water behind pace"
    case stepsBehindGoal    // "3k steps behind today's pace"
    case streakRisk         // "streak day with no progress yet"
    case noWorkoutYet       // "first workout in 3 days"
    case recoveryNeeded     // red day — body says rest
    case allClear           // user is on top of everything
}

/// Where the brief routes when tapped. Maps to existing dashboard
/// destinations — no new navigation graph entries required.
enum BriefCTA: Hashable {
    case startAutoWorkout(splitHint: String?, etaMin: Int)
    case startRecoveryDay
    case openMealLog
    case logWater
    case openChallenge(id: UUID)
    case openReadiness
    case openWeightLog
    /// Phase 3 (2026-04-27): scrolls to + glow-rings the matching
    /// quest card on the dashboard so the user can see THE EXACT
    /// quest the brief wants them to close. Carries the quest_key
    /// (raw String, not the enum) to avoid cross-module coupling.
    case focusQuest(questKey: String)
    case none
}

/// Compact stat chip rendered under the brief. Encoded with hex so
/// the disk cache survives a `Color` decode round-trip.
struct BriefChipPayload: Codable, Equatable, Hashable {
    let icon: String
    let value: String
    let label: String
    let accentHex: String
}

/// Phase 2 (2026-04-27 — Daily Mission Unification): the structured
/// signals the engine fused into today's brief. Stamped onto every
/// `DailyBrief` and read by `DailyQuestService.gatherUserContext`
/// to send brief-aware params to `get_daily_quests` v4 (Layer 7
/// capacity re-rank + Layer 8 debt booster). When the brief is nil
/// (cold start before first compose), the quest service passes
/// nulls and the server falls back to legacy 6-layer behavior — so
/// users with no wearable / no engine output see zero behavior change.
struct BriefDecision: Codable, Equatable {
    let capacityBand: CapacityBand
    let capacityScore: Int
    let topDebtKind: DebtKind?
    /// Same payload the templates layer interpolates from. Sent to
    /// the server verbatim so Layer 8's threshold check
    /// (deficitVsPaceG / deficitMl / gapRaw / days) reads the
    /// canonical Swift→SQL string rendering.
    let topDebtPayload: [String: String]
    let goalFamily: GoalFamily
    let boosterChallengeId: UUID?
    /// Quest keys already on today's slate that the engine considers
    /// "matching this brief's debt + capacity." Driven by
    /// `DailyBriefEngine.matchQuests`. Powers the `.focusQuest(...)`
    /// CTA and the "← from your brief" chip when the server-side
    /// `is_brief_influenced` flag is unavailable (legacy slate from
    /// before today's brief composed).
    let linkedQuestKeys: [String]

    /// Short hash-shaped string used by `daily_brief_impressions`
    /// telemetry to group impressions by Decision-shape, not just
    /// template-shape. Lets analytics answer "which Decision class
    /// converts best?".
    var signature: String {
        let debt = topDebtKind?.rawValue ?? "none"
        return "\(capacityBand.rawValue)|\(debt)|\(goalFamily.rawValue)"
    }
}

// MARK: - Brief Context (cross-facet signals for richer body copy)

/// Cross-facet signals fused into the brief so body templates can
/// reference EVERYTHING the user is doing — not just the firing
/// debt. Powers the new 1-2 line body copy that names rivals,
/// cites last-night sleep, mentions overdue muscles even when the
/// firing debt is something else, etc.
///
/// Built once per `compose()` after the top debt is picked, then
/// handed to `DailyBriefTemplates.compose(... context:)` for token
/// interpolation. All fields are nil/zero-tolerant — when a service
/// isn't connected (no WHOOP, no Strava, no rival), the matching
/// `{ifBehindRival}` / `{ifSleepLow}` / `{ifRecentRun}` clauses
/// collapse to empty strings, so the same template degrades
/// gracefully across user states.
///
/// NOT Codable on purpose — this is per-compose ephemeral state, not
/// persisted to disk like `BriefDecision`.
struct BriefContext {
    // — Active rival (most engaged 1v1, regardless of who's leading).
    /// First name of the most engaged opponent across active 1v1s.
    /// Picked via `FriendRankingService.opponentEngagementScore`
    /// (PE invariant 25e — never anchor on a ghost-friend). Nil
    /// when no 1v1 challenges are active.
    let rivalFirstName: String?
    /// Opponent's progress today, formatted for the unit
    /// ("4.2k" steps, "320 cal", "32 min"). Nil when no rival or
    /// the type doesn't have a clean unit display.
    let rivalTodayFormatted: String?
    /// Signed gap (myToday − oppToday). Positive = you're ahead,
    /// negative = behind. Nil when neither side has logged today.
    let rivalSignedGap: Int?
    /// "steps" / "calories" / "active_minutes" / "workouts" / etc.
    /// Used to format `{rivalUnit}` and the gap suffix.
    let rivalChallengeType: String?

    // — Wearable / readiness signals (DailyReadinessSnapshot mirror).
    let recoveryScore: Int?
    let sleepHours: Double?
    let sleepDebtMin: Int?
    let strainPrev: Double?
    let hrvDeltaPct: Double?
    let rhrTrendBpm: Double?
    /// "WHOOP" / "Oura" / "Apple Health" / nil.
    let primarySource: String?
    let hasWearableSignal: Bool

    // — Top overdue muscle pair (even when not the firing debt).
    /// e.g. "chest & triceps". Nil when nothing is meaningfully
    /// overdue or when muscle group IS the firing debt (in which
    /// case `{muscles}` already covers it via debtFields).
    let topOverdueMuscle: String?
    let topOverdueDays: Int?

    // — Today's activity (HealthKit).
    let stepsSoFar: Int
    let stepGoal: Int
    let activeMinutesToday: Int
    let caloriesBurnedToday: Int

    // — Strava recent.
    /// Distance in meters of the most recent run, or nil.
    let lastRunDistanceM: Double?
    /// Days since last run (0 = today, 1 = yesterday). Nil when
    /// no recent run.
    let lastRunDaysAgo: Int?

    // — Workout state.
    let workoutDoneToday: Bool
    let lastWorkoutDaysAgo: Int?

    let streak: Int
    let hour: Int
}

/// Final fused brief consumed by `WelcomeBriefRow`. Codable so we
/// can mirror it to UserDefaults for cold-start cold-paint.
struct DailyBrief: Codable, Equatable {
    let headline: String
    let body: String
    /// Persisted as a code+payload pair so the associated-value enum
    /// round-trips through the disk cache without a custom Codable
    /// implementation. See `BriefCTACoder`.
    let ctaCode: String
    let ctaPayload: String?
    let chips: [BriefChipPayload]
    /// Italic micro-line under chips (correlation, e.g. "Sleep ≥7h
    /// drove 84% of your PRs this month"). nil before V2 is on or
    /// when no relevant insight is found.
    let rotatingInsight: String?
    /// Debug + telemetry breadcrumb: ["whoop:green","muscle_debt:chest","goal:buildMuscle",...].
    let sourceTrace: [String]
    let composedAt: Date
    /// Phase 2 (2026-04-27): structured Decision the engine made.
    /// Read by `DailyQuestService.gatherUserContext` to send brief
    /// signals to `get_daily_quests` v4. Optional in the Codable
    /// shape so disk-cache reads from before this PR don't crash.
    let decision: BriefDecision?

    var cta: BriefCTA { BriefCTACoder.decode(code: ctaCode, payload: ctaPayload) }
}

// MARK: - Internal facet signal

/// Internal currency the engine trades in. Each facet returns one
/// of these (or nil); engine picks the winners and hands them to
/// `DailyBriefTemplates`.
struct FacetSignal {
    enum Payload {
        case capacity(CapacityBand, sourceLabel: String, headroomPct: Int?, score: Int)
        case debt(DebtKind, fields: [String: String])
        case goal(GoalFamily)
        /// Booster references a challenge id the chosen action also
        /// closes. Nil id → it's a quest gap, not a challenge.
        case booster(copy: String, challengeId: UUID?)
    }
    let payload: Payload
    let urgency: Int
    let trace: String
}

extension FacetSignal {
    var capacityBand: CapacityBand? {
        if case .capacity(let band, _, _, _) = payload { return band }
        return nil
    }
    var debtKind: DebtKind? {
        if case .debt(let kind, _) = payload { return kind }
        return nil
    }
    var debtFields: [String: String] {
        if case .debt(_, let fields) = payload { return fields }
        return [:]
    }
    var goal: GoalFamily? {
        if case .goal(let g) = payload { return g }
        return nil
    }
    var boosterCopy: String? {
        if case .booster(let c, _) = payload { return c }
        return nil
    }
    var boosterChallengeId: UUID? {
        if case .booster(_, let id) = payload { return id }
        return nil
    }
}

// MARK: - Engine

@MainActor
final class DailyBriefEngine {
    static let shared = DailyBriefEngine()
    private init() {}

    /// Compose today's fused brief. Always returns a brief — falls
    /// back to streak / no-wearable templates if nothing else fires.
    /// Idempotent and cheap: no side effects, no network IO; reads
    /// only `@Published` state already kept fresh by other services.
    func compose(streak: Int) async -> DailyBrief {
        // Phase 8 (2026-05-02 — New User Onboarding Brief). Brand-new
        // accounts (zero training data + zero XP + no last workout +
        // no recorded streak) bypass the entire urgency-cascade engine.
        // The `muscleDebtFacet` "never trained = 7d overdue" fallback
        // (line ~929) otherwise produces alarming "chest & triceps
        // are 7 days overdue" copy on a fresh signup — false-by-
        // construction for someone who literally just finished
        // onboarding and has zero workout history. The dedicated
        // welcome brief is goal-aware, directive, and conversion-
        // friendly: ONE clear next step (start your first session)
        // without the diagnostic-shaped copy that confused the
        // urgency cascade. Multi-signal gate mirrors
        // `DailyQuestService.isLikelyDay1User` so we don't
        // misclassify an established user mid-cold-start (cloud
        // profile sync race) as new.
        if isBrandNewUser() {
            return brandNewUserWelcomeBrief()
        }

        async let capacity = capacityFacet()
        async let muscleDebt = muscleDebtFacet()
        async let nutrition = nutritionFacet()
        async let hydration = hydrationFacet()
        async let stepsGap = stepsGapFacet()
        async let recovery = recoveryFacet()
        async let comp = competitionFacet()
        async let goal = goalFacet()
        async let workoutPivot = noWorkoutYetFacet()

        let capSignal = await capacity
        let goalSignal = await goal

        var debts: [FacetSignal] = []
        for d in [await muscleDebt, await nutrition, await hydration, await stepsGap,
                  await recovery, await workoutPivot, streakRiskFacet(streak: streak)] {
            if let d { debts.append(d) }
        }

        let band = capSignal.capacityBand ?? .unknown
        let compat = compatibleDebts(debts, band: band)
        let topDebt = compat.max(by: { $0.urgency < $1.urgency })
        let booster = await comp

        let goalFamily = goalSignal.goal ?? .generalFitness
        let debtKind = topDebt?.debtKind ?? .allClear

        // Phase 2: compute the linked-quest set ONCE — it feeds (a)
        // the templates layer's {linkedQuestTitle} / {ifLinked}
        // tokens, (b) the CTA preference (`.focusQuest` over jump-
        // tabs), and (c) the Decision struct stamped on the brief.
        let slate = DailyQuestService.shared.quests
        let linkedKeys = matchQuests(
            capacityBand: band,
            topDebtKind: topDebt?.debtKind,
            slate: slate
        )
        let linkedQuestTitle: String? = linkedKeys.first.flatMap { firstKey in
            slate.first(where: { $0.questKey == firstKey })?.title
        }

        // Phase 7 (2026-04-27 — Welcome card insight enrichment):
        // build the cross-facet `BriefContext` so body templates can
        // reference rivals, sleep, strain, overdue muscles, Strava
        // runs, etc. — not just the one debt that fired. Templates
        // gracefully degrade when fields are nil (no wearable / no
        // rival / no Strava → those `{if...}` clauses collapse).
        let context = await buildBriefContext(
            band: band,
            topDebt: topDebt,
            streak: streak
        )

        let rendered = DailyBriefTemplates.compose(
            band: band,
            debt: debtKind,
            goal: goalFamily,
            debtFields: topDebt?.debtFields ?? [:],
            booster: booster?.boosterCopy,
            streak: streak,
            linkedQuestTitle: linkedQuestTitle,
            context: context
        )

        // Phase 7b (2026-04-27 — Insight Promotion): decide whether
        // to keep the action-shaped body or swap in a rotating
        // insight line. Action wins when the user has a real
        // urgency to close (steep debts, red recovery, streak
        // risk). Otherwise we surface a trend / stat / flex from
        // the insight pool — same visual slot, different intent.
        // Headline is always factual either way; only the body
        // gets re-routed.
        let useInsightBody = shouldPromoteInsight(
            topDebt: topDebt,
            debtKind: debtKind
        )
        let promotedBody: String? = useInsightBody
            ? buildInsightBody(
                context: context,
                booster: booster?.boosterCopy
            )
            : nil
        let finalBody = promotedBody ?? rendered.body

        let templateCTA = DailyBriefTemplates.cta(
            band: band,
            debt: debtKind,
            goal: goalFamily,
            debtFields: topDebt?.debtFields ?? [:],
            boosterChallengeId: booster?.boosterChallengeId
        )
        // Phase 2 (2026-04-27 — Daily Mission Unification): when the
        // debt the brief surfaced is ALREADY represented by a quest
        // on today's slate, prefer the `.focusQuest` CTA over jumping
        // to a different tab. Closes the loop — user taps "100g
        // protein left" and the screen scrolls to the "Hit Protein
        // Goal" quest card with a glow ring instead of dumping them
        // in the meal log empty-state.
        let cta = preferFocusQuest(
            templateCTA: templateCTA,
            linkedQuestKeys: linkedKeys,
            debt: topDebt?.debtKind
        )

        let chips = buildChips(capacity: capSignal, debt: topDebt, streak: streak)
        let rotating = await rotatingCorrelationLine(band: band, debt: topDebt)

        var trace = [capSignal.trace]
        trace.append(topDebt?.trace ?? "debt:none")
        trace.append("goal:\(goalFamily.rawValue)")
        if let booster { trace.append(booster.trace) }

        // Phase 2 (2026-04-27 — Daily Mission Unification): stamp the
        // structured Decision onto the brief so DailyQuestService can
        // forward it to `get_daily_quests` v4. Reuses `linkedKeys`
        // computed once above so we don't re-walk the slate.
        let decision = BriefDecision(
            capacityBand: band,
            capacityScore: extractCapacityScore(capSignal),
            topDebtKind: topDebt?.debtKind,
            topDebtPayload: topDebt?.debtFields ?? [:],
            goalFamily: goalFamily,
            boosterChallengeId: booster?.boosterChallengeId,
            linkedQuestKeys: linkedKeys
        )

        // Phase 7b (2026-04-27): trace tag so analytics can A/B
        // action-vs-insight body framings. The italic third line
        // is no longer rendered by the row, but the underlying
        // `rotatingInsight` field stays populated for telemetry +
        // for the insight-pool to draw on (it's one of the
        // candidate sources inside `buildInsightBody`).
        if useInsightBody { trace.append("body:insight") }

        return DailyBrief(
            headline: rendered.headline,
            body: finalBody,
            ctaCode: BriefCTACoder.code(for: cta),
            ctaPayload: BriefCTACoder.payload(for: cta),
            chips: chips,
            rotatingInsight: rotating,
            sourceTrace: trace,
            composedAt: Date(),
            decision: decision
        )
    }

    /// Phase 2 (2026-04-27): pulls the score out of the capacity
    /// FacetSignal payload. Centralized so we don't repeat the
    /// `if case .capacity(...)` shape every place we want the number.
    private func extractCapacityScore(_ signal: FacetSignal) -> Int {
        if case .capacity(_, _, _, let score) = signal.payload {
            return score
        }
        return 0
    }

    // MARK: - Phase 8: Brand-new user welcome (bypass)

    /// Multi-signal Day-0 gate. Mirrors
    /// `DailyQuestService.isLikelyDay1User` so the brief and the
    /// quest slate agree on "is this a brand-new user?" — divergence
    /// would let one surface show beginner cards while the other
    /// shows alarming "chest is 7 days overdue" copy (the bug this
    /// gate fixes).
    ///
    /// EVERY signal of prior activity must be empty:
    ///   - `currentUser != nil` (profile hydrated — a nil currentUser
    ///     during cold-start race used to make every `?? 0` fallback
    ///     pass and silently fire the welcome brief for established
    ///     users; canonical incident 2026-05-02, Joe's streak=13
    ///     dashboard rendered "Welcome to the club." because the
    ///     brief composed before `UserManager.bootstrapFromCloud`
    ///     had hydrated currentUser, then got disk-cached).
    ///   - `createdAt` within the last 14 days (defense-in-depth —
    ///     a fresh-device install of an established account reads
    ///     zeros for streak/totalWorkouts/xp BEFORE the cloud
    ///     profile sync lands, but the cloud `createdAt` is months
    ///     old by then, so we'd never misfire as Day 0).
    ///   - `totalWorkouts == 0` (no completed workouts on this device)
    ///   - `currentStreak == 0` (no logged streak from cloud sync)
    ///   - `xp == 0` (no XP earned — populated by streak-check before
    ///     brief compose, so it's a reliable cold-start signal)
    ///   - `lastWorkoutDate == nil` (no historical workout)
    ///   - `experienceLevel != "intermediate" / "advanced"`
    ///     (onboarding-supplied — established users restoring on
    ///     a fresh device skip the welcome brief).
    private func isBrandNewUser() -> Bool {
        guard let user = UserManager.shared.currentUser else { return false }
        if let createdAt = user.createdAt,
           Date().timeIntervalSince(createdAt) > 14 * 86_400 {
            return false
        }
        guard user.totalWorkouts == 0 else { return false }
        guard user.currentStreak == 0 else { return false }
        guard user.xp == 0 else { return false }
        guard user.lastWorkoutDate == nil else { return false }
        let level = (user.experienceLevel ?? "").lowercased()
        if level == "intermediate" || level == "advanced" { return false }
        return true
    }

    /// Welcome brief for brand-new accounts. Bypasses the facet
    /// cascade because there's nothing to compare against — no
    /// training history, no streak, no rivals, no readiness baseline
    /// — and the cascade's "never trained = 7d overdue" path lands
    /// on copy that's false-by-construction at this user state.
    ///
    /// Tier model (Day 0 → Day 7+ since signup):
    ///   - Day 0: hero welcome + first-session directive.
    ///   - Day 1–2: softer "first session is the hardest" nudge.
    ///   - Day 3+: encouragement framing — "today's a good day to start."
    /// Goal-aware so build-muscle / lose-fat / endurance users
    /// each see their own framing. CTA always
    /// `.startAutoWorkout(splitHint: nil, etaMin: 25)` — one tap to
    /// the auto-gen, the only on-ramp that makes sense before the
    /// user has a single workout to compare against.
    private func brandNewUserWelcomeBrief() -> DailyBrief {
        let goal = GoalFamily(rawGoal: UserManager.shared.currentUser?.fitnessGoal)
        let createdAt = UserManager.shared.currentUser?.createdAt ?? Date()
        let daysSinceJoin = max(0, Int(Date().timeIntervalSince(createdAt) / 86_400))

        // First-name extraction follows the same pattern as
        // `DashboardView+Header.swift:288–289` so a user named "Kayli
        // Smith" → "Kayli". Empty/whitespace falls through to a clean
        // no-name greeting ("Welcome to the club.") rather than the
        // generic "there" used in greeting headers — sounds wrong in
        // a "Welcome to the club," construction.
        let firstName: String? = {
            let raw = UserManager.shared.currentUser?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return nil }
            let first = raw.components(separatedBy: " ").first ?? raw
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        let (headline, body) = welcomeCopy(goal: goal, daysSinceJoin: daysSinceJoin, firstName: firstName)
        let cta: BriefCTA = .startAutoWorkout(splitHint: nil, etaMin: 25)
        let trace: [String] = [
            "capacity:unknown:none",
            "debt:none",
            "goal:\(goal.rawValue)",
            "brand_new_user:day_\(min(daysSinceJoin, 30))"
        ]

        // Empty Decision so DailyQuestService.gatherUserContext sends
        // nulls to get_daily_quests v4 — Layer 7/8 fall back to legacy
        // 6-layer behavior, which is correct for a Day-0 slate (the
        // beginner quests already kick in via `isLikelyDay1User`).
        let decision = BriefDecision(
            capacityBand: .unknown,
            capacityScore: 0,
            topDebtKind: nil,
            topDebtPayload: [:],
            goalFamily: goal,
            boosterChallengeId: nil,
            linkedQuestKeys: []
        )

        return DailyBrief(
            headline: headline,
            body: body,
            ctaCode: BriefCTACoder.code(for: cta),
            ctaPayload: BriefCTACoder.payload(for: cta),
            chips: [],
            rotatingInsight: nil,
            sourceTrace: trace,
            composedAt: Date(),
            decision: decision
        )
    }

    /// Goal × days-since-signup → (headline, body). Pure data — copy
    /// edits live here, no engine plumbing needed. Three day buckets
    /// (Day 0 / Day 1–2 / Day 3+) keep the dashboard from reading
    /// static if the user takes a few days to start; goal pivots
    /// match `GoalFamily(rawGoal:)` from onboarding.
    ///
    /// Day 0 headline is the punchy "Welcome to the club." greeting —
    /// uniform across goals so the moment feels universal, not
    /// segmented. The banner above ("WELCOME TO FIT33, NAME") already
    /// carries the personal greeting, so the card stays clean and
    /// directive (2026-05-02 copy revision). Goal still drives the
    /// body so build-muscle vs lose-fat vs endurance get tailored
    /// next-step copy.
    private func welcomeCopy(
        goal: GoalFamily,
        daysSinceJoin: Int,
        firstName: String?
    ) -> (headline: String, body: String) {
        // 2026-05-02 — name dropped from card headline; banner
        // above already carries the personal greeting. `firstName`
        // arg kept on the signature for backwards-compat / future
        // re-introduction without a call-site sweep.
        _ = firstName
        let day0Headline = "Welcome to the club."

        switch (daysSinceJoin, goal) {
        // ── Day 0: hero welcome ─────────────────────────────────
        case (0, .buildMuscle):
            return (day0Headline,
                    "Your first session sets the tone — tap for a 25-min auto workout to bank +30 XP.")
        case (0, .loseFat):
            return (day0Headline,
                    "Tap to start a 25-min auto session — burn the deficit, earn +30 XP.")
        case (0, .endurance):
            return (day0Headline,
                    "Tap to start your first 25-min full-body session and lock day 1.")
        case (0, .generalFitness):
            return (day0Headline,
                    "Tap to start your first 25-min auto session and lock day 1 of your streak.")

        // ── Day 1–2: first-session-is-the-hardest nudge ─────────
        case (1...2, .buildMuscle):
            return ("Day \(daysSinceJoin + 1) — let's get session one in.",
                    "A 25-min push day banks your first set of gains.")
        case (1...2, .loseFat):
            return ("Day \(daysSinceJoin + 1) — your first session is the hardest.",
                    "25 min today and the deficit starts working with you.")
        case (1...2, .endurance):
            return ("Day \(daysSinceJoin + 1) — get the engine started.",
                    "A quick full-body session today builds your base.")
        case (1...2, _):
            return ("Day \(daysSinceJoin + 1) — your first session locks day 1.",
                    "Tap to start a 25-min auto workout (+30 XP).")

        // ── Day 3+: gentle encouragement ────────────────────────
        case (_, .buildMuscle):
            return ("Ready when you are.",
                    "Your first session is one tap away — 25 min, all the basics.")
        case (_, .loseFat):
            return ("Today's a good day to start.",
                    "25-min auto workout — short, simple, and the deficit pays you back.")
        case (_, .endurance):
            return ("Today's a good day to start.",
                    "Tap for a quick 25-min full-body session to build the base.")
        default:
            return ("Ready when you are.",
                    "Tap to start your first 25-min auto session.")
        }
    }

    // MARK: - Phase 7b: Action vs Insight body decision

    /// Threshold below which we PROMOTE an insight body in place of
    /// the template's action body. Calibrated against the urgency
    /// scale the facets emit (red=100, big muscle debt=82-90,
    /// late-evening hydration=70 cap, normal steps gap=30-70).
    /// Anything ≥ 60 = "user has a real time-sensitive gap; nudge
    /// the action." Anything < 60 = "they're cruising or only mildly
    /// off pace; surface a flex/trend instead." Same threshold
    /// shape we use for nudge cadence elsewhere.
    private static let actionUrgencyThreshold: Int = 60

    /// Returns true when the body should be a rotating
    /// insight/trend instead of the template's action line. Some
    /// debt kinds ALWAYS stay action-shaped — red recovery (the
    /// user genuinely needs to rest, not be flexed at) and
    /// late-day streak risk (the chain is on the line). Everything
    /// else flips to insight mode below the urgency threshold OR
    /// when there's no debt at all (`.allClear`).
    private func shouldPromoteInsight(
        topDebt: FacetSignal?,
        debtKind: DebtKind
    ) -> Bool {
        switch debtKind {
        case .recoveryNeeded, .streakRisk:
            return false
        case .allClear:
            return true
        default:
            return (topDebt?.urgency ?? 0) < Self.actionUrgencyThreshold
        }
    }

    /// Builds today's INSIGHT body — a flex / trend / stat the user
    /// can read in 1-2 lines. Pulls candidates from across every
    /// connected source (streak, rival, Strava, recovery, sleep,
    /// PersonalizedInsightsService) and picks one via day-of-year
    /// rotation so the same user sees a consistent line within a
    /// calendar day but the line evolves day-to-day. Booster
    /// (`+ your 1v1 with Manuel`) is appended when relevant so the
    /// insight body still carries the social anchor.
    ///
    /// Order of candidates is intentionally diverse — the picker is
    /// modulo-based, not preference-based, so streaks/PRs/rivals/
    /// runs/recovery all get airtime across the week. Empty pool
    /// (truly cold start, no signals at all) falls back to a quiet
    /// motivational line that NEVER reads like a nag.
    private func buildInsightBody(
        context: BriefContext,
        booster: String?
    ) -> String {
        var pool: [String] = []

        // 1. Streak flex (anything 3+).
        if context.streak >= 30 {
            pool.append("Day \(context.streak) of your streak — legendary territory.")
        } else if context.streak >= 7 {
            pool.append("\(context.streak)-day streak — full habit territory.")
        } else if context.streak >= 3 {
            pool.append("\(context.streak)-day streak — momentum's locked in.")
        }

        // 2. Rival flex (when AHEAD with a meaningful gap).
        if let name = context.rivalFirstName,
           let signed = context.rivalSignedGap, signed > 0,
           DailyBriefTemplates.isMeaningfulGapPublic(signed, type: context.rivalChallengeType) {
            let unit = DailyBriefTemplates.displayUnitPublic(for: context.rivalChallengeType)
            let formatted = DailyBriefTemplates.formatGapPublic(signed, unit: unit)
            pool.append("Up \(formatted) on \(name) — keep the pressure on.")
        }

        // 3. Rival flex (when BEHIND — converts the signal into a
        // "they're moving, you can still pass" framing rather than
        // a passive flex).
        if let name = context.rivalFirstName,
           let signed = context.rivalSignedGap, signed < 0,
           DailyBriefTemplates.isMeaningfulGapPublic(abs(signed), type: context.rivalChallengeType) {
            let unit = DailyBriefTemplates.displayUnitPublic(for: context.rivalChallengeType)
            let formatted = DailyBriefTemplates.formatGapPublic(abs(signed), unit: unit)
            pool.append("\(name) is up \(formatted) — closeable if you move now.")
        }

        // 4. Sleep flex (well-rested: ≥7.5h).
        if let sleep = context.sleepHours, sleep >= 7.5 {
            pool.append(String(format: "Slept %.1fh last night — recovery's earning compound interest.", sleep))
        }

        // 5. Strain headroom flex (low previous strain + green band).
        if let strain = context.strainPrev, strain < 10.0,
           context.recoveryScore != nil, (context.recoveryScore ?? 0) >= 70 {
            pool.append(String(format: "Yesterday's %.1f strain left tons of room — body's primed.", strain))
        }

        // 6. Recovery score flex (high recovery).
        if let rec = context.recoveryScore, rec >= 80 {
            pool.append("Recovery's at \(rec)% — your body's begging for a session.")
        }

        // 7. Strava recent (last run within 3 days, ≥1km).
        if let dist = context.lastRunDistanceM, dist >= 1000,
           let days = context.lastRunDaysAgo, days <= 3 {
            let km = dist / 1000.0
            let label: String
            if km >= 9.5 && km <= 10.5 { label = "10K" }
            else if km >= 4.5 && km <= 5.5 { label = "5K" }
            else { label = String(format: "%.1fK", km) }
            let when = days == 0 ? "today" : (days == 1 ? "yesterday" : "\(days)d ago")
            pool.append("Coming off your \(label) \(when) — the engine's primed.")
        }

        // 8. Workout already in (post-workout flex).
        if context.workoutDoneToday {
            pool.append("Workout's already in — protein + sleep close the loop.")
        }

        // 9. Overdue muscles as a "tomorrow's mission" flex.
        if let m = context.topOverdueMuscle, let d = context.topOverdueDays, d >= 5 {
            pool.append("\(m.capitalized) are \(d)d overdue — tomorrow's session is loaded.")
        }

        // 10. PersonalizedInsightsService correlation (existing
        // engine — tightened to ≤80 chars so it never tail-truncates
        // mid-word the way the old italic line did).
        if AppConfig.FeatureFlags.personalizedInsightsV2 {
            let insights = PersonalizedInsightsService.shared.activeInsights
            if let top = insights.max(by: { $0.priority < $1.priority }),
               !top.message.isEmpty, top.message.count <= 80 {
                pool.append(top.message)
            }
        }

        // 11. Last-resort fallback — quiet motivation that never nags.
        if pool.isEmpty {
            pool.append("Quiet day. Anything you do today protects what you've built.")
        }

        // Day-rotate so the same user sees the same line all day
        // but a different one tomorrow. Calendar.ordinality gives
        // a stable-within-a-day integer.
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        var pick = pool[day % pool.count]

        // Append the booster if the chosen line doesn't already
        // mention the rival by name (avoid double-naming).
        if let booster, !booster.isEmpty,
           let rival = context.rivalFirstName,
           !pick.contains(rival) {
            // Trim trailing period before splicing in the booster.
            if pick.hasSuffix(".") { pick.removeLast() }
            pick += " + \(booster)."
        }

        return pick
    }

    /// Phase 2 (2026-04-27): swaps the templates-layer CTA for
    /// `.focusQuest` when the debt category already has a matching
    /// quest on today's slate. Falls through to the template's CTA
    /// when there's no match (e.g. the quest engine hasn't ranked
    /// the protein quest in today's pool, or the brief is showing
    /// `.allClear` / `.streakRisk` / etc. that don't have a 1:1
    /// quest mapping). Workout / recovery / challenge / readiness
    /// CTAs stay as-is — those go where the user actually needs to
    /// be (the workout generator, etc.), not the quest card.
    private func preferFocusQuest(
        templateCTA: BriefCTA,
        linkedQuestKeys keys: [String],
        debt: DebtKind?
    ) -> BriefCTA {
        guard let firstKey = keys.first else { return templateCTA }
        switch templateCTA {
        case .openMealLog, .logWater, .openWeightLog:
            return .focusQuest(questKey: firstKey)
        default:
            return templateCTA
        }
    }

    // MARK: - Brief Context builder (Phase 7)

    /// Gathers cross-facet signals into a `BriefContext` for richer
    /// 1-2 line body copy. Reads only `@Published` state already
    /// kept fresh by other services + one Core Data hit for muscle
    /// recovery (the same one `muscleDebtFacet` made — engine-level
    /// memoization is a future optimization, but the call is cheap
    /// and runs off-main inside `WorkoutSuggestionEngine`).
    ///
    /// All lookups are nil-safe — when a service isn't connected
    /// (no rival, no WHOOP, no Strava), the corresponding fields
    /// stay nil and the templates' `{if...}` clauses collapse to
    /// empty strings. Same template, graceful degradation across
    /// every user state (free / Pro / wearable / no-wearable / new
    /// account / power user).
    private func buildBriefContext(
        band: CapacityBand,
        topDebt: FacetSignal?,
        streak: Int
    ) async -> BriefContext {
        let snapshot = ReadinessService.shared.todayReadiness
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)

        // Most-engaged rival across active 1v1s. We deliberately
        // pick a rival even when we ARE winning — body copy can
        // surface "you're up 1.2k on Manuel" as a flex, not just
        // "Manuel's leading you". Engagement-first ranking matches
        // PE invariant 25e (never anchor on a ghost-friend).
        let challenges = ChallengeService.shared.activeChallenges
        struct RivalCandidate {
            let firstName: String
            let myToday: Int
            let oppToday: Int
            let challengeType: String
            let engagement: Double
        }
        var rivalPick: RivalCandidate?
        for c in challenges {
            guard let oppName = c.opponentName else { continue }
            let firstName = oppName.components(separatedBy: " ").first ?? oppName
            let engagement = FriendRankingService.opponentEngagementScore(
                opponentId: c.opponentId,
                opponentTodayProgress: c.opponentTodayProgress,
                opponentLastProgressAt: c.opponentLastProgressAt,
                now: now
            )
            let cand = RivalCandidate(
                firstName: firstName,
                myToday: c.myTodayProgress ?? 0,
                oppToday: c.opponentTodayProgress ?? 0,
                challengeType: c.challengeType,
                engagement: engagement
            )
            if rivalPick == nil || cand.engagement > rivalPick!.engagement {
                rivalPick = cand
            }
        }
        let rivalFirstName = rivalPick?.firstName
        let rivalChallengeType = rivalPick?.challengeType
        let rivalSignedGap: Int? = rivalPick.map { $0.myToday - $0.oppToday }
        let rivalTodayFormatted: String? = rivalPick.map { c in
            switch c.challengeType {
            case "steps":
                return c.oppToday >= 1000
                    ? String(format: "%.1fk", Double(c.oppToday) / 1000.0)
                    : "\(c.oppToday)"
            case "calories":   return "\(c.oppToday) cal"
            case "active_minutes": return "\(c.oppToday) min"
            default:           return "\(c.oppToday)"
            }
        }

        // Top overdue muscle (even when NOT the firing debt — body
        // copy uses this for "still chest & triceps overdue" tail
        // clauses on protein/water/step debts). Phase 8 (2026-05-02):
        // mirrors the `muscleDebtFacet` Day-0/Day-1 gate — the
        // "never trained = 7d" fallback only applies for users with
        // enough training history that an untrained muscle is a
        // meaningful gap. Without this, the `{ifOverdue}` clause
        // appended to body templates would say "chest & triceps
        // still 7d overdue" for a Day 1 user who literally has zero
        // chest training to be overdue ON.
        let totalWorkoutsForCtx = Int(UserManager.shared.currentUser?.totalWorkouts ?? 0)
        let allowNeverTrainedOverdue = totalWorkoutsForCtx >= 3
        let muscleStates = await WorkoutSuggestionEngine.shared.getMuscleRecoveryStatesAsync()
        let overdueLifted: Set<WorkoutSuggestionEngine.MuscleCategory> = [
            .chest, .back, .shoulders, .biceps, .triceps,
            .quads, .hamstrings, .glutes
        ]
        let overdueCandidates = muscleStates
            .filter { overdueLifted.contains($0.category) }
            .compactMap { state -> (WorkoutSuggestionEngine.MuscleCategory, Int)? in
                guard let last = state.lastTrainedDate else {
                    guard allowNeverTrainedOverdue else { return nil }
                    return (state.category, 7)
                }
                let days = Int(now.timeIntervalSince(last) / 86_400)
                guard days >= 4 else { return nil }
                return (state.category, days)
            }
            .sorted { $0.1 > $1.1 }
        let topOverdueMuscle: String?
        let topOverdueDays: Int?
        if topDebt?.debtKind == .muscleGroup {
            topOverdueMuscle = nil
            topOverdueDays = nil
        } else if let pair = overdueCandidates.first {
            topOverdueMuscle = canonicalPairLabel(for: pair.0)
            topOverdueDays = pair.1
        } else {
            topOverdueMuscle = nil
            topOverdueDays = nil
        }

        // Last workout days-ago (across all muscle states).
        let mostRecentWorkout = muscleStates.compactMap(\.lastTrainedDate).max()
        let lastWorkoutDaysAgo: Int? = mostRecentWorkout.map {
            Int(now.timeIntervalSince($0) / 86_400)
        }

        // Today's workout completion — quest-state-driven so it
        // matches the same definition the engine's other facets use.
        let workoutDoneToday = DailyQuestService.shared.quests.contains {
            ["complete_workout", "complete_program_day",
             "exercise_sets_15", "exercise_sets_25",
             "complete_2_workouts", "early_bird_workout"]
                .contains($0.questKey) && $0.isCompleted
        }

        // Strava — most recent activity (run / walk / ride). We
        // consider anything within last 7 days "recent" for body
        // copy purposes.
        let recent = StravaService.shared.recentActivities
            .filter { ["Run", "Walk", "Ride", "VirtualRide"].contains($0.type) }
            .max(by: { $0.startDate < $1.startDate })
        let lastRunDistanceM = recent?.distance
        let lastRunDaysAgo: Int? = recent.map {
            Int(now.timeIntervalSince($0.startDate) / 86_400)
        }

        return BriefContext(
            rivalFirstName: rivalFirstName,
            rivalTodayFormatted: rivalTodayFormatted,
            rivalSignedGap: rivalSignedGap,
            rivalChallengeType: rivalChallengeType,
            recoveryScore: snapshot.hasWearableSignal ? snapshot.score : nil,
            sleepHours: snapshot.sleepHours,
            sleepDebtMin: snapshot.sleepDebtMin,
            strainPrev: snapshot.strainPrev,
            hrvDeltaPct: snapshot.hrvDeltaPct,
            rhrTrendBpm: snapshot.rhrTrendBpm,
            primarySource: snapshot.hasWearableSignal ? snapshot.primarySource.displayName : nil,
            hasWearableSignal: snapshot.hasWearableSignal,
            topOverdueMuscle: topOverdueMuscle,
            topOverdueDays: topOverdueDays,
            stepsSoFar: HealthKitService.shared.todaySteps,
            stepGoal: HealthKitManager.shared.stepGoal,
            activeMinutesToday: HealthKitService.shared.todayActiveMinutes,
            caloriesBurnedToday: HealthKitService.shared.todayCalories,
            lastRunDistanceM: lastRunDistanceM,
            lastRunDaysAgo: lastRunDaysAgo,
            workoutDoneToday: workoutDoneToday,
            lastWorkoutDaysAgo: lastWorkoutDaysAgo,
            streak: streak,
            hour: hour
        )
    }

    // MARK: - Quest matching (Phase 2)

    /// Returns the quest keys on today's slate that the engine
    /// considers "matching" the brief's debt + capacity. Drives the
    /// `.focusQuest(...)` CTA and the "← from your brief" chip on
    /// the quest cards. Pure function — no side effects.
    func matchQuests(
        capacityBand band: CapacityBand,
        topDebtKind debt: DebtKind?,
        slate: [DailyQuest]
    ) -> [String] {
        guard !slate.isEmpty else { return [] }
        var matches: Set<String> = []

        // Debt-driven matches: the quest the brief's debt is asking
        // the user to close.
        if let debt {
            let debtTargetKeys: Set<String>
            switch debt {
            case .proteinDeficit:
                debtTargetKeys = ["hit_protein_goal", "log_3_meals", "log_breakfast"]
            case .hydrationDeficit:
                debtTargetKeys = ["log_water_8", "log_water_3", "log_water"]
            case .stepsBehindGoal:
                debtTargetKeys = ["hit_step_goal", "walk_10k_steps", "walk_7500_steps", "walk_5k_steps"]
            case .muscleGroup, .noWorkoutYet:
                debtTargetKeys = ["complete_workout", "complete_program_day", "do_friend_workout", "workout_30_min", "exercise_sets_15"]
            case .recoveryNeeded:
                debtTargetKeys = ["active_recovery_logged", "walk_when_red", "evening_wind_down", "stretch_session"]
            case .streakRisk:
                debtTargetKeys = ["complete_workout", "complete_program_day", "exercise_sets_15"]
            case .allClear:
                debtTargetKeys = []
            }
            for q in slate where debtTargetKeys.contains(q.questKey) {
                matches.insert(q.questKey)
            }
        }

        // Capacity-driven matches: on red days, any recovery quest
        // already on the slate is brief-influenced (since Layer 7
        // server-side put it there).
        if band == .red {
            let recoveryKeys: Set<String> = [
                "active_recovery_logged", "walk_when_red", "evening_wind_down", "stretch_session"
            ]
            for q in slate where recoveryKeys.contains(q.questKey) {
                matches.insert(q.questKey)
            }
        }

        return Array(matches)
    }

    // MARK: - Facet: Capacity (always returns)

    private func capacityFacet() async -> FacetSignal {
        let snapshot = ReadinessService.shared.todayReadiness
        let band = CapacityBand(readiness: snapshot)
        let source = snapshot.primarySource.displayName

        // Strain headroom from WHOOP (today's strain vs typical 13-15
        // ceiling) — only when WHOOP is the primary source.
        var headroom: Int? = nil
        if snapshot.primarySource == .whoop, let strain = WhoopService.shared.todayStrain?.strain {
            // Strain is 0-21 logarithmic; "fresh" = today's strain
            // hasn't yet eaten >40% of a typical 14-strain ceiling.
            let pct = max(0, min(100, Int(((14.0 - strain) / 14.0) * 100)))
            headroom = pct
        }

        // Urgency rebalance (Phase 0 — 2026-04-27): tightened so a real
        // wearable + 5-day muscle debt out-votes a noise-level macro
        // gap. Red wearable is the only thing that ever pins to 100;
        // green/yellow/unknown stay below the muscle-debt ceiling
        // (90 at 7+ days) so the headline can pivot to "chest is
        // overdue" instead of "your recovery is mid".
        let urgency: Int
        switch band {
        case .red: urgency = 100      // red recovery always wins
        case .green: urgency = 75
        case .yellow: urgency = 70
        case .unknown: urgency = 35
        }

        return FacetSignal(
            payload: .capacity(band, sourceLabel: source, headroomPct: headroom, score: snapshot.score),
            urgency: urgency,
            trace: "capacity:\(band.rawValue):\(source.lowercased())"
        )
    }

    // MARK: - Facet: Muscle debt (Core Data via WorkoutSuggestionEngine)

    private func muscleDebtFacet() async -> FacetSignal? {
        // Phase 8 (2026-05-02 — New User Onboarding Brief): the
        // "never trained = 7d overdue" fallback below is meant to
        // surface a real gap for users who have ALREADY trained
        // SOMETHING but missed an entire muscle group. For users
        // with fewer than 3 total workouts every untrained muscle
        // is "untrained" by construction (no history exists yet),
        // so the fallback misfires — every body part appears 7d
        // overdue and the brief lands on alarming
        // "chest & triceps are 7 days overdue" copy that's
        // false-by-construction at this user state. Defense-in-
        // depth alongside the `isBrandNewUser()` short-circuit
        // in `compose(...)`: the short-circuit covers Day 0,
        // this gate covers Day 1–2 (first workout completed —
        // the user has a `lastWorkoutDate` so the brand-new
        // gate flips off, but `totalWorkouts` is still 1–2 and
        // ALL non-trained muscles would fire as 7d overdue).
        let totalWorkouts = Int(UserManager.shared.currentUser?.totalWorkouts ?? 0)
        let allowNeverTrainedFallback = totalWorkouts >= 3

        let states = await WorkoutSuggestionEngine.shared.getMuscleRecoveryStatesAsync()
        // Find groups that are recovered (>= recoveryHours) AND haven't
        // been touched in the last 5 days. Skip "cardio"/"core" since
        // those rotate often — we want the "you haven't lifted chest"
        // signal that drives the North-Star example.
        let lifted: Set<WorkoutSuggestionEngine.MuscleCategory> = [
            .chest, .back, .shoulders, .biceps, .triceps,
            .quads, .hamstrings, .glutes
        ]
        let now = Date()
        let candidates = states
            .filter { lifted.contains($0.category) }
            .compactMap { state -> (WorkoutSuggestionEngine.MuscleCategory, Int)? in
                guard let last = state.lastTrainedDate else {
                    // Never trained — count as 7d overdue so it surfaces,
                    // but only for users with enough training history that
                    // an untrained muscle is a meaningful gap (see Phase 8
                    // gate above).
                    guard allowNeverTrainedFallback else { return nil }
                    return (state.category, 7)
                }
                let days = Int(now.timeIntervalSince(last) / 86_400)
                guard days >= 4, state.isRecovered else { return nil }
                return (state.category, days)
            }
            .sorted { $0.1 > $1.1 }

        guard let topPair = candidates.first else { return nil }

        // Group adjacent muscles into the brief's natural pairing
        // ("chest + triceps", "back + biceps", "quads + glutes").
        let muscle = topPair.0
        let days = topPair.1
        let pairLabel = canonicalPairLabel(for: muscle)
        let splitHint = splitHint(for: muscle)

        // Urgency rebalance (Phase 0 — 2026-04-27): 4d → 58, 5d → 66,
        // 6d → 74, 7d → 82, 8d+ → 90. Out-votes yellow capacity (70)
        // at 5d; out-votes green capacity (75) at 6d. Caps at 90 so
        // red recovery (100) always wins.
        let urgency = min(90, 50 + days * 8)

        return FacetSignal(
            payload: .debt(.muscleGroup, fields: [
                "muscles": pairLabel,
                "days": "\(days)",
                "split": splitHint
            ]),
            urgency: urgency,
            trace: "debt:muscle:\(muscle.rawValue):\(days)d"
        )
    }

    private func canonicalPairLabel(for muscle: WorkoutSuggestionEngine.MuscleCategory) -> String {
        switch muscle {
        case .chest: return "chest & triceps"
        case .triceps: return "chest & triceps"
        case .back: return "back & biceps"
        case .biceps: return "back & biceps"
        case .shoulders: return "shoulders"
        case .quads: return "legs"
        case .hamstrings: return "legs"
        case .glutes: return "legs & glutes"
        case .calves: return "calves"
        default: return muscle.rawValue
        }
    }

    private func splitHint(for muscle: WorkoutSuggestionEngine.MuscleCategory) -> String {
        switch muscle {
        case .chest, .triceps, .shoulders: return "push"
        case .back, .biceps: return "pull"
        case .quads, .hamstrings, .glutes, .calves: return "legs"
        default: return "fullBody"
        }
    }

    // MARK: - Facet: Nutrition (protein deficit, pace-aware)

    /// Phase 0 (2026-04-27): pace-aware protein gating. Replaces the
    /// old absolute-deficit firing rule that surfaced a panicky "100g
    /// short" headline at 10:30 AM when the user just hadn't had
    /// breakfast yet.
    ///
    /// Pace model: meals are roughly 25% / 35% / 40% across breakfast
    /// / lunch / dinner. Linear ramp 7 AM → 8 PM is a good-enough
    /// approximation; we only fire as a real DEBT when the user is
    /// behind PACE by a meaningful margin AND it's late enough in the
    /// day to be alarming.
    ///
    /// Firing rules:
    ///   - Before 1 PM: never fire as a debt (morning is too early
    ///     to alarm — surfaces only as a chip when other facets
    ///     drive the headline). Exception: zero meals logged AND
    ///     hour >= 11 → fire with subKind=noBreakfast (softer copy).
    ///   - 1–6 PM: fire when deficit-vs-pace >= 30g.
    ///   - After 6 PM: fire when deficit-vs-pace >= 20g.
    ///
    /// Urgency capped at 75 so a meaningful protein gap never
    /// out-votes a real capacity signal except in the evening when
    /// the user has actually fallen far behind.
    private func nutritionFacet() async -> FacetSignal? {
        // App canon for protein goal — matches `WorkoutProgressView`,
        // `DashboardView+Macros`, `MealPlanView` (~0.8g per lb body
        // weight, floor 100g).
        let weight = UserManager.shared.currentUser?.weight ?? 0
        let proteinGoal = max(100, Int(Double(weight) * 0.8))
        guard weight > 0, proteinGoal > 0 else { return nil }

        let meals = MealService.shared.todaysMeals
        let consumed = meals.reduce(0) { $0 + $1.protein }
        let absoluteDeficit = max(0, proteinGoal - consumed)
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let mealCount = meals.count

        // No-breakfast pivot: zero meals logged AND it's late-morning.
        // Fire with the noBreakfast subKind so the templates layer
        // can emit softer copy ("Quick breakfast keeps the engine
        // going") instead of the alarming "30g short" pattern.
        if mealCount == 0, hour >= 11, hour < 14 {
            // Detect a completed workout today so the template can
            // pivot to celebration copy ("Workout's in — refuel for
            // the next session") instead of the generic "the day's
            // just getting started" line. Mirrors the
            // `hasCompletedWorkoutQuestToday` shape from
            // AdvancedIntelligenceService.
            let workoutDoneToday = DailyQuestService.shared.quests.contains {
                ["complete_workout", "complete_program_day",
                 "exercise_sets_15", "exercise_sets_25",
                 "complete_2_workouts", "early_bird_workout"]
                    .contains($0.questKey) && $0.isCompleted
            }
            return FacetSignal(
                payload: .debt(.proteinDeficit, fields: [
                    "deficitG": "\(absoluteDeficit)",
                    "goalG": "\(proteinGoal)",
                    "subKind": "noBreakfast",
                    "workoutDone": workoutDoneToday ? "1" : "0"
                ]),
                urgency: 50,
                trace: "debt:protein:no_breakfast\(workoutDoneToday ? ":wkout_done" : "")"
            )
        }

        // Pace model: linear 0% at 7 AM → 100% at 8 PM. Before 7 AM
        // we treat expected as 0 (everyone's still sleeping). After
        // 8 PM we treat expected as full goal (you should have eaten
        // by now).
        let elapsed = max(0.0, min(1.0, Double(hour - 7) / 13.0))
        let expectedG = Double(proteinGoal) * elapsed
        let deficitVsPace = max(0, Int(expectedG) - consumed)

        // Time-window gates.
        let shouldFire: Bool
        if hour < 13 {
            // Morning: never fire as a debt (handled by no-breakfast
            // pivot above when meals == 0).
            shouldFire = false
        } else if hour < 18 {
            // Afternoon: meaningful gap only.
            shouldFire = deficitVsPace >= 30
        } else {
            // Evening: tighter threshold — user has run out of time
            // to catch up.
            shouldFire = deficitVsPace >= 20
        }
        guard shouldFire else { return nil }

        // Urgency: scales with hour AND deficit-vs-pace, but caps
        // at 75 so a real wearable signal can still out-vote it.
        let timeMultiplier = min(1.0, Double(hour - 7) / 13.0)
        let urgency = min(75, 30 + Int(Double(min(deficitVsPace, 100)) * 0.7 * timeMultiplier))

        return FacetSignal(
            payload: .debt(.proteinDeficit, fields: [
                "deficitG": "\(absoluteDeficit)",
                "deficitVsPaceG": "\(deficitVsPace)",
                "goalG": "\(proteinGoal)",
                "subKind": "behindPace"
            ]),
            urgency: urgency,
            trace: "debt:protein:behind:\(deficitVsPace)g_at\(hour)h"
        )
    }

    // MARK: - Facet: Hydration (only fires when behind expected pace)

    private func hydrationFacet() async -> FacetSignal? {
        let svc = HydrationService.shared
        let goal = svc.settings.dailyGoalMl
        let consumed = svc.todayTotal
        guard goal > 0 else { return nil }

        let hour = Calendar.current.component(.hour, from: Date())
        // Expected pace: linear from 0 at 7am to goal at 9pm.
        let elapsed = max(0.0, min(1.0, Double(hour - 7) / 14.0))
        let expected = Double(goal) * elapsed
        let actual = Double(consumed)
        let deficitMl = Int(expected - actual)
        guard deficitMl > 250 else { return nil }    // <250ml behind = noise

        let deficitL = String(format: "%.1f", Double(deficitMl) / 1000.0)
        // Urgency rebalance (Phase 0 — 2026-04-27): caps at 70 so
        // hydration never out-votes a real wearable + meaningful
        // muscle debt; surfaces strongly in evenings when truly
        // behind. (Old cap was 75 — same level as protein, which
        // muddied the priority order.)
        let urgency = min(70, 30 + deficitMl / 100)

        return FacetSignal(
            payload: .debt(.hydrationDeficit, fields: [
                "deficitL": deficitL,
                "deficitMl": "\(deficitMl)",
                "goalMl": "\(goal)"
            ]),
            urgency: urgency,
            trace: "debt:water:\(deficitMl)ml"
        )
    }

    // MARK: - Facet: Steps behind goal

    private func stepsGapFacet() async -> FacetSignal? {
        let goal = HealthKitManager.shared.stepGoal
        let actual = HealthKitService.shared.todaySteps
        let gap = max(0, goal - actual)
        guard gap >= 1500 else { return nil }

        let hour = Calendar.current.component(.hour, from: Date())
        // Don't nag in the morning; ramp through the afternoon.
        guard hour >= 12 else { return nil }

        let urgency = min(70, 30 + gap / 200)
        let gapDisplay = gap >= 1000
            ? String(format: "%.1fk", Double(gap) / 1000.0)
            : "\(gap)"

        return FacetSignal(
            payload: .debt(.stepsBehindGoal, fields: [
                "gap": gapDisplay,
                "gapRaw": "\(gap)",
                "goal": "\(goal)"
            ]),
            urgency: urgency,
            trace: "debt:steps:\(gap)"
        )
    }

    // MARK: - Facet: Recovery needed (red wearable day)

    private func recoveryFacet() async -> FacetSignal? {
        let snapshot = ReadinessService.shared.todayReadiness
        guard snapshot.hasWearableSignal, snapshot.band == .red else { return nil }
        return FacetSignal(
            payload: .debt(.recoveryNeeded, fields: [
                "score": "\(snapshot.score)"
            ]),
            urgency: 100,    // red recovery always wins among debts
            trace: "debt:recovery:red"
        )
    }

    // MARK: - Facet: First workout in 3+ days

    private func noWorkoutYetFacet() async -> FacetSignal? {
        let lastDate = await WorkoutSuggestionEngine.shared
            .getMuscleRecoveryStatesAsync()
            .compactMap(\.lastTrainedDate)
            .max()
        guard let lastDate else {
            // Brand-new user — surface as a gentle nudge with
            // medium urgency so it doesn't out-rank a real wearable
            // signal but does fire when nothing else does.
            return FacetSignal(
                payload: .debt(.noWorkoutYet, fields: ["days": "0"]),
                urgency: 45,
                trace: "debt:no_workout:none_yet"
            )
        }
        let days = Int(Date().timeIntervalSince(lastDate) / 86_400)
        guard days >= 3 else { return nil }
        let urgency = min(85, 35 + days * 8)
        return FacetSignal(
            payload: .debt(.noWorkoutYet, fields: ["days": "\(days)"]),
            urgency: urgency,
            trace: "debt:no_workout:\(days)d"
        )
    }

    // MARK: - Facet: Streak risk

    private func streakRiskFacet(streak: Int) -> FacetSignal? {
        guard streak >= 3 else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 16 else { return nil }
        // Already trained? Quest service knows.
        let alreadyTrained = DailyQuestService.shared.quests.contains {
            ["complete_workout", "complete_program_day", "exercise_sets_15", "exercise_sets_25"]
                .contains($0.questKey) && $0.isCompleted
        }
        if alreadyTrained { return nil }

        // Urgency scales with streak length — losing a 30-day streak
        // hurts more than losing a 3-day one.
        let urgency = min(85, 50 + streak)
        return FacetSignal(
            payload: .debt(.streakRisk, fields: ["streak": "\(streak)"]),
            urgency: urgency,
            trace: "debt:streak_risk:\(streak)d"
        )
    }

    // MARK: - Facet: Goal (always returns)

    private func goalFacet() async -> FacetSignal {
        let raw = UserManager.shared.currentUser?.fitnessGoal
        let family = GoalFamily(rawGoal: raw)
        return FacetSignal(
            payload: .goal(family),
            urgency: 0,    // goal never competes — it's a shape, not a winner
            trace: "goal:\(family.rawValue)"
        )
    }

    // MARK: - Facet: Competition booster

    /// Picks the highest-urgency 1v1 challenge where the user is
    /// behind and the gap could plausibly be closed by today's
    /// suggested action. Surfaces as a Booster, never the only
    /// reason for the brief (FE invariant 20a-relative).
    private func competitionFacet() async -> FacetSignal? {
        let challenges = ChallengeService.shared.activeChallenges
        struct Best { let id: UUID; let copy: String; let urgency: Int; let engagement: Double }
        var best: Best?
        let now = Date()
        for challenge in challenges {
            guard !challenge.amWinning,
                  let opponentName = challenge.opponentName else { continue }
            let challengeId = challenge.challengeId
            let firstName = opponentName.components(separatedBy: " ").first ?? opponentName
            let copy = "your 1v1 with \(firstName)"
            // 1v1 leading-by-X-with-N-days-left → higher urgency.
            // Days_remaining and progress aren't always non-nil; we
            // use a flat 65 floor when behind.
            let urgency = 65
            // Social anchor priority (PE invariant 25e): when the user
            // has multiple active challenges, prefer the opponent who's
            // engaged in Fit33 — today's progress beats long-term
            // engagement beats nothing. Stops the brief from anchoring
            // on a ghost-rival ("your 1v1 with Abbie" when Abbie is at
            // 0 and hasn't opened the app in a week, while Manuel is
            // at 877 and active right now).
            let engagement = FriendRankingService.opponentEngagementScore(
                opponentId: challenge.opponentId,
                opponentTodayProgress: challenge.opponentTodayProgress,
                opponentLastProgressAt: challenge.opponentLastProgressAt,
                now: now
            )
            // Sort key: urgency primary (so a critically-behind challenge
            // can still override an active-but-comfortable rival), then
            // engagement, so within the same urgency tier the active
            // opponent wins.
            let isBetter: Bool = {
                guard let cur = best else { return true }
                if cur.urgency != urgency { return cur.urgency < urgency }
                return cur.engagement < engagement
            }()
            if isBetter {
                best = Best(id: challengeId, copy: copy, urgency: urgency, engagement: engagement)
            }
        }
        guard let best else { return nil }
        return FacetSignal(
            payload: .booster(copy: best.copy, challengeId: best.id),
            urgency: best.urgency,
            trace: "booster:1v1:eng_\(Int(best.engagement))"
        )
    }

    // MARK: - Capacity-veto compatibility filter

    private func compatibleDebts(_ debts: [FacetSignal], band: CapacityBand) -> [FacetSignal] {
        switch band {
        case .red:
            // Red recovery vetoes muscle / step / streak. Only
            // recovery-compatible debts survive.
            return debts.filter { sig in
                switch sig.debtKind {
                case .recoveryNeeded, .proteinDeficit, .hydrationDeficit, .allClear:
                    return true
                default:
                    return false
                }
            }
        case .green, .yellow, .unknown:
            // Green/yellow should never surface "your body says
            // rest" — that would contradict the wearable.
            return debts.filter { $0.debtKind != .recoveryNeeded }
        }
    }

    // MARK: - Chip strip

    /// Builds up to **2** chips for the welcome card. The big flame
    /// streak counter on the left of the welcome card is the canonical
    /// streak surface — we deliberately do NOT add a streak chip here
    /// (would duplicate the flame, 2026-04-27 design feedback). Order
    /// of preference: capacity (when wearable connected) → debt-specific
    /// → sleep — never more than 2 to keep the card from feeling dense.
    private func buildChips(capacity: FacetSignal, debt: FacetSignal?, streak: Int) -> [BriefChipPayload] {
        var chips: [BriefChipPayload] = []

        // Capacity chip — always first when a wearable is connected.
        if case .capacity(let band, _, _, let score) = capacity.payload, band != .unknown {
            let icon: String
            let hex: String
            switch band {
            case .green: icon = "bolt.heart.fill"; hex = "#34C759"
            case .yellow: icon = "equal.circle.fill"; hex = "#FFCC00"
            case .red: icon = "moon.zzz.fill"; hex = "#FF3B30"
            case .unknown: icon = "questionmark.circle"; hex = "#8E8E93"
            }
            chips.append(BriefChipPayload(icon: icon, value: "\(score)", label: "Recovery", accentHex: hex))
        }

        // Debt-specific chip — surfaces the actionable number that
        // matches the brief's headline (the "why" in chip form).
        if let debt {
            switch debt.debtKind {
            case .proteinDeficit:
                // Skip the alarming "-100g Protein" chip on the
                // noBreakfast pivot — the headline is deliberately
                // soft ("the day's just getting started") and a red
                // chip yelling -100g undermines the whole pivot.
                // Late-day "behindPace" debts still get the chip
                // because the headline IS treating it as a real gap.
                let subKind = debt.debtFields["subKind"] ?? ""
                if subKind != "noBreakfast", let g = debt.debtFields["deficitG"] {
                    chips.append(BriefChipPayload(icon: "fork.knife", value: "-\(g)g", label: "Protein", accentHex: "#FF453A"))
                }
            case .hydrationDeficit:
                if let l = debt.debtFields["deficitL"] {
                    chips.append(BriefChipPayload(icon: "drop.fill", value: "-\(l)L", label: "Water", accentHex: "#0A84FF"))
                }
            case .stepsBehindGoal:
                if let g = debt.debtFields["gap"] {
                    chips.append(BriefChipPayload(icon: "figure.walk", value: "-\(g)", label: "Steps", accentHex: "#30D158"))
                }
            case .muscleGroup:
                if let days = debt.debtFields["days"] {
                    chips.append(BriefChipPayload(icon: "calendar.badge.clock", value: "\(days)d", label: "Overdue", accentHex: "#AF52DE"))
                }
            case .noWorkoutYet:
                if let days = debt.debtFields["days"], (Int(days) ?? 0) >= 3 {
                    chips.append(BriefChipPayload(icon: "calendar.badge.clock", value: "\(days)d", label: "Off", accentHex: "#AF52DE"))
                }
            default:
                break
            }
        }

        // Sleep chip — secondary, only if we still have a slot AND a
        // wearable supplied a sleep value.
        if chips.count < 2, let sleep = ReadinessService.shared.todayReadiness.sleepHours {
            let v = String(format: "%.1fh", sleep)
            chips.append(BriefChipPayload(icon: "bed.double.fill", value: v, label: "Sleep", accentHex: "#5E5CE6"))
        }

        return Array(chips.prefix(2))
    }

    // MARK: - Rotating correlation insight (V2 only)

    /// Returns one short italic line drawn from
    /// `PersonalizedInsightsService.activeInsights`, gated by
    /// `personalizedInsightsV2`. Tries to pick a correlation that
    /// matches the day's capacity band so the line "feels" connected
    /// to today's brief (e.g. green day → surface a sleep × PR
    /// correlation, red day → surface an overtraining warning).
    /// Suppressed on the noBreakfast pivot — a generic "you completed
    /// 13 workouts" line is wildly off-topic when the headline is
    /// "Refuel — the day's just getting started", and a truncated
    /// off-topic line at the bottom of the card just adds noise.
    private func rotatingCorrelationLine(band: CapacityBand, debt: FacetSignal?) async -> String? {
        guard AppConfig.FeatureFlags.personalizedInsightsV2 else { return nil }
        // Suppress on noBreakfast: keep the morning-refuel headline
        // clean and singular.
        if debt?.debtKind == .proteinDeficit,
           debt?.debtFields["subKind"] == "noBreakfast" {
            return nil
        }
        let insights = PersonalizedInsightsService.shared.activeInsights
        guard !insights.isEmpty else { return nil }

        let preferredCategories: [String]
        switch band {
        case .green: preferredCategories = ["sleep", "workout", "streak"]
        case .yellow: preferredCategories = ["nutrition", "hydration"]
        case .red: preferredCategories = ["recovery", "sleep"]
        case .unknown: preferredCategories = ["streak", "workout"]
        }

        // Prefer the highest-priority insight in a relevant category.
        let pick = insights
            .filter { preferredCategories.contains($0.category) }
            .max(by: { $0.priority < $1.priority })
            ?? insights.max(by: { $0.priority < $1.priority })

        return pick?.message
    }
}

// MARK: - BriefCTA Codable bridge

/// Codes the associated-value `BriefCTA` enum into a (code, payload)
/// pair so `DailyBrief` can stay `Codable` without a hand-rolled
/// implementation. Disk cache survives unknown future cases by
/// falling back to `.none` on decode.
enum BriefCTACoder {
    static func code(for cta: BriefCTA) -> String {
        switch cta {
        case .startAutoWorkout: return "auto"
        case .startRecoveryDay: return "recovery"
        case .openMealLog: return "meal"
        case .logWater: return "water"
        case .openChallenge: return "challenge"
        case .openReadiness: return "readiness"
        case .openWeightLog: return "weight"
        case .focusQuest: return "focus_quest"
        case .none: return "none"
        }
    }

    static func payload(for cta: BriefCTA) -> String? {
        switch cta {
        case .startAutoWorkout(let split, let eta):
            return "\(split ?? "")|\(eta)"
        case .openChallenge(let id):
            return id.uuidString
        case .focusQuest(let key):
            return key
        default:
            return nil
        }
    }

    static func decode(code: String, payload: String?) -> BriefCTA {
        switch code {
        case "auto":
            let parts = (payload ?? "|0").split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let split = parts.first.flatMap { $0.isEmpty ? nil : $0 }
            let eta = parts.count > 1 ? Int(parts[1]) ?? 25 : 25
            return .startAutoWorkout(splitHint: split, etaMin: eta)
        case "recovery": return .startRecoveryDay
        case "meal": return .openMealLog
        case "water": return .logWater
        case "challenge":
            if let p = payload, let id = UUID(uuidString: p) {
                return .openChallenge(id: id)
            }
            return .none
        case "readiness": return .openReadiness
        case "weight": return .openWeightLog
        case "focus_quest":
            if let p = payload, !p.isEmpty {
                return .focusQuest(questKey: p)
            }
            return .none
        default: return .none
        }
    }
}
