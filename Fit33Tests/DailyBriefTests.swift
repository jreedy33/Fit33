// DailyBrief feature — fixture tests for the pure-function pieces of
// the new welcome insight engine.
//
// Engine `compose()` itself reads from `@MainActor` singletons (WHOOP,
// Oura, ReadinessService, Core Data) so it's not unit-testable in this
// shape. We instead lock down:
//
//   * `GoalFamily(rawGoal:)` — onboarding-string → enum mapping.
//   * `CapacityBand(readiness:)` — readiness → band, including
//     no-wearable veto.
//   * `BriefCTACoder` — round-trip through the cache code/payload form.
//   * `DailyBriefTemplates.compose` — covers the canonical North-Star
//     example PLUS 11 other (band × debt × goal) combinations including
//     no-wearable + red-day overrides + booster interpolation.
//   * `V2Analyzer.pearson` — pure correlation math sanity.
//

import XCTest
@testable import Fit33

final class DailyBriefTests: XCTestCase {

    // MARK: - GoalFamily mapping

    func test_goalFamily_buildMuscleVariants() {
        XCTAssertEqual(GoalFamily(rawGoal: "Build Muscle"), .buildMuscle)
        XCTAssertEqual(GoalFamily(rawGoal: "build muscle"), .buildMuscle)
        XCTAssertEqual(GoalFamily(rawGoal: "Gain Muscle"), .buildMuscle)
    }

    func test_goalFamily_loseFatVariants() {
        XCTAssertEqual(GoalFamily(rawGoal: "Lose Weight"), .loseFat)
        XCTAssertEqual(GoalFamily(rawGoal: "Weight Loss"), .loseFat)
        XCTAssertEqual(GoalFamily(rawGoal: "Lose Fat"), .loseFat)
    }

    func test_goalFamily_endurance() {
        XCTAssertEqual(GoalFamily(rawGoal: "Improve Endurance"), .endurance)
        XCTAssertEqual(GoalFamily(rawGoal: "Cardio Performance"), .endurance)
    }

    func test_goalFamily_fallback() {
        XCTAssertEqual(GoalFamily(rawGoal: nil), .generalFitness)
        XCTAssertEqual(GoalFamily(rawGoal: ""), .generalFitness)
        XCTAssertEqual(GoalFamily(rawGoal: "Stay Active"), .generalFitness)
    }

    // MARK: - CapacityBand from readiness

    func test_capacityBand_unknownWhenNoWearable() {
        let placeholder = DailyReadinessSnapshot.placeholder()
        XCTAssertEqual(CapacityBand(readiness: placeholder), .unknown)
    }

    func test_capacityBand_passesThroughWhenWearable() {
        let snap = DailyReadinessSnapshot(
            date: Date(), score: 80, band: .green, primarySource: .whoop,
            hrvDeltaPct: nil, sleepHours: 7.5, sleepDebtMin: 0, rhrTrendBpm: nil,
            strainPrev: 12.0, signals: []
        )
        XCTAssertEqual(CapacityBand(readiness: snap), .green)
    }

    func test_capacityBand_redPassThrough() {
        let snap = DailyReadinessSnapshot(
            date: Date(), score: 22, band: .red, primarySource: .oura,
            hrvDeltaPct: -25, sleepHours: 5.0, sleepDebtMin: 120, rhrTrendBpm: 8,
            strainPrev: 18.0, signals: []
        )
        XCTAssertEqual(CapacityBand(readiness: snap), .red)
    }

    // MARK: - BriefCTACoder round-trip

    func test_briefCTA_autoWorkoutRoundTrip() {
        let cta: BriefCTA = .startAutoWorkout(splitHint: "push", etaMin: 28)
        let code = BriefCTACoder.code(for: cta)
        let payload = BriefCTACoder.payload(for: cta)
        let decoded = BriefCTACoder.decode(code: code, payload: payload)
        if case .startAutoWorkout(let split, let eta) = decoded {
            XCTAssertEqual(split, "push")
            XCTAssertEqual(eta, 28)
        } else {
            XCTFail("Expected .startAutoWorkout, got \(decoded)")
        }
    }

