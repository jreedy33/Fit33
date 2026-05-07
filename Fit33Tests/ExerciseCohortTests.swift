import XCTest
@testable import Fit33

/// Unit tests for the equipment-cohort taxonomy that powers
/// `ExerciseSwapService` cohort biasing.
///
/// Background: per Fitness Expert ruling 2026-05-04, swap suggestions
/// must respect the source's stability/feel cohort. A user picking
/// `Bicep Curl (Machine)` is opting into low stabilizer demand; surfacing
/// `Bicep Curl (Barbell)` as the top swap violates that intent.
///
/// These tests pin the cohort assignments + closeness ladder so future
/// refactors can't silently regress the bug the user reported (three
/// barbell suggestions for a machine source).
final class ExerciseCohortTests: XCTestCase {

    // MARK: - Cohort Assignment

    func testStableGuidedCohortMembers() {
        let stableGuided: [String] = ["machine", "cable", "smith_machine"]
        for category in stableGuided {
            XCTAssertEqual(
                ExerciseFilterService.equipmentCohort(forCategory: category),
                .stableGuided,
                "\(category) should be Stable/Guided cohort"
            )
        }
    }

    func testFreeWeightCohortMembers() {
        let freeWeight: [String] = [
            "barbell", "dumbbell", "ez_bar",
            "kettlebell", "plate", "medicine_ball",
        ]
        for category in freeWeight {
            XCTAssertEqual(
                ExerciseFilterService.equipmentCohort(forCategory: category),
                .freeWeight,
                "\(category) should be Free Weight cohort"
            )
        }
    }

    func testBodyweightElasticCohortMembers() {
        let bodyweightElastic: [String] = [
            "bodyweight", "band", "trx",
            "gymnastic_rings", "pull_up_bar", "stability_ball",
        ]
        for category in bodyweightElastic {
            XCTAssertEqual(
                ExerciseFilterService.equipmentCohort(forCategory: category),
                .bodyweightElastic,
                "\(category) should be Bodyweight/Elastic cohort"
            )
        }
    }

    func testFoamRollerIsRecoveryNotSwapTarget() {
        XCTAssertEqual(
            ExerciseFilterService.equipmentCohort(forCategory: "foam_roller"),
            .recovery,
            "foam_roller is recovery-only — never a swap target"
        )
    }

    func testUnknownAndEmptyCategoriesReturnUnknown() {
        XCTAssertEqual(ExerciseFilterService.equipmentCohort(forCategory: nil), .unknown)
        XCTAssertEqual(ExerciseFilterService.equipmentCohort(forCategory: ""), .unknown)
        XCTAssertEqual(ExerciseFilterService.equipmentCohort(forCategory: "asdf"), .unknown)
    }

    func testUserDisplayCategoryAliasesResolveToCohorts() {
        // ExerciseSwapService callers may pass either snake_case raw values
        // or user-display strings ("Machines", "Cables", etc.). Both must
        // resolve to the same cohort.
        XCTAssertEqual(
            ExerciseFilterService.equipmentCohort(forCategory: "Machines"),
            .stableGuided
        )
        XCTAssertEqual(
            ExerciseFilterService.equipmentCohort(forCategory: "Cables"),
            .stableGuided
        )
        XCTAssertEqual(
            ExerciseFilterService.equipmentCohort(forCategory: "Dumbbells"),
            .freeWeight
        )
        XCTAssertEqual(
            ExerciseFilterService.equipmentCohort(forCategory: "Bodyweight"),
            .bodyweightElastic
        )
    }

    // MARK: - Cohort Closeness Ladder

    func testSameCohortClosenessIsMax() {
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.stableGuided, .stableGuided),
            100
        )
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.freeWeight, .freeWeight),
            100
        )
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.bodyweightElastic, .bodyweightElastic),
            100
        )
    }

    func testStableToFreeWeightIsAdjacent() {
        // Cable ↔ Dumbbell, Machine ↔ Barbell — adjacent feel, not nearly
        // as similar as cable↔machine but acceptable as a fallback.
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.stableGuided, .freeWeight),
            70
        )
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.freeWeight, .stableGuided),
            70,
            "Closeness must be symmetric"
        )
    }

    func testFreeWeightToBodyweightElasticIsAdjacent() {
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.freeWeight, .bodyweightElastic),
            60
        )
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.bodyweightElastic, .freeWeight),
            60,
            "Closeness must be symmetric"
        )
    }

    func testStableToBodyweightIsFarthest() {
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.stableGuided, .bodyweightElastic),
            50
        )
    }

    func testRecoveryAndUnknownReturnZeroCloseness() {
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.recovery, .freeWeight),
            0,
            "Recovery is never a swap target — closeness 0 against any strength cohort"
        )
        XCTAssertEqual(
            ExerciseFilterService.cohortCloseness(.unknown, .stableGuided),
            0,
            "Unknown source/candidate must not earn any cohort bonus"
        )
    }

    // MARK: - Regression Guard

    /// The literal bug the user reported: Bicep Curl (Machine) source
    /// surfacing three Barbell suggestions. The cohort closeness for
    /// (Machine source → Barbell candidate) MUST be lower than
    /// (Machine source → Cable candidate), so the cohort bias breaks the
    /// barbell-priority tie.
    func testMachineSourcePrefersCableOverBarbell() {
        let sourceCohort = ExerciseFilterService.equipmentCohort(forCategory: "machine")
        let cableCohort = ExerciseFilterService.equipmentCohort(forCategory: "cable")
        let barbellCohort = ExerciseFilterService.equipmentCohort(forCategory: "barbell")

        let cableScore = ExerciseFilterService.cohortCloseness(sourceCohort, cableCohort)
        let barbellScore = ExerciseFilterService.cohortCloseness(sourceCohort, barbellCohort)

        XCTAssertGreaterThan(
            cableScore, barbellScore,
            "Machine source must rank Cable variants above Barbell variants — this is the user-reported bug"
        )
    }

    /// Same regression guard, mirrored — Cable source should prefer Machine
    /// over Dumbbell (both Cable→Machine and Cable→Dumbbell are valid, but
    /// Cable→Machine is closer-feel for the joint-friendly cohort).
    func testCableSourcePrefersMachineOverDumbbell() {
        let sourceCohort = ExerciseFilterService.equipmentCohort(forCategory: "cable")
        let machineCohort = ExerciseFilterService.equipmentCohort(forCategory: "machine")
        let dumbbellCohort = ExerciseFilterService.equipmentCohort(forCategory: "dumbbell")

        let machineScore = ExerciseFilterService.cohortCloseness(sourceCohort, machineCohort)
        let dumbbellScore = ExerciseFilterService.cohortCloseness(sourceCohort, dumbbellCohort)

        XCTAssertGreaterThan(machineScore, dumbbellScore)
    }
}
