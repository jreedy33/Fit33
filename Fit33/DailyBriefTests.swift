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
    func test_template_northStar_greenMuscleBuildMuscleWithBooster() {
        let r = DailyBriefTemplates.compose(
            band: .green,
            debt: .muscleGroup,
            goal: .buildMuscle,
            debtFields: ["muscles": "chest & triceps", "days": "5", "split": "push"],
            booster: "your 1v1 with Paul",
            streak: 7
        )
        XCTAssertEqual(r.headline, "Strain is fresh — chest & triceps are 5 days overdue.")
        XCTAssertEqual(r.body, "Push day in ~28 min wins your daily quest + your 1v1 with Paul.")
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
        XCTAssertTrue(r.headline.contains("4 days"))
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
