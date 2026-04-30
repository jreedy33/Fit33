import SwiftUI
import CoreData

extension ActiveWorkoutView {
    func saveWorkoutData() {
        // Update the workout with completion data
        workout.isCompleted = true
        workout.duration = Int32(elapsedTime)
        
        // Generate custom workout name based on completed exercises
        workout.name = generateCustomWorkoutName()
        
        // Save workout notes
        if !workoutNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workout.notes = workoutNotes
        }
        
        // ⚠️ IMPORTANT: Clear any existing WorkoutExercise entries to prevent duplicates
        // This can happen if finishWorkout() is somehow called multiple times
        if let existingExercises = workout.exercises as? Set<WorkoutExercise>, !existingExercises.isEmpty {
            AppLogger.warning("⚠️ [SAVE] Clearing \(existingExercises.count) existing workout exercises to prevent duplicates", category: .workout)
            for existingExercise in existingExercises {
                viewContext.delete(existingExercise)
            }
        }
        
        // Create WorkoutExercise relationships and save all sets
        for (exerciseIndex, exercise) in exercises.enumerated() {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = workoutManager.exerciseSetsData[exerciseId],
                  !sets.isEmpty else { continue }
            
            // Create WorkoutExercise entity
            let workoutExercise = WorkoutExercise(context: viewContext)
            workoutExercise.id = UUID()
            workoutExercise.order = Int16(exerciseIndex)
            workoutExercise.workout = workout
            workoutExercise.exercise = exercise
            
            // Create sets for this exercise
            for (setIndex, setData) in sets.enumerated() {
                // Only save completed sets
                guard setData.isCompleted else { continue }
                
                let workoutSet = WorkoutSet(context: viewContext)
                workoutSet.id = UUID()
                workoutSet.setNumber = Int16(setIndex + 1)
                workoutSet.weight = setData.weight  // Double - preserves decimals like 187.5
                workoutSet.reps = Int16(setData.reps)
                workoutSet.isCompleted = setData.isCompleted
                workoutSet.completedAt = setData.completedAt  // wall-clock for pacing analysis (#156)
                workoutSet.restTime = Int32(setData.restTime)
                workoutSet.setType = setData.setType.rawValue  // Save set type (Warmup, Dropset, Failure, etc.)
                workoutSet.workoutExercise = workoutExercise
                
                #if DEBUG
                AppLogger.debug("💾 Saving set \(setIndex + 1): weight=\(setData.weight) (Double), reps=\(setData.reps)", category: .workout)
                #endif
            }
        }
        
