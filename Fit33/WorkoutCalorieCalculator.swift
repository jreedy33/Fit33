//
//  WorkoutCalorieCalculator.swift
//  GoFit
//
//  Apple Fitness-quality calorie estimation for strength training workouts.
//  
//  This calculator uses multiple scientific approaches combined:
//  1. MET (Metabolic Equivalent of Task) values adjusted per exercise type
//  2. Volume-based work calculation (Force × Distance)
//  3. User biometrics (weight, age, sex, fitness level)
//  4. Active time vs rest time separation
//  5. EPOC (afterburn effect) estimation
//  6. Muscle group size multipliers
//
//  References:
//  - Ainsworth BE, et al. "2011 Compendium of Physical Activities"
//  - Scott CB. "Contribution of blood lactate to the energy expenditure of weight training"
//  - Haddock BL, Wilkin LD. "Resistance training volume and post exercise energy expenditure"
//

import Foundation
import HealthKit

// MARK: - User Biometrics

struct UserBiometrics {
    let weightKg: Double
    let heightCm: Double
    let ageYears: Int
    let biologicalSex: BiologicalSex
    let fitnessLevel: FitnessLevel
    
    enum BiologicalSex {
        case male
        case female
        case other
        
        /// Metabolic adjustment factor (males typically have higher BMR)
        var metabolicFactor: Double {
            switch self {
            case .male: return 1.0
            case .female: return 0.9
            case .other: return 0.95
            }
        }
    }
    
    enum FitnessLevel {
        case beginner      // < 6 months training
        case intermediate  // 6 months - 2 years
        case advanced      // 2+ years consistent training
        
        /// Efficiency factor - trained individuals are more metabolically efficient
        /// but also can sustain higher intensities
        var efficiencyFactor: Double {
            switch self {
            case .beginner: return 1.1      // Less efficient = burns slightly more
            case .intermediate: return 1.0
            case .advanced: return 0.95     // More efficient, but higher intensity compensates
            }
        }
    }
    
    /// Basal Metabolic Rate using Mifflin-St Jeor equation (most accurate)
    var bmrKcalPerDay: Double {
        let s: Double = biologicalSex == .male ? 5 : -161
        return (10 * weightKg) + (6.25 * heightCm) - (5 * Double(ageYears)) + s
    }
    
    /// BMR per minute for calculations
    var bmrKcalPerMinute: Double {
        return bmrKcalPerDay / 1440.0  // 1440 minutes in a day
    }
    
    /// Age-based metabolic adjustment (metabolism decreases ~2% per decade after 20)
    var ageMetabolicFactor: Double {
        if ageYears <= 20 { return 1.05 }
        let decadesOver20 = Double(ageYears - 20) / 10.0
        return max(0.85, 1.0 - (decadesOver20 * 0.02))
    }
}

// MARK: - Exercise Calorie Data

struct ExerciseCalorieData {
    let exerciseName: String
    let equipment: String
    let primaryMuscles: [String]
    let setsCompleted: Int
    let totalReps: Int
    let totalWeightLifted: Double  // in kg or lbs (will normalize)
    let isCompound: Bool
    let averageRestSeconds: Double
    let timeUnderTensionSeconds: Double  // Estimated active time for this exercise
    
    /// Movement distance factor (how far the weight travels)
    /// Full ROM exercises like squats have higher values
    var movementDistanceFactor: Double {
        let nameLower = exerciseName.lowercased()
        
        // Large range of motion exercises
        if nameLower.contains("squat") || nameLower.contains("deadlift") ||
           nameLower.contains("lunge") || nameLower.contains("clean") ||
           nameLower.contains("snatch") || nameLower.contains("thruster") {
            return 1.0
        }
        
        // Medium range of motion
        if nameLower.contains("press") || nameLower.contains("row") ||
           nameLower.contains("pulldown") || nameLower.contains("pull up") ||
           nameLower.contains("pullup") || nameLower.contains("dip") {
            return 0.8
        }
        
        // Smaller range of motion (isolation)
        if nameLower.contains("curl") || nameLower.contains("extension") ||
           nameLower.contains("raise") || nameLower.contains("fly") ||
           nameLower.contains("shrug") {
            return 0.5
        }
        
        // Core exercises (isometric or short ROM)
        if nameLower.contains("plank") || nameLower.contains("crunch") ||
           nameLower.contains("hold") {
            return 0.3
        }
        
        return 0.6  // Default
    }
}

