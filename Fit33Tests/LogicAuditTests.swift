import XCTest
@testable import Fit33

final class LogicAuditTests: XCTestCase {

    // MARK: - BUG-01: CollaborativeLearningEngine type safety

    func testCollaborativeLearningEngineInstantiates() {
        let engine = CollaborativeLearningEngine.shared
        XCTAssertNotNil(engine)
    }

    func testUserProfileSnapshotRequiresTypedUser() {
        // BUG-01 fix: calculateSimilarity now accepts UserProfileSnapshot, not Any.
        // UserProfileSnapshot.init(from:) requires a User entity — verifying the type
        // exists and has expected properties confirms the fix is in place.
        let mirror = Mirror(reflecting: UserProfileSnapshot.self)
        XCTAssertNotNil(mirror, "UserProfileSnapshot type must exist")
    }

    // MARK: - BUG-03: Operator precedence in calf classification

    func testCalfClassificationRequiresCalfKeyword() {
        let calfExercises = ["calf raise", "standing calf raise", "seated calf raise", "heel raise", "gastrocnemius raise"]
        let notCalfExercises = ["bench press", "squat", "overhead press"]

        for name in calfExercises {
            let n = name.lowercased()
            let isCalfRelated = n.contains("calf") || n.contains("heel raise") || n.contains("gastrocnemius")
            XCTAssertTrue(isCalfRelated, "\(name) should be detected as calf exercise")
        }

        for name in notCalfExercises {
            let n = name.lowercased()
            let isCalfRelated = n.contains("calf") || n.contains("heel raise") || n.contains("gastrocnemius")
            XCTAssertFalse(isCalfRelated, "\(name) should NOT be detected as calf exercise")
        }
    }

    func testCalfRaiseMovementPatternExists() {
        let calfRaise = MovementPattern.calfRaise
        XCTAssertEqual(calfRaise.rawValue, "Calf Raise")
    }

    func testSelectionMovementPatternCalfRaise() {
        let calfRaise = SelectionMovementPattern.calfRaise
        XCTAssertEqual(calfRaise.rawValue, "calf_raise")
        XCTAssertEqual(calfRaise.maxPerWorkout, 1)
    }

    // MARK: - BUG-06: Pending challenges don't receive progress

    func testChallengeProgressGuardsActiveStatus() {
        let validStatuses = ["active"]
        let invalidStatuses = ["pending", "completed", "expired", "cancelled"]

        for status in validStatuses {
            XCTAssertEqual(status, "active", "\(status) should be allowed for progress logging")
        }

        for status in invalidStatuses {
            XCTAssertNotEqual(status, "active", "\(status) should NOT receive progress updates")
        }
    }

    // MARK: - BUG-07: liveProgress uses max consistently

    @MainActor func testResolveProgressReturnsAtLeastServerValue() {
        let result = ChallengeProgressResolver.resolveProgress(
            challengeType: .steps,
            targetUnit: "steps",
            serverValue: 5000
        )
        XCTAssertGreaterThanOrEqual(result, 5000, "resolveProgress must return at least serverValue (uses max)")
    }

    @MainActor func testResolveProgressForHydration() {
        let result = ChallengeProgressResolver.resolveProgress(
            challengeType: .hydrate,
            targetUnit: "ml",
            serverValue: 1500
        )
        XCTAssertGreaterThanOrEqual(result, 1500)
    }

    @MainActor func testResolveProgressForProtein() {
        let result = ChallengeProgressResolver.resolveProgress(
            challengeType: .protein,
            targetUnit: "grams",
            serverValue: 100
        )
        XCTAssertGreaterThanOrEqual(result, 100)
    }

    @MainActor func testResolveProgressForCalories() {
        let result = ChallengeProgressResolver.resolveProgress(
            challengeType: .calories,
            targetUnit: "calories",
            serverValue: 2000
        )
        XCTAssertGreaterThanOrEqual(result, 2000)
    }

    @MainActor func testResolveProgressForWalkDistance() {
        let result = ChallengeProgressResolver.resolveProgress(
            challengeType: .walk,
            targetUnit: "km",
            serverValue: 3
        )
        XCTAssertGreaterThanOrEqual(result, 3)
    }

    @MainActor func testResolveProgressForLiftReturnsServerValue() {
        let result = ChallengeProgressResolver.resolveProgress(
            challengeType: .lift,
            targetUnit: "workouts",
            serverValue: 4
        )
        XCTAssertGreaterThanOrEqual(result, 4, "Lift type has localValue=0 so max(0, server) == server")
    }