        do {
            try viewContext.save()
            AppLogger.debug("✅ Workout data saved successfully!", category: .workout)
            
            // 🔄 Record to SmartVariantRotationEngine for intelligent recommendations
            recordWorkoutToVariantEngine()
            
            // Sync workout to cloud (in background)
            // Note: Exercise history is saved separately in finishWorkout() with captured data
            Task {
                await syncWorkoutToCloud()
            }
        } catch {
            AppLogger.error("❌ Error saving workout: \(error)", category: .workout)
        }
    }
    
    /// Record workout completion to SmartVariantRotationEngine for smarter recommendations
    func recordWorkoutToVariantEngine() {
        var exerciseData: [(name: String, family: String, setsCompleted: Int, equipment: String)] = []
        var musclesTrained: Set<String> = []
        
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = workoutManager.exerciseSetsData[exerciseId] else { continue }
            
            let completedSets = sets.filter { $0.isCompleted }.count
            let exerciseName = exercise.name ?? ""
            let exerciseFamily = exercise.value(forKey: "exerciseFamily") as? String ?? ""
            let equipment = exercise.equipment ?? ""
            
            // Only count exercises with at least 1 completed set
            if completedSets > 0 {
                exerciseData.append((
                    name: exerciseName,
                    family: exerciseFamily,
                    setsCompleted: completedSets,
                    equipment: equipment
                ))
                
                // Track muscles trained
                if let muscles = exercise.getMuscleGroups() {
                    musclesTrained.formUnion(muscles.map { $0.lowercased() })
                }
            }
        }
        
        // Record to variant engine
        Task { @MainActor in
            SmartVariantRotationEngine.shared.recordWorkoutCompletion(
                exercises: exerciseData,
                musclesTrained: Array(musclesTrained)
            )
        }
    }
    
    /// 🍎 Save workout to Apple Health - Fills Exercise Ring!
    /// Uses Apple Fitness-quality calorie calculation and persists calories to Core Data
    func saveWorkoutToAppleHealth(startDate: Date, duration: TimeInterval, exerciseCount: Int) {
        // Capture calorie data synchronously while exerciseSetsData is still available.
        // The async Task below may run after SwiftUI invalidates this view.
        let exerciseCalorieData = buildExerciseCalorieData()

        // Always calculate and store calories locally, even if HealthKit sync is off
        Task {
            let calorieResult = await HealthKitManager.shared.calculateDetailedCalories(
                exercises: exerciseCalorieData,
                totalDurationSeconds: duration
            )
            
            // Persist calories to Core Data so they show in recent activity
            await MainActor.run {
                workout.caloriesBurned = calorieResult.totalCalories
                do {
                    try workout.managedObjectContext?.save()
                    AppLogger.debug("🔥 Calories saved to Core Data: \(Int(calorieResult.totalCalories))", category: .workout)
                } catch {
                    AppLogger.error("Failed to save calories to Core Data: \(error)", category: .workout)
                }
            }
            
            // Update cloud record with calculated calories (targeted update, not a full re-save)
            if SupabaseManager.shared.isAuthenticated, let workoutId = workout.id?.uuidString {
                do {
                    try await SupabaseManager.shared.updateWorkoutCalories(
                        workoutId: workoutId,
                        calories: calorieResult.totalCalories
                    )
                } catch {
                    AppLogger.error("Failed to update cloud workout calories: \(error)", category: .network)
                }
            }
            
            // Save to Apple Health if authorized and enabled
            guard HealthKitManager.shared.saveWorkoutsToHealth else {
                AppLogger.warning("🍎 [APPLE HEALTH] Skipping HealthKit save - user disabled Health sync", category: .workout)
                return
            }
            
            guard HealthKitManager.shared.isAuthorized else {
                AppLogger.warning("🍎 [APPLE HEALTH] Skipping HealthKit save - not authorized", category: .auth)
                return
            }
            
            do {
                let workoutType = determineWorkoutType()
                let workoutName = workout.name ?? generateCustomWorkoutName()
                
                try await HealthKitManager.shared.saveWorkoutToHealth(
                    workoutName: workoutName,
                    startDate: startDate,
                    endDate: Date(),
                    durationSeconds: duration,
                    caloriesBurned: calorieResult.totalCalories,
                    exerciseCount: exerciseCount,
                    workoutType: workoutType
                )
                
                AppLogger.debug("🍎 [APPLE HEALTH] Workout saved! Exercise ring filled 💚", category: .workout)
                AppLogger.debug("🔥 Calories: \(Int(calorieResult.totalCalories)) (MET: \(String(format: "%.1f", calorieResult.workoutMET)))", category: .workout)
                
            } catch {
                AppLogger.error("⚠️ [APPLE HEALTH] Could not save workout: \(error.localizedDescription)", category: .workout)
            }
        }
    }
    
    /// Build detailed exercise data for accurate calorie calculation
    func buildExerciseCalorieData() -> [ExerciseCalorieData] {
        var exerciseData: [ExerciseCalorieData] = []
        
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = workoutManager.exerciseSetsData[exerciseId] else { continue }
            
            let completedSets = sets.filter { $0.isCompleted }
            guard !completedSets.isEmpty else { continue }
            
            // Calculate totals
            let totalReps = completedSets.reduce(0) { $0 + $1.reps }
            let totalWeight = completedSets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            
            // Get average rest time (use default if not tracked)
            let avgRestSeconds: Double = 90.0  // Default rest time
            
            // Estimate time under tension (3 sec per rep average)
            let tutSeconds = Double(totalReps) * 3.0
            
            // Determine if compound exercise
            let isCompound = isCompoundExercise(exercise)
            
            // Get primary muscles
            let primaryMuscles = exercise.getMuscleGroups() ?? []
            
            let data = ExerciseCalorieData(
                exerciseName: exercise.name ?? "Unknown",
                equipment: exercise.equipment ?? "",
                primaryMuscles: primaryMuscles,
                setsCompleted: completedSets.count,
                totalReps: totalReps,
                totalWeightLifted: totalWeight,
                isCompound: isCompound,
                averageRestSeconds: avgRestSeconds,
                timeUnderTensionSeconds: tutSeconds
            )
            
            exerciseData.append(data)
        }
        
        return exerciseData
    }
    
    /// Determine if an exercise is a compound movement
    func isCompoundExercise(_ exercise: Exercise) -> Bool {
        let name = (exercise.name ?? "").lowercased()
        let compoundKeywords = [
            "squat", "deadlift", "bench press", "row", "press", "pull up", "pullup",
            "chin up", "chinup", "dip", "lunge", "clean", "snatch", "thruster",
            "push up", "pushup", "overhead press", "military press"
        ]
        
        return compoundKeywords.contains { name.contains($0) }
    }
    
    /// Determine the workout type for Apple Health based on exercises
    func determineWorkoutType() -> HealthKitManager.WorkoutActivityType {
        // Analyze the exercises to determine workout type
        var hasStrengthExercises = false
        var hasCardioExercises = false
        var hasCoreExercises = false
        
        for exercise in exercises {
            let name = (exercise.name ?? "").lowercased()
            let category = (exercise.category ?? "").lowercased()
            let muscles = (exercise.getMuscleGroups() ?? []).joined(separator: " ").lowercased()
            
            // Check for cardio exercises
            if name.contains("run") || name.contains("jump") || name.contains("burpee") ||
               name.contains("cardio") || name.contains("row") && name.contains("machine") ||
               category.contains("cardio") {
                hasCardioExercises = true
            }
            
            // Check for core exercises
            if muscles.contains("core") || muscles.contains("abs") || muscles.contains("oblique") ||
               name.contains("plank") || name.contains("crunch") || name.contains("situp") {
                hasCoreExercises = true
            }
            
            // Check for strength exercises
            if name.contains("press") || name.contains("curl") || name.contains("squat") ||
               name.contains("deadlift") || name.contains("row") || name.contains("fly") ||
               name.contains("extension") || name.contains("raise") {
                hasStrengthExercises = true
            }
        }
        
        // Determine primary type
        if hasStrengthExercises && hasCardioExercises {
            return .functionalTraining  // Mixed workout
        } else if hasCardioExercises && !hasStrengthExercises {
            return .cardio
        } else if hasCoreExercises && !hasStrengthExercises {
            return .coreTraining
        } else {
            return .strengthTraining  // Default for weight training
        }
    }
    
    /// Save exercise performance history to the cloud for previous set tracking and PRs
    /// This version uses captured data to avoid race condition with workoutManager clearing
    func saveExercisePerformanceHistoryWithData(
        exercises: [Exercise],
        setsData: [String: [WorkoutSetData]],
        workout: Workout,
        elapsedTime: TimeInterval
    ) async {
        AppLogger.debug("📊 [HISTORY SAVE] Starting exercise history save...", category: .workout)
        AppLogger.debug("📊 [HISTORY SAVE] User authenticated: \(SupabaseManager.shared.isAuthenticated)", category: .network)
        AppLogger.debug("📊 [HISTORY SAVE] User ID: \(SupabaseManager.shared.currentUser?.id.uuidString ?? "nil")", category: .network)
        AppLogger.debug("📊 [HISTORY SAVE] Captured sets data count: \(setsData.count)", category: .workout)
        
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.error("❌ [HISTORY SAVE] User not authenticated, skipping exercise history save", category: .auth)
            return
        }
        
        AppLogger.debug("📊 [HISTORY SAVE] Processing \(exercises.count) exercises...", category: .workout)
        
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = setsData[exerciseId],
                  !sets.isEmpty else {
                AppLogger.warning("⏭️ [HISTORY SAVE] Skipping exercise (no sets data): \(exercise.name ?? "Unknown") - ID: \(exercise.id?.uuidString.prefix(8) ?? "nil")", category: .workout)
                continue
            }
            
            // Only save if there are completed sets
            let completedSets = sets.filter { $0.isCompleted && ($0.weight > 0 || $0.reps > 0) }
            guard !completedSets.isEmpty else {
                AppLogger.warning("⏭️ [HISTORY SAVE] Skipping exercise (no completed sets): \(exercise.name ?? "Unknown")", category: .workout)
                continue
            }
            
            AppLogger.debug("💾 [HISTORY SAVE] Saving '\(exercise.name ?? "Unknown")' - \(completedSets.count) completed sets", category: .workout)
            for (i, set) in completedSets.enumerated() {
                AppLogger.debug("   Set \(i+1): \(Int(set.weight))lbs × \(set.reps) reps (completed: \(set.isCompleted))", category: .workout)
            }
            
            do {
                try await ExerciseHistoryService.shared.saveExercisePerformance(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name ?? "Exercise",
                    exerciseCategory: exercise.category,
                    workoutId: workout.id,
                    sets: Array(sets),
                    workoutDurationSeconds: Int(elapsedTime)
                )
                AppLogger.debug("✅ [HISTORY SAVE] Successfully saved '\(exercise.name ?? "Unknown")'", category: .workout)
            } catch {
                AppLogger.error("❌ [HISTORY SAVE] Failed to save '\(exercise.name ?? "")': \(error)", category: .workout)
                AppLogger.error("❌ [HISTORY SAVE] Error details: \(String(describing: error))", category: .workout)
            }
        }
        
        AppLogger.debug("📊 [HISTORY SAVE] Exercise history save complete!", category: .workout)
    }
    
    /// Track progressions for community learning
    func trackProgressions(
        exercises: [Exercise],
        setsData: [String: [WorkoutSetData]],
        user: User,
        context: NSManagedObjectContext
    ) async {
        
        AppLogger.debug("📈 [PROGRESSION] Analyzing workout for progressions...", category: .workout)
        
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let exerciseName = exercise.name,
                  let sets = setsData[exerciseId],
                  !sets.isEmpty else { continue }
            
            // Get completed sets
            let completedSets = sets.filter { $0.isCompleted && $0.weight > 0 }
            guard !completedSets.isEmpty else { continue }
            
            // Check if this is a progression from last workout
            if let previousPerformance = fetchPreviousWorkoutSets(exerciseName: exerciseName, context: context) {
                
                // Compare current vs previous
                let currentAvgWeight = completedSets.map { $0.weight }.reduce(0, +) / Double(completedSets.count)
                let previousAvgWeight = previousPerformance.map { $0.weight }.reduce(0, +) / Double(previousPerformance.count)
                
                // If weight increased, track as successful progression!
                if currentAvgWeight > previousAvgWeight {
                    let progression = currentAvgWeight - previousAvgWeight
                    
                    AppLogger.debug("📈 [PROGRESSION] '\(exerciseName)': \(Int(previousAvgWeight))→\(Int(currentAvgWeight))lbs (+\(Int(progression)))", category: .workout)
                    
                    // Track to community database
                    await ProgressiveWorkoutIntelligence.shared.trackSuccessfulProgression(
                        exerciseName: exerciseName,
                        fromWeight: previousAvgWeight,
                        toWeight: currentAvgWeight,
                        reps: completedSets.first?.reps ?? 0,
                        userAge: Int(user.age),
                        userGender: user.gender ?? "Other",
                        userExperience: user.experienceLevel ?? "Beginner",
                        context: context
                    )
                }
            }
        }
        
        AppLogger.debug("✅ [PROGRESSION] Progression tracking complete!", category: .workout)
    }
    
    /// Fetch previous workout's sets for an exercise (for comparing progression)
    func fetchPreviousWorkoutSets(
        exerciseName: String,
        context: NSManagedObjectContext
    ) -> [(weight: Double, reps: Int)]? {
        
        let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
        request.predicate = NSPredicate(
            format: "exercise.name ==[c] %@ AND workout.isCompleted == YES",
            exerciseName
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \WorkoutExercise.workout?.date, ascending: false)
        ]
        request.fetchLimit = 2  // Get last 2 workouts (skip current, get previous)
        request.relationshipKeyPathsForPrefetching = ["sets"]
        
        do {
            let workoutExercises = try context.fetch(request)
            // Skip first (current workout), use second (previous workout)
            guard workoutExercises.count >= 2,
                  let previousSets = workoutExercises[1].sets?.allObjects as? [WorkoutSet] else {
                return nil
            }
            
            let completedSets = previousSets
                .filter { $0.isCompleted && $0.weight > 0 && ($0.setType ?? "Normal") != "Warmup" }
                .map { (weight: $0.weight, reps: Int($0.reps)) }
            
            return completedSets.isEmpty ? nil : completedSets
            
        } catch {
            return nil
        }
    }
    
    func syncWorkoutToCloud() async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("ℹ️ User not authenticated, skipping workout cloud sync", category: .network)
            return
        }
        
        // Prepare workout data for Supabase
        let workoutName = workout.name ?? generateCustomWorkoutName()
        let workoutDate = workout.date ?? Date()
        let duration = Int(workout.duration)
        let xp = Int(workout.xpEarned)
        
        // Prepare exercises data
        var exercisesData: [(name: String, sets: Int)] = []
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = workoutManager.exerciseSetsData[exerciseId] else { continue }
            
            let completedSetsCount = sets.filter { $0.isCompleted }.count
            if completedSetsCount > 0 {
                exercisesData.append((name: exercise.name ?? "Unknown", sets: completedSetsCount))
            }
        }
        
        do {
            try await SupabaseManager.shared.saveWorkout(
                name: workoutName,
                date: workoutDate,
                durationSeconds: duration,
                xpEarned: xp,
                exercises: exercisesData
            )
            AppLogger.debug("✅ Workout synced to cloud!", category: .network)
            
            // Log exercise usage for popularity tracking (invisible to users)
            await logExerciseUsageToCloud()
            
        } catch {
            AppLogger.error("❌ Error syncing workout to cloud: \(error)", category: .network)
            // Don't block the app if cloud sync fails
        }
    }
    
    func logExerciseUsageToCloud() async {
        // Determine workout type
        let workoutType: String
        let programId: String?
        
        if let activeProgram = workoutManager.activeProgram {
            workoutType = "program"
            programId = activeProgram.id
        } else if workout.name?.contains("Generated") == true {
            workoutType = "auto_generated"
            programId = nil
        } else {
            workoutType = "custom"
            programId = nil
        }
        
        // Log usage for each exercise
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let exerciseName = exercise.name,
                  let sets = workoutManager.exerciseSetsData[exerciseId] else { continue }
            
            let completedSets = sets.filter { $0.isCompleted }
            guard !completedSets.isEmpty else { continue }
            
            let totalReps = completedSets.reduce(0) { $0 + $1.reps }
            let totalWeight = completedSets.reduce(0.0) { $0 + $1.weight }
            
            do {
                try await SupabaseManager.shared.logExerciseUsage(
                    exerciseName: exerciseName,
                    exerciseId: exerciseId,
                    setsCompleted: completedSets.count,
                    totalReps: totalReps,
                    totalWeightKg: totalWeight,
                    workoutType: workoutType,
                    programId: programId
                )
            } catch {
                // Silently fail - don't block workout completion
                AppLogger.error("⚠️ Failed to log exercise usage: \(error)", category: .workout)
            }
        }
        
        AppLogger.debug("📊 Exercise usage logged for analytics", category: .workout)
    }
    
    func generateCustomWorkoutName() -> String {
        return "\(liveWorkoutName) - \(formatDate())"
    }
    
    func parseMuscleGroups(from exercise: Exercise) -> [String] {
        var muscleGroups: [String] = []
        
        // Check primary muscle group from category
        if let category = exercise.category?.lowercased() {
            switch category {
            case "chest":
                muscleGroups.append("Chest")
            case "back":
                muscleGroups.append("Back")
            case "legs", "quadriceps", "hamstrings", "calves", "glutes":
                muscleGroups.append("Legs")
            case "shoulders":
                muscleGroups.append("Shoulders")
            case "biceps", "triceps", "arms":
                muscleGroups.append("Arms")
            case "core", "abs", "abdominals":
                muscleGroups.append("Core")
            default:
                break
            }
        }
        
        // Parse from muscle groups array if available
        if let muscleGroupsArray = exercise.muscleGroups as? [String] {
            for group in muscleGroupsArray {
                let cleanGroup = group.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).capitalized
                switch cleanGroup.lowercased() {
                case "chest", "pectorals", "pecs":
                    if !muscleGroups.contains("Chest") { muscleGroups.append("Chest") }
                case "back", "lats", "latissimus", "rhomboids", "traps":
                    if !muscleGroups.contains("Back") { muscleGroups.append("Back") }
                case "legs", "quadriceps", "hamstrings", "calves", "glutes", "quads", "hams":
                    if !muscleGroups.contains("Legs") { muscleGroups.append("Legs") }
                case "shoulders", "deltoids", "delts":
                    if !muscleGroups.contains("Shoulders") { muscleGroups.append("Shoulders") }
                case "biceps", "triceps", "arms", "forearms":
                    if !muscleGroups.contains("Arms") { muscleGroups.append("Arms") }
                case "core", "abs", "abdominals", "obliques":
                    if !muscleGroups.contains("Core") { muscleGroups.append("Core") }
                default:
                    break
                }
            }
        }
        
        // Parse from exercise name if no muscle groups found
        if muscleGroups.isEmpty, let exerciseName = exercise.name?.lowercased() {
            if exerciseName.contains("chest") || exerciseName.contains("bench") || exerciseName.contains("fly") {
                muscleGroups.append("Chest")
            } else if exerciseName.contains("back") || exerciseName.contains("row") || exerciseName.contains("pull") {
                muscleGroups.append("Back")
            } else if exerciseName.contains("squat") || exerciseName.contains("leg") || exerciseName.contains("lunge") {
                muscleGroups.append("Legs")
            } else if exerciseName.contains("shoulder") || exerciseName.contains("press") && !exerciseName.contains("bench") {
                muscleGroups.append("Shoulders")
            } else if exerciseName.contains("curl") || exerciseName.contains("tricep") || exerciseName.contains("bicep") {
                muscleGroups.append("Arms")
            } else if exerciseName.contains("plank") || exerciseName.contains("crunch") || exerciseName.contains("abs") {
                muscleGroups.append("Core")
            }
        }
        
        // Default to "Mixed" if no specific muscle group identified
        if muscleGroups.isEmpty {
            muscleGroups.append("Mixed")
        }
        
        return muscleGroups
    }
    
}
