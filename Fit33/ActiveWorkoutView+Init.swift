import SwiftUI
import CoreData

extension ActiveWorkoutView {
    /// ⚡️ INSTANT: Apply warmup data SYNCHRONOUSLY before first render
    /// This is FAST (< 1ms) - just dictionary lookups and assignments
    func applyWarmupDataInstantly() {
        let warmupService = PreviewWarmupService.shared
        
        // Only proceed if warmup completed on the preview screen
        guard warmupService.isWarmedUp else {
            #if DEBUG
            AppLogger.debug("⚡️ [INSTANT] Warmup not ready - will apply in deferred init", category: .workout)
            #endif
            return
        }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Apply all pre-warmed data SYNCHRONOUSLY
        var appliedCount = 0
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let exerciseName = exercise.name else { continue }
            
            if let preWarmedSets = warmupService.getPreviousSets(forExerciseId: exerciseId, exerciseName: exerciseName) {
                previousExerciseSets[exerciseId] = preWarmedSets
                appliedCount += 1
            }
        }
        
        #if DEBUG
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        AppLogger.debug("⚡️ [INSTANT] Applied \(appliedCount)/\(exercises.count) exercises in \(String(format: "%.2f", elapsed))ms", category: .performance)
        #endif
    }

    func initializeWorkout() {
        // GUARD: Prevent duplicate initialization (SwiftUI may call onAppear multiple times)
        guard !initializationComplete else {
            #if DEBUG
            AppLogger.warning("⏭️ [PERF] initializeWorkout() - Already initialized, skipping", category: .performance)
            #endif
            return
        }
        initializationComplete = true
        
        #if DEBUG
        AppLogger.debug("🚀 [PERF] initializeWorkout() - Scheduling deferred work", category: .performance)
        #endif
        
        // Defer SLOW operations (analytics, network, smart recs) to next frame
        DispatchQueue.main.async { [self] in
            performDeferredInitialization()
        }
    }
    
    /// Performs initialization work after the first frame has rendered
    func performDeferredInitialization() {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("🚀 [PERF] performDeferredInitialization() - Starting", category: .performance)
        #endif
        
        // Log screen with unique ID (non-blocking)
        SessionLogManager.shared.logScreen(.activeWorkout, metadata: [
            "workout_id": workout.id?.uuidString ?? "unknown",
            "exercise_count": exercises.count
        ])
        
        // Log workout start (non-blocking)
        SessionLogManager.shared.logWorkoutStart(
            workoutId: workout.id?.uuidString ?? "unknown",
            type: workout.name ?? "Custom",
            exerciseCount: exercises.count,
            source: workoutManager.currentProgramDayNumber != nil ? "Program" : "Manual"
        )
        
        // NOTE: Sets are already initialized in WorkoutManager.startWorkout()
        // Warmup data was already applied SYNCHRONOUSLY in applyWarmupDataInstantly()
        
        // ⚡️ DEFERRED: Only process exercises that STILL don't have previous data
        let exerciseNames = exercises.compactMap { $0.name }
        var exercisesNeedingSmartRecs: [(exercise: Exercise, name: String)] = []
        // Finding T (2026-07-31): history-backed exercises get the
        // progression analysis too (async enrichment below) — suggestions
        // used to run ONLY when history was empty, so the "+5 lb ready to
        // progress" sparkle cue was unreachable for exactly the users who
        // earned it.
        var exercisesWithHistory: [(exercise: Exercise, name: String)] = []
        
        // Check which exercises still need data (weren't covered by instant warmup)
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let exerciseName = exercise.name else { continue }
            
            // Skip if data was already applied
            if previousExerciseSets[exerciseId] != nil {
                exercisesWithHistory.append((exercise: exercise, name: exerciseName))
                continue
            }
            
            // Try ExerciseHistoryService cache as fallback
            if let cachedSets = ExerciseHistoryService.shared.previousSetsCache[exerciseName], !cachedSets.isEmpty {
                let previousData = cachedSets.map { cloudSet in
                    PreviousSetData(
                        setNumber: cloudSet.setNumber,
                        weight: cloudSet.weight,
                        reps: cloudSet.reps
                    )
                }
                previousExerciseSets[exerciseId] = previousData
                exercisesWithHistory.append((exercise: exercise, name: exerciseName))
            } else {
                // No cached data - queue for async smart recommendation
                exercisesNeedingSmartRecs.append((exercise: exercise, name: exerciseName))
            }
        }
        
        // Finding T: progression enrichment for history-backed exercises.
        // Runs at low priority AFTER previous-set placeholders are already
        // on screen; only takes over the PREVIOUS column when the engine is
        // confident (real-history progression, not a generic profile
        // placeholder).
        if !exercisesWithHistory.isEmpty {
            let currentUser = UserManager.shared.currentUser
            let progressionContext = viewContext
            let wmForProgression = workoutManager
            let progressionTask = Task.detached(priority: .utility) {
                guard let user = currentUser else { return }
                for (exercise, exerciseName) in exercisesWithHistory {
                    guard !Task.isCancelled else { return }
                    guard let exerciseId = exercise.id?.uuidString else { continue }
                    
                    let recs = await MainActor.run { () -> [StrengthProfileRecommendationEngine.SmartRecommendation] in
                        let prescription = wmForProgression.currentExercisePrescriptions[exerciseName.lowercased()]
                        return StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: prescription?.sets ?? WorkoutManager.userDefaultSetCount,
                            context: progressionContext,
                            programWeek: wmForProgression.currentProgramWeek,
                            prescribedReps: prescription?.repsRange
                        )
                    }
                    
                    guard !recs.isEmpty,
                          recs.allSatisfy({ !$0.isPlaceholder }),
                          (recs.first?.confidenceLevel ?? 0) >= 0.9 else { continue }
                    
                    let sparkleData = recs.enumerated().map { index, rec in
                        PreviousSetData(setNumber: index + 1, recommendation: rec)
                    }
                    await MainActor.run {
                        // Don't clobber values the user is already typing
                        // against — only swap the placeholder column.
                        previousExerciseSets[exerciseId] = sparkleData
                        #if DEBUG
                        AppLogger.debug("💡 [PROGRESSION] Sparkle cue for '\(exerciseName)': \(recs.first?.displayString ?? "")", category: .workout)
                        #endif
                    }
                    await Task.yield()
                }
            }
            initTasks.append(progressionTask)
        }
        
        #if DEBUG
        let syncTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        AppLogger.debug("🚀 [PERF] Deferred cache check: \(String(format: "%.1f", syncTime))ms", category: .performance)
        AppLogger.debug("🚀 [PERF] Exercises needing smart recs: \(exercisesNeedingSmartRecs.count)", category: .performance)
        #endif
        
        // 🔧 ASYNC: Generate smart recommendations in BACKGROUND (truly non-blocking!)
        if !exercisesNeedingSmartRecs.isEmpty {
            let currentUser = UserManager.shared.currentUser
            let context = viewContext
            let wm = workoutManager
            
            // Use Task.detached to run computation OFF the main thread entirely
            let smartRecsTask = Task.detached(priority: .userInitiated) {
                guard let user = currentUser else { return }
                guard !Task.isCancelled else { return }
                
                var recommendations: [(exerciseId: String, data: [PreviousSetData], sets: [WorkoutSetData]?)] = []
                
                for (exercise, exerciseName) in exercisesNeedingSmartRecs {
                    guard !Task.isCancelled else { return }
                    guard let exerciseId = exercise.id?.uuidString else { continue }
                    
                    // Heavy computation happens on background thread
                    let progWeek = workoutManager.currentProgramWeek
                    let defaultCount = WorkoutManager.userDefaultSetCount
                    let recs = await MainActor.run { () -> [StrengthProfileRecommendationEngine.SmartRecommendation] in
                        // Finding S: forward the program prescription
                        // (sets + rep range) when this session has one.
                        let prescription = wm.currentExercisePrescriptions[exerciseName.lowercased()]
                        return StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: prescription?.sets ?? defaultCount,
                            context: context,
                            programWeek: progWeek,
                            prescribedReps: prescription?.repsRange
                        )
                    }
                    
                    let smartPreviousData = recs.enumerated().map { index, rec in
                        PreviousSetData(setNumber: index + 1, recommendation: rec)
                    }
                    
                    // Sets are always empty — suggested values render as grey/orange
                    // placeholders via `previousExerciseSets`. Row count matches the number
                    // of recommendations (or defaultCount, whichever is larger).
                    var smartSets: [WorkoutSetData]? = nil
                    if !recs.isEmpty {
                        let rowCount = max(recs.count, defaultCount)
                        smartSets = (0..<rowCount).map { _ in WorkoutSetData() }
                    }

                    recommendations.append((exerciseId: exerciseId, data: smartPreviousData, sets: smartSets))
                    
                    #if DEBUG
                    await MainActor.run {
                        AppLogger.debug("💡 [SMART-ASYNC] Generated for '\(exerciseName)': \(recs.first?.displayString ?? "N/A")", category: .workout)
                    }
                    #endif
                    
                    // Yield to allow UI to remain responsive
                    await Task.yield()
                }
                
                // Apply results on main thread
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    for rec in recommendations {
                        previousExerciseSets[rec.exerciseId] = rec.data
                        
                        if let smartSets = rec.sets {
                            let existingSets = wm.getSetsForExercise(id: rec.exerciseId)
                            let allEmpty = existingSets.allSatisfy { $0.weight == 0 && $0.reps == 0 && !$0.isCompleted }
                            // Only resize if the user hasn't touched anything and row count differs.
                            // We don't overwrite values — placeholders come from `previousExerciseSets`.
                            if allEmpty && existingSets.count != smartSets.count {
                                wm.updateSetsForExercise(id: rec.exerciseId, sets: smartSets)
                            }
                        }
                    }
                    
                    #if DEBUG
                    AppLogger.debug("🚀 [PERF] Smart recommendations applied: \(recommendations.count) exercises", category: .performance)
                    #endif
                }
            }
            initTasks.append(smartRecsTask)
        }
        
        #if DEBUG
        AppLogger.debug("🚀 [PERF] performDeferredInitialization() - COMPLETE in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms", category: .performance)
        #endif
        
        // SLOW PATH: Fetch historical data asynchronously (BACKGROUND, truly non-blocking)
        let currentUser = UserManager.shared.currentUser
        let wm = workoutManager
        let ctx = viewContext
        let exs = exercises
        
        // Use Task.detached to ensure this runs off the main thread
        let historyTask = Task.detached(priority: .background) {
            guard !Task.isCancelled else { return }
            
            let allPreviousSets = await ExerciseHistoryService.shared.fetchPreviousSetsForExercises(exerciseNames)
            
            guard !Task.isCancelled else { return }
            
            // Process data in background, batch updates for main thread
            var updates: [(exerciseId: String, data: [PreviousSetData])] = []
            
            for exercise in exs {
                guard !Task.isCancelled else { return }
                guard let exerciseId = exercise.id?.uuidString,
                      let exerciseName = exercise.name else { continue }
                
                // Check on main thread if already set
                let alreadySet = await MainActor.run { previousExerciseSets[exerciseId] != nil }
                guard !alreadySet else { continue }
                
                if let cloudSets = allPreviousSets[exerciseName], !cloudSets.isEmpty {
                    var previousData = cloudSets.map { cloudSet in
                        PreviousSetData(
                            setNumber: cloudSet.setNumber,
                            weight: cloudSet.weight,
                            reps: cloudSet.reps
                        )
                    }
                    
                    // Finding T: history loaded — ALSO run the progression
                    // analysis so returning users get the sparkle cue.
                    if let user = currentUser {
                        let recs = await MainActor.run { () -> [StrengthProfileRecommendationEngine.SmartRecommendation] in
                            let prescription = workoutManager.currentExercisePrescriptions[exerciseName.lowercased()]
                            return StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                                exerciseName: exerciseName,
                                user: user,
                                numberOfSets: prescription?.sets ?? WorkoutManager.userDefaultSetCount,
                                context: ctx,
                                programWeek: workoutManager.currentProgramWeek,
                                prescribedReps: prescription?.repsRange
                            )
                        }
                        if !recs.isEmpty,
                           recs.allSatisfy({ !$0.isPlaceholder }),
                           (recs.first?.confidenceLevel ?? 0) >= 0.9 {
                            previousData = recs.enumerated().map { index, rec in
                                PreviousSetData(setNumber: index + 1, recommendation: rec)
                            }
                        }
                    }
                    
                    updates.append((exerciseId: exerciseId, data: previousData))
                } else if let user = currentUser {
                    let progWeek2 = workoutManager.currentProgramWeek
                    let recommendations = await MainActor.run { () -> [StrengthProfileRecommendationEngine.SmartRecommendation] in
                        // Finding S: forward the program prescription.
                        let prescription = workoutManager.currentExercisePrescriptions[exerciseName.lowercased()]
                        return StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: prescription?.sets ?? WorkoutManager.userDefaultSetCount,
                            context: ctx,
                            programWeek: progWeek2,
                            prescribedReps: prescription?.repsRange
                        )
                    }
                    
                    let smartPreviousData = recommendations.enumerated().map { index, rec in
                        PreviousSetData(
                            setNumber: index + 1,
                            recommendation: rec
                        )
                    }
                    
                    updates.append((exerciseId: exerciseId, data: smartPreviousData))
                    
                    #if DEBUG
                    await MainActor.run {
                        AppLogger.debug("💡 [SMART-FALLBACK] Generated for '\(exerciseName)'", category: .workout)
                    }
                    #endif
                }
                
                // Yield between exercises to keep UI responsive
                await Task.yield()
            }
            
            // Apply all updates at once on main thread
            guard !Task.isCancelled else { return }
            await MainActor.run {
                for update in updates {
                    if previousExerciseSets[update.exerciseId] == nil {
                        previousExerciseSets[update.exerciseId] = update.data
                    }
                }
            }
        }
        initTasks.append(historyTask)
    }
    
    /// Load historical data for a newly replaced/shuffled exercise
    /// Also adjusts set count to match previous workout and pre-populates weight/reps
    func loadHistoricalDataForExercise(_ exercise: Exercise) {
        guard let exerciseId = exercise.id?.uuidString,
              let exerciseName = exercise.name else { return }

        #if DEBUG
        AppLogger.debug("🔄 Loading historical data for replaced exercise: \(exerciseName)", category: .workout)
        #endif

        let currentUser = UserManager.shared.currentUser
        let ctx = viewContext
        let wm = workoutManager

        Task.detached(priority: .userInitiated) {
            // First check if we have cached data
            let cache = ExerciseHistoryService.shared.previousSetsCache

            if let cachedSets = cache[exerciseName], !cachedSets.isEmpty {
                // Use cached data
                let previousData = cachedSets.map { cloudSet in
                    PreviousSetData(
                        setNumber: cloudSet.setNumber,
                        weight: cloudSet.weight,
                        reps: cloudSet.reps
                    )
                }

                await MainActor.run {
                    previousExerciseSets[exerciseId] = previousData
                    // Adjust set count to match previous workout and pre-fill weight/reps
                    self.syncSetsWithPreviousData(exerciseId: exerciseId, previousData: previousData, wm: wm)
                    #if DEBUG
                    AppLogger.debug("✅ Loaded cached historical data for '\(exerciseName)': \(previousData.count) sets", category: .workout)
                    #endif
                }
                return
            }

            // Fetch from cloud
            let allPreviousSets = await ExerciseHistoryService.shared.fetchPreviousSetsForExercises([exerciseName])

            if let cloudSets = allPreviousSets[exerciseName], !cloudSets.isEmpty {
                let previousData = cloudSets.map { cloudSet in
                    PreviousSetData(
                        setNumber: cloudSet.setNumber,
                        weight: cloudSet.weight,
                        reps: cloudSet.reps
                    )
                }

                await MainActor.run {
                    previousExerciseSets[exerciseId] = previousData
                    self.syncSetsWithPreviousData(exerciseId: exerciseId, previousData: previousData, wm: wm)
                    #if DEBUG
                    AppLogger.debug("✅ Loaded cloud historical data for '\(exerciseName)': \(previousData.count) sets", category: .network)
                    #endif
                }
            } else if let user = currentUser {
                let progWeek3 = await MainActor.run { workoutManager.currentProgramWeek }
                let defaultCount = WorkoutManager.userDefaultSetCount
                let recommendations = await MainActor.run { () -> [StrengthProfileRecommendationEngine.SmartRecommendation] in
                    // Finding S: forward the program prescription.
                    let prescription = wm.currentExercisePrescriptions[exerciseName.lowercased()]
                    return StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                        exerciseName: exerciseName,
                        user: user,
                        numberOfSets: prescription?.sets ?? defaultCount,
                        context: ctx,
                        programWeek: progWeek3,
                        prescribedReps: prescription?.repsRange
                    )
                }

                let smartPreviousData = recommendations.enumerated().map { index, rec in
                    PreviousSetData(setNumber: index + 1, recommendation: rec)
                }

                await MainActor.run {
                    previousExerciseSets[exerciseId] = smartPreviousData
                    let currentSets = wm.getSetsForExercise(id: exerciseId)
                    if currentSets.allSatisfy({ $0.weight == 0 && $0.reps == 0 && !$0.isCompleted }) {
                        let rowCount = max(recommendations.count, defaultCount)
                        if rowCount != currentSets.count {
                            let smartSets = (0..<rowCount).map { _ in WorkoutSetData() }
                            wm.updateSetsForExercise(id: exerciseId, sets: smartSets)
                        }
                    }
                    #if DEBUG
                    AppLogger.debug("💡 Generated smart recommendations for '\(exerciseName)'", category: .workout)
                    #endif
                }
            }
        }
    }

    /// Adjust the exercise's row count to match `max(previousData.count, defaultSetCount)`.
    /// Does NOT copy weight/reps into `setData` — previous values render as grey placeholders
    /// in `SetRowView` (via `previousSet`). Pre-filling real values would overwrite the
    /// placeholder-only UX the user expects when repeating an exercise.
    /// Only runs when the user hasn't touched any rows yet (all empty, none completed).
    func syncSetsWithPreviousData(exerciseId: String, previousData: [PreviousSetData], wm: WorkoutManager) {
        let currentSets = wm.getSetsForExercise(id: exerciseId)
        let allEmpty = currentSets.allSatisfy { $0.weight == 0 && $0.reps == 0 && !$0.isCompleted }

        guard allEmpty else { return }

        let defaultCount = WorkoutManager.userDefaultSetCount
        let targetCount = max(previousData.count, defaultCount)

        guard targetCount != currentSets.count else { return }

        let newSets = (0..<targetCount).map { _ in WorkoutSetData() }
        wm.updateSetsForExercise(id: exerciseId, sets: newSets)
    }

    func handleWorkoutAppear() {
        if keepScreenOn { UIApplication.shared.isIdleTimerDisabled = true }
        // ⚡️ PERF (finding I): no root per-second timer anymore — the header
        // duration renders in `WorkoutDurationText` (TimelineView leaf).
        // Sync the captured elapsed value once; it's recomputed at finish.
        elapsedTime = workoutManager.workoutStartTime.map { Date().timeIntervalSince($0) } ?? 0
        refreshNotesPlaceholder()
        applyWarmupDataInstantly()
        isWorkoutFavorite = workout.isFavorite
        if activeExerciseId == nil || !exercises.contains(where: { $0.id?.uuidString == activeExerciseId }) {
            activeExerciseId = exercises.first?.id?.uuidString
        }
        isFinishingWorkout = false
        if workout.isCompleted {
            workout.isCompleted = false
            try? viewContext.save()
        }
        workout.name = liveWorkoutName
        // Initial push to the Apple Watch's live-workout slot so the
        // wrist sees "Bench Press · Set 1 of N" the moment the user
        // starts the workout. Subsequent updates flow through
        // `handleSetCompletion`. No-op when no watch is paired.
        if let firstExercise = exercises.first {
            pushLiveWorkoutStateToWatch(for: firstExercise)
        }
        DispatchQueue.main.async { initializeWorkout() }
    }
    
    func handleCompletionDismiss() {
        isFinishingWorkout = false
        if workout.isCompleted {
            workout.isCompleted = false
            try? viewContext.save()
        }
    }
    
}
