//
//  LimitationFilterTests.swift
//  Fit33
//
//  Unit tests for the Limitation/Injury Filtering System
//  Tests ensure the metadata-driven filtering works correctly
//  for all severity levels and body areas.
//
//  Created by Cursor AI
//
//  ⚠️ DEBUG ONLY - This entire file is excluded from production builds

#if DEBUG

import Foundation

// MARK: - Test Framework

/// Simple test framework for running limitation filter tests
class LimitationFilterTests {
    
    static let shared = LimitationFilterTests()
    private init() {}
    
    // MARK: - Test Results
    
    struct TestResult {
        let testName: String
        let passed: Bool
        let message: String
    }
    
    private(set) var results: [TestResult] = []
    
    // MARK: - Run All Tests
    
    func runAllTests() -> [TestResult] {
        results = []
        
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║       LIMITATION FILTER SYSTEM - UNIT TESTS                  ║")
        print("╠══════════════════════════════════════════════════════════════╣")
        
        // Test 1: Lower Back Skip Completely
        testLowerBackSkipCompletely()
        
        // Test 2: Lower Back Light Work Only
        testLowerBackLightWorkOnly()
        
        // Test 3: Lower Back Be Careful
        testLowerBackBeCareful()
        
        // Test 4: Shoulder Skip Completely
        testShoulderSkipCompletely()
        
        // Test 5: Shoulder Be Careful
        testShoulderBeCareful()
        
        // Test 6: Knee Skip Completely
        testKneeSkipCompletely()
        
        // Test 7: Stretching Only
        testStretchingOnly()
        
        // Test 8: Multiple Limitations
        testMultipleLimitations()
        
        // Test 9: Equipment Diversity Cap
        testEquipmentDiversityCap()
        
        // Test 10: Exercise Metadata Classification
        testExerciseMetadataClassification()
        
        // Print Summary
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count
        
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ RESULTS: \(passed) PASSED, \(failed) FAILED                            ")
        print("╚══════════════════════════════════════════════════════════════╝")
        
        return results
    }
    
    // MARK: - Test Helpers
    
    private func assert(_ condition: Bool, _ testName: String, message: String) {
        let result = TestResult(testName: testName, passed: condition, message: message)
        results.append(result)
        
        if condition {
            print("   ✅ \(testName)")
        } else {
            print("   ❌ \(testName): \(message)")
        }
    }
    
    /// Create a mock exercise with given name
    private func mockExercise(name: String, equipment: String = "Barbell") -> MockExercise {
        MockExercise(name: name, equipment: equipment)
    }
    
    /// Create test metadata directly
    private func createMetadata(
        spinalLoad: SpinalLoad = .none,
        axialLoading: AxialLoading = .none,
        unsupportedTorso: Bool = false,
        overheadWork: OverheadWork = .none,
        kneeFlexionDepth: KneeFlexionDepth = .low,
        shoulderStressFlags: ShoulderStressFlags = .none,
        impactLevel: ImpactLevel = .none,
        isMachine: Bool = false,
        isStretch: Bool = false,
        isChestSupported: Bool = false,
        hipHinge: Bool = false
    ) -> ExerciseRiskMetadata {
        return ExerciseRiskMetadata(
            movementPatterns: hipHinge ? [.hinge] : [],
            spinalLoad: spinalLoad,
            axialLoading: axialLoading,
            unsupportedTorso: unsupportedTorso,
            overheadWork: overheadWork,
            kneeFlexionDepth: kneeFlexionDepth,
            shoulderStressFlags: shoulderStressFlags,
            wristExtensionDemand: .low,
            hipHingeDemand: hipHinge,
            neckStress: false,
            elbowStress: false,
            impactLevel: impactLevel,
            balanceDemand: .low,
            isMachineSupported: isMachine,
            isStretchOrMobility: isStretch,
            isChestSupported: isChestSupported,
            isSeated: false,
            isLying: false,
            difficultyTier: .foundational
        )
    }
    
    // MARK: - Test Cases
    
