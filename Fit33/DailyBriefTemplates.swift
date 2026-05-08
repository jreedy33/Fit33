//
//  DailyBriefTemplates.swift
//  Fit33
//
//  Sentence templates for the Daily Brief — keyed by
//  (CapacityBand, DebtKind, GoalFamily). Pure data + small render
//  helper. Fitness Expert / Design can edit copy here without
//  touching the engine logic.
//
//  North-Star example (the user-endorsed Phase 11 cadence —
//  `{Action}. {Gap}.` headline + supporting insight body):
//
//      "Take a walk. 4.5k steps left in your day."
//      "Z2 walk burns clean fat — easiest deficit win{booster}."
//
//  And for the canonical green + muscleGroup + buildMuscle template:
//
//      "Push day. Chest & triceps 5d due."
//      "Long rest = your biggest growth window{booster}."
//
//  Tokens supported in templates (interpolated by `render`):
//    -- Debt-driven (from `debtFields`):
//    {muscles}     — debtFields["muscles"]   ("chest & triceps")
//    {days}        — debtFields["days"]      ("5")
//    {split}       — debtFields["split"]     ("push" / "pull" / "legs")
//    {splitTitle}  — title-cased {split}     ("Push", "Pull", "Legs")
//    {eta}         — recommended ETA (computed from split + goal)
//    {deficitG}    — protein gap in grams
//    {deficitL}    — water gap in liters
//    {gap}         — steps gap (formatted "3.0k" or "850")
//
//    -- Engine-driven (from `BriefContext`):
//    {rival}        — first name of the most engaged rival ("Manuel")
//    {rivalToday}   — opponent's progress today ("4.2k", "320 cal")
//    {rivalUnit}    — "steps" / "cal" / "min"
//    {sleep}        — last night sleep ("7.5h"), "" if no data
//    {recovery}     — recovery score ("78%")
//    {strainPrev}   — yesterday's strain ("16.2"), "" if no data
//    {primarySource}— "WHOOP" / "Oura"
//    {bedtime}      — suggested bedtime to clear sleep need ("10:45 PM")
//
//    -- Conditional clause tokens (whole phrase or empty):
//    {ifBehindRival}— " — {rival}'s up {gap}"  (when behind)
//    {ifAheadRival} — " — and you're up on {rival}" (when ahead)
//    {ifSleepLow}   — " — last night was only {sleep}" (when <6h)
//    {ifOverdue}    — " — {muscles} are {days}d overdue" (when not the firing debt)
//    {ifLowRecovery}— " — recovery's {score}%" (when <50)
//    {ifHighStrain} — " — {strainPrev} strain yesterday" (when >16)
//    {ifRecentRun}  — " — coming off {dist}" (when run in last 3d)
//    {ifWorkoutDone}— " — workout's already in" (when complete)
//
//    -- Streak / utility:
//    {streak}      — current streak length
//    {booster}     — " + your 1v1 with Paul" (already prefixed by " + ")
//                    or empty string
//

import Foundation

enum DailyBriefTemplates {
    struct Rendered {
        let headline: String
        let body: String
    }

    // MARK: - Public API

    static func compose(
        band: CapacityBand,
        debt: DebtKind,
        goal: GoalFamily,
        debtFields: [String: String],
        booster: String?,
        streak: Int,
        linkedQuestTitle: String? = nil,
        context: BriefContext? = nil
    ) -> Rendered {
        // Phase 0 (2026-04-27) — subKind override. The engine emits
        // `subKind: "noBreakfast"` for protein deficits triggered by
        // "user has logged zero meals in late morning" instead of the
        // alarming "30g short" pattern.
        if debt == .proteinDeficit, debtFields["subKind"] == "noBreakfast" {
            let workoutDone = debtFields["workoutDone"] == "1"
            let raw = noBreakfastTemplate(band: band, goal: goal, workoutDone: workoutDone)
            return Rendered(
                headline: interpolate(raw.headline, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle, context: context),
                body: interpolate(raw.body, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle, context: context)
            )
        }
        let raw = pick(band: band, debt: debt, goal: goal, streak: streak)
        return Rendered(
            headline: interpolate(raw.headline, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle, context: context),
            body: interpolate(raw.body, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle, context: context)
        )
    }