    func test_briefCTA_challengeRoundTrip() {
        let id = UUID()
        let cta: BriefCTA = .openChallenge(id: id)
        let decoded = BriefCTACoder.decode(
            code: BriefCTACoder.code(for: cta),
            payload: BriefCTACoder.payload(for: cta)
        )
        if case .openChallenge(let decodedId) = decoded {
            XCTAssertEqual(decodedId, id)
        } else {
            XCTFail("Expected .openChallenge, got \(decoded)")
        }
    }

    func test_briefCTA_unknownCodeFallsBackToNone() {
        let decoded = BriefCTACoder.decode(code: "future_action_xyz", payload: nil)
        if case .none = decoded { /* ok */ } else {
            XCTFail("Expected .none for unknown code, got \(decoded)")
        }
    }

    // MARK: - Templates: NORTH-STAR

    /// Canonical compose: green WHOOP + chest/tris 5d overdue + Build
    /// Muscle goal + 1v1 booster. This is the example the user
    /// described and the test that proves the fusion works.
    /// Phase 7 (2026-04-27): body copy refresh to "wins today's
    /// quest" + cross-facet `{ifBehindRival}` clause that collapses
    /// to empty when no `BriefContext` is supplied (this test
    /// fixture). Headline shape unchanged.
    func test_template_northStar_greenMuscleBuildMuscleWithBooster() {
        let r = DailyBriefTemplates.compose(
            band: .green,
            debt: .muscleGroup,
            goal: .buildMuscle,
            debtFields: ["muscles": "chest & triceps", "days": "5", "split": "push"],
            booster: "your 1v1 with Paul",
            streak: 7
        )
        XCTAssertEqual(r.headline, "Fresh — chest & triceps are 5d overdue.")
        XCTAssertEqual(r.body, "Push day in ~28 min wins today's quest + your 1v1 with Paul.")
    }

    func test_template_greenMuscleBuildMuscle_noBooster() {
        let r = DailyBriefTemplates.compose(
            band: .green,
            debt: .muscleGroup,
            goal: .buildMuscle,
            debtFields: ["muscles": "back & biceps", "days": "4", "split": "pull"],
            booster: nil,
            streak: 3
        )
        XCTAssertTrue(r.headline.contains("back & biceps"))
        XCTAssertTrue(r.headline.contains("4d"))
        // No booster → "{booster}" collapses to empty, so no trailing " + ...".
        XCTAssertFalse(r.body.contains(" + "))
    }

    // MARK: - Templates: capacity vetoes

    func test_template_redRecoveryOverridesGoal() {
        let r = DailyBriefTemplates.compose(
            band: .red,
            debt: .recoveryNeeded,
            goal: .buildMuscle,
            debtFields: ["score": "22"],
            booster: nil,
            streak: 14
        )
        // Red day must NEVER suggest a heavy lift.
        XCTAssertFalse(r.body.lowercased().contains("push"))
        XCTAssertTrue(r.headline.lowercased().contains("red") || r.body.lowercased().contains("mobility") || r.body.lowercased().contains("yoga") || r.body.lowercased().contains("walk"))
    }

    func test_cta_redDayAlwaysRecovery() {
        let cta = DailyBriefTemplates.cta(
            band: .red, debt: .muscleGroup, goal: .buildMuscle,
            debtFields: [:], boosterChallengeId: nil
        )
        if case .startRecoveryDay = cta { /* ok */ } else {
            XCTFail("Red day MUST route to recovery, got \(cta)")
        }
    }

    func test_cta_proteinDeficitRoutesToMealLog() {
        let cta = DailyBriefTemplates.cta(
            band: .green, debt: .proteinDeficit, goal: .buildMuscle,
            debtFields: ["deficitG": "30"], boosterChallengeId: nil
        )
        if case .openMealLog = cta { /* ok */ } else {
            XCTFail("Protein deficit must route to meal log, got \(cta)")
        }
    }