    /// Test 1: Lower Back Skip Completely
    /// Exercises with high spinal load should be excluded
    private func testLowerBackSkipCompletely() {
        print("\n║ Test 1: Lower Back - Skip Completely")
        
        let limitation = FilterLimitation(
            area: .lowerBack,
            severity: .skipCompletely,
            type: .injury
        )
        
        // High spinal load should be excluded
        let deadliftMeta = createMetadata(spinalLoad: .high, hipHinge: true)
        let (exclude1, _, _, _) = evaluateMetadata(deadliftMeta, limitation)
        assert(exclude1, "Deadlift excluded", message: "High spinal load exercises should be excluded")
        
        // Bent-over row (unsupported torso) should be excluded
        let bentRowMeta = createMetadata(spinalLoad: .moderate, unsupportedTorso: true)
        let (exclude2, _, _, _) = evaluateMetadata(bentRowMeta, limitation)
        assert(exclude2, "Bent-over row excluded", message: "Unsupported torso exercises should be excluded")
        
        // Machine row (supported) should NOT be excluded
        let machineRowMeta = createMetadata(spinalLoad: .low, isMachine: true)
        let (exclude3, _, _, _) = evaluateMetadata(machineRowMeta, limitation)
        assert(!exclude3, "Machine row included", message: "Machine-supported exercises should be included")
        
        // Chest-supported row should NOT be excluded
        let chestRowMeta = createMetadata(spinalLoad: .low, isChestSupported: true)
        let (exclude4, _, _, _) = evaluateMetadata(chestRowMeta, limitation)
        assert(!exclude4, "Chest-supported row included", message: "Chest-supported exercises should be included")
    }
    
    /// Test 2: Lower Back Light Work Only
    /// Heavy compounds excluded, machine/supported work allowed
    private func testLowerBackLightWorkOnly() {
        print("\n║ Test 2: Lower Back - Light Work Only")
        
        let limitation = FilterLimitation(
            area: .lowerBack,
            severity: .lightWorkOnly,
            type: .injury
        )
        
        // High spinal load should be excluded
        let deadliftMeta = createMetadata(spinalLoad: .high)
        let (exclude1, _, _, _) = evaluateMetadata(deadliftMeta, limitation)
        assert(exclude1, "Heavy deadlift excluded", message: "Heavy spinal exercises excluded for light work")
        
        // Unsupported hinge should be excluded
        let goodMorningMeta = createMetadata(unsupportedTorso: true, hipHinge: true)
        let (exclude2, _, _, _) = evaluateMetadata(goodMorningMeta, limitation)
        assert(exclude2, "Good morning excluded", message: "Unsupported hinges excluded for light work")
        
        // Machine exercise with low load should be allowed
        let machineRowMeta = createMetadata(spinalLoad: .low, isMachine: true)
        let (exclude3, penalty3, _, _) = evaluateMetadata(machineRowMeta, limitation)
        assert(!exclude3, "Machine row allowed", message: "Machine exercises allowed for light work")
        assert(penalty3 < 50, "Machine row low penalty", message: "Machine exercises get low/no penalty")
        
        // Chest-supported should get BOOST (negative penalty)
        let chestSupportedMeta = createMetadata(spinalLoad: .low, isChestSupported: true)
        let (_, penalty4, _, _) = evaluateMetadata(chestSupportedMeta, limitation)
        assert(penalty4 < 0, "Chest-supported boosted", message: "Chest-supported gets negative penalty (boost)")
    }
    
    /// Test 3: Lower Back Be Careful
    /// Risky exercises penalized, safe ones boosted
    private func testLowerBackBeCareful() {
        print("\n║ Test 3: Lower Back - Be Careful")
        
        let limitation = FilterLimitation(
            area: .lowerBack,
            severity: .beCareful,
            type: .chronic
        )
        
        // High spinal load should be PENALIZED but not excluded
        let deadliftMeta = createMetadata(spinalLoad: .high)
        let (exclude1, penalty1, _, _) = evaluateMetadata(deadliftMeta, limitation)
        assert(!exclude1, "Deadlift not excluded", message: "Be careful doesn't exclude")
        assert(penalty1 > 100, "Deadlift high penalty", message: "High spinal load gets high penalty")
        
        // Machine exercise should get BOOST
        let machineMeta = createMetadata(spinalLoad: .none, isMachine: true)
        let (_, penalty2, _, _) = evaluateMetadata(machineMeta, limitation)
        assert(penalty2 < 0, "Machine boosted", message: "Machine exercises get boost")
        
        // Chest-supported should get bigger BOOST
        let chestMeta = createMetadata(isChestSupported: true)
        let (_, penalty3, _, _) = evaluateMetadata(chestMeta, limitation)
        assert(penalty3 < penalty2, "Chest-supported > Machine", message: "Chest-supported gets more boost than machine")
    }
    