    static func cta(
        band: CapacityBand,
        debt: DebtKind,
        goal: GoalFamily,
        debtFields: [String: String],
        boosterChallengeId: UUID?
    ) -> BriefCTA {
        // Red day always lands on the recovery day. Booster challenge
        // (when present) is preferred over a workout when the brief is
        // hydration / nutrition / steps — those are passive enough that
        // jumping to the challenge view for context feels right. For
        // muscle / no-workout debts, the action stays "start auto
        // workout" so the user lands in the generator instead of a
        // challenge wall.
        if band == .red { return .startRecoveryDay }
        switch debt {
        case .muscleGroup:
            let split = debtFields["split"]
            return .startAutoWorkout(splitHint: split, etaMin: etaForSplit(split, goal: goal))
        case .recoveryNeeded:
            return .startRecoveryDay
        case .proteinDeficit:
            return .openMealLog
        case .hydrationDeficit:
            return .logWater
        case .stepsBehindGoal:
            // Steps gap → open challenge if one exists, else start a
            // walking-friendly auto workout.
            if let id = boosterChallengeId { return .openChallenge(id: id) }
            return .startAutoWorkout(splitHint: "fullBody", etaMin: 25)
        case .streakRisk:
            return .startAutoWorkout(splitHint: "fullBody", etaMin: 20)
        case .noWorkoutYet:
            return .startAutoWorkout(splitHint: nil, etaMin: 25)
        case .allClear:
            // Everything's done — surface readiness so user can drill in.
            return .openReadiness
        }
    }

    // MARK: - Template selection

    /// Matches (band, debt, goal); falls back to (band, debt, generalFitness),
    /// then to (any, debt, any) generic copy. Streak fallback only when
    /// debt is `.allClear`.
    private static func pick(band: CapacityBand, debt: DebtKind, goal: GoalFamily, streak: Int) -> RawTemplate {
        if let exact = catalog[Key(band, debt, goal)] { return exact }
        if let goalDefault = catalog[Key(band, debt, .generalFitness)] { return goalDefault }
        if debt == .allClear { return streakTemplate(streak: streak) }
        // Last-resort generic.
        return RawTemplate(
            headline: "Today's brief.",
            body: "Open up your day{booster}."
        )
    }

    /// Phase 0 (2026-04-27): no-breakfast pivot. Triggered by the
    /// engine when the user has zero meals logged AND it's
    /// late-morning (11 AM–2 PM). Different copy per goal family so
    /// muscle-building users get the protein-banking framing while
    /// fat-loss users get the metabolism-priming framing.
    /// `workoutDone` (post-workout) variants celebrate the lift
    /// instead of the generic "day's just getting started" — which
    /// felt off when the user had already crushed today's workout.
    private static func noBreakfastTemplate(
        band: CapacityBand,
        goal: GoalFamily,
        workoutDone: Bool
    ) -> RawTemplate {
        if workoutDone {
            switch goal {
            case .buildMuscle:
                return RawTemplate(
                    headline: "Refuel. Workout's already in.",
                    body: "Protein within the hour locks tonight's recovery."
                )
            case .loseFat:
                return RawTemplate(
                    headline: "Refuel. Feed the burn.",
                    body: "Protein-forward meal keeps the deficit honest."
                )
            case .endurance:
                return RawTemplate(
                    headline: "Restock. Session's already done.",
                    body: "Carbs + protein now to load up for tomorrow."
                )
            case .generalFitness:
                return RawTemplate(
                    headline: "Eat something. Workout's in.",
                    body: "First meal closes today's loop."
                )
            }
        }
        switch goal {
        case .buildMuscle:
            return RawTemplate(
                headline: "Refuel. Day's just getting started.",
                body: "Quick high-protein breakfast banks today's gains."
            )
        case .loseFat:
            return RawTemplate(
                headline: "Fuel up. Protein keeps cravings down.",
                body: "Eat now, train later, win the deficit."
            )
        case .endurance:
            return RawTemplate(
                headline: "Fuel up. Engine needs carbs + protein.",
                body: "Eating before training keeps pace strong."
            )
        case .generalFitness:
            return RawTemplate(
                headline: "Eat something. Engine needs fuel.",
                body: "Something small now sets up the rest of the day."
            )
        }
    }