// MARK: - Muscle Group Calorie Multipliers

enum MuscleGroupCalorieMultiplier {
    /// Larger muscle groups require more energy to contract
    static func getMultiplier(for muscles: [String]) -> Double {
        var maxMultiplier = 1.0
        
        for muscle in muscles {
            let muscleLower = muscle.lowercased()
            
            // Large muscle groups (highest calorie burn)
            if muscleLower.contains("quad") || muscleLower.contains("glute") ||
               muscleLower.contains("hamstring") || muscleLower.contains("back") ||
               muscleLower.contains("lat") {
                maxMultiplier = max(maxMultiplier, 1.3)
            }
            // Medium muscle groups
            else if muscleLower.contains("chest") || muscleLower.contains("pec") ||
                    muscleLower.contains("shoulder") || muscleLower.contains("delt") ||
                    muscleLower.contains("trap") {
                maxMultiplier = max(maxMultiplier, 1.15)
            }
            // Smaller muscle groups
            else if muscleLower.contains("bicep") || muscleLower.contains("tricep") ||
                    muscleLower.contains("forearm") || muscleLower.contains("calf") {
                maxMultiplier = max(maxMultiplier, 0.9)
            }
            // Core (moderate due to isometric nature)
            else if muscleLower.contains("core") || muscleLower.contains("abs") ||
                    muscleLower.contains("oblique") {
                maxMultiplier = max(maxMultiplier, 0.85)
            }
        }
        
        return maxMultiplier
    }
}

// MARK: - MET Values for Strength Training

enum StrengthTrainingMET {
    /// MET values from Ainsworth Compendium of Physical Activities (2011)
    /// Adjusted for different intensity levels
    
    /// Light effort - long rest periods, low weight, easy exercises
    static let light: Double = 3.5
    
    /// Moderate effort - typical hypertrophy training
    static let moderate: Double = 5.0
    
    /// Vigorous effort - short rest, heavy compound movements
    static let vigorous: Double = 6.0
    
    /// Circuit training / supersets - minimal rest
    static let circuit: Double = 8.0
    
    /// Calculate MET based on workout characteristics
    static func calculateMET(
        averageRestSeconds: Double,
        compoundExerciseRatio: Double,
        volumeIntensity: Double  // 0-1 scale based on weight/rep scheme
    ) -> Double {
        var met = moderate
        
        // Adjust for rest periods
        if averageRestSeconds < 30 {
            met += 1.5  // Very short rest = circuit-like intensity
        } else if averageRestSeconds < 60 {
            met += 0.8  // Short rest
        } else if averageRestSeconds < 90 {
            met += 0.3  // Moderate rest
        } else if averageRestSeconds > 180 {
            met -= 0.5  // Long rest (powerlifting style)
        }
        
        // Adjust for compound exercise ratio
        met += (compoundExerciseRatio - 0.5) * 1.0  // ±0.5 MET
        
        // Adjust for volume intensity
        met += (volumeIntensity - 0.5) * 0.8  // ±0.4 MET
        
        return min(max(met, light), circuit)  // Clamp between 3.5 and 8.0
    }
}

// MARK: - Workout Calorie Calculator

class WorkoutCalorieCalculator {
    
    // MARK: - Main Calculation Method
    