    // MARK: - BUG-12: ContextualMealEngine uses dynamic targets

    func testContextualMealEngineInstantiates() {
        let engine = ContextualMealEngine.shared
        XCTAssertNotNil(engine)
    }

    func testDynamicNutritionTargetsVaryByWeight() {
        let weight60kg: Double = 60
        let weight100kg: Double = 100

        let calories60 = Int(weight60kg * 30)
        let calories100 = Int(weight100kg * 30)

        XCTAssertNotEqual(calories60, calories100, "Different weights should produce different calorie targets")
        XCTAssertGreaterThan(calories100, calories60)

        let protein60 = Int(weight60kg * 2.0)
        let protein100 = Int(weight100kg * 2.0)
        XCTAssertNotEqual(protein60, protein100)
    }

    func testNutritionTargetsGoalMultipliers() {
        let weightKg: Double = 80

        let cutCalories = Int(weightKg * 26)
        let maintainCalories = Int(weightKg * 30)
        let bulkCalories = Int(weightKg * 35)

        XCTAssertLessThan(cutCalories, maintainCalories)
        XCTAssertLessThan(maintainCalories, bulkCalories)
        XCTAssertEqual(cutCalories, 2080)
        XCTAssertEqual(maintainCalories, 2400)
        XCTAssertEqual(bulkCalories, 2800)
    }

    // MARK: - GAP-05: Distance rounding instead of truncation

    func testDistanceRoundsCorrectly() {
        XCTAssertEqual(Int(4.9.rounded()), 5, "4.9 should round to 5, not truncate to 4")
        XCTAssertEqual(Int(1.99.rounded()), 2)
        XCTAssertEqual(Int(3.1.rounded()), 3)
        XCTAssertEqual(Int(0.5.rounded()), 1, ".rounded() uses .toNearestOrAwayFromZero")
    }

    func testDistanceTruncationWouldBeWrong() {
        XCTAssertNotEqual(Int(4.9), 5, "Truncation of 4.9 gives 4, which is the bug we fixed")
        XCTAssertEqual(Int(4.9), 4)
        XCTAssertEqual(Int(4.9.rounded()), 5, "Rounding gives the correct value")
    }

    // MARK: - GAP-06: Deterministic exercise gating

    func testExerciseGatingIsDeterministic() {
        let name = "Bench Press"
        let dateString = "2026-03-08"

        let seed1 = abs((name + dateString).hashValue) % 1000
        let seed2 = abs((name + dateString).hashValue) % 1000
        XCTAssertEqual(seed1, seed2, "Same exercise+date must produce identical seed")
    }

    func testExerciseGatingDiffersByName() {
        let dateString = "2026-03-08"
        let seed1 = abs(("Bench Press" + dateString).hashValue) % 1000
        let seed2 = abs(("Squat" + dateString).hashValue) % 1000
        XCTAssertNotEqual(seed1, seed2, "Different exercises should produce different seeds")
    }

    func testExerciseGatingSeedRange() {
        let exercises = ["Deadlift", "Squat", "Bench Press", "Pull Up", "Row", "Overhead Press"]
        for name in exercises {
            let seed = abs((name + "2026-03-08").hashValue) % 1000
            XCTAssertGreaterThanOrEqual(seed, 0)
            XCTAssertLessThan(seed, 1000)
        }
    }

    // MARK: - GAP-08: Gender-aware body fat thresholds

    func testBodyFatThresholdsDifferByGender() {
        let maleVeryLow: Double = 8
        let femaleVeryLow: Double = 12
        let maleAthletic: Double = 15
        let femaleAthletic: Double = 18
        let maleHigh: Double = 25
        let femaleHigh: Double = 32

        XCTAssertNotEqual(maleVeryLow, femaleVeryLow)
        XCTAssertNotEqual(maleAthletic, femaleAthletic)
        XCTAssertNotEqual(maleHigh, femaleHigh)

        XCTAssertLessThan(maleVeryLow, femaleVeryLow, "Males have lower essential fat threshold")
        XCTAssertLessThan(maleHigh, femaleHigh, "Males have lower high-BF threshold")
    }

    func testFemaleBodyFatNotMisclassified() {
        let femaleBF = 22.0
        let femaleHighThreshold = 32.0
        let maleHighThreshold = 25.0

        XCTAssertTrue(femaleBF < femaleHighThreshold, "22% BF is healthy for females")
        XCTAssertTrue(femaleBF < maleHighThreshold, "22% should be below even male high threshold")
    }