    /// Test 4: Shoulder Skip Completely
    /// Overhead and dangerous shoulder patterns excluded
    private func testShoulderSkipCompletely() {
        print("\n║ Test 4: Shoulder - Skip Completely")
        
        let limitation = FilterLimitation(
            area: .shoulders,
            severity: .skipCompletely,
            type: .injury
        )
        
        // Full overhead should be excluded
        let ohpMeta = createMetadata(overheadWork: .full)
        let (exclude1, _, _, _) = evaluateMetadata(ohpMeta, limitation)
        assert(exclude1, "OHP excluded", message: "Full overhead exercises excluded")
        
        // Upright row pattern should be excluded
        let uprightRowMeta = createMetadata(shoulderStressFlags: .uprightRowLike)
        let (exclude2, _, _, _) = evaluateMetadata(uprightRowMeta, limitation)
        assert(exclude2, "Upright row excluded", message: "Upright row pattern excluded")
        
        // Behind neck should be excluded
        let behindNeckMeta = createMetadata(shoulderStressFlags: .behindNeck)
        let (exclude3, _, _, _) = evaluateMetadata(behindNeckMeta, limitation)
        assert(exclude3, "Behind neck excluded", message: "Behind neck exercises excluded")
        
        // Heavy dip should be excluded
        let dipMeta = createMetadata(shoulderStressFlags: .heavyDip)
        let (exclude4, _, _, _) = evaluateMetadata(dipMeta, limitation)
        assert(exclude4, "Heavy dip excluded", message: "Heavy dips excluded")
        
        // Guillotine press should be excluded
        let guillotineMeta = createMetadata(shoulderStressFlags: .guillotine)
        let (exclude5, _, _, _) = evaluateMetadata(guillotineMeta, limitation)
        assert(exclude5, "Guillotine excluded", message: "Guillotine press excluded")
    }
    
    /// Test 5: Shoulder Be Careful
    /// Dangerous patterns penalized
    private func testShoulderBeCareful() {
        print("\n║ Test 5: Shoulder - Be Careful")
        
        let limitation = FilterLimitation(
            area: .shoulders,
            severity: .beCareful,
            type: .chronic
        )
        
        // Upright row pattern should be heavily penalized
        let uprightRowMeta = createMetadata(shoulderStressFlags: .uprightRowLike)
        let (exclude1, penalty1, _, _) = evaluateMetadata(uprightRowMeta, limitation)
        assert(!exclude1, "Upright row not excluded", message: "Be careful doesn't exclude")
        assert(penalty1 >= 100, "Upright row penalized", message: "Upright row heavily penalized")
        
        // Machine press should get boost
        let machineMeta = createMetadata(isMachine: true)
        let (_, penalty2, _, _) = evaluateMetadata(machineMeta, limitation)
        assert(penalty2 < 50, "Machine boosted", message: "Machine press gets low penalty/boost")
    }
    
    /// Test 6: Knee Skip Completely
    /// Deep flexion and impact excluded
    private func testKneeSkipCompletely() {
        print("\n║ Test 6: Knee - Skip Completely")
        
        let limitation = FilterLimitation(
            area: .knees,
            severity: .skipCompletely,
            type: .injury
        )
        
        // Deep squat should be excluded
        let deepSquatMeta = createMetadata(kneeFlexionDepth: .high)
        let (exclude1, _, _, _) = evaluateMetadata(deepSquatMeta, limitation)
        assert(exclude1, "Deep squat excluded", message: "Deep knee flexion excluded")
        
        // Plyometrics should be excluded
        let jumpMeta = createMetadata(impactLevel: .high)
        let (exclude2, _, _, _) = evaluateMetadata(jumpMeta, limitation)
        assert(exclude2, "Jump squat excluded", message: "High impact excluded")
        
        // Leg curl (machine, low impact) should be allowed
        let legCurlMeta = createMetadata(kneeFlexionDepth: .low, isMachine: true, impactLevel: .none)
        let (exclude3, _, _, _) = evaluateMetadata(legCurlMeta, limitation)
        assert(!exclude3, "Leg curl allowed", message: "Machine isolation allowed")
    }
    
    /// Test 7: Stretching Only
    /// Only stretch/mobility exercises allowed
    private func testStretchingOnly() {
        print("\n║ Test 7: Stretching Only")
        
        let limitation = FilterLimitation(
            area: .lowerBack,
            severity: .stretchingOnly,
            type: .injury
        )
        
        // Regular exercise should be excluded
        let regularMeta = createMetadata()
        let (exclude1, _, _, _) = evaluateMetadata(regularMeta, limitation)
        assert(exclude1, "Regular exercise excluded", message: "Non-stretch excluded for stretching only")
        
        // Stretch exercise should be allowed
        let stretchMeta = createMetadata(isStretch: true)
        let (exclude2, _, _, _) = evaluateMetadata(stretchMeta, limitation)
        assert(!exclude2, "Stretch allowed", message: "Stretch exercises allowed")
    }
    
