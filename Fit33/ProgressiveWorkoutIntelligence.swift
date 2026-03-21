import Foundation
import CoreData

// MARK: - Progressive Workout Intelligence System
// Advanced personalization that learns from individual AND community data

/// Analyzes user's workout history to generate intelligent progressive recommendations
class ProgressiveWorkoutIntelligence {
    static let shared = ProgressiveWorkoutIntelligence()
    
    private init() {}
    
    // MARK: - Program Phase Definitions
    
    enum ProgramPhase: String {
        case foundation  // Week 1: moderate intensity, form focus
        case build       // Week 2: slight volume increase
        case push        // Week 3: higher volume
        case peak        // Week 4: max intensity, failure sets
        case deload      // Week 5+: recovery, reduced volume
        
        static func from(weekNumber: Int) -> ProgramPhase {
            switch weekNumber {
            case 1: return .foundation
            case 2: return .build
            case 3: return .push
            case 4: return .peak
            default: return .deload
            }
        }
    }
    
    // MARK: - Progressive Set Recommendations
    
    /// Generate progressive set recommendations based on last workout
    /// Example: Did 45lbs×6 for 4 sets → Suggest [50×6, 50×6, 45×6, 45×6]
    func generateProgressiveSets(
        for exerciseName: String,
        targetSetCount: Int = 4,
        context: NSManagedObjectContext,
        programWeek: Int? = nil,
        prescribedReps: (min: Int, max: Int)? = nil
    ) -> [ProgressiveSetRecommendation] {
        
        // Get last workout performance
        guard let lastPerformance = fetchLastWorkoutPerformance(exerciseName: exerciseName, context: context) else {
            return []
        }
        
        AppLogger.debug("📊 Analyzing last performance for '\(exerciseName)':", category: .workout)
        AppLogger.debug("   Last workout: \(lastPerformance.sets.count) sets", category: .workout)
        if let week = programWeek {
            AppLogger.debug("   Program week: \(week) (\(ProgramPhase.from(weekNumber: week).rawValue))", category: .workout)
        }
        
        guard let analysis = analyzePerformanceForProgression(lastPerformance) else {
            return []
        }
        
        // If in a program context, use phase-aware logic
        if let week = programWeek {
            return generateProgramAwareSets(
                analysis: analysis,
                targetSetCount: targetSetCount,
                phase: ProgramPhase.from(weekNumber: week),
                prescribedReps: prescribedReps,
                exerciseName: exerciseName
            )
        }
        
        // Standalone workout: use standard progressive logic
        return generateStandaloneSets(
            analysis: analysis,
            targetSetCount: targetSetCount,
            exerciseName: exerciseName
        )
    }
    
