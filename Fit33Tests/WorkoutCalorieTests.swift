import XCTest
@testable import Fit33

final class WorkoutCalorieTests: XCTestCase {
    
    private let maleBiometrics = UserBiometrics(
        weightKg: 80,
        heightCm: 178,
        ageYears: 30,
        biologicalSex: .male,
        fitnessLevel: .intermediate
    )
    
    private let femaleBiometrics = UserBiometrics(
        weightKg: 60,
        heightCm: 165,
        ageYears: 28,
        biologicalSex: .female,
        fitnessLevel: .intermediate
    )
    
    // MARK: - Basic calorie calculation
    
    func testZeroDurationReturnsZeroCalories() {
        let result = WorkoutCalorieCalculator.calculateCalories(
            durationSeconds: 0,
            exercises: [],
            biometrics: maleBiometrics
        )
        XCTAssertEqual(result.totalCalories, 0)
    }
    
    func testPositiveDurationReturnsPositiveCalories() {
        let result = WorkoutCalorieCalculator.calculateCalories(
            durationSeconds: 3600,
            exercises: [],
            biometrics: maleBiometrics
        )
        XCTAssertGreaterThan(result.totalCalories, 0)
    }
    
    func testLongerWorkoutBurnsMoreCalories() {
        let short = WorkoutCalorieCalculator.calculateCalories(
            durationSeconds: 1800,
            exercises: [],
            biometrics: maleBiometrics
        )
        let long = WorkoutCalorieCalculator.calculateCalories(
            durationSeconds: 3600,
            exercises: [],
            biometrics: maleBiometrics
        )
        XCTAssertGreaterThan(long.totalCalories, short.totalCalories)
    }
    
    // MARK: - Biometric factors
    
    func testHeavierPersonBurnsMore() {
        let light = UserBiometrics(weightKg: 55, heightCm: 165, ageYears: 30, biologicalSex: .male, fitnessLevel: .intermediate)
        let heavy = UserBiometrics(weightKg: 100, heightCm: 185, ageYears: 30, biologicalSex: .male, fitnessLevel: .intermediate)
        
        let lightResult = WorkoutCalorieCalculator.calculateCalories(durationSeconds: 3600, exercises: [], biometrics: light)
        let heavyResult = WorkoutCalorieCalculator.calculateCalories(durationSeconds: 3600, exercises: [], biometrics: heavy)
        
        XCTAssertGreaterThan(heavyResult.totalCalories, lightResult.totalCalories)
    }
    
    // MARK: - Reasonable ranges
    
    func testOneHourWorkoutInReasonableRange() {
        let result = WorkoutCalorieCalculator.calculateCalories(
            durationSeconds: 3600,
            exercises: [],
            biometrics: maleBiometrics
        )
        XCTAssertGreaterThan(result.totalCalories, 100, "1-hour workout should burn at least 100 cal")
        XCTAssertLessThan(result.totalCalories, 1500, "1-hour workout should burn less than 1500 cal")
    }
}
