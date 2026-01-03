//
//  AdvancedIntelligenceService.swift
//  GoFit
//
//  Comprehensive intelligence tracking service that collects and analyzes:
//  - Progression velocity (how fast user gains strength)
//  - Time-of-day performance patterns
//  - Set drop-off patterns
//  - Nutrition ↔ performance correlations
//  - Steps ↔ recovery correlations
//  - Exercise swap patterns
//  - Weekly volume trends
//  - Body weight strength ratios
//  - Rest time patterns
//  - Goal progress tracking
//

import Foundation
import CoreData

// MARK: - Advanced Intelligence Service

@MainActor
class AdvancedIntelligenceService: ObservableObject {
    static let shared = AdvancedIntelligenceService()
    
    @Published var isAnalyzing = false
    @Published var lastAnalysisDate: Date?
    
    private var supabase: SupabaseClient {
        SupabaseManager.shared.supabaseClient
    }
    
    // Cached ISO8601 formatter (expensive to create)
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// Convert Date to ISO8601 string
    @inline(__always) private func dateToISO(_ date: Date) -> String {
        iso8601.string(from: date)
    }
    
    private init() {
        print("🧠 [ADVANCED INTELLIGENCE] Service initialized")
    }
    
    // MARK: - 1. PROGRESSION VELOCITY TRACKING
    
    /// Track weekly performance trends for an exercise
    func trackPerformanceTrend(
        userId: UUID,
        exerciseName: String,
        weight: Double,
        reps: Int,
        sets: Int
    ) async {
        let weekStart = getWeekStart(from: Date())
        let volume = weight * Double(reps) * Double(sets)
        
        do {
            // Upsert to aggregate weekly data
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "exercise_name": .string(exerciseName),
                "week_start": .string(dateToISO( weekStart)),
                "avg_weight": .double(weight),
                "max_weight": .double(weight),
                "total_volume": .double(volume),
                "total_sets": .integer(sets),
                "total_reps": .integer(reps * sets),
                "workout_count": .integer(1),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("user_performance_trends")
                .upsert(data, onConflict: "user_id,exercise_name,week_start")
                .execute()
            
            // Calculate progression velocity
            await calculateProgressionVelocity(userId: userId, exerciseName: exerciseName)
            
            print("📈 [INTELLIGENCE] Tracked performance: \(exerciseName) \(Int(weight))lbs × \(reps)")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to track performance: \(error)")
        }
    }
    
    /// Calculate how fast user is progressing (lbs/week)
    private func calculateProgressionVelocity(userId: UUID, exerciseName: String) async {
        do {
            struct TrendData: Decodable {
                let week_start: String
                let avg_weight: Double
            }
            
            let trends: [TrendData] = try await supabase
                .from("user_performance_trends")
                .select("week_start, avg_weight")
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .order("week_start", ascending: false)
                .limit(4)  // Last 4 weeks
                .execute()
                .value
            
            guard trends.count >= 2,
                  let newestTrend = trends.first,
                  let oldestTrend = trends.last else { return }
            
            // Calculate velocity: (newest - oldest) / weeks
            let newest = newestTrend.avg_weight
            let oldest = oldestTrend.avg_weight
            let weeks = Double(trends.count - 1)
            let velocity = (newest - oldest) / weeks
            
            // Update the latest trend with velocity
            let updateData: [String: AnyJSON] = ["velocity_lbs_per_week": .double(velocity)]
            try await supabase
                .from("user_performance_trends")
                .update(updateData)
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .eq("week_start", value: newestTrend.week_start)
                .execute()
            
            if abs(velocity) > 0.1 {
                print("📊 [INTELLIGENCE] \(exerciseName) velocity: \(String(format: "%.2f", velocity)) lbs/week")
            }
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to calculate velocity: \(error)")
        }
    }
    
    // MARK: - 2. TIME-OF-DAY PERFORMANCE
    