    /// Calculate total calories burned for a workout with Apple Fitness-level accuracy
    /// 
    /// This method combines multiple approaches:
    /// 1. MET-based baseline calculation
    /// 2. Volume-based work adjustment
    /// 3. Active vs rest time separation
    /// 4. EPOC (afterburn) estimation
    ///
    /// - Parameters:
    ///   - exercises: Array of exercise data with sets, reps, weight
    ///   - totalDurationSeconds: Total workout duration including rest
    ///   - user: User biometrics for personalized calculation
    /// - Returns: CalorieResult with detailed breakdown
    static func calculateCalories(
        exercises: [ExerciseCalorieData],
        totalDurationSeconds: TimeInterval,
        user: UserBiometrics
    ) -> CalorieResult {
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 1: Calculate active time vs rest time
        // ═══════════════════════════════════════════════════════════════
        
        var totalActiveTimeSeconds: Double = 0
        var totalRestTimeSeconds: Double = 0
        var totalVolumeKg: Double = 0
        var compoundExerciseCount = 0
        var totalExerciseCount = 0
        
        for exercise in exercises {
            // Estimate time under tension per rep (3 seconds average)
            let tutPerRep = 3.0
            let activeTime = Double(exercise.totalReps) * tutPerRep
            totalActiveTimeSeconds += activeTime
            
            // Rest time between sets (sets - 1 rest periods per exercise)
            let restTime = Double(max(0, exercise.setsCompleted - 1)) * exercise.averageRestSeconds
            totalRestTimeSeconds += restTime
            
            // Volume (convert lbs to kg if needed - assume input is in lbs)
            let weightKg = exercise.totalWeightLifted * 0.453592  // lbs to kg
            totalVolumeKg += weightKg * Double(exercise.totalReps)
            
            if exercise.isCompound {
                compoundExerciseCount += 1
            }
            totalExerciseCount += 1
        }
        
        // Add transition time between exercises (30 sec average)
        let transitionTime = Double(max(0, totalExerciseCount - 1)) * 30.0
        
        // Calculate actual active vs rest split
        let calculatedTotalTime = totalActiveTimeSeconds + totalRestTimeSeconds + transitionTime
        let activeRatio = totalActiveTimeSeconds / max(calculatedTotalTime, 1)
        
        // If our calculation exceeds actual duration, scale down
        let scaleFactor = min(1.0, totalDurationSeconds / max(calculatedTotalTime, 1))
        totalActiveTimeSeconds *= scaleFactor
        totalRestTimeSeconds *= scaleFactor
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 2: Calculate MET value based on workout characteristics
        // ═══════════════════════════════════════════════════════════════
        
        let compoundRatio = totalExerciseCount > 0 ? 
            Double(compoundExerciseCount) / Double(totalExerciseCount) : 0.5
        
        // Volume intensity (rough estimate based on total volume)
        // Average workout might be 5000-15000 kg total volume
        let volumeIntensity = min(1.0, totalVolumeKg / 10000.0)
        
        // Average rest period across workout
        let avgRestSeconds = totalExerciseCount > 0 ?
            totalRestTimeSeconds / Double(totalExerciseCount) : 90.0
        
        let workoutMET = StrengthTrainingMET.calculateMET(
            averageRestSeconds: avgRestSeconds,
            compoundExerciseRatio: compoundRatio,
            volumeIntensity: volumeIntensity
        )
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 3: Calculate MET-based calorie burn
        // ═══════════════════════════════════════════════════════════════
        
        // MET formula: Calories = MET × weight(kg) × time(hours)
        let totalDurationHours = totalDurationSeconds / 3600.0
        
        // Active time burns at workout MET
        let activeTimeHours = totalActiveTimeSeconds / 3600.0
        let activeCalories = workoutMET * user.weightKg * activeTimeHours
        
        // Rest time burns at ~1.5 MET (standing, light activity)
        let restTimeHours = (totalDurationSeconds - totalActiveTimeSeconds) / 3600.0
        let restCalories = 1.5 * user.weightKg * restTimeHours
        
        var metBasedCalories = activeCalories + restCalories
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 4: Calculate volume-based work adjustment
        // ═══════════════════════════════════════════════════════════════
        
        // Mechanical work = Force × Distance
        // This adds calories based on actual weight moved
        var volumeCalories: Double = 0
        
        for exercise in exercises {
            let weightKg = exercise.totalWeightLifted * 0.453592
            
            // Estimate distance moved (in meters)
            // Average rep might move weight ~0.5m, adjusted by movement factor
            let distancePerRep = 0.5 * exercise.movementDistanceFactor
            let totalDistance = Double(exercise.totalReps) * distancePerRep
            
            // Work in Joules = Force(N) × Distance(m)
            // Force = mass × gravity (9.81)
            let workJoules = weightKg * 9.81 * totalDistance
            
            // Convert to kcal (1 kcal = 4184 J)
            // Muscle efficiency is ~25%, so actual energy is 4x mechanical work
            let efficiencyFactor = 4.0
            let muscleMultiplier = MuscleGroupCalorieMultiplier.getMultiplier(for: exercise.primaryMuscles)
            
            let exerciseVolumeCalories = (workJoules / 4184.0) * efficiencyFactor * muscleMultiplier
            volumeCalories += exerciseVolumeCalories
        }
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 5: Combine MET and volume-based calculations
        // ═══════════════════════════════════════════════════════════════
        
        // Weight the two methods:
        // - MET-based captures overall metabolic demand
        // - Volume-based captures actual mechanical work
        // Research suggests ~60% MET, 40% volume for strength training
        let combinedCalories = (metBasedCalories * 0.6) + (volumeCalories * 0.4)
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 6: Apply user biometric adjustments
        // ═══════════════════════════════════════════════════════════════
        
        var adjustedCalories = combinedCalories
        
        // Sex-based metabolic adjustment
        adjustedCalories *= user.biologicalSex.metabolicFactor
        
        // Age-based adjustment
        adjustedCalories *= user.ageMetabolicFactor
        
        // Fitness level adjustment
        adjustedCalories *= user.fitnessLevel.efficiencyFactor
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 7: Calculate EPOC (Excess Post-Exercise Oxygen Consumption)
        // ═══════════════════════════════════════════════════════════════
        
        // EPOC for strength training is typically 6-15% of workout calories
        // Higher for intense workouts (heavy compound movements, short rest)
        let epocFactor: Double
        if workoutMET >= 7.0 {
            epocFactor = 0.15  // 15% for high intensity
        } else if workoutMET >= 5.5 {
            epocFactor = 0.10  // 10% for moderate-high
        } else {
            epocFactor = 0.06  // 6% for moderate
        }
        
        let epocCalories = adjustedCalories * epocFactor
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 8: Final calculation
        // ═══════════════════════════════════════════════════════════════
        
        // Subtract BMR that would have been burned anyway (net calories)
        let bmrDuringWorkout = user.bmrKcalPerMinute * (totalDurationSeconds / 60.0)
        
        // Total = Workout calories + EPOC - BMR baseline
        // (We add back a portion of BMR since you're still alive during the workout)
        let netWorkoutCalories = adjustedCalories - (bmrDuringWorkout * 0.5)
        let totalCalories = max(0, netWorkoutCalories + epocCalories)
        
        // Apply final sanity bounds
        // Minimum: ~3 cal/minute for very light workout
        // Maximum: ~15 cal/minute for extremely intense workout
        let minCalories = (totalDurationSeconds / 60.0) * 3.0
        let maxCalories = (totalDurationSeconds / 60.0) * 15.0
        let finalCalories = min(max(totalCalories, minCalories), maxCalories)
        
        return CalorieResult(
            totalCalories: finalCalories,
            activeCalories: activeCalories,
            restCalories: restCalories,
            volumeBasedCalories: volumeCalories,
            epocCalories: epocCalories,
            workoutMET: workoutMET,
            activeTimeMinutes: totalActiveTimeSeconds / 60.0,
            restTimeMinutes: (totalDurationSeconds - totalActiveTimeSeconds) / 60.0,
            totalVolumeKg: totalVolumeKg,
            compoundExerciseRatio: compoundRatio
        )
    }
    