    /// Test 8: Multiple Limitations
    /// All limitations should be applied
    private func testMultipleLimitations() {
        print("\n║ Test 8: Multiple Limitations")
        
        // User has both lower back and knee issues
        let backLimitation = FilterLimitation(area: .lowerBack, severity: .beCareful)
        let kneeLimitation = FilterLimitation(area: .knees, severity: .skipCompletely)
        
        // Squat affects both - should be excluded due to knee skip completely
        let squatMeta = createMetadata(
            spinalLoad: .moderate,
            kneeFlexionDepth: .moderate
        )
        
        // Test with knee limitation (should exclude)
        let (exclude1, _, _, _) = evaluateMetadata(squatMeta, kneeLimitation)
        assert(exclude1, "Squat excluded (knee)", message: "Squat excluded due to knee skip completely")
        
        // Test with back limitation only (should penalize but not exclude)
        let (exclude2, penalty2, _, _) = evaluateMetadata(squatMeta, backLimitation)
        assert(!exclude2, "Squat not excluded (back)", message: "Squat not excluded for back be-careful")
        assert(penalty2 > 0, "Squat penalized (back)", message: "Squat gets penalty for back be-careful")
    }
    
    /// Test 9: Equipment Diversity Cap
    /// Should limit number of distinct equipment types
    private func testEquipmentDiversityCap() {
        print("\n║ Test 9: Equipment Diversity Cap")
        
        // Test foundational user (max 2 equipment types)
        let maxForFoundational = EquipmentDiversityCap.calculateMax(duration: 30, isFoundational: true)
        assert(maxForFoundational <= 2, "Foundational cap", message: "Foundational users capped at 2 equipment types")
        
        // Test short workout (max 2)
        let maxFor15Min = EquipmentDiversityCap.calculateMax(duration: 15, isFoundational: false)
        assert(maxFor15Min <= 2, "Short workout cap", message: "15-min workouts capped at 2")
        
        // Test long workout (more equipment ok)
        let maxFor60Min = EquipmentDiversityCap.calculateMax(duration: 60, isFoundational: false)
        assert(maxFor60Min >= 4, "Long workout cap", message: "60-min workouts allow 4+ equipment types")
    }
    
    /// Test 10: Exercise Metadata Classification
    /// Classifier should correctly identify exercise characteristics
    private func testExerciseMetadataClassification() {
        print("\n║ Test 10: Exercise Metadata Classification")
        
        let classifier = ExerciseMetadataClassifier.shared
        
        // Test deadlift classification
        let deadlift = MockExercise(name: "Barbell Deadlift", equipment: "Barbell")
        let deadliftMeta = classifier.classify(exercise: deadlift.asExercise)
        assert(deadliftMeta.spinalLoad == .high, "Deadlift spinal load", message: "Deadlift has high spinal load")
        assert(deadliftMeta.hipHingeDemand, "Deadlift hip hinge", message: "Deadlift is hip hinge")
        
        // Test machine row classification
        let machineRow = MockExercise(name: "Seated Machine Row", equipment: "Machine")
        let machineMeta = classifier.classify(exercise: machineRow.asExercise)
        assert(machineMeta.isMachineSupported, "Machine row supported", message: "Machine row is machine-supported")
        assert(machineMeta.spinalLoad <= .low, "Machine row low spinal", message: "Machine row has low spinal load")
        
        // Test overhead press classification
        let ohp = MockExercise(name: "Standing Overhead Press", equipment: "Barbell")
        let ohpMeta = classifier.classify(exercise: ohp.asExercise)
        assert(ohpMeta.overheadWork == .full, "OHP overhead", message: "OHP has full overhead work")
        
        // Test stretch classification
        let stretch = MockExercise(name: "Standing Quad Stretch", equipment: "Bodyweight")
        let stretchMeta = classifier.classify(exercise: stretch.asExercise)
        assert(stretchMeta.isStretchOrMobility, "Stretch classification", message: "Stretch correctly classified")
    }
    
    // MARK: - Evaluation Helper
    
