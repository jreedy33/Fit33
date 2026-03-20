import XCTest
@testable import Fit33

final class ExercisePopularityTests: XCTestCase {

    private var service: ExercisePopularityService!

    override func setUp() {
        super.setUp()
        service = ExercisePopularityService.shared
    }

    func testTopTierExercisesScoreAbove90() {
        let topTier = ["bench press", "barbell squat", "deadlift", "pull up", "push up"]
        for exercise in topTier {
            XCTAssertTrue(
                service.isTopTierExercise(exercise),
                "\(exercise) should be top tier"
            )
        }
    }

    func testPopularExercisesScoreAbove70() {
        let popular = ["leg press", "incline bench press", "romanian deadlift", "lat pulldown"]
        for exercise in popular {
            XCTAssertTrue(
                service.isPopularExercise(exercise),
                "\(exercise) should be popular"
            )
        }
    }

    func testUnknownExerciseReturnsDefaultScore() {
        let score = service.getPopularityScore(for: "completely made up exercise xyz")
        XCTAssertEqual(score, 50, "Unknown exercise should default to 50")
    }

    func testGetTopExercisesReturnsRequestedCount() {
        let top10 = service.getTopExercises(count: 10)
        XCTAssertEqual(top10.count, 10)

        let top50 = service.getTopExercises(count: 50)
        XCTAssertEqual(top50.count, 50)
    }

    func testPopularityBoostWithinBounds() {
        let exercises = ["bench press", "deadlift", "unknown exercise"]
        for exercise in exercises {
            let boost = service.getPopularityBoost(for: exercise)
            XCTAssertGreaterThanOrEqual(boost, 0)
            XCTAssertLessThanOrEqual(boost, 250, "Boost for \(exercise) should be capped at 250")
        }
    }

    func testPartialNameMatchReturnsScore() {
        let score = service.getPopularityScore(for: "barbell bench press flat")
        XCTAssertGreaterThan(score, 50, "Partial match should return above-default score")
    }
}