    private static func streakTemplate(streak: Int) -> RawTemplate {
        // Phase 7 (2026-04-27): all-clear days are the BEST surface
        // for cross-domain flexes — user's done their work, body
        // copy can lean on rivals + Strava + overdue muscles to
        // tease tomorrow without nagging today.
        switch streak {
        case 0:
            return RawTemplate(
                headline: "Today's the day to start your streak.",
                body: "A 25-min auto session locks in day 1{ifOverdue}{booster}."
            )
        case 1...6:
            return RawTemplate(
                headline: "{streak}-day streak — momentum is building.",
                body: "Quick session keeps the chain alive{ifOverdue}{booster}."
            )
        case 7...29:
            return RawTemplate(
                headline: "{streak}-day streak. You're in habit territory.",
                body: "Stay light and consistent{ifAheadRival}{ifBehindRival}{booster}."
            )
        default:
            return RawTemplate(
                headline: "Legendary {streak}-day streak.",
                body: "Anything you do today protects the chain{ifOverdue}{booster}."
            )
        }
    }

    // MARK: - Interpolation

    private static func interpolate(_ raw: String, fields: [String: String], booster: String?, streak: Int, debt: DebtKind, goal: GoalFamily, linkedQuestTitle: String? = nil, context: BriefContext? = nil) -> String {
        var out = raw

        // Field substitutions.
        for (k, v) in fields {
            out = out.replacingOccurrences(of: "{\(k)}", with: v)
        }

        // Phase 11 (2026-05-08 — "actionable headlines, insight bodies"):
        // `{Muscles}` is the first-letter-capitalized variant of
        // `{muscles}` ("chest & triceps" → "Chest & triceps"). Lets
        // headlines lead with a clean noun-phrase capitalization
        // ("Chest & triceps are 5d overdue.") instead of the
        // lowercase grammar fragment the raw `{muscles}` field
        // produces ("chest & triceps are 5d overdue."). The raw
        // lowercase form stays available in mid-sentence body copy.
        if let muscles = fields["muscles"], !muscles.isEmpty {
            let capitalized = muscles.prefix(1).uppercased() + muscles.dropFirst()
            out = out.replacingOccurrences(of: "{Muscles}", with: capitalized)
        } else {
            out = out.replacingOccurrences(of: "{Muscles}", with: "")
        }

        // Phase 2 (2026-04-27): {linkedQuestTitle} token — gets the
        // matching quest's title when there's one on today's slate
        // ("Crush Protein", "Set Machine"). Empty string when no
        // match — templates that use the token should phrase around
        // it gracefully (e.g. "Eat now{ifLinked} and run a lighter
        // session" pattern, where {ifLinked} expands to " (Crush
        // Protein)" when present, "" otherwise).
        if let title = linkedQuestTitle, !title.isEmpty {
            out = out.replacingOccurrences(of: "{linkedQuestTitle}", with: title)
            out = out.replacingOccurrences(of: "{ifLinked}", with: " (\(title))")
        } else {
            out = out.replacingOccurrences(of: "{linkedQuestTitle}", with: "")
            out = out.replacingOccurrences(of: "{ifLinked}", with: "")
        }

        // {splitTitle}: title-cased split.
        if let s = fields["split"] {
            let title: String
            switch s {
            case "push": title = "Push"
            case "pull": title = "Pull"
            case "legs": title = "Legs"
            case "fullBody", "full_body": title = "Full body"
            default: title = s.capitalized
            }
            out = out.replacingOccurrences(of: "{splitTitle}", with: title)
        } else {
            out = out.replacingOccurrences(of: "{splitTitle}", with: "Workout")
        }

        // {eta}: derived from split + goal.
        let eta = etaForSplit(fields["split"], goal: goal)
        out = out.replacingOccurrences(of: "{eta}", with: "\(eta)")

        // {streak}.
        out = out.replacingOccurrences(of: "{streak}", with: "\(streak)")

        // Phase 7 (2026-04-27): cross-facet context tokens. All
        // nil-safe — when a service isn't connected the whole
        // `{if...}` clause collapses, so the same template degrades
        // across every user state.
        out = applyContextTokens(out, context: context)

        // {booster}: prefixed " + " when present, empty otherwise. We
        // intentionally swallow the prefix into the token so templates
        // can write "wins your daily quest{booster}" and naturally read
        // "wins your daily quest" OR "wins your daily quest + your 1v1
        // with Paul" without per-template branching.
        if let booster, !booster.isEmpty {
            out = out.replacingOccurrences(of: "{booster}", with: " + \(booster)")
        } else {
            out = out.replacingOccurrences(of: "{booster}", with: "")
        }

        return out
    }