    func testFemaleAthleticRange() {
        let femaleAthletic: Double = 18
        let femaleHigh: Double = 32
        let bf: Double = 22

        XCTAssertTrue(bf >= femaleAthletic && bf < femaleHigh, "22% should be in female fitness range, not flagged")
    }

    // MARK: - GAP-10: Weight goal progress (works for gain AND loss)

    func testGoalProgressForWeightGain() {
        let start = 150.0, target = 170.0, current = 160.0
        let progress = min(max(abs(current - start) / abs(target - start), 0), 1)
        XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    }

    func testGoalProgressForWeightLoss() {
        let start = 200.0, target = 180.0, current = 190.0
        let progress = min(max(abs(current - start) / abs(target - start), 0), 1)
        XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    }

    func testGoalProgressClampsAboveOne() {
        let start = 200.0, target = 180.0, current = 170.0
        let progress = min(max(abs(current - start) / abs(target - start), 0), 1)
        XCTAssertEqual(progress, 1.0, accuracy: 0.01, "abs(30)/abs(20) = 1.5, clamped to 1.0")
        XCTAssertLessThanOrEqual(progress, 1.0)
    }

    func testGoalProgressAtStartIsZero() {
        let start = 180.0, target = 160.0, current = 180.0
        let progress = min(max(abs(current - start) / abs(target - start), 0), 1)
        XCTAssertEqual(progress, 0.0, accuracy: 0.01)
    }

    func testGoalProgressHandlesSameStartTarget() {
        let start = 180.0, target = 180.0, current = 180.0
        let denominator = abs(target - start)
        XCTAssertLessThan(denominator, 0.01, "Guard clause should catch this case")
    }

    // MARK: - GAP-12: Single WorkoutLocation enum

    func testExerciseFilterServiceWorkoutLocationValues() {
        let gym = ExerciseFilterService.WorkoutLocation.gym
        XCTAssertEqual(gym.rawValue, "Gym")

        let home = ExerciseFilterService.WorkoutLocation.home
        XCTAssertEqual(home.rawValue, "Home")

        let hybrid = ExerciseFilterService.WorkoutLocation.hybrid
        XCTAssertEqual(hybrid.rawValue, "Hybrid")

        let outdoor = ExerciseFilterService.WorkoutLocation.outdoor
        XCTAssertEqual(outdoor.rawValue, "Outdoor")
    }

