import SwiftUI
import CoreData

extension ActiveWorkoutView {
    /// Mirror local `@State var exercises` back to `workoutManager.currentExercises` and
    /// immediately flush to UserDefaults. MUST be called after every mutation to the
    /// local `exercises` array (add / remove / shuffle / drag-reorder). Without this,
    /// mid-workout changes are invisible to `saveActiveWorkoutToStorage()` — which
    /// snapshots from `currentExercises` — so an iOS background-kill restores the
    /// original exercises only and silently drops anything added during the session.
    @MainActor
    func syncExercisesToWorkoutManager() {
        workoutManager.currentExercises = exercises
        workoutManager.saveActiveWorkoutToStorage()
    }

    func handleSetCompletion(for exercise: Exercise, setData: WorkoutSetData) {
        guard let exerciseId = exercise.id?.uuidString else { return }
        
        // Add completed set
        workoutManager.addSetToExercise(id: exerciseId, set: setData)
        
        // Rest timer is shown via the ad interstitial timing

        // Mirror the new "next set" state to the paired Apple Watch
        // so its live workout view advances + shows the rest-timer
        // countdown. No-op when no watch is paired/installed.
        pushLiveWorkoutStateToWatch(for: exercise)
    }

    /// Sends the current "next set" state for `exercise` to the watch
    /// via `PhoneToWatchLiveWorkoutBridge`. Called from
    /// `handleSetCompletion` and from the workout-appear path so the
    /// watch's `WatchLiveWorkoutView` always shows the active set.
    func pushLiveWorkoutStateToWatch(for exercise: Exercise) {
        guard let exerciseId = exercise.id?.uuidString else { return }
        let sets = workoutManager.exerciseSetsData[exerciseId] ?? []
        // Next set the user is about to do = first non-completed set,
        // or `sets.count` if every existing set is done (in which case
        // the watch shows "Set N+1 of N" until the user moves to the
        // next exercise on the phone).
        let nextIndex = sets.firstIndex(where: { !$0.isCompleted }) ?? sets.count
        let totalSets = max(sets.count, defaultSetCount)
        let targetSet: WorkoutSetData? = nextIndex < sets.count ? sets[nextIndex] : nil
        let targetWeight: Double? = (targetSet?.weight ?? 0) > 0 ? targetSet?.weight : nil
        let targetReps: Int = targetSet?.reps ?? 0

        PhoneToWatchLiveWorkoutBridge.shared.pushExercise(
            exerciseId: exerciseId,
            exerciseName: exercise.name ?? "",
            setIndex: nextIndex,
            totalSets: totalSets,
            targetWeight: targetWeight,
            targetReps: targetReps
        )
    }
    
    func getRestDuration(for exercise: Exercise) -> TimeInterval {
        // Use user-configured default rest seconds (0 = timer off)
        return TimeInterval(defaultRestSeconds)
    }
    
    func cleanupPreviousExercises(currentExerciseId: String) {
        AppLogger.debug("🧹 Cleaning up previous exercises. Current: \(currentExerciseId)", category: .workout)
        AppLogger.debug("🧹 Last interacted exercise: \(lastInteractedExerciseId ?? "none")", category: .workout)
        AppLogger.debug("🧹 All exercise sets before cleanup: \(workoutManager.exerciseSetsData.mapValues { $0.count })", category: .workout)
        
        // FIXED: Less aggressive cleanup - preserve sets with data entered
        for (exerciseId, sets) in workoutManager.exerciseSetsData {
            if exerciseId != currentExerciseId {
                // Keep sets that are EITHER:
                // 1. Completed (user finished them)
                // 2. Have data entered (weight > 0 OR reps > 0) - user is working on them
                // 3. Are in the first 3 positions (standard workout structure)
                let validSets = sets.enumerated().filter { (index, set) in
                    // Keep if completed
                    if set.isCompleted { return true }
                    
                    // Keep if has data entered (user entered weight/reps but didn't complete yet)
                    if set.weight > 0 || set.reps > 0 { return true }
                    
                    // Keep first 3 sets for standard workout structure
                    if index < 3 { return true }
                    
                    // Remove extra blank sets beyond the first 3
                    return false
                }.map { $0.element }
                
                if validSets.count != sets.count {
                    AppLogger.debug("🧹 Exercise \(exerciseId): Had \(sets.count) sets, keeping \(validSets.count) sets", category: .workout)
                    AppLogger.debug("🧹 Removed \(sets.count - validSets.count) extra blank sets", category: .workout)
                    workoutManager.exerciseSetsData[exerciseId] = validSets.isEmpty ? [WorkoutSetData()] : validSets
                } else {
                    AppLogger.debug("🧹 Exercise \(exerciseId): All \(sets.count) sets preserved", category: .workout)
                }
            }
        }
        
        // Update last interacted exercise
        lastInteractedExerciseId = currentExerciseId
        AppLogger.debug("🧹 All exercise sets after cleanup: \(workoutManager.exerciseSetsData.mapValues { $0.count })", category: .workout)
        AppLogger.debug("🧹 Cleanup complete. Last interacted exercise: \(currentExerciseId)", category: .workout)
    }
    