    /// Phase 7 (2026-04-27): replace every `{rival}` / `{sleep}` /
    /// `{ifBehindRival}` / etc. in the template with the matching
    /// value from `BriefContext`. Conditional clauses (`{ifSleepLow}`)
    /// resolve to a complete phrase OR an empty string — never to
    /// raw braces — so the templates degrade cleanly even when no
    /// context was supplied (cold path for the test harness).
    private static func applyContextTokens(_ input: String, context: BriefContext?) -> String {
        var out = input
        let ctx = context

        // — Simple value tokens (empty when not available).
        let rival = ctx?.rivalFirstName ?? ""
        out = out.replacingOccurrences(of: "{rival}", with: rival)

        let rivalToday = ctx?.rivalTodayFormatted ?? ""
        out = out.replacingOccurrences(of: "{rivalToday}", with: rivalToday)

        let rivalUnit = displayUnit(for: ctx?.rivalChallengeType)
        out = out.replacingOccurrences(of: "{rivalUnit}", with: rivalUnit)

        if let sleep = ctx?.sleepHours {
            out = out.replacingOccurrences(of: "{sleep}", with: String(format: "%.1fh", sleep))
        } else {
            out = out.replacingOccurrences(of: "{sleep}", with: "")
        }

        if let recovery = ctx?.recoveryScore {
            out = out.replacingOccurrences(of: "{recovery}", with: "\(recovery)%")
        } else {
            out = out.replacingOccurrences(of: "{recovery}", with: "")
        }

        if let s = ctx?.strainPrev {
            out = out.replacingOccurrences(of: "{strainPrev}", with: String(format: "%.1f", s))
        } else {
            out = out.replacingOccurrences(of: "{strainPrev}", with: "")
        }

        out = out.replacingOccurrences(of: "{primarySource}", with: ctx?.primarySource ?? "")

        // {bedtime}: best-effort — if WHOOP supplied a sleep need OR
        // last-night sleep was short, suggest a bedtime that gives
        // ~8h to wake at 7am. Conservative: if nothing else, use
        // 10:30 PM as the canonical "wind down" anchor.
        out = out.replacingOccurrences(of: "{bedtime}", with: bedtimeSuggestion(for: ctx))

        // — Conditional clause tokens (whole phrase or empty).
        out = out.replacingOccurrences(of: "{ifBehindRival}", with: behindRivalClause(ctx))
        out = out.replacingOccurrences(of: "{ifAheadRival}", with: aheadRivalClause(ctx))
        out = out.replacingOccurrences(of: "{ifRival}", with: rivalGenericClause(ctx))
        out = out.replacingOccurrences(of: "{ifSleepLow}", with: sleepLowClause(ctx))
        out = out.replacingOccurrences(of: "{ifSleepDebt}", with: sleepDebtClause(ctx))
        out = out.replacingOccurrences(of: "{ifLowRecovery}", with: lowRecoveryClause(ctx))
        out = out.replacingOccurrences(of: "{ifHighStrain}", with: highStrainClause(ctx))
        out = out.replacingOccurrences(of: "{ifOverdue}", with: overdueClause(ctx))
        out = out.replacingOccurrences(of: "{ifRecentRun}", with: recentRunClause(ctx))
        out = out.replacingOccurrences(of: "{ifWorkoutDone}", with: workoutDoneClause(ctx))

        return out
    }

    // MARK: - Conditional clause helpers

    /// Phase 7b (2026-04-27): expose the gap formatting helpers to
    /// the engine's `buildInsightBody` so it can render the same
    /// "Up 1.2k on Manuel" / "320 cal" cadence inside its own
    /// rotating insight pool. Keeps gap-formatting logic in one
    /// place across action AND insight bodies.
    static func displayUnitPublic(for challengeType: String?) -> String {
        displayUnit(for: challengeType)
    }
    static func formatGapPublic(_ value: Int, unit: String) -> String {
        formatGap(value, unit: unit)
    }
    static func isMeaningfulGapPublic(_ absGap: Int, type: String?) -> Bool {
        isMeaningfulGap(absGap, type: type)
    }

    private static func displayUnit(for challengeType: String?) -> String {
        switch challengeType {
        case "steps":          return "steps"
        case "calories":       return "cal"
        case "active_minutes": return "min"
        case "workouts":       return "workouts"
        default:               return ""
        }
    }