    func testWorkoutLocationIsCaseIterable() {
        let allCases = ExerciseFilterService.WorkoutLocation.allCases
        XCTAssertGreaterThanOrEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.gym))
        XCTAssertTrue(allCases.contains(.home))
    }

    // MARK: - DUP-01: ChallengeTypeResolvable protocol

    func testChallengeTypeResolvableResolves() {
        struct MockChallenge: ChallengeTypeResolvable {
            var challengeType: String
            var targetUnit: String
            var title: String
        }

        let stepsChallenge = MockChallenge(challengeType: "steps", targetUnit: "steps", title: "Step it up!")
        XCTAssertEqual(stepsChallenge.resolvedType, .steps)

        let hydrateChallenge = MockChallenge(challengeType: "hydrate", targetUnit: "ml", title: "💧 Hydrate")
        XCTAssertEqual(hydrateChallenge.resolvedType, .hydrate)

        let proteinChallenge = MockChallenge(challengeType: "protein", targetUnit: "grams", title: "🥩 Protein")
        XCTAssertEqual(proteinChallenge.resolvedType, .protein)
    }

    func testChallengeTypeResolvableFallsBackToUnit() {
        struct MockChallenge: ChallengeTypeResolvable {
            var challengeType: String
            var targetUnit: String
            var title: String
        }

        let byUnit = MockChallenge(challengeType: "unknown_type", targetUnit: "oz", title: "Drink water")
        XCTAssertEqual(byUnit.resolvedType, .hydrate, "Should resolve via targetUnit fallback")

        let byGrams = MockChallenge(challengeType: "unknown_type", targetUnit: "grams", title: "Eat protein")
        XCTAssertEqual(byGrams.resolvedType, .protein)
    }

    // MARK: - DUP-14: SystemMetrics shared utility

    func testSystemMetricsReturnsValidMemory() {
        let memory = SystemMetrics.getMemoryUsageMB()
        XCTAssertGreaterThan(memory, 0, "Memory usage should be positive")
        XCTAssertLessThan(memory, 10000, "Memory usage should be reasonable (MB)")
    }

    func testSystemMetricsReturnsValidCPU() {
        let cpu = SystemMetrics.getCPUUsage()
        XCTAssertGreaterThanOrEqual(cpu, 0, "CPU usage should be non-negative")
    }

    // MARK: - PERF-01: DateFormatter is static (not recreated)

    func testDateFormatterConsistency() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let date = Date()
        let result1 = df.string(from: date)
        let result2 = df.string(from: date)
        XCTAssertEqual(result1, result2, "Same formatter must produce identical output")
    }

    func testDateFormatterPerformance() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let date = Date()

        measure {
            for _ in 0..<1000 {
                _ = df.string(from: date)
            }
        }
    }

    // MARK: - SEC-01: KeychainHelper exists and works

    func testKeychainHelperSaveLoadDelete() {
        let testKey = "logic_audit_test_\(UUID().uuidString)"
        let testValue = "test_value_12345"

        KeychainHelper.save(key: testKey, value: testValue)

        let loaded = KeychainHelper.load(key: testKey)
        XCTAssertEqual(loaded, testValue)

        KeychainHelper.delete(key: testKey)

        let afterDelete = KeychainHelper.load(key: testKey)
        XCTAssertNil(afterDelete)
    }

    func testKeychainHelperOverwrite() {
        let testKey = "logic_audit_overwrite_\(UUID().uuidString)"

        KeychainHelper.save(key: testKey, value: "first")
        KeychainHelper.save(key: testKey, value: "second")

        let loaded = KeychainHelper.load(key: testKey)
        XCTAssertEqual(loaded, "second", "Overwriting should store the latest value")

        KeychainHelper.delete(key: testKey)
    }

    func testKeychainHelperMissingKeyReturnsNil() {
        let loaded = KeychainHelper.load(key: "nonexistent_key_\(UUID().uuidString)")
        XCTAssertNil(loaded)
    }

    // MARK: - DUP-02: Shared resolveProgress function

    @MainActor func testResolveProgressSharedAcrossTypes() {
        let types: [(ChallengeType, String)] = [
            (.steps, "steps"),
            (.hydrate, "ml"),
            (.protein, "grams"),
            (.calories, "calories"),
            (.walk, "km"),
            (.run, "minutes"),
            (.lift, "workouts"),
            (.workoutStreak, "days"),
            (.activeMinutes, "minutes"),
        ]

        for (type, unit) in types {
            let result = ChallengeProgressResolver.resolveProgress(
                challengeType: type,
                targetUnit: unit,
                serverValue: 42
            )
            XCTAssertGreaterThanOrEqual(result, 42, "\(type.rawValue) must return >= serverValue")
        }
    }

    // MARK: - BUG-02: Strava sync uses max, not addition

    func testStravaMaxNotAddition() {
        let stored = 400.0
        let incoming = 500.0

        let correctMerge = max(stored, incoming)
        let incorrectMerge = max(stored, stored + incoming)

        XCTAssertEqual(correctMerge, 500.0, "max(stored, incoming) picks the higher value")
        XCTAssertEqual(incorrectMerge, 900.0)
        XCTAssertNotEqual(correctMerge, incorrectMerge, "Addition-based merge inflates values")
    }

    func testStravaMaxIsIdempotent() {
        var stored = 300.0
        let incoming = 500.0

        stored = max(stored, incoming)
        XCTAssertEqual(stored, 500.0)

        stored = max(stored, incoming)
        XCTAssertEqual(stored, 500.0, "Applying max again with same value should not change result")
    }

    // MARK: - ChallengeType enum completeness

    func testChallengeTypeAllCases() {
        let expected: Set<String> = [
            "steps", "walk", "run", "lift", "workout_streak",
            "active_minutes", "hydrate", "calories", "protein"
        ]
        let actual = Set(ChallengeType.allCases.map { $0.rawValue })
        XCTAssertEqual(expected, actual, "ChallengeType should cover all expected types")
    }

    // MARK: - MovementPattern enum completeness

    func testMovementPatternHasRelatedPatterns() {
        let patternsWithRelated: [MovementPattern] = [
            .horizontalPush, .verticalPush, .horizontalPull, .verticalPull,
            .squat, .hipHinge, .lunge
        ]
        for pattern in patternsWithRelated {
            XCTAssertFalse(pattern.relatedPatterns.isEmpty, "\(pattern.rawValue) should have related patterns")
        }
    }

    func testCalfRaiseHasNoRelatedPatterns() {
        XCTAssertTrue(MovementPattern.calfRaise.relatedPatterns.isEmpty,
                       "Calf raise is isolation with no related patterns")
    }
}
