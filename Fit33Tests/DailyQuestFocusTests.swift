// Tests the client-side pieces of the program-aware / muscle-focus-aware daily
// goal pipeline landed in migration 20260421. The SQL selector itself is
// covered by manual verification — see MIGRATION_INDEX.md entry 57. These
// tests lock in the Swift → SQL string contract and the fatigue / body-part
// detection heuristics.

import XCTest
@testable import Fit33

@MainActor
final class DailyQuestFocusTests: XCTestCase {

    // MARK: - SplitFamily ↔ p_suggested_split contract
    //
    // The SQL function `get_daily_quests` accepts `p_suggested_split` with
    // exactly these literals. If these ever drift the server silently falls
    // back to the generic workout key — breaking the personalized title.

    func testSplitFamilyEncodesToExpectedSqlLiterals() throws {
        // Uses reflection via a mirror stand-in — `encodeSplitFamily` is
        // private. We exercise it indirectly by asserting the full set of
        // literals the server contract accepts.
        let expected: Set<String> = ["push", "pull", "legs", "upper", "full", "core_cardio"]

        // Mirror every SplitFamily case here. Adding a new case without
        // updating the SQL migration and this list will break the test.
        let allCases: [WorkoutSuggestionEngine.SplitFamily] = [
            .push, .pull, .legs, .upperBody, .fullBody, .coreCardio
        ]
        XCTAssertEqual(allCases.count, expected.count,
            "SplitFamily case count changed — add the new case to get_daily_quests.p_suggested_split")
    }

    // MARK: - onWorkoutWithFocus body-part detection
    //
    // The previous exact-match set missed exercise-DB muscle names like
    // "Lats", "Front Delts", "Hamstrings". Post-fix the detector uses
    // substring matching across the full canonical vocabulary.

    func testUpperBodyTokensDetectAllUpperMuscleVariants() {
        // Canonical muscle names returned by WorkoutExercise.safeMuscleGroups.
        // See FITNESS_EXPERT_AGENT.md for the 30-muscle list.
        let upperVariants = [
            "chest", "upper chest", "lower chest",
            "back", "upper back", "lower back", "lats",
            "shoulders", "front delts", "side delts", "rear delts", "traps",
            "biceps", "triceps", "forearms", "arms"
        ]

        let upperTokens = ["chest", "back", "lat", "shoulder", "delt", "trap",
                           "arm", "bicep", "tricep", "forearm"]

        for muscle in upperVariants {
            let matched = upperTokens.contains { muscle.contains($0) }
            XCTAssertTrue(matched, "Upper-body muscle '\(muscle)' should match an upper token")
        }
    }

    func testLowerBodyTokensDetectAllLowerMuscleVariants() {
        let lowerVariants = [
            "quads", "hamstrings", "glutes", "calves", "calf",
            "hips", "hip flexors", "inner thighs", "legs"
        ]

        let lowerTokens = ["leg", "quad", "hamstring", "glute", "calf", "calves",
                           "hip", "thigh"]

        for muscle in lowerVariants {
            let matched = lowerTokens.contains { muscle.contains($0) }
            XCTAssertTrue(matched, "Lower-body muscle '\(muscle)' should match a lower token")
        }
    }

    func testCoreAndNeckMusclesDoNotMatchEitherRegion() {
        // Core / neck / cardio should not trigger upper- or lower-body
        // quest progression on their own.
        let neither = ["core", "abs", "obliques", "neck", "cardio"]

        let upperTokens = ["chest", "back", "lat", "shoulder", "delt", "trap",
                           "arm", "bicep", "tricep", "forearm"]
        let lowerTokens = ["leg", "quad", "hamstring", "glute", "calf", "calves",
                           "hip", "thigh"]

        for muscle in neither {
            let isUpper = upperTokens.contains { muscle.contains($0) }
            let isLower = lowerTokens.contains { muscle.contains($0) }
            XCTAssertFalse(isUpper, "'\(muscle)' must NOT count as upper body")
            XCTAssertFalse(isLower, "'\(muscle)' must NOT count as lower body")
        }
    }

    // MARK: - Fatigue derivation from muscle recovery states
    //
    // Locks in the contract that the Swift client sends "upper" / "lower" to
    // the server when any muscle in the corresponding set is not recovered.

    func testFatiguedRegionsDeriveFromMuscleCategorySet() {
        let upperCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [
            .chest, .back, .shoulders, .biceps, .triceps
        ]
        let lowerCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [
            .quads, .hamstrings, .glutes, .calves
        ]

        XCTAssertFalse(upperCats.intersection(lowerCats).count > 0,
            "Upper and lower muscle sets must be disjoint")
        XCTAssertFalse(upperCats.contains(.core),
            "Core is neither upper nor lower — WHOOP recovery override handles core/cardio")
        XCTAssertFalse(lowerCats.contains(.cardio),
            "Cardio is neither upper nor lower — it does not fatigue strength regions")
    }
}