    /// Evaluate metadata against a limitation
    private func evaluateMetadata(
        _ metadata: ExerciseRiskMetadata,
        _ limitation: FilterLimitation
    ) -> (shouldExclude: Bool, penalty: Double, warnings: [String], reason: String?) {
        
        // Check if exercise affects this limitation area
        let affectsArea = doesMetadataAffectArea(metadata: metadata, area: limitation.area)
        
        guard affectsArea else {
            return (false, 0, [], nil)
        }
        
        // Apply severity-specific rules
        switch limitation.severity {
        case .skipCompletely:
            let rules = LimitationRuleTables.getSkipCompletelyRules(for: limitation.area)
            for rule in rules {
                if rule.matches(metadata) {
                    return (true, 0, [], rule.reason)
                }
            }
            return (false, 300, [], nil)
            
        case .stretchingOnly:
            if metadata.isStretchOrMobility {
                return (false, 0, [], nil)
            }
            return (true, 0, [], "Only stretching allowed")
            
        case .lightWorkOnly:
            let exclusionRules = LimitationRuleTables.getLightWorkExclusionRules(for: limitation.area)
            for rule in exclusionRules {
                if rule.matches(metadata) {
                    return (true, 0, [], rule.reason)
                }
            }
            
            var penalty: Double = 0
            let preferenceRules = LimitationRuleTables.getLightWorkPreferenceRules(for: limitation.area)
            for rule in preferenceRules {
                if rule.matches(metadata) {
                    if rule.isNegative {
                        penalty += rule.penalty
                    } else {
                        penalty -= rule.penalty
                    }
                }
            }
            return (false, penalty, [], nil)
            
        case .beCareful:
            var penalty: Double = 0
            let rules = LimitationRuleTables.getBeCarefulRules(for: limitation.area)
            for rule in rules {
                if rule.matches(metadata) {
                    if rule.isNegative {
                        penalty += rule.penalty
                    } else {
                        penalty -= rule.penalty
                    }
                }
            }
            return (false, penalty, [], nil)
        }
    }
    
    /// Check if metadata indicates the exercise affects a body area
    private func doesMetadataAffectArea(metadata: ExerciseRiskMetadata, area: LimitationArea) -> Bool {
        switch area {
        case .lowerBack:
            return metadata.spinalLoad >= .moderate ||
                   metadata.axialLoading >= .low ||
                   metadata.unsupportedTorso ||
                   metadata.hipHingeDemand
            
        case .shoulders:
            return !metadata.shoulderStressFlags.isEmpty ||
                   metadata.overheadWork != .none ||
                   metadata.movementPatterns.contains(RiskMovementPattern.push)
            
        case .knees:
            return metadata.kneeFlexionDepth >= .moderate ||
                   metadata.impactLevel >= .moderate ||
                   metadata.movementPatterns.contains(RiskMovementPattern.squat) ||
                   metadata.movementPatterns.contains(RiskMovementPattern.lunge)
            
        case .hips:
            return metadata.hipHingeDemand ||
                   metadata.movementPatterns.contains(RiskMovementPattern.hinge) ||
                   metadata.movementPatterns.contains(RiskMovementPattern.squat)
            
        case .neck:
            return metadata.neckStress ||
                   metadata.axialLoading >= .high
            
        case .wrists:
            return metadata.wristExtensionDemand != .low
            
        case .elbows:
            return metadata.elbowStress
            
        case .ankles:
            return metadata.impactLevel >= .moderate ||
                   metadata.balanceDemand == .high
            
        case .upperBack, .other:
            return false
        }
    }
}

// MARK: - Mock Exercise

/// Mock exercise for testing
struct MockExercise {
    let name: String
    let equipment: String
    
    /// Convert to Exercise-like object for classifier
    var asExercise: Exercise {
        // Create a minimal mock that the classifier can work with
        // In real usage, this would be a Core Data Exercise
        return MockExerciseWrapper(name: name, equipment: equipment)
    }
}

/// Wrapper to make mock work with classifier
class MockExerciseWrapper: Exercise {
    private let _name: String
    private let _equipment: String
    
    init(name: String, equipment: String) {
        self._name = name
        self._equipment = equipment
        super.init(entity: Exercise.entity(), insertInto: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var name: String? { _name }
    override var equipment: String? { _equipment }
    override var primaryMuscle: String? { nil }
    override var secondaryMuscles: [String]? { nil }
    override var difficultyTier: String? { nil }
}

// MARK: - Test Runner

/// Run tests and generate report
func runLimitationFilterTests() {
    let results = LimitationFilterTests.shared.runAllTests()
    
    let passed = results.filter { $0.passed }.count
    let failed = results.filter { !$0.passed }.count
    
    print("\n📊 Test Summary: \(passed)/\(results.count) tests passed")
    
    if failed > 0 {
        print("\n❌ Failed Tests:")
        for result in results where !result.passed {
            print("   • \(result.testName): \(result.message)")
        }
    }
}

#endif // DEBUG