    // Calculate shift direction for cards during drag reorder
    func shiftDirection(for index: Int) -> Int {
        guard let dragging = draggingIndex, let target = dragTargetIndex else { return 0 }
        
        // Card being dragged doesn't shift
        if index == dragging { return 0 }
        
        // Dragging up (target < dragging): cards between target and dragging shift down
        if target < dragging {
            if index >= target && index < dragging {
                return 1 // Shift down
            }
        }
        // Dragging down (target > dragging): cards between dragging and target shift up
        else if target > dragging {
            if index > dragging && index <= target {
                return -1 // Shift up
            }
        }
        
        return 0
    }
    
    func finishWorkout() {
        // Guard against duplicate finishes (prevents duplicate workout saves)
        guard !isFinishingWorkout else {
            AppLogger.warning("⚠️ [FINISH] Already finishing workout, ignoring duplicate call", category: .workout)
            return
        }
        
        // Guard against finishing an already completed workout
        guard !workout.isCompleted else {
            AppLogger.warning("⚠️ [FINISH] Workout already completed, ignoring duplicate call", category: .workout)
            return
        }
        
        isFinishingWorkout = true
        
        // Finding I: no root per-second tick anymore — compute the final
        // duration once from the canonical start timestamp.
        elapsedTime = workoutManager.workoutStartTime.map { Date().timeIntervalSince($0) } ?? elapsedTime

        // Sync kg values on all sets before saving
        for (_, sets) in workoutManager.exerciseSetsData {
            for set in sets where set.isCompleted {
                set.syncWeightUnits(fromLbs: true)
            }
        }
        
        // "Reopen" on the completion screen re-arms FINISH (it resets
        // `isFinishingWorkout` + `workout.isCompleted` in
        // `handleCompletionDismiss`). The XP/streak/league/quest/HealthKit/
        // program-day fanout must only run ONCE per session — on a second
        // finish, re-run only the durable saves: `saveWorkoutData()`
        // (which also kicks the idempotent cloud upsert) and re-present
        // the completion screen.
        if workoutManager.didRunCompletionFanout {
            AppLogger.info("🔁 [FINISH] Completion fanout already ran this session — re-running durable saves only", category: .workout)
            saveWorkoutData()
            showingCompletionView = true
            return
        }
        workoutManager.didRunCompletionFanout = true
        
        let capturedSetsData = workoutManager.exerciseSetsData
        let capturedExercises = exercises
        let capturedWorkout = workout
        let capturedElapsedTime = elapsedTime

        // #156: stamp `completedReplacement` on each pending swap event by
        // checking whether the replacement exercise has any completed sets.
        // Done before the cloud upload Task captures `pendingSwapEvents`.
        for i in workoutManager.pendingSwapEvents.indices {
            let evt = workoutManager.pendingSwapEvents[i]
            let replacementId = evt.replacementExerciseId?.uuidString ?? ""
            let sets = capturedSetsData[replacementId] ?? []
            workoutManager.pendingSwapEvents[i].completedReplacement = sets.contains { $0.isCompleted }
        }

        // Migration #154: score the workout BEFORE clearing transient data.
        // The result is stashed on WorkoutManager so the Done-button path
        // (collaborative engine corpus gate) and the cloud upsert below
        // both read the same canonical value.
        let qualityResult = WorkoutQualityScorer.score(
            workout: capturedWorkout,
            exercises: capturedExercises,
            exerciseSets: capturedSetsData,
            workoutDuration: capturedElapsedTime
        )
        workoutManager.lastWorkoutQuality = qualityResult
        AppLogger.info("📊 [QUALITY] Workout scored \(qualityResult.score)/100 (\(qualityResult.band.rawValue)) — corpus: \(qualityResult.qualifiesForCorpus ? "✅" : "❌")", category: .workout)

        // Calculate totals for logging
        var totalSetsCompleted = 0
        var exercisesCompleted = 0
        for (_, sets) in capturedSetsData {
            let completed = sets.filter { $0.isCompleted }.count
            totalSetsCompleted += completed
            if completed > 0 { exercisesCompleted += 1 }
        }
        
        // Log workout completion
        SessionLogManager.shared.logWorkoutEnd(
            workoutId: workout.id?.uuidString ?? "unknown",
            duration: capturedElapsedTime,
            exercisesCompleted: exercisesCompleted,
            totalSets: totalSetsCompleted,
            caloriesBurned: nil // Will be calculated later
        )

        AppLogger.debug("📦 [FINISH] Captured \(capturedSetsData.count) exercise sets before clearing", category: .workout)
        for (id, sets) in capturedSetsData {
            let completed = sets.filter { $0.isCompleted }
            AppLogger.debug("   Exercise \(id.prefix(8)): \(completed.count)/\(sets.count) completed sets", category: .workout)
        }
        
        // Save workout data to Core Data
        saveWorkoutData()
        
        // 🍎 Save workout to Apple Health (fills Exercise ring!)
        saveWorkoutToAppleHealth(
            startDate: workout.date ?? Date().addingTimeInterval(-capturedElapsedTime),
            duration: capturedElapsedTime,
            exerciseCount: capturedExercises.count
        )
        
        // Complete workout through UserManager (handles XP, achievements, etc.)
        userManager.completeWorkout(workout)
        
        // If this is a program workout, mark the day as complete
        if let dayNumber = workoutManager.currentProgramDayNumber {
            // Mark complete in WorkoutManager (for legacy programs)
            workoutManager.markProgramDayComplete(dayNumber)
            
            // Mark complete in CloudProgramService (for cloud programs)
            Task {
                await CloudProgramService.shared.completeDay(dayNumber, xpEarned: Int(workout.xpEarned))
                AppLogger.debug("☁️ Cloud program day \(dayNumber) marked complete", category: .network)
            }
        }
        
        // Save workout to cloud for sync across devices. Failures enqueue
        // onto the persistent retry queue (Sprint 2 Q2-34) so a network blip
        // at finish-time no longer silently loses sets.
        if SupabaseManager.shared.isAuthenticated {
            Task {
                do {
                    try await SupabaseManager.shared.saveWorkoutToCloud(workout: workout, quality: qualityResult)
                } catch {
                    AppLogger.error("⚠️ Failed to sync workout to cloud: \(error)", category: .network)
                    await MainActor.run {
                        CloudSyncRetryQueue.shared.enqueueWorkoutCloudSync(workout)
                    }
                }
            }
        } else {
            // Not authenticated yet — still queue so it flushes after auth recovers.
            CloudSyncRetryQueue.shared.enqueueWorkoutCloudSync(workout)
        }
        
        // 🔧 Show completion view FIRST (before clearing active state)
        // WorkoutCompletionView will call workoutManager.finishWorkout() when Done is tapped
        // This prevents the view from disappearing before the completion screen shows
        showingCompletionView = true
        
        AppLogger.debug("✅ Workout completion view shown - workout still active until Done is tapped", category: .ui)
        
        // Save exercise performance history AFTER capturing data but in background
        // Use captured data since workoutManager.exerciseSetsData is now cleared
        Task {
            await saveExercisePerformanceHistoryWithData(
                exercises: capturedExercises,
                setsData: capturedSetsData,
                workout: capturedWorkout,
                elapsedTime: capturedElapsedTime
            )
        }
        
        // ⚡️ Track exercise completions for dynamic popularity ranking
        // Exercises the user actually completes rise to the top of the Recommended list over time
        Task { @MainActor in
            let filterCache = ExerciseLibraryFilterCache.shared
            for exercise in capturedExercises {
                guard let exerciseId = exercise.id?.uuidString,
                      let exerciseName = exercise.name,
                      let sets = capturedSetsData[exerciseId] else { continue }
                let completedSets = sets.filter { $0.isCompleted }.count
                if completedSets > 0 {
                    // Each completed set adds weight to this exercise's ranking
                    for _ in 0..<completedSets {
                        filterCache.trackExerciseCompletion(exerciseName: exerciseName)
                    }
                }
            }
            // Re-sort recommended list so next tab visit reflects updated rankings
            filterCache.refreshSort()
        }
        
        // 🧠 Update the learning engine with this workout data
        // This helps the recommendation engine learn user preferences over time
        Task {
            await UserBehaviorLearningEngine.shared.refreshAfterWorkout(
                capturedWorkout,
                context: viewContext
            )
            AppLogger.debug("🧠 [LEARNING] User preferences updated from completed workout", category: .workout)
            
            // 📊 Track progressions for community learning
            if let user = userManager.currentUser, let userId = user.id {
                await trackProgressions(
                    exercises: capturedExercises,
                    setsData: capturedSetsData,
                    user: user,
                    context: viewContext
                )
                
                await analyzeWorkoutWithAdvancedIntelligence(
                    userId: userId,
                    exercises: capturedExercises,
                    setsData: capturedSetsData,
                    workoutDate: capturedWorkout.date ?? Date(),
                    durationMinutes: Int(capturedElapsedTime / 60),
                    bodyWeightKg: Double(user.weight)
                )
            }
        }
    }
    