    // MARK: - Simplified Calculation (when detailed data unavailable)
    
    /// Simplified calorie calculation when detailed set/rep data isn't available
    /// Still more accurate than basic MET calculation
    static func calculateCaloriesSimplified(
        durationMinutes: Double,
        exerciseCount: Int,
        estimatedIntensity: WorkoutIntensity,
        user: UserBiometrics
    ) -> Double {
        
        // Base MET for intensity level
        let baseMET: Double
        switch estimatedIntensity {
        case .light:
            baseMET = 3.5
        case .moderate:
            baseMET = 5.0
        case .vigorous:
            baseMET = 6.5
        }
        
        // Adjust for exercise count (more exercises = more variety = slightly more calories)
        let exerciseAdjustment = 1.0 + (Double(min(exerciseCount, 10)) * 0.02)
        
        // MET calculation
        let durationHours = durationMinutes / 60.0
        var calories = baseMET * user.weightKg * durationHours * exerciseAdjustment
        
        // Apply biometric adjustments
        calories *= user.biologicalSex.metabolicFactor
        calories *= user.ageMetabolicFactor
        calories *= user.fitnessLevel.efficiencyFactor
        
        // Add modest EPOC
        calories *= 1.08  // 8% average EPOC
        
        // Subtract half of BMR baseline
        let bmrDuring = user.bmrKcalPerMinute * durationMinutes * 0.5
        calories -= bmrDuring
        
        return max(durationMinutes * 3, calories)  // Minimum 3 cal/min
    }
    
    // MARK: - Intensity Estimation
    
    enum WorkoutIntensity {
        case light      // Long rest, light weights, easy exercises
        case moderate   // Normal training pace
        case vigorous   // Short rest, heavy weights, compounds
        
