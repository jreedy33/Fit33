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
//    {muscles}     — debtFields["muscles"]   ("chest & triceps")
//    {days}        — debtFields["days"]      ("5")
//    {split}       — debtFields["split"]     ("push" / "pull" / "legs")
//    {splitTitle}  — title-cased {split}     ("Push", "Pull", "Legs")
//    {eta}         — recommended ETA (computed from split + goal)
//    {deficitG}    — protein gap in grams
//    {deficitL}    — water gap in liters
//    {gap}         — steps gap (formatted "3.0k" or "850")
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
        linkedQuestTitle: String? = nil
    ) -> Rendered {
        // Phase 0 (2026-04-27) — subKind override. The engine emits
        // `subKind: "noBreakfast"` for protein deficits triggered by
        // "user has logged zero meals in late morning" instead of the
        // alarming "30g short" pattern.
        if debt == .proteinDeficit, debtFields["subKind"] == "noBreakfast" {
            let workoutDone = debtFields["workoutDone"] == "1"
            let raw = noBreakfastTemplate(band: band, goal: goal, workoutDone: workoutDone)
            return Rendered(
                headline: interpolate(raw.headline, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle),
                body: interpolate(raw.body, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle)
            )
        }
        let raw = pick(band: band, debt: debt, goal: goal, streak: streak)
        return Rendered(
            headline: interpolate(raw.headline, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle),
            body: interpolate(raw.body, fields: debtFields, booster: booster, streak: streak, debt: debt, goal: goal, linkedQuestTitle: linkedQuestTitle)
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
                    body: "Protein within an hour locks in tonight's recovery."
                )
            case .loseFat:
                return RawTemplate(
                    headline: "Workout done — feed the burn.",
                    body: "Protein-forward meal keeps the deficit honest."
                )
            case .endurance:
                return RawTemplate(
                    headline: "Session in — restock the tank.",
                    body: "Carbs + protein now to load up for tomorrow."
                )
            case .generalFitness:
                return RawTemplate(
                    headline: "Workout's in — eat something.",
                    body: "First meal closes today's loop."
                )
            }
        }
        switch goal {
        case .buildMuscle:
            return RawTemplate(
                headline: "Refuel — the day's just getting started.",
                body: "Quick high-protein breakfast banks today's gains."
            )
        case .loseFat:
            return RawTemplate(
                headline: "Fuel up — protein keeps cravings down.",
                body: "Eat now, train later, win the deficit."
            )
        case .endurance:
            return RawTemplate(
                headline: "Fuel the engine.",
                body: "Carbs + protein before your session keeps pace strong."
            )
        case .generalFitness:
            return RawTemplate(
                headline: "Quick breakfast keeps the engine going.",
                body: "Something small now sets up the rest of the day."
            )
        }
    }

    private static func streakTemplate(streak: Int) -> RawTemplate {
        switch streak {
        case 0:
            return RawTemplate(
                headline: "Today's the day to start your streak.",
                body: "A 25-min auto session locks in day 1."
            )
        case 1...6:
            return RawTemplate(
                headline: "{streak}-day streak — momentum is building.",
                body: "Quick session keeps the chain alive."
            )
        case 7...29:
            return RawTemplate(
                headline: "{streak}-day streak. You're in habit territory.",
                body: "Stay light and consistent — daily wins compound."
            )
        default:
            return RawTemplate(
                headline: "Legendary {streak}-day streak.",
                body: "Anything you do today protects the chain."
            )
        }
    }

    // MARK: - Interpolation

    private static func interpolate(_ raw: String, fields: [String: String], booster: String?, streak: Int, debt: DebtKind, goal: GoalFamily, linkedQuestTitle: String? = nil) -> String {
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
    private static let catalog: [Key: RawTemplate] = [

        // ─── GREEN × MUSCLE GROUP ─────────────────────────────────
        Key(.green, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "Strain is fresh — {muscles} are {days} days overdue.",
            body: "{splitTitle} day in ~{eta} min wins your daily quest{booster}."
        ),
        Key(.green, .muscleGroup, .loseFat): RawTemplate(
            headline: "Recovery's green — {muscles} are {days} days overdue.",
            body: "Hit {splitTitle} hard for ~{eta} min, burn the deficit{booster}."
        ),
        Key(.green, .muscleGroup, .endurance): RawTemplate(
            headline: "Body's primed — {muscles} need a session.",
            body: "{splitTitle} circuit (~{eta} min) doubles as conditioning{booster}."
        ),
        Key(.green, .muscleGroup, .generalFitness): RawTemplate(
            headline: "You're recovered — {muscles} haven't been hit in {days} days.",
            body: "{splitTitle} day in ~{eta} min keeps you balanced{booster}."
        ),

        // ─── GREEN × NO WORKOUT YET ──────────────────────────────
        Key(.green, .noWorkoutYet, .buildMuscle): RawTemplate(
            headline: "Green light — and {days} days since your last lift.",
            body: "{eta}-min auto session locks today's quest{booster}."
        ),
        Key(.green, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "You're rested. {days} days off — time to move.",
            body: "Auto workout in ~{eta} min{booster}."
        ),

        // ─── GREEN × PROTEIN ─────────────────────────────────────
        Key(.green, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Recovery's prime, but you're {deficitG}g short on protein.",
            body: "Eat now to bank tonight's gains{booster}."
        ),
        Key(.green, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "{deficitG}g of protein left to hit your goal.",
            body: "A meal closes the gap{booster}."
        ),

        // ─── GREEN × HYDRATION ───────────────────────────────────
        Key(.green, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "You're {deficitL}L behind on water.",
            body: "Catch up before your next session{booster}."
        ),

        // ─── GREEN × STEPS ───────────────────────────────────────
        Key(.green, .stepsBehindGoal, .loseFat): RawTemplate(
            headline: "{gap} steps to go — and you're rested for it.",
            body: "Z2 walk closes the day{booster}."
        ),
        Key(.green, .stepsBehindGoal, .generalFitness): RawTemplate(
            headline: "{gap} steps left in your day.",
            body: "A short walk wraps it up{booster}."
        ),

        // ─── GREEN × STREAK RISK ─────────────────────────────────
        Key(.green, .streakRisk, .generalFitness): RawTemplate(
            headline: "{streak}-day streak — clock's ticking.",
            body: "{eta}-min full-body session protects the chain{booster}."
        ),

        // ─── YELLOW × MUSCLE GROUP ───────────────────────────────
        Key(.yellow, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "Recovery's mid — {muscles} could use a session.",
            body: "Keep the last rep in the tank. {splitTitle} in ~{eta} min{booster}."
        ),
        Key(.yellow, .muscleGroup, .loseFat): RawTemplate(
            headline: "Yellow band — {muscles} are {days} days overdue.",
            body: "Moderate {splitTitle} day (~{eta} min) without redlining{booster}."
        ),
        Key(.yellow, .muscleGroup, .generalFitness): RawTemplate(
            headline: "Steady day — {muscles} are due.",
            body: "Smart {splitTitle} session in ~{eta} min{booster}."
        ),

        // ─── YELLOW × NO WORKOUT YET ─────────────────────────────
        Key(.yellow, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "Steady recovery, {days} days since your last session.",
            body: "Easy {eta}-min routine fits the band{booster}."
        ),

        // ─── YELLOW × PROTEIN ────────────────────────────────────
        Key(.yellow, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Mid recovery + {deficitG}g protein short.",
            body: "Eat now and run a lighter session later{booster}."
        ),
        Key(.yellow, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "{deficitG}g of protein left.",
            body: "Refuel before your next move{booster}."
        ),

        // ─── YELLOW × HYDRATION ──────────────────────────────────
        Key(.yellow, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Yellow band and {deficitL}L behind on water.",
            body: "Hydration is the cheapest readiness boost{booster}."
        ),

        // ─── YELLOW × STEPS ──────────────────────────────────────
        Key(.yellow, .stepsBehindGoal, .loseFat): RawTemplate(
            headline: "{gap} steps to go — Z2 fits your band.",
            body: "Easy walk burns the deficit without redlining{booster}."
        ),

        // ─── RED × RECOVERY NEEDED ───────────────────────────────
        Key(.red, .recoveryNeeded, .buildMuscle): RawTemplate(
            headline: "Red recovery. Your nervous system needs the day.",
            body: "Mobility or yoga only — heavy lifts wait until tomorrow{booster}."
        ),
        Key(.red, .recoveryNeeded, .loseFat): RawTemplate(
            headline: "Red recovery. Save the burn for tomorrow.",
            body: "30-min walk + hydration is the play{booster}."
        ),
        Key(.red, .recoveryNeeded, .endurance): RawTemplate(
            headline: "Red day — capacity is low.",
            body: "Easy spin or recovery walk. Don't bank fatigue{booster}."
        ),
        Key(.red, .recoveryNeeded, .generalFitness): RawTemplate(
            headline: "Red recovery — body's tapped.",
            body: "Stretch, hydrate, sleep early{booster}."
        ),

        // ─── RED × PROTEIN (still actionable) ────────────────────
        Key(.red, .proteinDeficit, .buildMuscle): RawTemplate(
            headline: "Red day — still {deficitG}g protein short.",
            body: "Skip the lift, eat the protein. Recovery wins{booster}."
        ),

        // ─── RED × HYDRATION ─────────────────────────────────────
        Key(.red, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "Red day with {deficitL}L water deficit.",
            body: "Rehydrate first; rest is non-negotiable{booster}."
        ),

        // ─── UNKNOWN (no wearable) — never cite recovery ─────────
        Key(.unknown, .muscleGroup, .buildMuscle): RawTemplate(
            headline: "{muscles} are {days} days overdue.",
            body: "{splitTitle} day in ~{eta} min wins your daily quest{booster}."
        ),
        Key(.unknown, .muscleGroup, .loseFat): RawTemplate(
            headline: "{muscles} are {days} days overdue.",
            body: "Hit {splitTitle} hard (~{eta} min) — burn the deficit{booster}."
        ),
        Key(.unknown, .muscleGroup, .generalFitness): RawTemplate(
            headline: "{muscles} haven't seen a session in {days} days.",
            body: "{splitTitle} day in ~{eta} min{booster}."
        ),
        Key(.unknown, .noWorkoutYet, .generalFitness): RawTemplate(
            headline: "{days} days since your last workout.",
            body: "Auto session in ~{eta} min{booster}."
        ),
        Key(.unknown, .proteinDeficit, .generalFitness): RawTemplate(
            headline: "{deficitG}g of protein left.",
            body: "A meal closes the gap{booster}."
        ),
        Key(.unknown, .hydrationDeficit, .generalFitness): RawTemplate(
            headline: "{deficitL}L water behind pace.",
            body: "Catch up before your next move{booster}."
        ),
        Key(.unknown, .stepsBehindGoal, .generalFitness): RawTemplate(
            headline: "{gap} steps left today.",
            body: "Walk it out{booster}."
        ),
        Key(.unknown, .streakRisk, .generalFitness): RawTemplate(
            headline: "{streak}-day streak — clock's ticking.",
            body: "{eta}-min session protects the chain{booster}."
        ),
    ]
}