    /// Track workout performance by time of day
    func trackTimePerformance(
        userId: UUID,
        workoutDate: Date,
        avgWeight: Double,
        completionRate: Double,
        duration: Int,
        exerciseCount: Int,
        volume: Double,
        hadPR: Bool
    ) async {
        let hour = Calendar.current.component(.hour, from: workoutDate)
        let timeSlot = getTimeSlot(hour: hour)
        
        do {
            // Get existing data for this time slot
            struct ExistingData: Decodable {
                let workout_count: Int
                let avg_weight_multiplier: Double
                let avg_completion_rate: Double
                let avg_workout_duration: Int
                let avg_exercises_completed: Int
                let personal_records_count: Int
            }
            
            let existing: [ExistingData] = try await supabase
                .from("workout_time_performance")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("time_slot", value: timeSlot)
                .limit(1)
                .execute()
                .value
            
            let count = (existing.first?.workout_count ?? 0) + 1
            let existingMultiplier = existing.first?.avg_weight_multiplier ?? 1.0
            let existingCompletion = existing.first?.avg_completion_rate ?? 1.0
            let existingDuration = existing.first?.avg_workout_duration ?? 0
            let existingExercises = existing.first?.avg_exercises_completed ?? 0
            let existingPRs = existing.first?.personal_records_count ?? 0
            
            // Calculate running averages
            // Normalize weight to a multiplier (1.0 = baseline, higher = stronger performance)
            // Use completion rate as the multiplier instead of raw weight
            let weightMultiplier = min(2.0, max(0.5, completionRate + (hadPR ? 0.1 : 0)))
            let newMultiplier = ((existingMultiplier * Double(count - 1)) + weightMultiplier) / Double(count)
            let newCompletion = ((existingCompletion * Double(count - 1)) + completionRate) / Double(count)
            let newDuration = ((existingDuration * (count - 1)) + duration) / count
            let newExercises = ((existingExercises * (count - 1)) + exerciseCount) / count
            
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "time_slot": .string(timeSlot),
                "workout_count": .integer(count),
                "avg_weight_multiplier": .double(newMultiplier),
                "avg_completion_rate": .double(newCompletion),
                "avg_workout_duration": .integer(newDuration),
                "avg_exercises_completed": .integer(newExercises),
                "avg_volume_per_workout": .double(volume),
                "personal_records_count": .integer(existingPRs + (hadPR ? 1 : 0)),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("workout_time_performance")
                .upsert(data, onConflict: "user_id,time_slot")
                .execute()
            
            print("⏰ [INTELLIGENCE] Tracked \(timeSlot) workout performance")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to track time performance: \(error)")
        }
    }
    
    /// Get user's optimal workout time
    func getOptimalWorkoutTime(userId: UUID) async -> (timeSlot: String, multiplier: Double)? {
        do {
            struct TimePerf: Decodable {
                let time_slot: String
                let avg_weight_multiplier: Double
                let workout_count: Int
            }
            
            let results: [TimePerf] = try await supabase
                .from("workout_time_performance")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("avg_weight_multiplier", ascending: false)
                .limit(1)
                .execute()
                .value
            
            guard let best = results.first, best.workout_count >= 3 else { return nil }
            return (best.time_slot, best.avg_weight_multiplier)
        } catch {
            return nil
        }
    }
    
    // MARK: - 3. SET DROP-OFF PATTERNS
    
    /// Track which sets users complete vs skip
    func trackSetCompletion(
        userId: UUID,
        exerciseName: String,
        setsAttempted: Int,
        setsCompleted: [Bool]  // Array of completion status per set
    ) async {
        guard !setsCompleted.isEmpty else { return }
        
        do {
            // Get existing patterns
            struct ExistingPattern: Decodable {
                let sample_size: Int
                let set_1_completion_rate: Double
                let set_2_completion_rate: Double
                let set_3_completion_rate: Double
                let set_4_completion_rate: Double
                let set_5_completion_rate: Double
            }
            
            let existing: [ExistingPattern] = try await supabase
                .from("set_completion_patterns")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .limit(1)
                .execute()
                .value
            
            let sampleSize = (existing.first?.sample_size ?? 0) + 1
            
            // Calculate new rates
            func updateRate(existingRate: Double, newValue: Bool, index: Int) -> Double {
                if index >= setsCompleted.count { return existingRate }
                let newVal = newValue ? 1.0 : 0.0
                return ((existingRate * Double(sampleSize - 1)) + (setsCompleted[index] ? 1.0 : 0.0)) / Double(sampleSize)
            }
            
            let set1Rate = updateRate(existingRate: existing.first?.set_1_completion_rate ?? 1.0, newValue: setsCompleted.count > 0 ? setsCompleted[0] : true, index: 0)
            let set2Rate = updateRate(existingRate: existing.first?.set_2_completion_rate ?? 1.0, newValue: setsCompleted.count > 1 ? setsCompleted[1] : true, index: 1)
            let set3Rate = updateRate(existingRate: existing.first?.set_3_completion_rate ?? 0.9, newValue: setsCompleted.count > 2 ? setsCompleted[2] : true, index: 2)
            let set4Rate = updateRate(existingRate: existing.first?.set_4_completion_rate ?? 0.8, newValue: setsCompleted.count > 3 ? setsCompleted[3] : true, index: 3)
            let set5Rate = updateRate(existingRate: existing.first?.set_5_completion_rate ?? 0.5, newValue: setsCompleted.count > 4 ? setsCompleted[4] : true, index: 4)
            
            // Calculate average completed and optimal sets
            let avgCompleted = Double(setsCompleted.filter { $0 }.count)
            let dropOffSet = setsCompleted.firstIndex(where: { !$0 }) ?? setsCompleted.count
            let optimalSets = max(2, min(5, dropOffSet))
            
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "exercise_name": .string(exerciseName),
                "set_1_completion_rate": .double(set1Rate),
                "set_2_completion_rate": .double(set2Rate),
                "set_3_completion_rate": .double(set3Rate),
                "set_4_completion_rate": .double(set4Rate),
                "set_5_completion_rate": .double(set5Rate),
                "avg_sets_completed": .double(avgCompleted),
                "typical_drop_off_set": .integer(dropOffSet + 1),
                "optimal_set_count": .integer(optimalSets),
                "sample_size": .integer(sampleSize),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("set_completion_patterns")
                .upsert(data, onConflict: "user_id,exercise_name")
                .execute()
            
            print("📊 [INTELLIGENCE] Set patterns: \(exerciseName) - \(setsCompleted.filter { $0 }.count)/\(setsCompleted.count) completed")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to track set patterns: \(error)")
        }
    }
    
