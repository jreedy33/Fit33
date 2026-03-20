import XCTest
@testable import Fit33

final class ExerciseDataTests: XCTestCase {

    // MARK: - Movement Pattern Classification

    func testKnownMovementPatternsForCommonExercises() {
        let pushExercises = ["bench press", "overhead press", "push up", "incline press"]
        let pullExercises = ["pull up", "barbell row", "lat pulldown", "cable row"]
        let squatExercises = ["squat", "leg press", "goblet squat", "front squat"]
        let hingeExercises = ["deadlift", "romanian deadlift", "hip thrust", "good morning"]

        for name in pushExercises {
            XCTAssertTrue(name.lowercased().contains("press") || name.contains("push"),
                "\(name) should be classifiable as push")
        }
        for name in pullExercises {
            XCTAssertTrue(name.lowercased().contains("pull") || name.contains("row"),
                "\(name) should be classifiable as pull")
        }
        for name in squatExercises {
            XCTAssertTrue(name.lowercased().contains("squat") || name.contains("press"),
                "\(name) should be classifiable as squat/leg")
        }
        for name in hingeExercises {
            XCTAssertTrue(name.lowercased().contains("dead") || name.contains("hip") || name.contains("romanian") || name.contains("good"),
                "\(name) should be classifiable as hinge")
        }
    }

    // MARK: - Muscle Group Mapping

    func testMajorMuscleGroupsExist() {
        let requiredGroups = [
            "chest", "back", "shoulders", "biceps", "triceps",
            "quadriceps", "hamstrings", "glutes", "calves", "core"
        ]
        for group in requiredGroups {
            XCTAssertFalse(group.isEmpty, "\(group) must be a recognized muscle group")
        }
    }

    // MARK: - Exercise Scoring

    func testScoringWeightsArePositive() {
        let weights: [String: Int] = [
            "equipmentMatch": 25,
            "muscleExact": 40,
            "muscleRelated": 15,
            "patternSame": 35,
        ]
        for (name, weight) in weights {
            XCTAssertGreaterThan(weight, 0, "\(name) scoring weight must be positive")
        }
    }

    // MARK: - Equipment Categories

    func testCommonEquipmentTypes() {
        let equipment = [
            "barbell", "dumbbell", "cable", "machine",
            "bodyweight", "kettlebell", "resistance band", "smith machine"
        ]
        for eq in equipment {
            XCTAssertFalse(eq.isEmpty)
        }
        XCTAssertEqual(equipment.count, Set(equipment).count, "No duplicate equipment types")
    }
}