    /// Standard progressive overload for standalone (non-program) workouts
    private func generateStandaloneSets(
        analysis: PerformanceAnalysis,
        targetSetCount: Int,
        exerciseName: String
    ) -> [ProgressiveSetRecommendation] {
        var recommendations: [ProgressiveSetRecommendation] = []
        
        if analysis.readyForProgression {
            let progressiveWeight = analysis.suggestedProgressionWeight
            let maintenanceWeight = analysis.mostConsistentWeight
            let progressiveSets = max(1, targetSetCount / 2)
            let maintenanceSets = targetSetCount - progressiveSets
            
            for i in 1...progressiveSets {
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: i,
                    weight: progressiveWeight,
                    reps: analysis.targetReps,
                    type: .progressive,
                    note: i == 1 ? "🔥 Push yourself!" : "💪 Keep going!"
                ))
            }
            for i in 1...maintenanceSets {
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: progressiveSets + i,
                    weight: maintenanceWeight,
                    reps: analysis.targetReps,
                    type: .maintenance,
                    note: "✓ Maintain form"
                ))
            }
            
            AppLogger.info("   ✅ Progressive plan: \(progressiveSets)×\(Int(progressiveWeight))lbs + \(maintenanceSets)×\(Int(maintenanceWeight))lbs", category: .workout)
            
        } else if analysis.shouldDeload {
            let deloadWeight = analysis.mostConsistentWeight * 0.9
            for i in 1...targetSetCount {
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: i,
                    weight: deloadWeight,
                    reps: analysis.targetReps + 2,
                    type: .deload,
                    note: "🧘 Deload week - focus on form"
                ))
            }
            AppLogger.warning("   ⚠️ Deload recommended: \(Int(deloadWeight))lbs for recovery", category: .workout)
            
        } else {
            let weight = analysis.mostConsistentWeight
            for i in 1...targetSetCount {
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: i,
                    weight: weight,
                    reps: analysis.targetReps,
                    type: .maintenance,
                    note: "💪 Build consistency"
                ))
            }
            AppLogger.debug("   → Maintain: \(Int(weight))lbs × \(analysis.targetReps)", category: .workout)
        }
        
        return recommendations
    }
    
    /// Program-aware progressive overload that respects periodization phases
    private func generateProgramAwareSets(
        analysis: PerformanceAnalysis,
        targetSetCount: Int,
        phase: ProgramPhase,
        prescribedReps: (min: Int, max: Int)?,
        exerciseName: String
    ) -> [ProgressiveSetRecommendation] {
        var recommendations: [ProgressiveSetRecommendation] = []
        let baseWeight = analysis.mostConsistentWeight
        let repTarget = prescribedReps.map { ($0.min + $0.max) / 2 } ?? analysis.targetReps
        
        switch phase {
        case .foundation:
            // Week 1: moderate intensity, focus on form. Use same weight, prescribed reps.
            for i in 1...targetSetCount {
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: i,
                    weight: baseWeight,
                    reps: repTarget,
                    type: .maintenance,
                    note: "📐 Foundation - nail your form"
                ))
            }
            AppLogger.debug("   📐 Foundation phase: \(Int(baseWeight))lbs × \(repTarget)", category: .workout)
            
        case .build:
            // Week 2: try progression on anchor sets (first half)
            if analysis.readyForProgression {
                let progressiveWeight = analysis.suggestedProgressionWeight
                let progressiveSets = max(1, targetSetCount / 2)
                for i in 1...progressiveSets {
                    recommendations.append(ProgressiveSetRecommendation(
                        setNumber: i,
                        weight: progressiveWeight,
                        reps: repTarget,
                        type: .progressive,
                        note: "📈 Build phase - push slightly"
                    ))
                }
                for i in (progressiveSets + 1)...targetSetCount {
                    recommendations.append(ProgressiveSetRecommendation(
                        setNumber: i,
                        weight: baseWeight,
                        reps: repTarget,
                        type: .maintenance,
                        note: "✓ Maintain form"
                    ))
                }
            } else {
                for i in 1...targetSetCount {
                    recommendations.append(ProgressiveSetRecommendation(
                        setNumber: i,
                        weight: baseWeight,
                        reps: repTarget,
                        type: .maintenance,
                        note: "📈 Build phase - build consistency"
                    ))
                }
            }
            AppLogger.debug("   📈 Build phase for '\(exerciseName)'", category: .workout)
            
        case .push:
            // Week 3: higher volume, all sets at progression weight if ready
            let weight = analysis.readyForProgression ? analysis.suggestedProgressionWeight : baseWeight
            for i in 1...targetSetCount {
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: i,
                    weight: weight,
                    reps: repTarget,
                    type: analysis.readyForProgression ? .progressive : .maintenance,
                    note: "🔥 Push phase - challenge yourself"
                ))
            }
            AppLogger.debug("   🔥 Push phase: \(Int(weight))lbs × \(repTarget)", category: .workout)
            
        case .peak:
            // Week 4: max intensity, last set to failure
            let weight = analysis.readyForProgression ? analysis.suggestedProgressionWeight : baseWeight
            for i in 1...targetSetCount {
                let isLastSet = i == targetSetCount
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: i,
                    weight: weight,
                    reps: isLastSet ? max(repTarget - 2, prescribedReps?.min ?? 4) : repTarget,
                    type: isLastSet ? .progressive : .maintenance,
                    note: isLastSet ? "⚡ Peak - go to failure!" : "💪 Keep intensity high"
                ))
            }
            AppLogger.debug("   ⚡ Peak phase: \(Int(weight))lbs, last set to failure", category: .workout)
            
        case .deload:
            // Week 5+: reduced volume and intensity for recovery
            let deloadWeight = baseWeight * 0.6
            let deloadReps = repTarget + 3
            for i in 1...targetSetCount {
                recommendations.append(ProgressiveSetRecommendation(
                    setNumber: i,
                    weight: deloadWeight,
                    reps: deloadReps,
                    type: .deload,
                    note: "🧘 Deload - light and controlled"
                ))
            }
            AppLogger.debug("   🧘 Deload phase: \(Int(deloadWeight))lbs × \(deloadReps)", category: .workout)
        }
        
        return recommendations
    }
    
    // MARK: - Performance History Analysis
    
    private func fetchLastWorkoutPerformance(
        exerciseName: String,
        context: NSManagedObjectContext
    ) -> WorkoutPerformance? {
        
        // Get last workout with this exercise
        let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
        request.predicate = NSPredicate(
            format: "exercise.name ==[c] %@ AND workout.isCompleted == YES",
            exerciseName
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \WorkoutExercise.workout?.date, ascending: false)
        ]
        request.fetchLimit = 1
        request.relationshipKeyPathsForPrefetching = ["sets", "workout"]
        
        do {
            guard let workoutExercise = try context.fetch(request).first,
                  let workout = workoutExercise.workout,
                  let date = workout.date,
                  let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else {
                return nil
            }
            
            let completedSets = sets
                .filter { $0.isCompleted && $0.weight > 0 && ($0.setType ?? "Normal") != "Warmup" }
                .sorted { $0.setNumber < $1.setNumber }
            
            guard !completedSets.isEmpty else { return nil }
            
            let setData = completedSets.map { set in
                SetPerformance(
                    setNumber: Int(set.setNumber),
                    weight: set.weight,
                    reps: Int(set.reps)
                )
            }
            
            return WorkoutPerformance(
                exerciseName: exerciseName,
                date: date,
                sets: setData
            )
            
        } catch {
            AppLogger.warning("⚠️ Error fetching last workout: \(error)", category: .workout)
            return nil
        }
    }
    
    private func analyzePerformanceForProgression(_ performance: WorkoutPerformance) -> PerformanceAnalysis? {
        let sets = performance.sets
        guard let firstSet = sets.first else { return nil }
        
        // Find most common weight used
        let weightCounts = Dictionary(grouping: sets, by: { $0.weight })
            .mapValues { $0.count }
        let mostConsistentWeight = weightCounts.max(by: { $0.value < $1.value })?.key ?? firstSet.weight
        
        // Check if they completed all sets successfully
        let setsAtConsistentWeight = sets.filter { $0.weight == mostConsistentWeight }
        let avgReps = setsAtConsistentWeight.map { $0.reps }.reduce(0, +) / max(1, setsAtConsistentWeight.count)
        let targetReps = avgReps
        
        // Progression criteria:
        // 1. Completed all sets (or lost max 1-2 reps on last set)
        // 2. Reps are in reasonable range (6-15)
        // 3. Consistency across sets
        
        let repVariance = setsAtConsistentWeight.map { abs($0.reps - avgReps) }.reduce(0, +)
        let isConsistent = repVariance <= 2 // Low variance = consistent
        
        let readyForProgression = isConsistent && avgReps >= 6 && sets.count >= 3
        
        // Check if deload needed (more than 3 weeks same weight, or failing sets)
        let lastSetReps = sets.last?.reps ?? avgReps
        let shouldDeload = lastSetReps < (avgReps - 3) // Lost 3+ reps on last set
        
        // Calculate progression weight (typically 2.5-5 lb increase)
        let increment: Double = mostConsistentWeight < 30 ? 2.5 : 5.0
        let progressionWeight = mostConsistentWeight + increment
        
        return PerformanceAnalysis(
            mostConsistentWeight: mostConsistentWeight,
            targetReps: targetReps,
            readyForProgression: readyForProgression,
            shouldDeload: shouldDeload,
            suggestedProgressionWeight: progressionWeight,
            consistency: isConsistent ? .high : .medium
        )
    }
    
    // MARK: - Community Learning (Aggregate Data)
    
    /// Save successful progression to cloud for community learning
    func trackSuccessfulProgression(
        exerciseName: String,
        fromWeight: Double,
        toWeight: Double,
        reps: Int,
        userAge: Int,
        userGender: String,
        userExperience: String,
        context: NSManagedObjectContext
    ) async {
        
        // This data is aggregated (anonymized) to help all users
        struct ProgressionData: Encodable {
            let exercise_name: String
            let from_weight: Double
            let to_weight: Double
            let reps: Int
            let progression_amount: Double
            let user_age_range: String  // "20-29", "30-39", etc
            let user_gender: String
            let user_experience: String
            let success: Bool
            let date: String
        }
        
        let ageRange = "\((userAge/10)*10)-\((userAge/10)*10+9)"
        
        let data = ProgressionData(
            exercise_name: exerciseName,
            from_weight: fromWeight,
            to_weight: toWeight,
            reps: reps,
            progression_amount: toWeight - fromWeight,
            user_age_range: ageRange,
            user_gender: userGender,
            user_experience: userExperience,
            success: true,
            date: ISO8601DateFormatter().string(from: Date())
        )
        
        // Save to Supabase for community insights
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("exercise_progressions")
                .insert(data)
                .execute()
            
            AppLogger.debug("📊 Progression tracked for community learning: \(exerciseName) \(Int(fromWeight))→\(Int(toWeight))lbs", category: .workout)
        } catch {
            AppLogger.warning("⚠️ Could not track progression: \(error)", category: .workout)
            // Non-blocking - don't throw
        }
    }
    
    /// Get community insights for an exercise
    func getCommunityProgressionInsights(
        for exerciseName: String,
        userWeight: Double,
        userAge: Int,
        userGender: String
    ) async -> CommunityProgressionInsight? {
        
        struct ProgressionRecord: Codable {
            let progression_amount: Double
            let from_weight: Double
            let to_weight: Double
        }
        
        do {
            let ageRange = "\((userAge/10)*10)-\((userAge/10)*10+9)"
            
            // Get similar users' successful progressions
            let response: [ProgressionRecord] = try await SupabaseManager.shared.supabaseClient
                .from("exercise_progressions")
                .select()
                .eq("exercise_name", value: exerciseName)
                .eq("user_gender", value: userGender)
                .eq("user_age_range", value: ageRange)
                .eq("success", value: true)
                .gte("from_weight", value: userWeight - 10) // Similar weight range
                .lte("from_weight", value: userWeight + 10)
                .order("date", ascending: false)
                .limit(50)
                .execute()
                .value
            
            guard !response.isEmpty else { return nil }
            
            // Calculate average successful progression
            let avgProgression = response.map { $0.progression_amount }.reduce(0, +) / Double(response.count)
            
            return CommunityProgressionInsight(
                averageProgression: avgProgression,
                sampleSize: response.count,
                confidence: min(1.0, Double(response.count) / 10.0) // More data = higher confidence
            )
            
        } catch {
            AppLogger.warning("⚠️ Could not fetch community insights: \(error)", category: .workout)
            return nil
        }
    }
}

// MARK: - Data Models

struct WorkoutPerformance {
    let exerciseName: String
    let date: Date
    let sets: [SetPerformance]
}

struct SetPerformance {
    let setNumber: Int
    let weight: Double
    let reps: Int
}

struct PerformanceAnalysis {
    let mostConsistentWeight: Double
    let targetReps: Int
    let readyForProgression: Bool
    let shouldDeload: Bool
    let suggestedProgressionWeight: Double
    let consistency: ConsistencyLevel
    
    enum ConsistencyLevel {
        case high, medium, low
    }
}

struct ProgressiveSetRecommendation {
    let setNumber: Int
    let weight: Double
    let reps: Int
    let type: SetType
    let note: String
    
    enum SetType {
        case progressive  // Heavier weight - push yourself
        case maintenance  // Same as last time
        case deload       // Lighter for recovery/form
    }
    
    var displayString: String {
        "\(Int(weight)) × \(reps)"
    }
}

struct CommunityProgressionInsight {
    let averageProgression: Double  // e.g., 2.5 lbs average increase
    let sampleSize: Int             // How many users contributed
    let confidence: Double          // 0-1, based on sample size
    
    var recommendedProgression: Double {
        // Use community data to suggest realistic progression
        return averageProgression
    }
}