    /// Comprehensive workout analysis using Advanced Intelligence Service
    func analyzeWorkoutWithAdvancedIntelligence(
        userId: UUID,
        exercises: [Exercise],
        setsData: [String: [WorkoutSetData]],
        workoutDate: Date,
        durationMinutes: Int,
        bodyWeightKg: Double?
    ) async {
        // Convert exercise data to the format expected by intelligence service
        var exerciseAnalysisData: [(name: String, sets: [(weight: Double, reps: Int, completed: Bool)], muscleGroups: [String])] = []
        
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = setsData[exerciseId],
                  !sets.isEmpty else { continue }
            
            let setsForAnalysis = sets.map { (weight: $0.weight, reps: $0.reps, completed: $0.isCompleted) }
            let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
            
            exerciseAnalysisData.append((
                name: exercise.name ?? "Unknown",
                sets: setsForAnalysis,
                muscleGroups: muscleGroups
            ))
        }
        
        // Detect if any exercise hit a new personal record (weight PR)
        var hadPR = false
        for exercise in exercises {
            guard let exerciseName = exercise.name ?? exercise.displayName as String?,
                  let exerciseId = exercise.id?.uuidString,
                  let sets = setsData[exerciseId] else { continue }
            let completedSets = sets.filter { $0.isCompleted && $0.weight > 0 }
            guard let bestWeight = completedSets.map({ $0.weight }).max() else { continue }
            if let cached = ExerciseHistoryService.shared.personalRecordsCache[exerciseName],
               bestWeight > cached.maxWeight {
                hadPR = true
                break
            }
        }