    /// Get optimal set count for user + exercise
    func getOptimalSetCount(userId: UUID, exerciseName: String) async -> Int {
        do {
            struct Pattern: Decodable {
                let optimal_set_count: Int
            }
            
            let results: [Pattern] = try await supabase
                .from("set_completion_patterns")
                .select("optimal_set_count")
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .limit(1)
                .execute()
                .value
            
            return results.first?.optimal_set_count ?? 3
        } catch {
            return 3  // Default
        }
    }
    
    // MARK: - 4. NUTRITION ↔ PERFORMANCE
    
    /// Link nutrition data to next-day workout performance
    func trackNutritionPerformanceLink(
        userId: UUID,
        date: Date,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        mealsLogged: Int
    ) async {
        let dateString = formatDate(date)
        
        do {
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "date": .string(dateString),
                "total_calories": .integer(calories),
                "total_protein_g": .integer(protein),
                "total_carbs_g": .integer(carbs),
                "total_fat_g": .integer(fat),
                "meals_logged": .integer(mealsLogged)
            ]
            
            try await supabase
                .from("nutrition_performance_link")
                .upsert(data, onConflict: "user_id,date")
                .execute()
            
            print("🍎 [INTELLIGENCE] Logged nutrition: \(protein)g protein, \(calories) cal")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to track nutrition: \(error)")
        }
    }
    
    /// Update yesterday's nutrition entry with today's workout performance
    func linkWorkoutToYesterdayNutrition(
        userId: UUID,
        performanceScore: Double,
        volume: Double,
        hadPR: Bool
    ) async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dateString = formatDate(yesterday)
        
        do {
            let updateData: [String: AnyJSON] = [
                "next_day_had_workout": .bool(true),
                "next_day_performance_score": .double(performanceScore),
                "next_day_volume": .double(volume),
                "next_day_prs": .integer(hadPR ? 1 : 0)
            ]
            try await supabase
                .from("nutrition_performance_link")
                .update(updateData)
                .eq("user_id", value: userId.uuidString)
                .eq("date", value: dateString)
                .execute()
            
            print("🔗 [INTELLIGENCE] Linked workout to yesterday's nutrition")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to link workout to nutrition: \(error)")
        }
    }
    
    // MARK: - 5. STEPS ↔ RECOVERY
    
    /// Track daily activity for recovery analysis
    func trackActivityForRecovery(userId: UUID, date: Date, steps: Int) async {
        let dateString = formatDate(date)
        let activityLevel = getActivityLevel(steps: steps)
        
        do {
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "date": .string(dateString),
                "steps": .integer(steps),
                "activity_level": .string(activityLevel)
            ]
            
            try await supabase
                .from("activity_recovery_correlation")
                .upsert(data, onConflict: "user_id,date")
                .execute()
            
            print("👣 [INTELLIGENCE] Tracked activity: \(steps) steps (\(activityLevel))")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to track activity: \(error)")
        }
    }
    
    /// Get recovery recommendation based on yesterday's activity
    func getIntelligenceRecoveryRecommendation(userId: UUID) async -> IntelligenceRecoveryRecommendation {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dateString = formatDate(yesterday)
        
        do {
            struct ActivityData: Decodable {
                let steps: Int
                let activity_level: String
            }
            
            let results: [ActivityData] = try await supabase
                .from("activity_recovery_correlation")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("date", value: dateString)
                .limit(1)
                .execute()
                .value
            
            guard let activity = results.first else {
                return IntelligenceRecoveryRecommendation(status: IntelligenceRecoveryStatus.unknown, recommendation: "No activity data", legMultiplier: 1.0, upperMultiplier: 1.0)
            }
            
            switch activity.activity_level {
            case "very_active":
                return IntelligenceRecoveryRecommendation(
                    status: IntelligenceRecoveryStatus.fatigued,
                    recommendation: "You walked \(activity.steps.formatted()) steps yesterday - consider upper body focus today",
                    legMultiplier: 0.85,
                    upperMultiplier: 1.0
                )
            case "active":
                return IntelligenceRecoveryRecommendation(
                    status: IntelligenceRecoveryStatus.moderate,
                    recommendation: "Moderate activity yesterday - you're ready for any workout",
                    legMultiplier: 0.95,
                    upperMultiplier: 1.0
                )
            case "sedentary":
                return IntelligenceRecoveryRecommendation(
                    status: IntelligenceRecoveryStatus.wellRested,
                    recommendation: "Well rested - great day for leg workout!",
                    legMultiplier: 1.05,
                    upperMultiplier: 1.0
                )
            default:
                return IntelligenceRecoveryRecommendation(
                    status: IntelligenceRecoveryStatus.normal,
                    recommendation: "Normal recovery status",
                    legMultiplier: 1.0,
                    upperMultiplier: 1.0
                )
            }
        } catch {
            return IntelligenceRecoveryRecommendation(status: IntelligenceRecoveryStatus.unknown, recommendation: "Could not fetch activity data", legMultiplier: 1.0, upperMultiplier: 1.0)
        }
    }
    
    // MARK: - 6. EXERCISE SWAP TRACKING
    
    /// Track when user swaps an exercise for another
    func trackExerciseSwap(
        userId: UUID,
        originalExercise: String,
        swappedTo: String,
        reason: IntelligenceSwapReason = .preference
    ) async {
        do {
            // Check if this swap exists
            struct ExistingSwap: Decodable {
                let times_swapped: Int
            }
            
            let existing: [ExistingSwap] = try await supabase
                .from("exercise_swap_analytics")
                .select("times_swapped")
                .eq("user_id", value: userId.uuidString)
                .eq("original_exercise", value: originalExercise)
                .eq("swapped_to_exercise", value: swappedTo)
                .limit(1)
                .execute()
                .value
            
            let timesSwapped = (existing.first?.times_swapped ?? 0) + 1
            
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "original_exercise": .string(originalExercise),
                "swapped_to_exercise": .string(swappedTo),
                "swap_reason": .string(reason.rawValue),
                "times_swapped": .integer(timesSwapped),
                "last_swap_date": .string(dateToISO( Date())),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("exercise_swap_analytics")
                .upsert(data, onConflict: "user_id,original_exercise,swapped_to_exercise")
                .execute()
            
            print("🔄 [INTELLIGENCE] Tracked swap: \(originalExercise) → \(swappedTo) (\(reason.rawValue))")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to track swap: \(error)")
        }
    }
    
    /// Get commonly swapped exercises for smart suggestions
    func getCommonSwaps(userId: UUID, exerciseName: String) async -> [String] {
        do {
            struct SwapData: Decodable {
                let swapped_to_exercise: String
                let times_swapped: Int
            }
            
            let swaps: [SwapData] = try await supabase
                .from("exercise_swap_analytics")
                .select("swapped_to_exercise, times_swapped")
                .eq("user_id", value: userId.uuidString)
                .eq("original_exercise", value: exerciseName)
                .order("times_swapped", ascending: false)
                .limit(3)
                .execute()
                .value
            
            return swaps.map { $0.swapped_to_exercise }
        } catch {
            return []
        }
    }
    
    // MARK: - 7. WEEKLY VOLUME TRENDS
    
    /// Track weekly volume per muscle group
    func trackWeeklyVolume(
        userId: UUID,
        muscleGroup: String,
        sets: Int,
        reps: Int,
        volume: Double,
        exerciseCount: Int
    ) async {
        let weekStart = getWeekStart(from: Date())
        
        do {
            // Get existing week data
            struct ExistingVolume: Decodable {
                let total_sets: Int
                let total_reps: Int
                let total_volume: Double
                let workout_count: Int
                let exercise_variety: Int
            }
            
            let existing: [ExistingVolume] = try await supabase
                .from("weekly_volume_trends")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("muscle_group", value: muscleGroup)
                .eq("week_start", value: dateToISO( weekStart))
                .limit(1)
                .execute()
                .value
            
            let totalSets = (existing.first?.total_sets ?? 0) + sets
            let totalReps = (existing.first?.total_reps ?? 0) + reps
            let totalVolume = (existing.first?.total_volume ?? 0) + volume
            let workoutCount = (existing.first?.workout_count ?? 0) + 1
            let exerciseVariety = max(existing.first?.exercise_variety ?? 0, exerciseCount)
            
            // Determine training status
            let trainingStatus = getTrainingStatus(sets: totalSets, forMuscleGroup: muscleGroup)
            
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "muscle_group": .string(muscleGroup),
                "week_start": .string(dateToISO( weekStart)),
                "total_sets": .integer(totalSets),
                "total_reps": .integer(totalReps),
                "total_volume": .double(totalVolume),
                "workout_count": .integer(workoutCount),
                "exercise_variety": .integer(exerciseVariety),
                "training_status": .string(trainingStatus),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("weekly_volume_trends")
                .upsert(data, onConflict: "user_id,muscle_group,week_start")
                .execute()
            
            print("📊 [INTELLIGENCE] Volume: \(muscleGroup) - \(totalSets) sets this week (\(trainingStatus))")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to track volume: \(error)")
        }
    }
    
    /// Get muscles that need attention (undertrained or overtrained)
    func getIntelligenceMuscleVolumeStatus(userId: UUID) async -> [IntelligenceMuscleVolumeStatus] {
        let weekStart = getWeekStart(from: Date())
        
        do {
            struct VolumeData: Decodable {
                let muscle_group: String
                let total_sets: Int
                let training_status: String
                let days_since_last_trained: Int
            }
            
            let results: [VolumeData] = try await supabase
                .from("weekly_volume_trends")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("week_start", value: dateToISO( weekStart))
                .execute()
                .value
            
            return results.map { data in
                IntelligenceMuscleVolumeStatus(
                    muscleGroup: data.muscle_group,
                    totalSets: data.total_sets,
                    status: IntelligenceTrainingStatus(rawValue: data.training_status) ?? .normal,
                    daysSinceLastTrained: data.days_since_last_trained
                )
            }
        } catch {
            return []
        }
    }
    
    // MARK: - 8. BODY WEIGHT STRENGTH RATIOS
    
    /// Update strength ratios based on performance
    func updateStrengthRatios(
        userId: UUID,
        bodyWeightKg: Double,
        exercise: String,
        weight: Double,
        reps: Int
    ) async {
        // Calculate estimated 1RM using Epley formula
        let oneRM = weight * (1 + Double(min(reps, 12)) / 30.0)
        let ratio = oneRM / (bodyWeightKg * 2.205)  // Convert to lbs for ratio
        
        do {
            // Get current ratios
            struct CurrentRatios: Decodable {
                let bench_press_ratio: Double?
                let squat_ratio: Double?
                let deadlift_ratio: Double?
                let overhead_press_ratio: Double?
            }
            
            let existing: [CurrentRatios] = try await supabase
                .from("user_strength_ratios")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("recorded_date", value: formatDate(Date()))
                .limit(1)
                .execute()
                .value
            
            var benchRatio = existing.first?.bench_press_ratio ?? 0
            var squatRatio = existing.first?.squat_ratio ?? 0
            var deadliftRatio = existing.first?.deadlift_ratio ?? 0
            var ohpRatio = existing.first?.overhead_press_ratio ?? 0
            
            // Update the appropriate ratio
            let normalizedName = exercise.lowercased()
            if normalizedName.contains("bench press") && !normalizedName.contains("incline") && !normalizedName.contains("decline") {
                benchRatio = max(benchRatio, ratio)
            } else if normalizedName.contains("squat") {
                squatRatio = max(squatRatio, ratio)
            } else if normalizedName.contains("deadlift") {
                deadliftRatio = max(deadliftRatio, ratio)
            } else if normalizedName.contains("overhead press") || normalizedName.contains("shoulder press") {
                ohpRatio = max(ohpRatio, ratio)
            }
            
            // Calculate overall strength level
            let avgRatio = (benchRatio + squatRatio + deadliftRatio) / 3.0
            let strengthLevel = getStrengthLevel(avgRatio: avgRatio)
            
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "body_weight_kg": .double(bodyWeightKg),
                "recorded_date": .string(formatDate(Date())),
                "bench_press_ratio": .double(benchRatio),
                "squat_ratio": .double(squatRatio),
                "deadlift_ratio": .double(deadliftRatio),
                "overhead_press_ratio": .double(ohpRatio),
                "bench_press_1rm": .double(normalizedName.contains("bench") ? oneRM : 0),
                "squat_1rm": .double(normalizedName.contains("squat") ? oneRM : 0),
                "deadlift_1rm": .double(normalizedName.contains("deadlift") ? oneRM : 0),
                "overhead_press_1rm": .double(normalizedName.contains("press") ? oneRM : 0),
                "overall_strength_level": .string(strengthLevel),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("user_strength_ratios")
                .upsert(data, onConflict: "user_id,recorded_date")
                .execute()
            
            if ratio > 0.5 {
                print("💪 [INTELLIGENCE] Strength ratio: \(exercise) = \(String(format: "%.2f", ratio))x bodyweight")
            }
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to update strength ratios: \(error)")
        }
    }
    
    // MARK: - 9. GOAL PROGRESS TRACKING
    
    /// Update goal progress based on workout data
    func updateGoalProgress(
        userId: UUID,
        goalType: IntelligenceGoalType,
        volumeIncrease: Double = 0,
        strengthIncrease: Double = 0,
        prsThisMonth: Int = 0,
        calorieDeficit: Int = 0,
        cardioMinutes: Int = 0,
        repsIncrease: Double = 0
    ) async {
        do {
            // Calculate progress based on goal type
            var progressPercent: Double = 0
            
            switch goalType {
            case .buildMuscle:
                // Progress based on volume increase (target: 20% increase over 12 weeks)
                progressPercent = min(100, (volumeIncrease / 0.20) * 100)
            case .getStronger:
                // Progress based on strength gains and PRs
                progressPercent = min(100, (strengthIncrease / 0.15) * 100 + Double(prsThisMonth) * 5)
            case .loseFat:
                // Progress based on consistent calorie deficit
                progressPercent = min(100, Double(calorieDeficit) / 5.0)  // 500 cal deficit = 100%
            case .improveEndurance:
                // Progress based on reps increase
                progressPercent = min(100, (repsIncrease / 0.25) * 100)
            case .generalFitness:
                progressPercent = min(100, (volumeIncrease + strengthIncrease + repsIncrease) / 0.3 * 100)
            }
            
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "goal_type": .string(goalType.rawValue),
                "progress_percent": .double(progressPercent),
                "volume_increase_percent": .double(volumeIncrease * 100),
                "strength_increase_percent": .double(strengthIncrease * 100),
                "prs_this_month": .integer(prsThisMonth),
                "avg_calorie_deficit": .integer(calorieDeficit),
                "cardio_minutes_this_week": .integer(cardioMinutes),
                "avg_reps_increase": .double(repsIncrease),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("user_goal_progress")
                .upsert(data, onConflict: "user_id,goal_type")
                .execute()
            
            print("🎯 [INTELLIGENCE] Goal progress: \(goalType.rawValue) = \(String(format: "%.0f", progressPercent))%")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to update goal progress: \(error)")
        }
    }
    
    // MARK: - 10. EXERCISE EFFECTIVENESS
    
    /// Update how effective an exercise is for this user
    func updateExerciseEffectiveness(
        userId: UUID,
        exerciseName: String,
        progressionVelocity: Double,
        completionRate: Double,
        wasReturned: Bool
    ) async {
        do {
            struct ExistingData: Decodable {
                let times_performed: Int
                let return_rate: Double
            }
            
            let existing: [ExistingData] = try await supabase
                .from("exercise_user_effectiveness")
                .select("times_performed, return_rate")
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .limit(1)
                .execute()
                .value
            
            let timesPerformed = (existing.first?.times_performed ?? 0) + 1
            let existingReturnRate = existing.first?.return_rate ?? 0
            let newReturnRate = ((existingReturnRate * Double(timesPerformed - 1)) + (wasReturned ? 1 : 0)) / Double(timesPerformed)
            
            // Calculate effectiveness score (0-100)
            let effectivenessScore = (progressionVelocity * 20) + (completionRate * 30) + (newReturnRate * 50)
            let normalizedScore = min(100, max(0, effectivenessScore))
            
            // Determine recommendations
            let shouldPrioritize = normalizedScore > 70
            let shouldReduce = normalizedScore < 30 && timesPerformed > 5
            
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "exercise_name": .string(exerciseName),
                "progression_velocity": .double(progressionVelocity),
                "completion_rate": .double(completionRate),
                "return_rate": .double(newReturnRate),
                "effectiveness_score": .double(normalizedScore),
                "should_prioritize": .bool(shouldPrioritize),
                "should_reduce": .bool(shouldReduce),
                "times_performed": .integer(timesPerformed),
                "last_performed": .string(formatDate(Date())),
                "updated_at": .string(dateToISO( Date()))
            ]
            
            try await supabase
                .from("exercise_user_effectiveness")
                .upsert(data, onConflict: "user_id,exercise_name")
                .execute()
            
            print("⭐ [INTELLIGENCE] Effectiveness: \(exerciseName) = \(String(format: "%.0f", normalizedScore))/100")
        } catch {
            print("⚠️ [INTELLIGENCE] Failed to update effectiveness: \(error)")
        }
    }
    
    /// Get most effective exercises for user
    func getMostEffectiveExercises(userId: UUID, limit: Int = 10) async -> [IntelligenceEffectiveExercise] {
        do {
            struct EffectivenessData: Decodable {
                let exercise_name: String
                let effectiveness_score: Double
                let progression_velocity: Double
                let times_performed: Int
            }
            
            let results: [EffectivenessData] = try await supabase
                .from("exercise_user_effectiveness")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gt("times_performed", value: 3)
                .order("effectiveness_score", ascending: false)
                .limit(limit)
                .execute()
                .value
            
            return results.map { data in
                IntelligenceEffectiveExercise(
                    name: data.exercise_name,
                    effectivenessScore: data.effectiveness_score,
                    progressionVelocity: data.progression_velocity,
                    timesPerformed: data.times_performed
                )
            }
        } catch {
            return []
        }
    }
    
    // MARK: - COMPREHENSIVE WORKOUT ANALYSIS
    
    /// Call this after every workout to update all intelligence
    func analyzeCompletedWorkout(
        userId: UUID,
        exercises: [(name: String, sets: [(weight: Double, reps: Int, completed: Bool)], muscleGroups: [String])],
        workoutDate: Date,
        durationMinutes: Int,
        bodyWeightKg: Double?,
        hadPR: Bool = false
    ) async {
        print("🧠 [INTELLIGENCE] Analyzing completed workout...")
        
        var totalVolume: Double = 0
        var totalSets = 0
        var completedSets = 0
        var muscleVolumes: [String: (sets: Int, reps: Int, volume: Double, exerciseCount: Int)] = [:]
        
        for exercise in exercises {
            let exerciseSets = exercise.sets
            let avgWeight = exerciseSets.map { $0.weight }.reduce(0, +) / max(1, Double(exerciseSets.count))
            let totalReps = exerciseSets.map { $0.reps }.reduce(0, +)
            let exerciseVolume = exerciseSets.map { $0.weight * Double($0.reps) }.reduce(0, +)
            let completions = exerciseSets.map { $0.completed }
            
            totalVolume += exerciseVolume
            totalSets += exerciseSets.count
            completedSets += completions.filter { $0 }.count
            
            // Track muscle group volumes
            for muscle in exercise.muscleGroups {
                var current = muscleVolumes[muscle] ?? (sets: 0, reps: 0, volume: 0, exerciseCount: 0)
                current.sets += exerciseSets.count
                current.reps += totalReps
                current.volume += exerciseVolume
                current.exerciseCount += 1
                muscleVolumes[muscle] = current
            }
            
            // 1. Track performance trend
            await trackPerformanceTrend(
                userId: userId,
                exerciseName: exercise.name,
                weight: avgWeight,
                reps: totalReps / max(1, exerciseSets.count),
                sets: exerciseSets.count
            )
            
            // 3. Track set completion patterns
            await trackSetCompletion(
                userId: userId,
                exerciseName: exercise.name,
                setsAttempted: exerciseSets.count,
                setsCompleted: completions
            )
            
            // 8. Update strength ratios if we have body weight
            if let bw = bodyWeightKg, avgWeight > 0 {
                await updateStrengthRatios(
                    userId: userId,
                    bodyWeightKg: bw,
                    exercise: exercise.name,
                    weight: avgWeight,
                    reps: totalReps / max(1, exerciseSets.count)
                )
            }
            
            // 10. Update exercise effectiveness
            await updateExerciseEffectiveness(
                userId: userId,
                exerciseName: exercise.name,
                progressionVelocity: 0,  // Calculated separately
                completionRate: Double(completions.filter { $0 }.count) / Double(max(1, completions.count)),
                wasReturned: true  // They did it again
            )
        }
        
        // 2. Track time performance
        let completionRate = Double(completedSets) / Double(max(1, totalSets))
        await trackTimePerformance(
            userId: userId,
            workoutDate: workoutDate,
            avgWeight: totalVolume / Double(max(1, totalSets)),
            completionRate: completionRate,
            duration: durationMinutes,
            exerciseCount: exercises.count,
            volume: totalVolume,
            hadPR: hadPR
        )
        
        // 4. Link to yesterday's nutrition
        await linkWorkoutToYesterdayNutrition(
            userId: userId,
            performanceScore: completionRate * 10,
            volume: totalVolume,
            hadPR: hadPR
        )
        
        // 7. Track weekly volume per muscle group
        for (muscle, data) in muscleVolumes {
            await trackWeeklyVolume(
                userId: userId,
                muscleGroup: muscle,
                sets: data.sets,
                reps: data.reps,
                volume: data.volume,
                exerciseCount: data.exerciseCount
            )
        }
        
        print("✅ [INTELLIGENCE] Workout analysis complete!")
    }
    
    // MARK: - Helper Functions
    
    private func getWeekStart(from date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private func getTimeSlot(hour: Int) -> String {
        if hour >= 5 && hour < 9 { return "early_morning" }
        if hour >= 9 && hour < 12 { return "morning" }
        if hour >= 12 && hour < 17 { return "afternoon" }
        if hour >= 17 && hour < 21 { return "evening" }
        return "night"
    }
    
    private func getActivityLevel(steps: Int) -> String {
        if steps < 3000 { return "sedentary" }
        if steps < 5000 { return "light" }
        if steps < 10000 { return "normal" }
        if steps < 15000 { return "active" }
        return "very_active"
    }
    
    private func getTrainingStatus(sets: Int, forMuscleGroup: String) -> String {
        // Optimal weekly sets per muscle group
        let optimalSets: [String: ClosedRange<Int>] = [
            "chest": 10...20,
            "back": 10...20,
            "shoulders": 8...16,
            "biceps": 6...14,
            "triceps": 6...14,
            "quadriceps": 10...18,
            "hamstrings": 8...14,
            "glutes": 8...16,
            "calves": 8...14,
            "abs": 6...12
        ]
        
        let range = optimalSets[forMuscleGroup.lowercased()] ?? 8...16
        
        if sets < range.lowerBound / 2 { return "undertrained" }
        if sets < range.lowerBound { return "normal" }
        if sets <= range.upperBound { return "optimal" }
        if sets <= Int(Double(range.upperBound) * 1.5) { return "high_volume" }
        return "overreaching"
    }
    
    private func getStrengthLevel(avgRatio: Double) -> String {
        if avgRatio < 0.5 { return "untrained" }
        if avgRatio < 0.75 { return "novice" }
        if avgRatio < 1.25 { return "intermediate" }
        if avgRatio < 1.75 { return "advanced" }
        return "elite"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - PERSONALIZED DASHBOARD RECOMMENDATION
    
    struct PersonalizedRecommendation {
        let message: String
        let icon: String
        let priority: Int  // Higher = more important
        let actionType: ActionType
        
        enum ActionType {
            case workout(muscleGroup: String?)
            case rest
            case nutrition
            case celebrate
            case general
        }
    }
    
    /// Generate a personalized, actionable recommendation for the dashboard
    func getPersonalizedRecommendation(userId: UUID, streak: Int) async -> PersonalizedRecommendation {
        // Collect all intelligence data in parallel
        async let recoveryData = getIntelligenceRecoveryRecommendation(userId: userId)
        async let volumeData = getIntelligenceMuscleVolumeStatus(userId: userId)
        async let timeData = getOptimalWorkoutTime(userId: userId)
        async let effectiveExercises = getMostEffectiveExercises(userId: userId, limit: 3)
        
        let recovery = await recoveryData
        let volumes = await volumeData
        let optimalTime = await timeData
        let topExercises = await effectiveExercises
        
        // Priority 1: Recovery status (most critical)
        if recovery.status == .fatigued {
            return PersonalizedRecommendation(
                message: "Your body needs recovery. Try stretching or light cardio today 🧘",
                icon: "bed.double.fill",
                priority: 100,
                actionType: .rest
            )
        }
        
        // Priority 2: Undertrained muscle groups
        let undertrainedMuscles = volumes.filter { $0.status == .undertrained }
        if let needsWork = undertrainedMuscles.first {
            let muscleDisplay = needsWork.muscleGroup.capitalized
            return PersonalizedRecommendation(
                message: "Your \(muscleDisplay) could use some work this week! 🎯",
                icon: "figure.strengthtraining.traditional",
                priority: 90,
                actionType: .workout(muscleGroup: needsWork.muscleGroup)
            )
        }
        
        // Priority 3: Well-rested and ready to push
        if recovery.status == .wellRested {
            return PersonalizedRecommendation(
                message: "You're well-rested! Perfect day to push harder 💪",
                icon: "bolt.fill",
                priority: 85,
                actionType: .workout(muscleGroup: nil)
            )
        }
        
        // Priority 4: Optimal workout time approaching
        if let optimal = optimalTime {
            let hour = Calendar.current.component(.hour, from: Date())
            let currentSlot = getTimeSlot(hour: hour)
            
            if optimal.timeSlot != currentSlot {
                let timeDisplay = optimal.timeSlot == "morning" ? "mornings" :
                                  optimal.timeSlot == "afternoon" ? "afternoons" : "evenings"
                return PersonalizedRecommendation(
                    message: "You perform best in the \(timeDisplay)! Plan accordingly ⏰",
                    icon: "clock.fill",
                    priority: 70,
                    actionType: .general
                )
            }
        }
        
        // Priority 5: High volume week - warn about overtraining
        let overreachingMuscles = volumes.filter { $0.status == .overreaching }
        if let overworked = overreachingMuscles.first {
            let muscleDisplay = overworked.muscleGroup.capitalized
            return PersonalizedRecommendation(
                message: "Easy on the \(muscleDisplay) - you've trained it hard! 🛡️",
                icon: "exclamationmark.triangle.fill",
                priority: 80,
                actionType: .rest
            )
        }
        
        // Priority 6: Celebrate top performer
        if let topExercise = topExercises.first, topExercise.effectivenessScore > 70 {
            let shortName = topExercise.name.components(separatedBy: " ").prefix(3).joined(separator: " ")
            return PersonalizedRecommendation(
                message: "\(shortName) is working great for you! Keep it up 🌟",
                icon: "star.fill",
                priority: 60,
                actionType: .celebrate
            )
        }
        
        // Fallback: Streak-based motivation
        return getStreakBasedRecommendation(streak: streak)
    }
    
    private func getStreakBasedRecommendation(streak: Int) -> PersonalizedRecommendation {
        switch streak {
        case 0:
            return PersonalizedRecommendation(
                message: "Start your streak today! Every journey begins with one step 🚀",
                icon: "flag.fill",
                priority: 50,
                actionType: .workout(muscleGroup: nil)
            )
        case 1:
            return PersonalizedRecommendation(
                message: "Great start! Keep the momentum going 🔥",
                icon: "flame.fill",
                priority: 50,
                actionType: .workout(muscleGroup: nil)
            )
        case 2...6:
            return PersonalizedRecommendation(
                message: "You're on fire! \(streak) days strong 💥",
                icon: "flame.fill",
                priority: 50,
                actionType: .workout(muscleGroup: nil)
            )
        case 7...13:
            return PersonalizedRecommendation(
                message: "One week down! You're building a habit 🏆",
                icon: "trophy.fill",
                priority: 50,
                actionType: .celebrate
            )
        case 14...29:
            return PersonalizedRecommendation(
                message: "Two weeks of consistency! You're unstoppable 💎",
                icon: "diamond.fill",
                priority: 50,
                actionType: .celebrate
            )
        case 30...99:
            return PersonalizedRecommendation(
                message: "Legendary \(streak)-day streak! Pure dedication 👑",
                icon: "crown.fill",
                priority: 50,
                actionType: .celebrate
            )
        default:
            return PersonalizedRecommendation(
                message: "You're a fitness machine! \(streak) days! 🏅",
                icon: "medal.fill",
                priority: 50,
                actionType: .celebrate
            )
        }
    }
}

// MARK: - Supporting Types (Prefixed to avoid conflicts)

struct IntelligenceRecoveryRecommendation {
    let status: IntelligenceRecoveryStatus
    let recommendation: String
    let legMultiplier: Double
    let upperMultiplier: Double
}

enum IntelligenceRecoveryStatus {
    case wellRested, normal, moderate, fatigued, unknown
}

enum IntelligenceSwapReason: String {
    case equipment, preference, injury, difficulty, time, unknown
}

enum IntelligenceGoalType: String {
    case buildMuscle = "build_muscle"
    case loseFat = "lose_fat"
    case getStronger = "get_stronger"
    case improveEndurance = "improve_endurance"
    case generalFitness = "general_fitness"
}

enum IntelligenceTrainingStatus: String {
    case undertrained, normal, optimal, highVolume = "high_volume", overreaching
}

struct IntelligenceMuscleVolumeStatus {
    let muscleGroup: String
    let totalSets: Int
    let status: IntelligenceTrainingStatus
    let daysSinceLastTrained: Int
}

struct IntelligenceEffectiveExercise {
    let name: String
    let effectivenessScore: Double
    let progressionVelocity: Double
    let timesPerformed: Int
}

// Import Supabase client type
import Supabase