    private static func bedtimeSuggestion(for ctx: BriefContext?) -> String {
        // Anchor: 10:30 PM — generic but consistent. WHOOP's
        // "sleep_need" surface lives one layer below
        // `DailyReadinessSnapshot`; until we lift that into the
        // snapshot, we pin a sensible default that aligns with the
        // "8h to a 6:30am wake" cadence the readiness service
        // already targets.
        return "10:30 PM"
    }

    private static func rivalGenericClause(_ ctx: BriefContext?) -> String {
        // Used for "or just" copy where rival presence matters but
        // direction (ahead/behind) doesn't.
        guard let name = ctx?.rivalFirstName, !name.isEmpty else { return "" }
        return " — and {rival} won't see it coming".replacingOccurrences(of: "{rival}", with: name)
    }

    private static func behindRivalClause(_ ctx: BriefContext?) -> String {
        guard let name = ctx?.rivalFirstName, !name.isEmpty else { return "" }
        guard let signed = ctx?.rivalSignedGap, signed < 0 else { return "" }
        let absGap = abs(signed)
        guard isMeaningfulGap(absGap, type: ctx?.rivalChallengeType) else { return "" }
        let unit = displayUnit(for: ctx?.rivalChallengeType)
        let formatted = formatGap(absGap, unit: unit)
        // " — Manuel's up 1.2k" or " — Manuel's leading by 320 cal"
        return " — \(name)'s up \(formatted)"
    }

    private static func aheadRivalClause(_ ctx: BriefContext?) -> String {
        guard let name = ctx?.rivalFirstName, !name.isEmpty else { return "" }
        guard let signed = ctx?.rivalSignedGap, signed > 0 else { return "" }
        let absGap = signed
        guard isMeaningfulGap(absGap, type: ctx?.rivalChallengeType) else { return "" }
        let unit = displayUnit(for: ctx?.rivalChallengeType)
        let formatted = formatGap(absGap, unit: unit)
        return " — and you're up \(formatted) on \(name)"
    }

    /// Suppress noise-level gaps so we never render "Manuel's up 12 steps".
    /// Thresholds calibrated to match the body-copy "is this worth
    /// mentioning" gut check — a 250-step lead won't change anyone's
    /// behavior; a 1k+ lead will.
    private static func isMeaningfulGap(_ absGap: Int, type: String?) -> Bool {
        switch type {
        case "steps":          return absGap >= 250
        case "calories":       return absGap >= 50
        case "active_minutes": return absGap >= 10
        case "workouts":       return absGap >= 1
        default:               return absGap >= 1
        }
    }

    private static func formatGap(_ value: Int, unit: String) -> String {
        switch unit {
        case "steps":
            if value >= 1000 {
                return String(format: "%.1fk", Double(value) / 1000.0)
            }
            return "\(value) steps"
        case "cal", "min":
            return "\(value) \(unit)"
        case "workouts":
            return value == 1 ? "1 workout" : "\(value) workouts"
        default:
            return "\(value)"
        }
    }

    private static func sleepLowClause(_ ctx: BriefContext?) -> String {
        guard let h = ctx?.sleepHours, h > 0, h < 6.5 else { return "" }
        return String(format: " — last night was only %.1fh", h)
    }

    private static func sleepDebtClause(_ ctx: BriefContext?) -> String {
        guard let mins = ctx?.sleepDebtMin, mins >= 60 else { return "" }
        return " — you're \(mins)min sleep-debt"
    }

    private static func lowRecoveryClause(_ ctx: BriefContext?) -> String {
        guard let r = ctx?.recoveryScore, r > 0, r <= 50 else { return "" }
        return " — recovery's \(r)%"
    }

    private static func highStrainClause(_ ctx: BriefContext?) -> String {
        guard let s = ctx?.strainPrev, s >= 16.0 else { return "" }
        return String(format: " — yesterday's %.1f strain ate the tank", s)
    }

    private static func overdueClause(_ ctx: BriefContext?) -> String {
        guard let m = ctx?.topOverdueMuscle, !m.isEmpty,
              let d = ctx?.topOverdueDays, d >= 4 else { return "" }
        return " — \(m) still \(d)d overdue"
    }

    private static func recentRunClause(_ ctx: BriefContext?) -> String {
        guard let dist = ctx?.lastRunDistanceM, dist >= 1000,
              let days = ctx?.lastRunDaysAgo, days <= 3 else { return "" }
        let km = dist / 1000.0
        let distLabel: String
        if km >= 9.5 && km <= 10.5 {
            distLabel = "10K"
        } else if km >= 4.5 && km <= 5.5 {
            distLabel = "5K"
        } else {
            distLabel = String(format: "%.1fK", km)
        }
        let when = days == 0 ? "today" : (days == 1 ? "yesterday" : "\(days)d ago")
        return " — coming off your \(distLabel) \(when)"
    }