        await AdvancedIntelligenceService.shared.analyzeCompletedWorkout(
            userId: userId,
            exercises: exerciseAnalysisData,
            workoutDate: workoutDate,
            durationMinutes: durationMinutes,
            bodyWeightKg: bodyWeightKg,
            hadPR: hadPR
        )
        
        AppLogger.debug("🧠 [ADVANCED INTELLIGENCE] Workout analyzed for: progression, time patterns, volume trends, strength ratios", category: .workout)
    }
    
    func cancelWorkout() {
        // Cancel through WorkoutManager
        workoutManager.cancelWorkout()
        
        AppLogger.error("❌ Workout cancelled", category: .workout)
    }
    
    func removeExercise(at index: Int) {
        guard index < exercises.count else { return }
        let exerciseId = exercises[index].id?.uuidString ?? ""
        
        // Remove exercise from list
        exercises.remove(at: index)
        
        // Remove associated sets and timers
        workoutManager.exerciseSetsData.removeValue(forKey: exerciseId)
        exerciseRestTimers.removeValue(forKey: exerciseId)
        
        syncExercisesToWorkoutManager()
        
        AppLogger.debug("🗑️ Removed exercise at index \(index)", category: .workout)
    }
    
    func shuffleExercise(at index: Int, with newExercise: Exercise) {
        guard index < exercises.count else { return }
        // Belt-and-braces (the exclusion set in ExerciseCard should prevent
        // this): never swap in an exercise that's already another slot in
        // the workout — the two slots would share one `exerciseSetsData`
        // key (wiping logged sets) and duplicate ForEach ids.
        if exercises.contains(where: { $0.id == newExercise.id }) {
            HapticManager.notification(.warning)
            AppLogger.warning("⚠️ Shuffle picked an exercise already in the workout (\(newExercise.name ?? "?")) — ignoring", category: .workout)
            return
        }
        let oldExercise = exercises[index]
        let oldExerciseId = oldExercise.id?.uuidString ?? ""
        let newExerciseId = newExercise.id?.uuidString ?? ""
        let oldExerciseName = oldExercise.name ?? "Unknown"
        let newExerciseName = newExercise.name ?? "Unknown"

        // Workout intelligence audit (#156). Captured locally; flushed to
        // `workout_swap_events` post-finishWorkout when we have a stable
        // workout_id. shuffleCount is global swap counter; we surface it as
        // `swap_index` for FE-invariant-25 tier inference (1-2 = equipment
        // variant, 3+ = complementary). picked_rank = 0 because
        // `ExerciseCard.shuffleToSimilarExercise` always accepts the
        // `getQuickSwap` top suggestion (no menu). When the
        // `SmartExerciseSwapView` menu becomes the active path, threading
        // an explicit pickedRank through the closure chain is the V2 fix.
        workoutManager.pendingSwapEvents.append(WorkoutManager.PendingSwapEvent(
            originalExerciseId: oldExercise.id,
            originalExerciseName: oldExerciseName,
            replacementExerciseId: newExercise.id,
            replacementExerciseName: newExerciseName,
            swapIndex: shuffleCount,
            pickedRank: 0,
            swapSource: "quick_swap",
            completedReplacement: nil
        ))

        // Log swap for dev session analytics
        if AdvancedSessionLogger.isActive {
            Task { @MainActor in
                AdvancedSessionLogger.shared.log(
                    type: "exercise_swap",
                    detail: "SWAP: \(oldExerciseName) -> \(newExerciseName)",
                    screen: "ActiveWorkout",
                    extra: [
                        "old_exercise": oldExerciseName,
                        "new_exercise": newExerciseName,
                        "swap_index": index,
                        "swap_count": shuffleCount,
                    ]
                )
            }
        }
        
        // Replace exercise in list
        withAnimation(.easeInOut(duration: 0.3)) {
            exercises[index] = newExercise
        }
        
        syncExercisesToWorkoutManager()
        
        // Shuffle = brand-new exercise, so reset the sets entirely. We only
        // preserve the SET COUNT (so the user's "I do 4 sets" preference for
        // this slot survives the swap) — the new exercise gets fresh
        // `WorkoutSetData()` rows: `isCompleted = false`, `weight = 0`,
        // `reps = 0`. Carrying over completion checkmarks / weights / reps
        // from a different exercise is misleading: a user who just shuffled
        // away from the old exercise hasn't actually done THIS one yet
        // (per user request 2026-04-29). The set-row UI's placeholder text
        // immediately re-populates from `previousExerciseSets[newExerciseId]`
        // once `loadHistoricalDataForExercise(newExercise)` returns below.
        let existingSets = workoutManager.exerciseSetsData[oldExerciseId] ?? []
        let setCount = max(existingSets.count, WorkoutManager.userDefaultSetCount)
        workoutManager.exerciseSetsData[newExerciseId] = (0..<setCount).map { _ in WorkoutSetData() }

        // Clean up old exercise data
        workoutManager.exerciseSetsData.removeValue(forKey: oldExerciseId)
        previousExerciseSets.removeValue(forKey: oldExerciseId) // Clear old previous data
        exerciseRestTimers.removeValue(forKey: oldExerciseId)

        // Transfer rest timer preference if set
        if let customRest = exerciseRestTimers[oldExerciseId] {
            exerciseRestTimers[newExerciseId] = customRest
        }

        AppLogger.debug("🔀 Shuffled '\(oldExerciseName)' → '\(newExerciseName)'", category: .workout)

        // Load historical data for the new exercise (populates placeholders)
        loadHistoricalDataForExercise(newExercise)
        
        // 🧠 ADVANCED INTELLIGENCE: Track exercise swap for learning user preferences
        // This helps understand which exercises users prefer over others
        if let userId = userManager.currentUser?.id {
            Task {
                await AdvancedIntelligenceService.shared.trackExerciseSwap(
                    userId: userId,
                    originalExercise: oldExerciseName,
                    swappedTo: newExerciseName,
                    reason: IntelligenceSwapReason.preference
                )
            }
        }
        
        // 🧠 BEHAVIOR LEARNING: Record swap for smarter recommendations
        // After 3+ swaps of same exercise, reduce its recommendation score
        UserBehaviorLearningEngine.shared.recordExerciseSwap(
            from: oldExerciseName,
            to: newExerciseName
        )
        
        // 🔄 VARIANT ENGINE: Record swap for variant rotation
        // Swaps during workout = user dislikes this exercise
        Task { @MainActor in
            SmartVariantRotationEngine.shared.recordSwapFrom(
                exerciseName: oldExerciseName,
                toExercise: newExerciseName
            )
        }
    }
    
    // MARK: - Ad Display Between Sets
    
    /// Shows an ad between sets if ads are enabled
    /// The ad serves as the rest timer - ensuring at least 30 seconds of rest
    /// Only shows ad every 3rd completed set
    func showAdBetweenSets(completion: @escaping () -> Void) {
        // Increment completed sets counter
        completedSetsCount += 1
        
        // Show interstitial ad every 3 completed sets
        guard completedSetsCount % 3 == 0 else {
            AppLogger.warning("📺 Set \(completedSetsCount) - skipping ad", category: .workout)
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        AppLogger.debug("📺 Set \(completedSetsCount) - attempting to show ad", category: .workout)
        
        // Check if ads should be shown
        guard AdManager.shared.shouldShowAd() else {
            AppLogger.debug("📺 Ads disabled or not ready, continuing without ad", category: .workout)
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        // Get the root view controller to present the ad
        guard let viewController = RootViewControllerFinder.find() else {
            AppLogger.error("📺 Could not find view controller, skipping ad", category: .ui)
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        DispatchQueue.main.async { [self] in
            isShowingAd = true
        }
        
        // Show the interstitial ad
        AdManager.shared.showInterstitialAd(from: viewController) { [self] in
            DispatchQueue.main.async {
                AppLogger.debug("📺 Ad completed, resuming workout", category: .workout)
                isShowingAd = false
                completion()
            }
        }
    }
    
    /// Shows an ad for shuffle action (every 2nd shuffle)
    func showShuffleAd(completion: @escaping () -> Void) {
        // Get the root view controller to present the ad
        guard let viewController = RootViewControllerFinder.find() else {
            AppLogger.error("📺 Could not find view controller, skipping shuffle ad", category: .ui)
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        DispatchQueue.main.async { [self] in
            isShowingAd = true
        }
        
        AdManager.shared.showInterstitialAd(from: viewController) { [self] in
            DispatchQueue.main.async {
                AppLogger.debug("📺 Shuffle ad completed", category: .workout)
                isShowingAd = false
                completion()
            }
        }
    }
}