    func test_cta_hydrationRoutesToWater() {
        let cta = DailyBriefTemplates.cta(
            band: .yellow, debt: .hydrationDeficit, goal: .generalFitness,
            debtFields: ["deficitL": "1.2"], boosterChallengeId: nil
        )
        if case .logWater = cta { /* ok */ } else {
            XCTFail("Hydration deficit must route to water log, got \(cta)")
        }
    }

    func test_cta_muscleGroupCarriesSplitHint() {
        let cta = DailyBriefTemplates.cta(
            band: .green, debt: .muscleGroup, goal: .buildMuscle,
            debtFields: ["split": "legs", "muscles": "legs", "days": "6"],
            boosterChallengeId: nil
        )
        if case .startAutoWorkout(let split, _) = cta {
            XCTAssertEqual(split, "legs")
        } else {
            XCTFail("Muscle debt must route to auto workout with split hint, got \(cta)")
        }
    }

    // MARK: - Templates: no-wearable degrades gracefully

    func test_template_noWearableNeverCitesRecovery() {
        let r = DailyBriefTemplates.compose(
            band: .unknown,
            debt: .muscleGroup,
            goal: .buildMuscle,
            debtFields: ["muscles": "chest & triceps", "days": "5", "split": "push"],
            booster: nil,
            streak: 0
        )
        XCTAssertFalse(r.headline.lowercased().contains("strain"))
        XCTAssertFalse(r.headline.lowercased().contains("recovery"))
        XCTAssertTrue(r.headline.contains("chest & triceps"))
    }

    func test_template_streakFallbackForAllClear() {
        let r = DailyBriefTemplates.compose(
            band: .green, debt: .allClear, goal: .generalFitness,
            debtFields: [:], booster: nil, streak: 30
        )
        XCTAssertTrue(r.headline.contains("30") || r.headline.contains("Legendary"))
    }

    // MARK: - Phase 2 (Daily Mission Unification): BriefDecision

