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
        
        // Check which exercises still need data (weren't covered by instant warmup)
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let exerciseName = exercise.name else { continue }
            
            // Skip if data was already applied
            if previousExerciseSets[exerciseId] != nil { continue }
            
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
            } else {
                // No cached data - queue for async smart recommendation
                exercisesNeedingSmartRecs.append((exercise: exercise, name: exerciseName))
            }
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
                    let recs = await MainActor.run {
                        StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: defaultCount,
                            context: context,
                            programWeek: progWeek
                        )
                    }
                    
                    let smartPreviousData = recs.enumerated().map { index, rec in
                        PreviousSetData(setNumber: index + 1, recommendation: rec)
                    }
                    
                    var smartSets: [WorkoutSetData]? = nil
                    if !recs.isEmpty {
                        smartSets = recs.map { rec in
                            let setData = WorkoutSetData()
                            setData.weight = rec.weight
                            setData.reps = rec.reps
                            return setData
                        }
                        while smartSets!.count < defaultCount {
                            smartSets!.append(WorkoutSetData())
                        }
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
                            if existingSets.count == 1 && existingSets.first?.weight == 0 && existingSets.first?.reps == 0 {
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
                    let previousData = cloudSets.map { cloudSet in
                        PreviousSetData(
                            setNumber: cloudSet.setNumber,
                            weight: cloudSet.weight,
                            reps: cloudSet.reps
                        )
                    }
                    updates.append((exerciseId: exerciseId, data: previousData))
                } else if let user = currentUser {
                    let progWeek2 = workoutManager.currentProgramWeek
                    let recommendations = await MainActor.run {
                        StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: WorkoutManager.userDefaultSetCount,
                            context: ctx,
                            programWeek: progWeek2
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
                let recommendations = await MainActor.run {
                    StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                        exerciseName: exerciseName,
                        user: user,
                        numberOfSets: defaultCount,
                        context: ctx,
                        programWeek: progWeek3
                    )
                }

                let smartPreviousData = recommendations.enumerated().map { index, rec in
                    PreviousSetData(setNumber: index + 1, recommendation: rec)
                }

                await MainActor.run {
                    previousExerciseSets[exerciseId] = smartPreviousData
                    let currentSets = wm.getSetsForExercise(id: exerciseId)
                    if currentSets.allSatisfy({ $0.weight == 0 && $0.reps == 0 && !$0.isCompleted }) {
                        var smartSets = recommendations.map { rec in
                            let setData = WorkoutSetData()
                            setData.weight = rec.weight
                            setData.reps = rec.reps
                            return setData
                        }
                        while smartSets.count < defaultCount {
                            smartSets.append(WorkoutSetData())
                        }
                        wm.updateSetsForExercise(id: exerciseId, sets: smartSets)
                    }
                    #if DEBUG
                    AppLogger.debug("💡 Generated smart recommendations for '\(exerciseName)'", category: .workout)
                    #endif
                }
            }
        }
    }

    /// Sync the exercise's set count and pre-fill values from previous workout data
    func syncSetsWithPreviousData(exerciseId: String, previousData: [PreviousSetData], wm: WorkoutManager) {
        let currentSets = wm.getSetsForExercise(id: exerciseId)
        let allEmpty = currentSets.allSatisfy { $0.weight == 0 && $0.reps == 0 && !$0.isCompleted }

        guard allEmpty else { return }

        let defaultCount = WorkoutManager.userDefaultSetCount
        var newSets = previousData.map { prev in
            let setData = WorkoutSetData()
            setData.weight = prev.weight
            setData.reps = prev.reps
            return setData
        }
        while newSets.count < defaultCount {
            newSets.append(WorkoutSetData())
        }

        if !newSets.isEmpty {
            wm.updateSetsForExercise(id: exerciseId, sets: newSets)
        }
    }

    func handleWorkoutAppear() {
        if keepScreenOn { UIApplication.shared.isIdleTimerDisabled = true }
        startTimer()
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
        DispatchQueue.main.async { initializeWorkout() }
    }
    
    func handleCompletionDismiss() {
        isFinishingWorkout = false
        if workout.isCompleted {
            workout.isCompleted = false
            try? viewContext.save()
        }
    }
    
    func startTimer() {
        // Sprint 3 (Q2-33): `ActiveWorkoutView` is a struct, so `[weak self]`
        // doesn't apply. The live anchor is the class-backed `workoutManager`.
        // We capture it weakly and self-invalidate if it disappears, so a
        // rogue/stale timer can never outlive the workout session and keep
        // mutating `@State` storage from a now-detached view.
        guard let startTime = workoutManager.workoutStartTime else {
            AppLogger.warning("⚠️ [TIMER] No workout start time available, using current time", category: .workout)
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak workoutManager] t in
                guard workoutManager != nil else {
                    t.invalidate()
                    return
                }
                elapsedTime += 1
            }
            if let t = timer { RunLoop.main.add(t, forMode: .common) }
            return
        }
        
        elapsedTime = Date().timeIntervalSince(startTime)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak workoutManager] t in
            guard workoutManager != nil else {
                t.invalidate()
                return
            }
            elapsedTime = Date().timeIntervalSince(startTime)
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
