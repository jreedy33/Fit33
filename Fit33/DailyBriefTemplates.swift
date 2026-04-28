//
//  DailyBriefTemplates.swift
//  Fit33
//
//  Sentence templates for the Daily Brief — keyed by
//  (CapacityBand, DebtKind, GoalFamily). Pure data + small render
//  helper. Fitness Expert / Design can edit copy here without
//  touching the engine logic.
//
//  North-Star example (the canonical green + muscleGroup + buildMuscle
//  template):
//
//      "Strain is fresh — chest & triceps are 5 days overdue."
//      "Push day in ~23 min wins your daily quest{booster}."
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
                    headline: "Workout's in. Now refuel.",
                    body: "Protein within an hour locks in tonight's recovery{ifOverdue}."
                )
            case .loseFat:
                return RawTemplate(
                    headline: "Workout done — feed the burn.",
                    body: "Protein-forward meal keeps the deficit honest{ifBehindRival}."
                )
            case .endurance:
                return RawTemplate(
                    headline: "Session in — restock the tank.",
                    body: "Carbs + protein now to load up for tomorrow{ifRecentRun}."
                )
            case .generalFitness:
                return RawTemplate(
                    headline: "Workout's in — eat something.",
                    body: "First meal closes today's loop{ifBehindRival}."
                )
            }
        }
        switch goal {
        case .buildMuscle:
            return RawTemplate(
                headline: "Refuel — the day's just getting started.",
                body: "Quick high-protein breakfast banks today's gains{ifOverdue}."
            )
        case .loseFat:
            return RawTemplate(
                headline: "Fuel up — protein keeps cravings down.",
                body: "Eat now, train later, win the deficit{ifBehindRival}."
            )
        case .endurance:
            return RawTemplate(
                headline: "Fuel the engine.",
                body: "Carbs + protein before your session keeps pace strong{ifRecentRun}."
            )
        case .generalFitness:
            return RawTemplate(
                headline: "Quick breakfast keeps the engine going.",
                body: "Something small now sets up the rest of the day{ifBehindRival}."
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
    /// Body copy contract (Phase 7 — 2026-04-27): every body is a
    /// 1-2 line cross-domain insight that names a specific number,
    /// references at least one other facet (rival / sleep / strain
    /// / overdue muscles / Strava run / recovery), and ends with an
    /// optional `{booster}` clause. Conditional `{if...}` tokens
    /// degrade gracefully when their facet isn't connected — same
    /// template covers WHOOP / Oura / no-wearable users.
    private static let catalog: [Key: RawTemplate] = [

        // ─── GREEN × MUSCLE GROUP ─────────────────────────────────
        Key(.green, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "Strain is fresh — {muscles} are {days} days overdue.",
            body: "{splitTitle} day in ~{eta} min wins today's quest{ifBehindRival}{booster}."
        ),
        Key(.green, .muscleGroup, .loseFat): RawTemplate(
            headline: "Recovery's green — {muscles} are {days} days overdue.",
            body: "{splitTitle} session (~{eta} min) burns the deficit{ifRecentRun}{booster}."
        ),
        Key(.green, .muscleGroup, .endurance): RawTemplate(
            headline: "Body's primed — {muscles} need a session.",
            body: "{splitTitle} circuit (~{eta} min) doubles as conditioning{ifRecentRun}{booster}."
        ),
        Key(.green, .muscleGroup, .generalFitness): RawTemplate(
            headline: "You're recovered — {muscles} haven't been hit in {days} days.",
            body: "{splitTitle} day in ~{eta} min keeps you balanced{ifBehindRival}{booster}."
        ),

        // ─── GREEN × NO WORKOUT YET ──────────────────────────────
        Key(.green, .noWorkoutYet, .buildMuscle): RawTemplate(
            headline: "Green light — and {days} days since your last lift.",
            body: "{eta}-min auto session locks today's quest{ifOverdue}{booster}."
        ),
        Key(.green, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "You're rested. {days} days off — time to move.",
            body: "Auto workout in ~{eta} min{ifOverdue}{booster}."
        ),

        // ─── GREEN × PROTEIN ─────────────────────────────────────
        Key(.green, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Recovery's prime, but you're {deficitG}g short on protein.",
            body: "Eat now to bank tonight's gains{ifOverdue}{booster}."
        ),
        Key(.green, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "{deficitG}g of protein left to hit your goal.",
            body: "A meal closes the gap and locks today's recovery{booster}."
        ),

        // ─── GREEN × HYDRATION ───────────────────────────────────
        Key(.green, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "You're {deficitL}L behind on water.",
            body: "Knock it back — dehydration suppresses tomorrow's HRV{ifOverdue}{booster}."
        ),

        // ─── GREEN × STEPS ───────────────────────────────────────
        Key(.green, .stepsBehindGoal, .loseFat): RawTemplate(
            headline: "{gap} steps to go — and you're rested for it.",
            body: "20-min Z2 walk closes the deficit{ifBehindRival}{booster}."
        ),
        Key(.green, .stepsBehindGoal, .generalFitness): RawTemplate(
            headline: "{gap} steps left in your day.",
            body: "Quick walk wraps it{ifBehindRival}{booster}."
        ),

        // ─── GREEN × STREAK RISK ─────────────────────────────────
        Key(.green, .streakRisk, .generalFitness): RawTemplate(
            headline: "{streak}-day streak — clock's ticking.",
            body: "{eta}-min full-body protects the chain{ifOverdue}{booster}."
        ),

        // ─── YELLOW × MUSCLE GROUP ───────────────────────────────
        Key(.yellow, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "Recovery's mid — {muscles} could use a session.",
            body: "{splitTitle} day in ~{eta} min, last rep in the tank{ifHighStrain}{booster}."
        ),
        Key(.yellow, .muscleGroup, .loseFat): RawTemplate(
            headline: "Yellow band — {muscles} are {days} days overdue.",
            body: "Moderate {splitTitle} (~{eta} min) without redlining{ifSleepLow}{booster}."
        ),
        Key(.yellow, .muscleGroup, .generalFitness): RawTemplate(
            headline: "Steady day — {muscles} are due.",
            body: "Smart {splitTitle} session in ~{eta} min{ifHighStrain}{booster}."
        ),

        // ─── YELLOW × NO WORKOUT YET ─────────────────────────────
        Key(.yellow, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "Steady recovery, {days} days since your last session.",
            body: "Easy {eta}-min routine fits the band{ifSleepLow}{booster}."
        ),

        // ─── YELLOW × PROTEIN ────────────────────────────────────
        Key(.yellow, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Mid recovery + {deficitG}g protein short.",
            body: "Eat now to bank tomorrow's strain budget{ifOverdue}{booster}."
        ),
        Key(.yellow, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "{deficitG}g of protein left.",
            body: "Refuel before your next move — recovery starts at the table{booster}."
        ),

        // ─── YELLOW × HYDRATION ──────────────────────────────────
        Key(.yellow, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Yellow band and {deficitL}L behind on water.",
            body: "Hydration's the cheapest readiness boost — green by tonight{booster}."
        ),

        // ─── YELLOW × STEPS ──────────────────────────────────────
        Key(.yellow, .stepsBehindGoal, .loseFat): RawTemplate(
            headline: "{gap} steps to go — Z2 fits your band.",
            body: "Easy walk burns the deficit and lowers stress{ifBehindRival}{booster}."
        ),

        // ─── RED × RECOVERY NEEDED ───────────────────────────────
        Key(.red, .recoveryNeeded, .buildMuscle): RawTemplate(
            headline: "Red recovery. Your nervous system needs the day.",
            body: "Mobility + bed by {bedtime} sets up tomorrow's lift{ifOverdue}{booster}."
        ),
        Key(.red, .recoveryNeeded, .loseFat): RawTemplate(
            headline: "Red recovery. Save the burn for tomorrow.",
            body: "30-min walk + hydration + early sleep clears the deficit{ifBehindRival}{booster}."
        ),
        Key(.red, .recoveryNeeded, .endurance): RawTemplate(
            headline: "Red day — capacity is low.",
            body: "Easy spin or recovery walk; don't bank fatigue{ifSleepLow}{booster}."
        ),
        Key(.red, .recoveryNeeded, .generalFitness): RawTemplate(
            headline: "Red recovery — body's tapped.",
            body: "Stretch, hydrate, bed by {bedtime}{ifSleepLow}{booster}."
        ),

        // ─── RED × PROTEIN (still actionable) ────────────────────
        Key(.red, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Red day — still {deficitG}g protein short.",
            body: "Skip the lift, hit the protein — recovery wins tomorrow's session{booster}."
        ),

        // ─── RED × HYDRATION ─────────────────────────────────────
        Key(.red, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Red day with {deficitL}L water deficit.",
            body: "Rehydrate first, sleep early — rest is non-negotiable{booster}."
        ),

        // ─── UNKNOWN (no wearable) — never cite recovery ─────────
        Key(.unknown, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "{muscles} are {days} days overdue.",
            body: "{splitTitle} day in ~{eta} min wins today's quest{ifBehindRival}{booster}."
        ),
        Key(.unknown, .muscleGroup, .loseFat): RawTemplate(
            headline: "{muscles} are {days} days overdue.",
            body: "Hit {splitTitle} hard (~{eta} min) — burn the deficit{ifBehindRival}{booster}."
        ),
        Key(.unknown, .muscleGroup, .generalFitness): RawTemplate(
            headline: "{muscles} haven't seen a session in {days} days.",
            body: "{splitTitle} day in ~{eta} min keeps the rotation honest{ifBehindRival}{booster}."
        ),
        Key(.unknown, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "{days} days since your last workout.",
            body: "Auto session in ~{eta} min{ifOverdue}{booster}."
        ),
        Key(.unknown, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "{deficitG}g of protein left.",
            body: "A meal closes the gap and primes tomorrow's session{ifOverdue}{booster}."
        ),
        Key(.unknown, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "{deficitL}L water behind pace.",
            body: "Knock it back — recovery starts with hydration{booster}."
        ),
        Key(.unknown, .stepsBehindGoal, .generalFitness): RawTemplate(
            headline: "{gap} steps left today.",
            body: "20-min walk closes it{ifBehindRival}{ifOverdue}{booster}."
        ),
        Key(.unknown, .streakRisk, .generalFitness): RawTemplate(
            headline: "{streak}-day streak — clock's ticking.",
            body: "{eta}-min session protects the chain{ifOverdue}{booster}."
        ),
    ]
}