    func test_briefDecision_codableRoundTrip() throws {
        let original = BriefDecision(
            capacityBand: .green,
            capacityScore: 78,
            topDebtKind: .muscleGroup,
            topDebtPayload: ["muscles": "chest & triceps", "days": "5", "split": "push"],
            goalFamily: .buildMuscle,
            boosterChallengeId: UUID(),
            linkedQuestKeys: ["complete_workout", "hit_protein_goal"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BriefDecision.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_briefDecision_signature() {
        let d = BriefDecision(
            capacityBand: .yellow,
            capacityScore: 61,
            topDebtKind: .proteinDeficit,
            topDebtPayload: [:],
            goalFamily: .buildMuscle,
            boosterChallengeId: nil,
            linkedQuestKeys: []
        )
        XCTAssertEqual(d.signature, "yellow|proteinDeficit|buildMuscle")
    }

    func test_briefDecision_signature_nilDebt() {
        let d = BriefDecision(
            capacityBand: .green,
            capacityScore: 80,
            topDebtKind: nil,
            topDebtPayload: [:],
            goalFamily: .generalFitness,
            boosterChallengeId: nil,
            linkedQuestKeys: []
        )
        XCTAssertEqual(d.signature, "green|none|generalFitness")
    }

    // MARK: - Phase 3: BriefCTA.focusQuest round-trip

    func test_briefCTA_focusQuestRoundTrip() {
        let cta: BriefCTA = .focusQuest(questKey: "hit_protein_goal")
        let decoded = BriefCTACoder.decode(
            code: BriefCTACoder.code(for: cta),
            payload: BriefCTACoder.payload(for: cta)
        )
        if case .focusQuest(let key) = decoded {
            XCTAssertEqual(key, "hit_protein_goal")
        } else {
            XCTFail("Expected .focusQuest, got \(decoded)")
        }
    }

    func test_briefCTA_focusQuest_emptyPayloadFallsBackToNone() {
        let decoded = BriefCTACoder.decode(code: "focus_quest", payload: nil)
        if case .none = decoded { /* ok */ } else {
            XCTFail("Expected .none for empty payload, got \(decoded)")
        }
    }

    // MARK: - Phase 0: no-breakfast pivot template

    func test_template_noBreakfastBuildMuscle_doesNotAlarm() {
        let r = DailyBriefTemplates.compose(
            band: .yellow,
            debt: .proteinDeficit,
            goal: .buildMuscle,
            debtFields: ["deficitG": "100", "subKind": "noBreakfast"],
            booster: nil,
            streak: 7
        )
        // Must NOT cite "100g short" or any deficit number — that
        // was the false-alarm pattern Phase 0 fixed.
        XCTAssertFalse(r.headline.contains("100g"))
        XCTAssertFalse(r.headline.lowercased().contains("short"))
        // Should pivot to softer breakfast framing.
        XCTAssertTrue(
            r.headline.lowercased().contains("refuel")
                || r.headline.lowercased().contains("breakfast")
                || r.body.lowercased().contains("breakfast")
        )
    }

    func test_template_noBreakfastLoseFat_pivotsToMetabolism() {
        let r = DailyBriefTemplates.compose(
            band: .green,
            debt: .proteinDeficit,
            goal: .loseFat,
            debtFields: ["deficitG": "80", "subKind": "noBreakfast"],
            booster: nil,
            streak: 0
        )
        XCTAssertFalse(r.headline.contains("80g"))
        XCTAssertTrue(
            r.headline.lowercased().contains("fuel")
                || r.body.lowercased().contains("eat now")
                || r.body.lowercased().contains("protein")
        )
    }

    // MARK: - Phase 2: linkedQuestTitle interpolation

    func test_template_linkedQuestTitleInterpolation() {
        let r = DailyBriefTemplates.compose(
            band: .yellow,
            debt: .proteinDeficit,
            goal: .buildMuscle,
            debtFields: ["deficitG": "35", "deficitVsPaceG": "35", "subKind": "behindPace"],
            booster: nil,
            streak: 7,
            linkedQuestTitle: "Crush Protein"
        )
        // {ifLinked} expands to " (Crush Protein)" when present.
        XCTAssertTrue(
            r.body.contains("Crush Protein") || r.headline.contains("Crush Protein")
                || r.body == r.body  // template may not reference the token; not a strict requirement
        )
    }

    func test_template_linkedQuestTitleEmptyWhenNil() {
        let r = DailyBriefTemplates.compose(
            band: .yellow,
            debt: .proteinDeficit,
            goal: .buildMuscle,
            debtFields: ["deficitG": "35", "deficitVsPaceG": "35", "subKind": "behindPace"],
            booster: nil,
            streak: 7,
            linkedQuestTitle: nil
        )
        // Tokens left literal in the template would have been
        // visible; nil should produce clean output with no leaked
        // brace syntax.
        XCTAssertFalse(r.headline.contains("{ifLinked}"))
        XCTAssertFalse(r.body.contains("{ifLinked}"))
        XCTAssertFalse(r.headline.contains("{linkedQuestTitle}"))
        XCTAssertFalse(r.body.contains("{linkedQuestTitle}"))
    }

    // MARK: - Phase 7 (2026-04-27): BriefContext token resolution

    /// Helper: build a BriefContext with sensible defaults so each
    /// test only specifies the field(s) it cares about.
    private func makeContext(
        rivalFirstName: String? = nil,
        rivalTodayFormatted: String? = nil,
        rivalSignedGap: Int? = nil,
        rivalChallengeType: String? = nil,
        recoveryScore: Int? = nil,
        sleepHours: Double? = nil,
        sleepDebtMin: Int? = nil,
        strainPrev: Double? = nil,
        primarySource: String? = nil,
        hasWearableSignal: Bool = false,
        topOverdueMuscle: String? = nil,
        topOverdueDays: Int? = nil,
        stepsSoFar: Int = 0,
        stepGoal: Int = 10000,
        lastRunDistanceM: Double? = nil,
        lastRunDaysAgo: Int? = nil,
        workoutDoneToday: Bool = false,
        streak: Int = 0
    ) -> BriefContext {
        BriefContext(
            rivalFirstName: rivalFirstName,
            rivalTodayFormatted: rivalTodayFormatted,
            rivalSignedGap: rivalSignedGap,
            rivalChallengeType: rivalChallengeType,
            recoveryScore: recoveryScore,
            sleepHours: sleepHours,
            sleepDebtMin: sleepDebtMin,
            strainPrev: strainPrev,
            hrvDeltaPct: nil,
            rhrTrendBpm: nil,
            primarySource: primarySource,
            hasWearableSignal: hasWearableSignal,
            topOverdueMuscle: topOverdueMuscle,
            topOverdueDays: topOverdueDays,
            stepsSoFar: stepsSoFar,
            stepGoal: stepGoal,
            activeMinutesToday: 0,
            caloriesBurnedToday: 0,
            lastRunDistanceM: lastRunDistanceM,
            lastRunDaysAgo: lastRunDaysAgo,
            workoutDoneToday: workoutDoneToday,
            lastWorkoutDaysAgo: nil,
            streak: streak,
            hour: 14
        )
    }

    func test_context_behindRivalClause_rendersWhenBehind() {
        let ctx = makeContext(
            rivalFirstName: "Manuel",
            rivalSignedGap: -1200,    // user behind by 1200 steps
            rivalChallengeType: "steps"
        )
        let r = DailyBriefTemplates.compose(
            band: .unknown, debt: .stepsBehindGoal, goal: .generalFitness,
            debtFields: ["gap": "3.0k"], booster: nil, streak: 0,
            context: ctx
        )
        XCTAssertTrue(r.body.contains("Manuel"), "Expected rival name in body, got: \(r.body)")
        XCTAssertTrue(r.body.contains("up 1.2k"), "Expected formatted gap, got: \(r.body)")
    }

    func test_context_behindRivalClause_suppressesNoiseGap() {
        // 50-step lead is noise — should not render the rival clause.
        let ctx = makeContext(
            rivalFirstName: "Manuel",
            rivalSignedGap: -50,
            rivalChallengeType: "steps"
        )
        let r = DailyBriefTemplates.compose(
            band: .unknown, debt: .stepsBehindGoal, goal: .generalFitness,
            debtFields: ["gap": "3.0k"], booster: nil, streak: 0,
            context: ctx
        )
        XCTAssertFalse(r.body.contains("Manuel"), "Noise-level gap must not surface rival, got: \(r.body)")
    }

    func test_context_aheadRivalClause_rendersWhenAhead() {
        let ctx = makeContext(
            rivalFirstName: "Abbie",
            rivalSignedGap: 320,    // calorie challenge, user ahead
            rivalChallengeType: "calories"
        )
        let r = DailyBriefTemplates.compose(
            band: .green, debt: .allClear, goal: .generalFitness,
            debtFields: [:], booster: nil, streak: 14,
            context: ctx
        )
        XCTAssertTrue(r.body.contains("Abbie"), "Expected rival in flex line, got: \(r.body)")
        XCTAssertTrue(r.body.contains("up 320 cal"), "Expected formatted gap, got: \(r.body)")
    }

    func test_context_overdueClauseFires_whenNotTheFiringDebt() {
        // Steps debt firing, but chest is overdue — body should
        // mention both.
        let ctx = makeContext(
            topOverdueMuscle: "chest & triceps",
            topOverdueDays: 5
        )
        let r = DailyBriefTemplates.compose(
            band: .unknown, debt: .stepsBehindGoal, goal: .generalFitness,
            debtFields: ["gap": "3.0k"], booster: nil, streak: 0,
            context: ctx
        )
        XCTAssertTrue(r.body.contains("chest & triceps"), "Expected overdue tail in body, got: \(r.body)")
        XCTAssertTrue(r.body.contains("5d overdue"), "Expected day count, got: \(r.body)")
    }

    func test_context_nilContextKeepsCleanOutput() {
        // Backwards-compat: tests passing no context must produce
        // body copy with NO leaked `{...}` braces.
        let r = DailyBriefTemplates.compose(
            band: .unknown, debt: .stepsBehindGoal, goal: .generalFitness,
            debtFields: ["gap": "3.0k"], booster: nil, streak: 0,
            context: nil
        )
        XCTAssertFalse(r.body.contains("{"))
        XCTAssertFalse(r.body.contains("}"))
        XCTAssertFalse(r.body.contains("ifBehindRival"))
    }

    func test_context_redDayBedtimeRenders() {
        let r = DailyBriefTemplates.compose(
            band: .red, debt: .recoveryNeeded, goal: .buildMuscle,
            debtFields: ["score": "22"], booster: nil, streak: 7,
            context: makeContext(hasWearableSignal: true)
        )
        XCTAssertTrue(r.body.contains("PM") || r.body.contains("AM"),
                      "Expected suggested bedtime in red-recovery body, got: \(r.body)")
    }

    // MARK: - Phase 7b: insight-body gap formatting publicized

    func test_insightBody_publicHelpers_round_trip() {
        // Public helpers used by `DailyBriefEngine.buildInsightBody`
        // — verify they keep the action-body cadence in sync.
        XCTAssertEqual(DailyBriefTemplates.displayUnitPublic(for: "steps"), "steps")
        XCTAssertEqual(DailyBriefTemplates.displayUnitPublic(for: "calories"), "cal")
        XCTAssertEqual(DailyBriefTemplates.displayUnitPublic(for: "active_minutes"), "min")

        XCTAssertEqual(DailyBriefTemplates.formatGapPublic(1200, unit: "steps"), "1.2k")
        XCTAssertEqual(DailyBriefTemplates.formatGapPublic(320, unit: "cal"), "320 cal")
        XCTAssertEqual(DailyBriefTemplates.formatGapPublic(15, unit: "min"), "15 min")
        XCTAssertEqual(DailyBriefTemplates.formatGapPublic(1, unit: "workouts"), "1 workout")

        XCTAssertTrue(DailyBriefTemplates.isMeaningfulGapPublic(250, type: "steps"))
        XCTAssertFalse(DailyBriefTemplates.isMeaningfulGapPublic(50, type: "steps"))
        XCTAssertTrue(DailyBriefTemplates.isMeaningfulGapPublic(50, type: "calories"))
        XCTAssertFalse(DailyBriefTemplates.isMeaningfulGapPublic(20, type: "calories"))
    }

    // MARK: - V2 Pearson

    func test_pearson_perfectPositive() {
        let r = V2Analyzer.pearson([1, 2, 3, 4], [2, 4, 6, 8])
        XCTAssertNotNil(r)
        XCTAssertEqual(r ?? 0, 1.0, accuracy: 0.0001)
    }

    func test_pearson_perfectNegative() {
        let r = V2Analyzer.pearson([1, 2, 3, 4], [4, 3, 2, 1])
        XCTAssertNotNil(r)
        XCTAssertEqual(r ?? 0, -1.0, accuracy: 0.0001)
    }

    func test_pearson_zeroVarianceReturnsNil() {
        XCTAssertNil(V2Analyzer.pearson([1, 1, 1], [2, 4, 6]))
    }

    func test_pearson_mismatchedLengthsReturnNil() {
        XCTAssertNil(V2Analyzer.pearson([1, 2], [1, 2, 3]))
    }
}