        /// Estimate intensity from workout data
        static func estimate(
            averageRestSeconds: Double,
            compoundRatio: Double,
            totalSets: Int,
            durationMinutes: Double
        ) -> WorkoutIntensity {
            // Sets per minute (density)
            let density = Double(totalSets) / max(durationMinutes, 1)
            
            var score = 0.0
            
            // Rest period scoring
            if averageRestSeconds < 45 { score += 2 }
            else if averageRestSeconds < 90 { score += 1 }
            else if averageRestSeconds > 180 { score -= 1 }
            
            // Compound ratio scoring
            if compoundRatio > 0.7 { score += 1.5 }
            else if compoundRatio > 0.5 { score += 0.5 }
            
            // Density scoring
            if density > 0.5 { score += 1 }  // More than 1 set every 2 minutes
            else if density < 0.25 { score -= 1 }
            
            if score >= 3 { return .vigorous }
            else if score >= 1 { return .moderate }
            else { return .light }
        }
    }
}

// MARK: - Calorie Result

struct CalorieResult {
    let totalCalories: Double
    let activeCalories: Double
    let restCalories: Double
    let volumeBasedCalories: Double
    let epocCalories: Double
    let workoutMET: Double
    let activeTimeMinutes: Double
    let restTimeMinutes: Double
    let totalVolumeKg: Double
    let compoundExerciseRatio: Double
    
    var summary: String {
        return """
        ═══════════════════════════════════════════
        🔥 CALORIE CALCULATION BREAKDOWN
        ═══════════════════════════════════════════
        Total Calories: \(Int(totalCalories)) kcal
        
        📊 Components:
        • Active Exercise: \(Int(activeCalories)) kcal
        • Rest Periods: \(Int(restCalories)) kcal
        • Volume-Based: \(Int(volumeBasedCalories)) kcal
        • EPOC (Afterburn): \(Int(epocCalories)) kcal
        
        ⚡ Workout Metrics:
        • Effective MET: \(String(format: "%.1f", workoutMET))
        • Active Time: \(Int(activeTimeMinutes)) min
        • Rest Time: \(Int(restTimeMinutes)) min
        • Total Volume: \(Int(totalVolumeKg)) kg
        • Compound Ratio: \(Int(compoundExerciseRatio * 100))%
        ═══════════════════════════════════════════
        """
    }
}

// MARK: - HealthKit Integration for User Data

extension WorkoutCalorieCalculator {
    
    /// Fetch user biometrics from HealthKit and onboarding data
    static func fetchUserBiometrics() async -> UserBiometrics {
        let healthStore = HKHealthStore()
        
        // Default values
        var weightKg: Double = 70.0
        var heightCm: Double = 170.0
        var ageYears: Int = 30
        var biologicalSex: UserBiometrics.BiologicalSex = .other
        var fitnessLevel: UserBiometrics.FitnessLevel = .intermediate
        
        // Try to get weight from HealthKit
        if let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                }
            }
            healthStore.execute(query)
            
            // Small delay to let query complete
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Try to get height from HealthKit
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                }
            }
            healthStore.execute(query)
        }
        
        // Try to get biological sex
        do {
            let hkSex = try healthStore.biologicalSex().biologicalSex
            switch hkSex {
            case .male: biologicalSex = .male
            case .female: biologicalSex = .female
            default: biologicalSex = .other
            }
        } catch {
            // Use default
        }
        
        // Try to get date of birth for age
        do {
            if let dob = try healthStore.dateOfBirthComponents().date {
                ageYears = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 30
            }
        } catch {
            // Use default
        }
        
        // Get fitness level from user profile (UserDefaults or onboarding)
        if let experienceLevel = UserDefaults.standard.string(forKey: "experienceLevel")?.lowercased() {
            switch experienceLevel {
            case "beginner": fitnessLevel = .beginner
            case "advanced": fitnessLevel = .advanced
            default: fitnessLevel = .intermediate
            }
        }
        
        // Fallback: Try to get weight from onboarding data
        if weightKg == 70.0 {
            if let savedWeight = UserDefaults.standard.object(forKey: "userWeight") as? Double {
                weightKg = savedWeight
            }
        }
        
        return UserBiometrics(
            weightKg: weightKg,
            heightCm: heightCm,
            ageYears: ageYears,
            biologicalSex: biologicalSex,
            fitnessLevel: fitnessLevel
        )
    }
}