    private static func workoutDoneClause(_ ctx: BriefContext?) -> String {
        return (ctx?.workoutDoneToday == true) ? " — workout's already in" : ""
    }

    private static func etaForSplit(_ split: String?, goal: GoalFamily) -> Int {
        // Build muscle = slightly longer (volume); lose fat = shorter
        // (intensity). Numbers are intentionally specific so the brief
        // feels concrete, not vague ("about 30 minutes").
        let base: Int
        switch split {
        case "push", "pull": base = 28
        case "legs": base = 35
        case "fullBody", "full_body": base = 25
        default: base = 25
        }
        switch goal {
        case .buildMuscle: return base
        case .loseFat, .endurance: return max(20, base - 5)
        case .generalFitness: return base
        }
    }

    // MARK: - Catalog

    private struct RawTemplate {
        let headline: String
        let body: String
    }

    private struct Key: Hashable {
        let band: CapacityBand
        let debt: DebtKind
        let goal: GoalFamily
        init(_ band: CapacityBand, _ debt: DebtKind, _ goal: GoalFamily) {
            self.band = band; self.debt = debt; self.goal = goal
        }
    }

    /// Every entry; goals fall back to `.generalFitness` if the more
    /// specific (buildMuscle / loseFat / endurance) entry is absent.
    ///
    /// Body copy contract (Phase 11 — 2026-05-08, "actionable
    /// headlines, insight bodies"):
    ///   • HEADLINE = `{Action}. {Gap}.` — TWO sentences. First
    ///     sentence is an imperative action verb ("Take a walk.",
    ///     "Refuel.", "Rest today.", "Push day."). Second sentence
    ///     is the concrete gap / state ("4.5k steps left in your
    ///     day.", "100g of protein left today."). Mirrors the
    ///     "Take a walk. 4.5k steps left in your day." cadence
    ///     the user explicitly endorsed. NEVER prescribes a time
    ///     budget like `"~35 min"` — that read as a deadline
    ///     ("if you don't do legs in 35 min you fail today's
    ///     quest", which is false). The `{eta}` token is
    ///     RETIRED from action bodies as of Phase 11.
    ///   • BODY = one supporting INSIGHT — recovery science,
    ///     longest-gap framing, "compound lifts burn the most
    ///     cal/min", or a small contextual fact — that supports
    ///     the gap WITHOUT locking to a specific quest. Phrases
    ///     like `"wins today's quest"` are banned because they
    ///     imply the daily-goals card and this brief are a single
    ///     unit (they're not — the brief should support quests,
    ///     not depend on them).
    ///   • EM-DASH RULE — at most ONE em-dash per card across
    ///     headline + body combined. Two em-dash chains in one
    ///     card was the canonical "clunky" complaint
    ///     (Phase 10 incident). Default convention: headline is
    ///     em-dash-free, body MAY use one em-dash for an
    ///     "X — Y" insight clause.
    ///   • The only optional tail token bodies may carry is
    ///     `{booster}` (" + your 1v1 with Paul") — " + " prefix,
    ///     not " — " dash, so it doesn't chain visually with any
    ///     em-dash in the body itself.
    ///
    /// Cross-facet color (rivals, recovery, Strava) lives in (a)
    /// the dedicated dashboard widgets, and (b) the engine's
    /// `buildInsightBody` rotating insight pool — which fully
    /// REPLACES the action body on low-urgency / `.allClear` days.
    /// The conditional-clause machinery (`{ifBehindRival}` etc.)
    /// in `applyContextTokens` is preserved for the streak
    /// template (`.allClear`-only, replaced by `buildInsightBody`
    /// in production — effectively a test-only path that
    /// exercises the helper) and `buildInsightBody`'s pool.
    ///
    /// Length contract (Phase 9 — 2026-05-02, tightened by Phase 10
    /// + Phase 11): the welcome card uses `lineLimit(2)` for both
    /// headline (`.ds_heading2`, 22pt bold) and body
    /// (`.ds_bodySmall`, 13pt) with `.minimumScaleFactor(0.9)`. On
    /// iPhone SE the medallion + spacing leaves ~245pt of text
    /// width, which fits ~21 chars/line at the min-scale → 42-char
    /// hard cap on the headline post-interpolation. Bodies cap at
    /// ~72 chars (base + booster). Worst-case token sizes to plan
    /// against: `{muscles}` = "chest & triceps" (15 chars),
    /// `{Muscles}` = "Chest & triceps" (15), `{days}` = "10" (2),
    /// `{splitTitle}` = "Full body" (9), `{deficitG}` = "100" (3),
    /// `{deficitL}` = "1.5" (3), `{gap}` = "10.0k" (5), `{streak}`
    /// = "100" (3), `{booster}` = " + your 1v1 with Manuel" (~22).
    /// Use `{days}d` shorthand instead of `{days} days` everywhere
    /// — the "d" suffix is universally readable and saves 4 chars
    /// per occurrence. `{eta}` is RETIRED from action bodies as
    /// of Phase 11 (read as a deadline); the helper is preserved
    /// for any future surface that wants a pure "estimated
    /// duration" data point but no template should reintroduce
    /// it into welcome-card copy.
    private static let catalog: [Key: RawTemplate] = [

        // ─── GREEN × MUSCLE GROUP ─────────────────────────────────
        // Phase 11 (2026-05-08) — `{Action}. {Gap}.` headline pattern.
        // {splitTitle} doubles as the action lead ("Push day.")
        // because it's already the most concrete action verb the
        // template knows. Bodies are static insights — recovery
        // science / longest-gap framing — that support the gap
        // without locking to a specific quest.
        Key(.green, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "{splitTitle} day. {Muscles} {days}d due.",
            body: "Long rest = your biggest growth window{booster}."
        ),
        Key(.green, .muscleGroup, .loseFat): RawTemplate(
            headline: "{splitTitle} day. {Muscles} {days}d due.",
            body: "Compound lifts torch the most cal/min{booster}."
        ),
        Key(.green, .muscleGroup, .endurance): RawTemplate(
            headline: "{splitTitle} day. {Muscles} {days}d due.",
            body: "Strength carry-over lifts pace 48h later{booster}."
        ),
        Key(.green, .muscleGroup, .generalFitness): RawTemplate(
            headline: "{splitTitle} day. {Muscles} {days}d due.",
            body: "Longest gap in your rotation — balance day{booster}."
        ),

        // ─── GREEN × NO WORKOUT YET ──────────────────────────────
        Key(.green, .noWorkoutYet, .buildMuscle): RawTemplate(
            headline: "Train today. {days}d off the lifts.",
            body: "Recovered + rested = your best growth window{booster}."
        ),
        Key(.green, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "Train today. {days}d off the lifts.",
            body: "Body's primed — first set's the hardest{booster}."
        ),

        // ─── GREEN × PROTEIN ─────────────────────────────────────
        Key(.green, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Refuel. {deficitG}g of protein left today.",
            body: "MPS window's wide open — bank tonight's gains{booster}."
        ),
        Key(.green, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "Refuel. {deficitG}g of protein left today.",
            body: "Recovery starts at the table{booster}."
        ),

        // ─── GREEN × HYDRATION ───────────────────────────────────
        Key(.green, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Top off. {deficitL}L behind on water today.",
            body: "Cheapest readiness boost in your toolkit{booster}."
        ),

        // ─── GREEN × STEPS ───────────────────────────────────────
        // Canonical Phase 11 example endorsed by the user:
        // "Take a walk. 4.5k steps left in your day."
        Key(.green, .stepsBehindGoal, .loseFat): RawTemplate(
            headline: "Take a walk. {gap} steps left in your day.",
            body: "Z2 walk burns clean fat — easiest deficit win{booster}."
        ),
        Key(.green, .stepsBehindGoal, .generalFitness): RawTemplate(
            headline: "Take a walk. {gap} steps left in your day.",
            body: "Easiest goal on the card. Worth a podcast{booster}."
        ),

        // ─── GREEN × STREAK RISK ─────────────────────────────────
        Key(.green, .streakRisk, .generalFitness): RawTemplate(
            headline: "Lock it in. {streak}-day streak on the line.",
            body: "Streaks are habit anchors — one set locks it{booster}."
        ),

        // ─── YELLOW × MUSCLE GROUP ───────────────────────────────
        Key(.yellow, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "Go moderate. {Muscles} {days}d overdue.",
            body: "Recovery's mid — leave one rep in the tank{booster}."
        ),
        Key(.yellow, .muscleGroup, .loseFat): RawTemplate(
            headline: "Go moderate. {Muscles} {days}d overdue.",
            body: "Trim intensity, hold volume — burn smart{booster}."
        ),
        Key(.yellow, .muscleGroup, .generalFitness): RawTemplate(
            headline: "Go moderate. {Muscles} {days}d overdue.",
            body: "Yellow band = maintain, don't max{booster}."
        ),

        // ─── YELLOW × NO WORKOUT YET ─────────────────────────────
        Key(.yellow, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "Easy session. {days}d since your last.",
            body: "Easy fits the band — momentum > intensity{booster}."
        ),

        // ─── YELLOW × PROTEIN ────────────────────────────────────
        Key(.yellow, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Refuel. {deficitG}g of protein left today.",
            body: "Eat now to bank tomorrow's strain budget{booster}."
        ),
        Key(.yellow, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "Refuel. {deficitG}g of protein left today.",
            body: "Recovery starts at the table{booster}."
        ),

        // ─── YELLOW × HYDRATION ──────────────────────────────────
        Key(.yellow, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Top off. {deficitL}L behind on water today.",
            body: "Cheapest readiness boost in your toolkit{booster}."
        ),

        // ─── YELLOW × STEPS ──────────────────────────────────────
        Key(.yellow, .stepsBehindGoal, .loseFat): RawTemplate(
            headline: "Easy walk. {gap} steps left in your day.",
            body: "Easy walk burns clean fat — no recovery cost{booster}."
        ),

        // ─── RED × RECOVERY NEEDED ───────────────────────────────
        // Red days: action verb is "Rest" / "Recover" — body
        // explains why bypassing today protects tomorrow.
        Key(.red, .recoveryNeeded, .buildMuscle): RawTemplate(
            headline: "Rest day. Body needs the reset.",
            body: "Hard sessions cost tomorrow. Bank the rest{booster}."
        ),
        Key(.red, .recoveryNeeded, .loseFat): RawTemplate(
            headline: "Recovery day. Burn tomorrow.",
            body: "Walk + hydration + early sleep clears it{booster}."
        ),
        Key(.red, .recoveryNeeded, .endurance): RawTemplate(
            headline: "Easy spin only. Capacity's low.",
            body: "Don't bank fatigue. Load up tomorrow{booster}."
        ),
        Key(.red, .recoveryNeeded, .generalFitness): RawTemplate(
            headline: "Rest day. Body's tapped.",
            body: "Sleep + hydration earn compound interest{booster}."
        ),

        // ─── RED × PROTEIN (still actionable) ────────────────────
        Key(.red, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Refuel. {deficitG}g of protein left today.",
            body: "Skip the lift, hit the protein{booster}."
        ),

        // ─── RED × HYDRATION ─────────────────────────────────────
        Key(.red, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Hydrate. {deficitL}L water deficit today.",
            body: "Rehydrate first, sleep early{booster}."
        ),

        // ─── UNKNOWN (no wearable) — never cite recovery ─────────
        Key(.unknown, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "{splitTitle} day. {Muscles} {days}d due.",
            body: "Long rest = your biggest growth window{booster}."
        ),
        Key(.unknown, .muscleGroup, .loseFat): RawTemplate(
            headline: "{splitTitle} day. {Muscles} {days}d due.",
            body: "Compound lifts torch the most cal/min{booster}."
        ),
        Key(.unknown, .muscleGroup, .generalFitness): RawTemplate(
            headline: "{splitTitle} day. {Muscles} {days}d due.",
            body: "Longest gap in your rotation{booster}."
        ),
        Key(.unknown, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "Train today. {days}d off the lifts.",
            body: "First set's the hardest. Auto-gen has the plan{booster}."
        ),
        Key(.unknown, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "Refuel. {deficitG}g of protein left today.",
            body: "Recovery starts at the table{booster}."
        ),
        Key(.unknown, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Top off. {deficitL}L behind on water.",
            body: "Cheapest readiness boost in your toolkit{booster}."
        ),
        Key(.unknown, .stepsBehindGoal, .generalFitness): RawTemplate(
            headline: "Take a walk. {gap} steps left in your day.",
            body: "Easiest goal on the card. Worth a podcast{booster}."
        ),
        Key(.unknown, .streakRisk, .generalFitness): RawTemplate(
            headline: "Lock it in. {streak}-day streak on the line.",
            body: "Streaks are habit anchors — one set locks it{booster}."
        ),
    ]
}
