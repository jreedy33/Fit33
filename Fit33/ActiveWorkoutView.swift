import SwiftUI
import CoreData
import Foundation

struct ActiveWorkoutView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    // AdManager accessed lazily via .shared to avoid blocking view init
    @Binding var isPresented: Bool
    
    // ⚡️ PERFORMANCE: Use centralized HapticManager (pre-warmed generators)
    
    let workout: Workout
    @State private var exercises: [Exercise]
    
    // exerciseSets is now stored in workoutManager.exerciseSetsData to survive view rebuilds during ads
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var workoutStartTime = Date()
    @State private var showingCompletionView = false
    @State private var isFinishingWorkout = false // Prevents duplicate workout saves
    @State private var exerciseRestTimers: [String: TimeInterval] = [:]
    @State private var lastInteractedExerciseId: String? = nil // Track which exercise was last interacted with
    @State private var showingWorkoutInsights = false
    @State private var previousExerciseSets: [String: [PreviousSetData]] = [:] // Store previous workout data
    @State private var isShowingAd = false // Track if an ad is currently showing
    @State private var isWorkoutFavorite = false // Track if workout is marked as favorite
    @State private var showingExerciseSelection = false // For adding exercises during workout
    @State private var initializationComplete = false // Guard against duplicate initialization
    @State private var initTasks: [Task<Void, Never>] = [] // Track async tasks for cancellation
    
    // Drag reorder state
    @State private var draggingIndex: Int? = nil
    @State private var dragTargetIndex: Int? = nil
    
    // Active exercise tracking for highlight and auto-scroll
    @State private var activeExerciseId: String? = nil
    
    // Track which exercise currently has an active rest timer (to stop when switching)
    @State private var exerciseWithActiveTimer: String? = nil
    
    // Ad frequency tracking - only show ad every 3rd set
    @State private var completedSetsCount: Int = 0
    
    // Shuffle ad tracking - show ad every 2nd shuffle
    @State private var shuffleCount: Int = 0
    
    // MARK: - Ad Logic
    
    /// Determine if inline ads should show based on workout source
    private var shouldShowInlineAds: Bool {
        guard AdManager.shared.adsEnabled else { return false }
        
        // Check workout name to determine source
        let workoutName = workout.name?.lowercased() ?? ""
        
        // Don't show ads for custom workouts (user built their own)
        if workoutName.contains("custom workout") {
            return false
        }
        
        // Show ads for auto-generated, received, and program workouts
        return true
    }
    
    init(isPresented: Binding<Bool>, workout: Workout, exercises: [Exercise]) {
        self._isPresented = isPresented
        self.workout = workout
        self._exercises = State(initialValue: exercises)
    }
    
    var workoutDuration: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack {
            // Full screen background gradient
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.04, green: 0.04, blue: 0.06)]
                    : [Color.blue.opacity(0.15), Color.purple.opacity(0.08), Color(.systemGroupedBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Program Day Badge - only show if this is a program workout
                if let dayNumber = workoutManager.currentProgramDayNumber,
                   let dayFocus = workoutManager.currentProgramDayFocus {
                    programDayBadge(dayNumber: dayNumber, focus: dayFocus)
                        .padding(.top, 8)
                }
                
                // Exercise list - transparent container
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Top spacing for glow effect visibility
                            Spacer().frame(height: 12)
                            
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                let exerciseId = exercise.id?.uuidString ?? ""
                                ExerciseCard(
                                    exercise: exercise,
                                    sets: Binding(
                                        get: { workoutManager.getSetsForExercise(id: exerciseId) },
                                        set: { workoutManager.updateSetsForExercise(id: exerciseId, sets: $0) }
                                    ),
                                    previousSets: previousExerciseSets[exerciseId] ?? [],
                                    onAddSet: {
                                        let newSet = WorkoutSetData()
                                        let existingSets = workoutManager.getSetsForExercise(id: exerciseId)
                                        if let lastSet = existingSets.last {
                                            newSet.weight = lastSet.weight
                                            newSet.reps = lastSet.reps
                                        }
                                        workoutManager.addSetToExercise(id: exerciseId, set: newSet)
                                    },
                                    onRemoveExercise: {
                                        removeExercise(at: index)
                                    },
                                    onReplaceExercise: { newExercise in
                                        // Load historical data for the replaced exercise
                                        loadHistoricalDataForExercise(newExercise)
                                    },
                                    onShuffleExercise: { newExercise in
                                        shuffleCount += 1
                                        // Show ad every 2nd shuffle
                                        if shuffleCount % 2 == 0 && AdManager.shared.shouldShowAd() {
                                            print("🔀 Shuffle \(shuffleCount) - showing ad")
                                            showShuffleAd {
                                                shuffleExercise(at: index, with: newExercise)
                                            }
                                        } else {
                                            print("🔀 Shuffle \(shuffleCount) - no ad")
                                            shuffleExercise(at: index, with: newExercise)
                                        }
                                    },
                                    onSetRestTimer: { restTime in
                                        exerciseRestTimers[exerciseId] = restTime
                                    },
                                    restDuration: getRestDuration(for: exercise),
                                    customRestTimer: exerciseRestTimers[exerciseId],
                                    onNewExerciseInteraction: {
                                        // When user interacts with this exercise, clean up others
                                        if lastInteractedExerciseId != exerciseId {
                                            cleanupPreviousExercises(currentExerciseId: exerciseId)
                                        }
                                    },
                                    onShowAd: { completion in
                                        showAdBetweenSets(completion: completion)
                                    },
                                    isFirstExercise: index == 0,
                                    exerciseWithActiveTimer: $exerciseWithActiveTimer,
                                    exerciseId: exerciseId,
                                    onFocusChanged: { isFocused in
                                        if isFocused {
                                            // Set this card as active
                                            activeExerciseId = exerciseId
                                            // Auto-scroll to the active card
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                scrollProxy.scrollTo(exerciseId, anchor: .center)
                                            }
                                            // Stop any running timers on OTHER exercises
                                            if exerciseWithActiveTimer != nil && exerciseWithActiveTimer != exerciseId {
                                                print("⏹️ Stopping timer on exercise \(exerciseWithActiveTimer ?? "") - user switched to \(exerciseId)")
                                                exerciseWithActiveTimer = nil
                                            }
                                        }
                                    },
                                    onDragChanged: { targetIdx in
                                        print("🔄 Drag changed: index=\(index), target=\(targetIdx), current draggingIndex=\(String(describing: draggingIndex))")
                                        draggingIndex = index
                                        dragTargetIndex = targetIdx
                                    },
                                    onDragEnded: {
                                        let fromIndex = draggingIndex
                                        let toIndex = dragTargetIndex
                                        
                                        // Perform the move immediately (no animation - cards already in position visually)
                                        if let from = fromIndex, let to = toIndex, from != to {
                                            let item = exercises.remove(at: from)
                                            exercises.insert(item, at: min(to, exercises.count))
                                        }
                                        
                                        // Reset drag state after move
                                        draggingIndex = nil
                                        dragTargetIndex = nil
                                    },
                                    currentIndex: index,
                                    totalCount: exercises.count,
                                    isBeingDragged: draggingIndex == index,
                                    shouldShift: shiftDirection(for: index),
                                    isActiveCard: activeExerciseId == exerciseId
                                )
                                .id(exerciseId) // For ScrollViewReader
                                
                                // Show inline ad after every 2nd exercise
                                if shouldShowInlineAds && (index + 1) % 2 == 0 && index < exercises.count - 1 {
                                    NativeAdCardView()
                                        .id("inline_ad_\(index)")
                                }
                            }
                        }
                        
                        // Add Exercise button - hollow pill with gradient outline
                        Button(action: {
                            showingExerciseSelection = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20, weight: .medium))
                                Text("Add Exercise")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple.opacity(0.9)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.clear)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple.opacity(0.9)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .clipShape(Capsule())
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .background(Color.clear)
                }
                .background(Color.clear)
                .scrollDismissesKeyboard(.immediately)
                // Fade mask - content blurs/fades as it scrolls off top
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.08)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                        
                        Rectangle().fill(Color.black)
                    }
                )
            }
            .background(Color.clear)
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside text fields
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $showingExerciseSelection) {
            AddExerciseDuringWorkoutView(
                exercises: $exercises,
                onExercisesAdded: { newExercises in
                    // Initialize sets for new exercises
                    for exercise in newExercises {
                        let exerciseId = exercise.id?.uuidString ?? ""
                        if workoutManager.getSetsForExercise(id: exerciseId).isEmpty {
                            let initialSet = WorkoutSetData()
                            workoutManager.addSetToExercise(id: exerciseId, set: initialSet)
                        }
                    }
                }
            )
        }
        // Header overlay - same style as home tab
        .safeAreaInset(edge: .top) {
            // Header content
            ZStack {
                // Centered timer
                Text(workoutDuration)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Left/Right buttons
                HStack {
                    Button(action: {
                        workoutManager.navigateToHomeTab()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        if workoutManager.workoutInsights != nil {
                            Button(action: {
                                showingWorkoutInsights = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        // Favorite button
                        Button(action: {
                            HapticManager.selectionChanged() // ⚡️ Pre-warmed haptics
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isWorkoutFavorite.toggle()
                                workout.isFavorite = isWorkoutFavorite
                                
                                // Save immediately to Core Data
                                do {
                                    try viewContext.save()
                                    print("⭐ Workout favorite status: \(isWorkoutFavorite)")
                                    
                                    // Sync to cloud if authenticated
                                    if SupabaseManager.shared.isAuthenticated, let workoutId = workout.id?.uuidString {
                                        Task {
                                            do {
                                                if isWorkoutFavorite {
                                                    // Save favorite to cloud with exercise list
                                                    let exerciseNames = exercises.compactMap { $0.name }
                                                    try await SupabaseManager.shared.saveFavoriteWorkout(
                                                        workoutName: workout.name ?? "Workout",
                                                        exerciseNames: exerciseNames,
                                                        originalWorkoutId: workoutId
                                                    )
                                                } else {
                                                    // Remove favorite from cloud
                                                    try await SupabaseManager.shared.removeFavoriteWorkout(
                                                        originalWorkoutId: workoutId
                                                    )
                                                }
                                                print("☁️ Workout favorite synced to cloud!")
                                            } catch {
                                                print("⚠️ Failed to sync workout favorite to cloud: \(error)")
                                            }
                                        }
                                    }
                                } catch {
                                    print("❌ Error saving workout favorite status: \(error)")
                                }
                            }
                        }) {
                            Image(systemName: isWorkoutFavorite ? "star.fill" : "star")
                                .font(.system(size: 18))
                                .foregroundColor(isWorkoutFavorite ? .yellow : (colorScheme == .dark ? .white : .primary))
                                .scaleEffect(isWorkoutFavorite ? 1.1 : 1.0)
                        }
                        
                        Button("FINISH") {
                            // Haptic feedback on finish (UX Audit)
                            let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
                            heavyImpact.impactOccurred()
                            finishWorkout()
                        }
                        .foregroundColor(.blue)
                        .fontWeight(.bold)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.clear)
        }
        .onAppear {
            initializeWorkout()
            startTimer()
            // Initialize favorite status from workout
            isWorkoutFavorite = workout.isFavorite
            // Set first exercise as active for glow effect
            if activeExerciseId == nil {
                activeExerciseId = exercises.first?.id?.uuidString
            }
        }
        // ⚡️ SYNC: Update local exercises when WorkoutManager exercises change (e.g., after replace)
        .onChange(of: workoutManager.currentExercises) { oldExercises, newExercises in
            // Only update if the exercises actually changed
            let oldIds = Set(oldExercises.compactMap { $0.id })
            let newIds = Set(newExercises.compactMap { $0.id })
            
            if oldIds != newIds {
                #if DEBUG
                print("🔄 [SYNC] Exercises changed - updating local state")
                print("   Old: \(oldExercises.compactMap { $0.name })")
                print("   New: \(newExercises.compactMap { $0.name })")
                #endif
                exercises = newExercises
            }
        }
        .onDisappear {
            stopTimer()
            // Cancel async tasks to prevent crashes when view is dismissed
            for task in initTasks {
                task.cancel()
            }
            initTasks.removeAll()
        }
        // 🔧 Hide navigation bar to prevent "smashed header" (double back button)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingCompletionView) {
            WorkoutCompletionView(
                workout: workout,
                exercises: exercises,
                exerciseSets: workoutManager.exerciseSetsData,
                workoutDuration: elapsedTime
            )
            .environmentObject(workoutManager)
        }
        .sheet(isPresented: $showingWorkoutInsights) {
            WorkoutInsightsView(insights: workoutManager.workoutInsights)
        }
    }
    

    private func initializeWorkout() {
        // GUARD: Prevent duplicate initialization (SwiftUI may call onAppear multiple times)
        guard !initializationComplete else {
            #if DEBUG
            print("⏭️ [PERF] initializeWorkout() - Already initialized, skipping")
            #endif
            return
        }
        initializationComplete = true
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🚀 [PERF] initializeWorkout() - Starting for \(exercises.count) exercises")
        #endif
        
        // ⚡️ INSTANT: Defer ALL heavy work to next run loop cycle
        // This ensures the view renders IMMEDIATELY with exercise names visible
        // Analytics, cache lookups, and smart recommendations happen AFTER first frame
        
        #if DEBUG
        print("🚀 [PERF] initializeWorkout() - INSTANT RETURN (deferring work)")
        #endif
        
        // Defer all initialization work to allow first frame to render
        DispatchQueue.main.async { [self] in
            performDeferredInitialization()
        }
    }
    
    /// Performs initialization work after the first frame has rendered
    private func performDeferredInitialization() {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🚀 [PERF] performDeferredInitialization() - Starting")
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
        // Do NOT re-initialize here as it can cause race conditions with SwiftUI rendering
        
        // ⚡ FAST PATH: Check cache synchronously - ONLY apply cached data
        let exerciseNames = exercises.compactMap { $0.name }
        let cache = ExerciseHistoryService.shared.previousSetsCache
        var exercisesNeedingSmartRecs: [(exercise: Exercise, name: String)] = []
        
        for exerciseName in exerciseNames {
            if let cachedSets = cache[exerciseName], !cachedSets.isEmpty {
                // Data is cached - apply it synchronously (historical data)
                if let exercise = exercises.first(where: { $0.name == exerciseName }),
                   let exerciseId = exercise.id?.uuidString {
                    let previousData = cachedSets.map { cloudSet in
                        PreviousSetData(
                            setNumber: cloudSet.setNumber,
                            weight: cloudSet.weight,
                            reps: cloudSet.reps
                        )
                    }
                    previousExerciseSets[exerciseId] = previousData
                }
            } else {
                // No cached history - queue for async smart recommendation
                if let exercise = exercises.first(where: { $0.name == exerciseName }) {
                    exercisesNeedingSmartRecs.append((exercise: exercise, name: exerciseName))
                }
            }
        }
        
        #if DEBUG
        let syncTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("🚀 [PERF] Cache applied: \(String(format: "%.1f", syncTime))ms")
        print("🚀 [PERF] Exercises needing smart recs: \(exercisesNeedingSmartRecs.count)")
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
                    let recs = await MainActor.run {
                        StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: 3,
                            context: context
                        )
                    }
                    
                    let smartPreviousData = recs.enumerated().map { index, rec in
                        PreviousSetData(setNumber: index + 1, recommendation: rec)
                    }
                    
                    var smartSets: [WorkoutSetData]? = nil
                    if !recs.isEmpty {
                        smartSets = recs.map { _ in WorkoutSetData() }
                    }
                    
                    recommendations.append((exerciseId: exerciseId, data: smartPreviousData, sets: smartSets))
                    
                    #if DEBUG
                    await MainActor.run {
                        print("💡 [SMART-ASYNC] Generated for '\(exerciseName)': \(recs.first?.displayString ?? "N/A")")
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
                    print("🚀 [PERF] Smart recommendations applied: \(recommendations.count) exercises")
                    #endif
                }
            }
            initTasks.append(smartRecsTask)
        }
        
        #if DEBUG
        print("🚀 [PERF] performDeferredInitialization() - COMPLETE in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms")
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
                    // Fallback: generate smart recs (on main thread since it needs Core Data context)
                    let recommendations = await MainActor.run {
                        StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: 3,
                            context: ctx
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
                        print("💡 [SMART-FALLBACK] Generated for '\(exerciseName)'")
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
    
    /// Load historical data for a newly replaced exercise
    private func loadHistoricalDataForExercise(_ exercise: Exercise) {
        guard let exerciseId = exercise.id?.uuidString,
              let exerciseName = exercise.name else { return }
        
        #if DEBUG
        print("🔄 Loading historical data for replaced exercise: \(exerciseName)")
        #endif
        
        let currentUser = UserManager.shared.currentUser
        let ctx = viewContext
        
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
                    #if DEBUG
                    print("✅ Loaded cached historical data for '\(exerciseName)': \(previousData.count) sets")
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
                    #if DEBUG
                    print("✅ Loaded cloud historical data for '\(exerciseName)': \(previousData.count) sets")
                    #endif
                }
            } else if let user = currentUser {
                // No historical data - generate smart recommendations
                let recommendations = await MainActor.run {
                    StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                        exerciseName: exerciseName,
                        user: user,
                        numberOfSets: 3,
                        context: ctx
                    )
                }
                
                let smartPreviousData = recommendations.enumerated().map { index, rec in
                    PreviousSetData(setNumber: index + 1, recommendation: rec)
                }
                
                await MainActor.run {
                    previousExerciseSets[exerciseId] = smartPreviousData
                    #if DEBUG
                    print("💡 Generated smart recommendations for '\(exerciseName)'")
                    #endif
                }
            }
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(workoutStartTime)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func handleSetCompletion(for exercise: Exercise, setData: WorkoutSetData) {
        guard let exerciseId = exercise.id?.uuidString else { return }
        
        // Add completed set
        workoutManager.addSetToExercise(id: exerciseId, set: setData)
        
        // Rest timer is shown via the ad interstitial timing
    }
    
    private func getRestDuration(for exercise: Exercise) -> TimeInterval {
        // Default rest times based on exercise type
        switch exercise.category?.lowercased() {
        case "legs":
            return 180 // 3 minutes for legs
        case "back", "chest":
            return 120 // 2 minutes for compound movements
        default:
            return 90  // 1.5 minutes for accessories
        }
    }
    
    private func cleanupPreviousExercises(currentExerciseId: String) {
        print("🧹 Cleaning up previous exercises. Current: \(currentExerciseId)")
        print("🧹 Last interacted exercise: \(lastInteractedExerciseId ?? "none")")
        print("🧹 All exercise sets before cleanup: \(workoutManager.exerciseSetsData.mapValues { $0.count })")
        
        // Remove unfinished AND blank sets from all other exercises
        for (exerciseId, sets) in workoutManager.exerciseSetsData {
            if exerciseId != currentExerciseId {
                // Keep only completed sets that have actual data (not blank)
                let validSets = sets.filter { set in
                    // A set is valid if it's completed AND has weight or reps entered
                    set.isCompleted && (set.weight > 0 || set.reps > 0)
                }
                
                // Also remove blank uncompleted sets (weight = 0 AND reps = 0)
                let nonBlankSets = sets.filter { set in
                    set.isCompleted || set.weight > 0 || set.reps > 0
                }
                
                // Use the more restrictive filter - keep only truly valid sets
                let cleanedSets = validSets
                
                if cleanedSets.count != sets.count {
                    print("🧹 Exercise \(exerciseId): Had \(sets.count) sets, keeping \(cleanedSets.count) valid sets")
                    print("🧹 Removing \(sets.count - cleanedSets.count) blank/unfinished sets from exercise \(exerciseId)")
                    // If no valid sets remain, keep one empty set for the UI
                    workoutManager.exerciseSetsData[exerciseId] = cleanedSets.isEmpty ? [WorkoutSetData()] : cleanedSets
                } else {
                    print("🧹 Exercise \(exerciseId): All sets valid, no cleanup needed")
                }
            }
        }
        
        // Update last interacted exercise
        lastInteractedExerciseId = currentExerciseId
        print("🧹 All exercise sets after cleanup: \(workoutManager.exerciseSetsData.mapValues { $0.count })")
        print("🧹 Cleanup complete. Last interacted exercise: \(currentExerciseId)")
    }
    
    // Calculate shift direction for cards during drag reorder
    private func shiftDirection(for index: Int) -> Int {
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
    
    private func finishWorkout() {
        // Guard against duplicate finishes (prevents duplicate workout saves)
        guard !isFinishingWorkout else {
            print("⚠️ [FINISH] Already finishing workout, ignoring duplicate call")
            return
        }
        
        // Guard against finishing an already completed workout
        guard !workout.isCompleted else {
            print("⚠️ [FINISH] Workout already completed, ignoring duplicate call")
            return
        }
        
        isFinishingWorkout = true
        
        // Stop the timer immediately
        stopTimer()

        // ⚠️ IMPORTANT: Capture sets data BEFORE any async tasks or clearing
        // workoutManager.finishWorkout() will clear this data!
        let capturedSetsData = workoutManager.exerciseSetsData
        let capturedExercises = exercises
        let capturedWorkout = workout
        let capturedElapsedTime = elapsedTime
        
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

        print("📦 [FINISH] Captured \(capturedSetsData.count) exercise sets before clearing")
        for (id, sets) in capturedSetsData {
            let completed = sets.filter { $0.isCompleted }
            print("   Exercise \(id.prefix(8)): \(completed.count)/\(sets.count) completed sets")
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
                print("☁️ Cloud program day \(dayNumber) marked complete")
            }
        }
        
        // Save workout to cloud for sync across devices
        if SupabaseManager.shared.isAuthenticated {
            Task {
                do {
                    try await SupabaseManager.shared.saveWorkoutToCloud(workout: workout)
                } catch {
                    print("⚠️ Failed to sync workout to cloud: \(error)")
                }
            }
        }
        
        // 🔧 Show completion view FIRST (before clearing active state)
        // WorkoutCompletionView will call workoutManager.finishWorkout() when Done is tapped
        // This prevents the view from disappearing before the completion screen shows
        showingCompletionView = true
        
        print("✅ Workout completion view shown - workout still active until Done is tapped")
        
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
        
        // 🧠 Update the learning engine with this workout data
        // This helps the recommendation engine learn user preferences over time
        Task {
            await UserBehaviorLearningEngine.shared.refreshAfterWorkout(
                capturedWorkout,
                context: viewContext
            )
            print("🧠 [LEARNING] User preferences updated from completed workout")
            
            // 📊 Track progressions for community learning
            if let user = userManager.currentUser {
                await trackProgressions(
                    exercises: capturedExercises,
                    setsData: capturedSetsData,
                    user: user,
                    context: viewContext
                )
                
                // 🧠 ADVANCED INTELLIGENCE: Comprehensive workout analysis
                // Tracks: progression velocity, time patterns, set drop-offs, volume trends, strength ratios
                await analyzeWorkoutWithAdvancedIntelligence(
                    userId: user.id ?? UUID(),
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
    private func analyzeWorkoutWithAdvancedIntelligence(
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
        
        // Run comprehensive analysis
        await AdvancedIntelligenceService.shared.analyzeCompletedWorkout(
            userId: userId,
            exercises: exerciseAnalysisData,
            workoutDate: workoutDate,
            durationMinutes: durationMinutes,
            bodyWeightKg: bodyWeightKg,
            hadPR: false  // TODO: Detect PRs
        )
        
        print("🧠 [ADVANCED INTELLIGENCE] Workout analyzed for: progression, time patterns, volume trends, strength ratios")
    }
    
    private func cancelWorkout() {
        // Stop the timer immediately
        stopTimer()
        
        // Cancel through WorkoutManager
        workoutManager.cancelWorkout()
        
        print("❌ Workout cancelled")
    }
    
    private func removeExercise(at index: Int) {
        guard index < exercises.count else { return }
        let exerciseId = exercises[index].id?.uuidString ?? ""
        
        // Remove exercise from list
        exercises.remove(at: index)
        
        // Remove associated sets and timers
        workoutManager.exerciseSetsData.removeValue(forKey: exerciseId)
        exerciseRestTimers.removeValue(forKey: exerciseId)
        
        print("🗑️ Removed exercise at index \(index)")
    }
    
    private func shuffleExercise(at index: Int, with newExercise: Exercise) {
        guard index < exercises.count else { return }
        let oldExercise = exercises[index]
        let oldExerciseId = oldExercise.id?.uuidString ?? ""
        let newExerciseId = newExercise.id?.uuidString ?? ""
        let oldExerciseName = oldExercise.name ?? "Unknown"
        let newExerciseName = newExercise.name ?? "Unknown"
        
        // Replace exercise in list
        withAnimation(.easeInOut(duration: 0.3)) {
            exercises[index] = newExercise
        }
        
        // Transfer any sets data to the new exercise (or initialize fresh)
        let existingSets = workoutManager.exerciseSetsData[oldExerciseId] ?? []
        if existingSets.isEmpty || existingSets.allSatisfy({ !$0.isCompleted && $0.weight == 0 && $0.reps == 0 }) {
            // No meaningful data - start fresh with one empty set
            workoutManager.exerciseSetsData[newExerciseId] = [WorkoutSetData()]
        } else {
            // Transfer existing sets to new exercise
            workoutManager.exerciseSetsData[newExerciseId] = existingSets
        }
        
        // Clean up old exercise data
        workoutManager.exerciseSetsData.removeValue(forKey: oldExerciseId)
        exerciseRestTimers.removeValue(forKey: oldExerciseId)
        
        // Transfer rest timer preference if set
        if let customRest = exerciseRestTimers[oldExerciseId] {
            exerciseRestTimers[newExerciseId] = customRest
        }
        
        print("🔀 Shuffled '\(oldExerciseName)' → '\(newExerciseName)'")
        
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
    private func showAdBetweenSets(completion: @escaping () -> Void) {
        // Increment completed sets counter
        completedSetsCount += 1
        
        // Show interstitial ad every 3 completed sets
        guard completedSetsCount % 3 == 0 else {
            print("📺 Set \(completedSetsCount) - skipping ad")
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        print("📺 Set \(completedSetsCount) - attempting to show ad")
        
        // Check if ads should be shown
        guard AdManager.shared.shouldShowAd() else {
            print("📺 Ads disabled or not ready, continuing without ad")
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        // Get the root view controller to present the ad
        guard let viewController = RootViewControllerFinder.find() else {
            print("📺 Could not find view controller, skipping ad")
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
                print("📺 Ad completed, resuming workout")
                isShowingAd = false
                completion()
            }
        }
    }
    
    /// Shows an ad for shuffle action (every 2nd shuffle)
    private func showShuffleAd(completion: @escaping () -> Void) {
        // Get the root view controller to present the ad
        guard let viewController = RootViewControllerFinder.find() else {
            print("📺 Could not find view controller, skipping shuffle ad")
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
                print("📺 Shuffle ad completed")
                isShowingAd = false
                completion()
            }
        }
    }
    
    private func saveWorkoutData() {
        // Update the workout with completion data
        workout.isCompleted = true
        workout.duration = Int32(elapsedTime)
        
        // Generate custom workout name based on completed exercises
        workout.name = generateCustomWorkoutName()
        
        // ⚠️ IMPORTANT: Clear any existing WorkoutExercise entries to prevent duplicates
        // This can happen if finishWorkout() is somehow called multiple times
        if let existingExercises = workout.exercises as? Set<WorkoutExercise>, !existingExercises.isEmpty {
            print("⚠️ [SAVE] Clearing \(existingExercises.count) existing workout exercises to prevent duplicates")
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
                workoutSet.weight = setData.weight
                workoutSet.reps = Int16(setData.reps)
                workoutSet.isCompleted = setData.isCompleted
                workoutSet.restTime = Int32(setData.restTime)
                workoutSet.setType = setData.setType.rawValue  // Save set type (Warmup, Dropset, Failure, etc.)
                workoutSet.workoutExercise = workoutExercise
            }
        }
        
        do {
            try viewContext.save()
            print("✅ Workout data saved successfully!")
            
            // 🔄 Record to SmartVariantRotationEngine for intelligent recommendations
            recordWorkoutToVariantEngine()
            
            // Sync workout to cloud (in background)
            // Note: Exercise history is saved separately in finishWorkout() with captured data
            Task {
                await syncWorkoutToCloud()
            }
        } catch {
            print("❌ Error saving workout: \(error)")
        }
    }
    
    /// Record workout completion to SmartVariantRotationEngine for smarter recommendations
    private func recordWorkoutToVariantEngine() {
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
    /// Uses Apple Fitness-quality calorie calculation
    private func saveWorkoutToAppleHealth(startDate: Date, duration: TimeInterval, exerciseCount: Int) {
        // Check if user wants to save workouts to Health
        guard HealthKitManager.shared.saveWorkoutsToHealth else {
            print("🍎 [APPLE HEALTH] Skipping - user disabled Health sync")
            return
        }
        
        // Check if HealthKit is authorized
        guard HealthKitManager.shared.isAuthorized else {
            print("🍎 [APPLE HEALTH] Skipping - not authorized")
            return
        }
        
        Task {
            do {
                // Determine workout type based on exercises
                let workoutType = determineWorkoutType()
                
                // Build detailed exercise data for accurate calorie calculation
                let exerciseCalorieData = buildExerciseCalorieData()
                
                // Calculate calories with Apple Fitness-level accuracy
                let calorieResult = await HealthKitManager.shared.calculateDetailedCalories(
                    exercises: exerciseCalorieData,
                    totalDurationSeconds: duration
                )
                
                // Generate workout name
                let workoutName = workout.name ?? generateCustomWorkoutName()
                
                // Save to Apple Health
                try await HealthKitManager.shared.saveWorkoutToHealth(
                    workoutName: workoutName,
                    startDate: startDate,
                    endDate: Date(),
                    durationSeconds: duration,
                    caloriesBurned: calorieResult.totalCalories,
                    exerciseCount: exerciseCount,
                    workoutType: workoutType
                )
                
                print("🍎 [APPLE HEALTH] Workout saved! Exercise ring filled 💚")
                print("🔥 Calories: \(Int(calorieResult.totalCalories)) (MET: \(String(format: "%.1f", calorieResult.workoutMET)))")
                
            } catch {
                // Don't fail the workout if HealthKit save fails
                print("⚠️ [APPLE HEALTH] Could not save workout: \(error.localizedDescription)")
            }
        }
    }
    
    /// Build detailed exercise data for accurate calorie calculation
    private func buildExerciseCalorieData() -> [ExerciseCalorieData] {
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
    private func isCompoundExercise(_ exercise: Exercise) -> Bool {
        let name = (exercise.name ?? "").lowercased()
        let compoundKeywords = [
            "squat", "deadlift", "bench press", "row", "press", "pull up", "pullup",
            "chin up", "chinup", "dip", "lunge", "clean", "snatch", "thruster",
            "push up", "pushup", "overhead press", "military press"
        ]
        
        return compoundKeywords.contains { name.contains($0) }
    }
    
    /// Determine the workout type for Apple Health based on exercises
    private func determineWorkoutType() -> HealthKitManager.WorkoutActivityType {
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
    private func saveExercisePerformanceHistoryWithData(
        exercises: [Exercise],
        setsData: [String: [WorkoutSetData]],
        workout: Workout,
        elapsedTime: TimeInterval
    ) async {
        print("📊 [HISTORY SAVE] Starting exercise history save...")
        print("📊 [HISTORY SAVE] User authenticated: \(SupabaseManager.shared.isAuthenticated)")
        print("📊 [HISTORY SAVE] User ID: \(SupabaseManager.shared.currentUser?.id.uuidString ?? "nil")")
        print("📊 [HISTORY SAVE] Captured sets data count: \(setsData.count)")
        
        guard SupabaseManager.shared.isAuthenticated else {
            print("❌ [HISTORY SAVE] User not authenticated, skipping exercise history save")
            return
        }
        
        print("📊 [HISTORY SAVE] Processing \(exercises.count) exercises...")
        
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = setsData[exerciseId],
                  !sets.isEmpty else {
                print("⏭️ [HISTORY SAVE] Skipping exercise (no sets data): \(exercise.name ?? "Unknown") - ID: \(exercise.id?.uuidString.prefix(8) ?? "nil")")
                continue
            }
            
            // Only save if there are completed sets
            let completedSets = sets.filter { $0.isCompleted && ($0.weight > 0 || $0.reps > 0) }
            guard !completedSets.isEmpty else {
                print("⏭️ [HISTORY SAVE] Skipping exercise (no completed sets): \(exercise.name ?? "Unknown")")
                continue
            }
            
            print("💾 [HISTORY SAVE] Saving '\(exercise.name ?? "Unknown")' - \(completedSets.count) completed sets")
            for (i, set) in completedSets.enumerated() {
                print("   Set \(i+1): \(Int(set.weight))lbs × \(set.reps) reps (completed: \(set.isCompleted))")
            }
            
            do {
                try await ExerciseHistoryService.shared.saveExercisePerformance(
                    exerciseName: exercise.name ?? "Exercise",
                    exerciseCategory: exercise.category,
                    workoutId: workout.id,
                    sets: Array(sets),
                    workoutDurationSeconds: Int(elapsedTime)
                )
                print("✅ [HISTORY SAVE] Successfully saved '\(exercise.name ?? "Unknown")'")
            } catch {
                print("❌ [HISTORY SAVE] Failed to save '\(exercise.name ?? "")': \(error)")
                print("❌ [HISTORY SAVE] Error details: \(String(describing: error))")
            }
        }
        
        print("📊 [HISTORY SAVE] Exercise history save complete!")
    }
    
    /// Track progressions for community learning
    private func trackProgressions(
        exercises: [Exercise],
        setsData: [String: [WorkoutSetData]],
        user: User,
        context: NSManagedObjectContext
    ) async {
        
        print("📈 [PROGRESSION] Analyzing workout for progressions...")
        
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
                    
                    print("📈 [PROGRESSION] '\(exerciseName)': \(Int(previousAvgWeight))→\(Int(currentAvgWeight))lbs (+\(Int(progression)))")
                    
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
        
        print("✅ [PROGRESSION] Progression tracking complete!")
    }
    
    /// Fetch previous workout's sets for an exercise (for comparing progression)
    private func fetchPreviousWorkoutSets(
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
                .filter { $0.isCompleted && $0.weight > 0 }
                .map { (weight: $0.weight, reps: Int($0.reps)) }
            
            return completedSets.isEmpty ? nil : completedSets
            
        } catch {
            return nil
        }
    }
    
    private func syncWorkoutToCloud() async {
        guard SupabaseManager.shared.isAuthenticated else {
            print("ℹ️ User not authenticated, skipping workout cloud sync")
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
            print("✅ Workout synced to cloud!")
            
            // Log exercise usage for popularity tracking (invisible to users)
            await logExerciseUsageToCloud()
            
        } catch {
            print("❌ Error syncing workout to cloud: \(error)")
            // Don't block the app if cloud sync fails
        }
    }
    
    private func logExerciseUsageToCloud() async {
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
                print("⚠️ Failed to log exercise usage: \(error)")
            }
        }
        
        print("📊 Exercise usage logged for analytics")
    }
    
    private func generateCustomWorkoutName() -> String {
        // Get all completed exercises with their muscle groups
        var muscleGroupCounts: [String: Int] = [:]
        var completedExercises: [Exercise] = []
        
        // Count exercises by muscle group
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString,
                  let sets = workoutManager.exerciseSetsData[exerciseId],
                  sets.contains(where: { $0.isCompleted }) else { continue }
            
            completedExercises.append(exercise)
            
            // Parse muscle groups from the exercise
            let muscleGroups = parseMuscleGroups(from: exercise)
            for muscleGroup in muscleGroups {
                muscleGroupCounts[muscleGroup, default: 0] += 1
            }
        }
        
        // If no completed exercises, return default name
        guard !completedExercises.isEmpty else {
            return "Workout - \(formatDate())"
        }
        
        // Sort muscle groups by count (most worked first)
        let sortedMuscleGroups = muscleGroupCounts.sorted { $0.value > $1.value }
        
        // Generate name based on top muscle groups
        let workoutName: String
        if sortedMuscleGroups.count == 1 {
            // Single muscle group
            workoutName = "\(sortedMuscleGroups[0].key)"
        } else if sortedMuscleGroups.count >= 2 {
            // Multiple muscle groups - take top 2
            let primaryMuscle = sortedMuscleGroups[0].key
            let secondaryMuscle = sortedMuscleGroups[1].key
            
            // Check if it's a balanced split or one dominant muscle
            if sortedMuscleGroups[0].value == sortedMuscleGroups[1].value {
                workoutName = "\(primaryMuscle) & \(secondaryMuscle)"
            } else if sortedMuscleGroups[0].value > sortedMuscleGroups[1].value * 2 {
                // Primary muscle is dominant
                workoutName = "\(primaryMuscle) Focus"
            } else {
                workoutName = "\(primaryMuscle) & \(secondaryMuscle)"
            }
        } else {
            // Fallback to exercise-based naming
            if completedExercises.count == 1 {
                workoutName = completedExercises[0].name ?? "Single Exercise"
            } else {
                workoutName = "Mixed Workout"
            }
        }
        
        return "\(workoutName) - \(formatDate())"
    }
    
    private func parseMuscleGroups(from exercise: Exercise) -> [String] {
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
    
    private func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: Date())
    }
    
    @ViewBuilder
    private func programDayBadge(dayNumber: Int, focus: String) -> some View {
        HStack(spacing: 8) {
            // Day badge
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Day \(dayNumber)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            
            // Separator
            Text("•")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            // Focus badge
            HStack(spacing: 4) {
                Image(systemName: "target")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(focus)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.cardBackground)
    }
    
}

struct ExerciseCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    let exercise: Exercise
    @Binding var sets: [WorkoutSetData]
    let previousSets: [PreviousSetData]
    let onAddSet: () -> Void
    let onRemoveExercise: () -> Void
    let onReplaceExercise: (Exercise) -> Void // Pass the new exercise for historical data loading
    let onShuffleExercise: (Exercise) -> Void // Callback to shuffle to a similar exercise
    let onSetRestTimer: (TimeInterval) -> Void
    let restDuration: TimeInterval
    let customRestTimer: TimeInterval?
    let onNewExerciseInteraction: () -> Void
    let onShowAd: (@escaping () -> Void) -> Void // Callback to show ad between sets
    var isFirstExercise: Bool = false // Whether this is the first exercise (for auto-focus)
    @Binding var exerciseWithActiveTimer: String? // Track which exercise has the active timer globally
    var exerciseId: String = "" // This exercise's ID
    var onFocusChanged: ((Bool) -> Void)? = nil // Callback when focus changes
    var onDragChanged: ((Int) -> Void)? = nil // Callback when drag position changes with target index
    var onDragEnded: (() -> Void)? = nil // Callback when drag ends
    var currentIndex: Int = 0
    var totalCount: Int = 1
    var isBeingDragged: Bool = false
    var shouldShift: Int = 0 // -1 shift up, 0 no shift, 1 shift down
    var isActiveCard: Bool = false // Whether this card is currently active/focused
    
    @State private var showingExerciseDetail = false
    @State private var shuffledExerciseIds: Set<UUID> = [] // Track which exercises we've already shuffled to
    @State private var prefetchedExercises: [Exercise] = [] // Prefetched similar exercises ready to shuffle
    @State private var showingActionSheet = false
    @State private var showingRestTimerSheet = false
    @State private var showingReplaceExercise = false
    @State private var showingRenameExercise = false
    @State private var activeTimerSetNumber: Int? = nil // Track which set currently has an active timer
    @State private var isFavorite: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasAppeared: Bool = false // Track first appearance to skip initial animation
    
    private let cardHeight: CGFloat = 180 // Approximate card height for drag calculations
    
    // Computed property to determine if this exercise is currently being worked on
    private var isExerciseActive: Bool {
        // Exercise is active ONLY if there's an active rest timer running
        // This ensures only the exercise with a live timer has scrolling text
        return activeTimerSetNumber != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Exercise header
            exerciseHeader
            
            // Sets table
            setsTable
            
            // Add set button
            addSetButton
        }
        .background(Color.cardBackground)
        .cornerRadius(16)
        .contentShape(Rectangle()) // Make entire card tappable
        .onTapGesture {
            // Set this card as active when tapped anywhere
            onFocusChanged?(true)
        }
        .overlay(
            // Active card glow effect
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActiveCard ? 2 : 0
                )
        )
        .shadow(color: isActiveCard ? Color.blue.opacity(0.3) : .black.opacity(0.15), 
                radius: isActiveCard ? 12 : 8, 
                x: 0, 
                y: isActiveCard ? 4 : 6)
        // Drag offset for card being dragged, shift offset for other cards making room
        .offset(y: isBeingDragged ? dragOffset : CGFloat(shouldShift) * cardHeight)
        .scaleEffect(isBeingDragged ? 1.02 : 1.0)
        .zIndex(isBeingDragged ? 100 : (isActiveCard ? 50 : 0))
        .animation(.easeInOut(duration: 0.2), value: shouldShift)
        .animation(hasAppeared ? .easeInOut(duration: 0.2) : nil, value: isActiveCard)
        .animation(nil, value: isBeingDragged)
        .sheet(isPresented: $showingExerciseDetail) {
            NavigationView {
                ExerciseDetailView(exercise: exercise)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingExerciseDetail = false
                            }
                        }
                    }
            }
        }
        .confirmationDialog("Exercise Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Remove Exercise", role: .destructive) {
                onRemoveExercise()
            }
            Button("Replace Exercise") {
                showingReplaceExercise = true
            }
            Button("Rename Exercise") {
                showingRenameExercise = true
            }
            Button("Add Rest Timer") {
                showingRestTimerSheet = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingRestTimerSheet) {
            RestTimerSetupView(onSetTimer: onSetRestTimer)
        }
        .sheet(isPresented: $showingReplaceExercise) {
            CustomWorkoutBuilderView(
                replacing: exercise,
                onSelect: { newExercise in
                    // Replace this exercise with the selected one
                    WorkoutManager.shared.replaceExercise(exercise, with: newExercise)
                    // Pass the new exercise so historical data can be loaded
                    onReplaceExercise(newExercise)
                }
            )
            .environmentObject(WorkoutManager.shared)
            .environmentObject(UserManager.shared)
        }
        .sheet(isPresented: $showingRenameExercise) {
            RenameExerciseView(exercise: exercise)
        }
        .onAppear {
            // ⚡ PERF: Access cached property directly (no Core Data fetch)
            // The exercise object already has this loaded from the fetch
            guard !exercise.isFault else {
                print("⚠️ Exercise is a fault in onAppear, skipping favorite init")
                return
            }
            isFavorite = exercise.isFavorite
            
            // Enable animations after first render (glow appears instantly)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
            
            // Prefetch similar exercises AFTER a delay to not block initial interaction
            // Stagger based on exercise index to spread out the work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(currentIndex) * 0.1) {
                prefetchSimilarExercises()
            }
        }
        .onChange(of: exercise.id) { _, newId in
            // Refetch when exercise changes (after a shuffle)
            guard newId != nil else {
                print("⚠️ Exercise ID became nil, skipping prefetch")
                return
            }
            prefetchSimilarExercises()
        }
        .onChange(of: exerciseWithActiveTimer) { _, newActiveExercise in
            // If another exercise became active with timer, stop this exercise's timer
            if newActiveExercise != exerciseId && activeTimerSetNumber != nil {
                print("⏹️ [\(exercise.name ?? "?")] Stopping timer - user switched to different exercise")
                activeTimerSetNumber = nil
            }
        }
    }
    
    // ⚡ PERF: Cache exercise name to avoid repeated property access
    private var exerciseName: String {
        exercise.name ?? "Exercise"
    }
    
    // MARK: - Prefetch Similar Exercises (Using Smart Alternative Engine)
    private func prefetchSimilarExercises() {
        Task.detached(priority: .background) {
            let userEquipment = await MainActor.run { UserManager.shared.currentUser?.getEquipment() ?? [] }
            let currentExercise = exercise
            let alreadyShuffled = shuffledExerciseIds
            
            // Use the smart alternative engine for intelligent matching
            let alternatives = await AlternativeExerciseEngine.shared.getAlternatives(
                for: currentExercise,
                userEquipment: userEquipment,
                excludeIds: alreadyShuffled,
                maxResults: 5
            )
            
            let exercises = alternatives.map { $0.exercise }
            
            await MainActor.run {
                prefetchedExercises = exercises
                if !alternatives.isEmpty {
                    print("📦 Prefetched \(exercises.count) smart alternatives for '\(exercise.name ?? "")'")
                    print("   Top match: \(alternatives.first?.exercise.name ?? "none") (score: \(alternatives.first?.score ?? 0))")
                }
            }
        }
    }
    
    // MARK: - Shuffle to Similar Exercise (Smart Alternative Matching)
    private func shuffleToSimilarExercise() {
        // Use prefetched exercises if available
        if let newExercise = prefetchedExercises.first {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            // Track this exercise as shuffled
            if let newId = newExercise.id {
                shuffledExerciseIds.insert(newId)
            }
            
            // Remove from prefetched list
            prefetchedExercises.removeFirst()
            
            print("🔄 Shuffled to prefetched alternative: \(newExercise.name ?? "")")
            
            // Call the parent to replace
            onShuffleExercise(newExercise)
            return
        }
        
        // Fallback: Use smart alternative engine on-demand if prefetch is empty
        let userEquipment = UserManager.shared.currentUser?.getEquipment() ?? []
        
        // Build set of IDs to exclude (current exercise + already shuffled)
        var excludeIds = shuffledExerciseIds
        if let currentId = exercise.id {
            excludeIds.insert(currentId)
        }
        
        // Use the smart alternative engine
        if let newExercise = AlternativeExerciseEngine.shared.getBestAlternative(
            for: exercise,
            userEquipment: userEquipment,
            excludeIds: excludeIds
        ) {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            // Track this exercise as shuffled
            if let newId = newExercise.id {
                shuffledExerciseIds.insert(newId)
            }
            
            print("🔄 Shuffled to smart alternative: \(newExercise.name ?? "")")
            
            // Call the parent to replace
            onShuffleExercise(newExercise)
        } else {
            // No similar exercises found - subtle haptic to indicate nothing happened
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            print("⚠️ No alternatives found for: \(exercise.name ?? "")")
        }
    }
    
    private var exerciseHeader: some View {
        HStack(spacing: 0) {
            // Exercise title - scrolling marquee for long names, long press to drag
            // Uses nickname if user has set one, otherwise official name
            MarqueeText(
                text: exercise.displayName,
                font: .headline,
                weight: .semibold,
                shouldAnimate: isActiveCard // Only animate when this card is active
            )
                .foregroundColor(isBeingDragged ? .blue : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
                .transaction { transaction in
                    transaction.animation = .easeInOut(duration: 0.2)
                }
                .onTapGesture {
                    if !isBeingDragged {
                        showingExerciseDetail = true
                    }
                }
                .onLongPressGesture(minimumDuration: 0.75, pressing: { isPressing in
                    // Don't do anything on pressing - wait for the full duration
                    print("👆 Long press pressing: \(isPressing)")
                }, perform: {
                    // Long press completed - NOW activate drag mode
                    print("✅ Long press completed - activating drag mode for index \(currentIndex)")
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onDragChanged?(currentIndex)
                })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { value in
                            guard isBeingDragged else { 
                                print("⚠️ Drag ignored - not in drag mode")
                                return 
                            }
                            dragOffset = value.translation.height
                            
                            // Calculate target index and notify parent
                            let movement = Int(round(value.translation.height / cardHeight))
                            let targetIndex = max(0, min(totalCount - 1, currentIndex + movement))
                            onDragChanged?(targetIndex)
                        }
                        .onEnded { value in
                            guard isBeingDragged else { 
                                print("⚠️ Drag end ignored - not in drag mode")
                                return 
                            }
                            print("🏁 Drag gesture ended")
                            // Reset drag offset instantly - parent handles the rest
                            dragOffset = 0
                            
                            // Notify parent to finalize the move
                            onDragEnded?()
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                )
            
            // Fixed icons on the right
            HStack(spacing: 12) {
                // Shuffle button - replaces exercise with a similar one
                Button(action: {
                    shuffleToSimilarExercise()
                }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Favorite star button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isFavorite.toggle()
                        
                        // Fetch fresh copy by ID to avoid stale references
                        guard let exerciseId = exercise.id else {
                            print("❌ Cannot favorite: exercise has no ID")
                            return
                        }
                        
                        let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", exerciseId as CVarArg)
                        fetchRequest.fetchLimit = 1
                        
                        do {
                            if let freshExercise = try viewContext.fetch(fetchRequest).first {
                                freshExercise.isFavorite = isFavorite
                                try viewContext.save()
                                print("⭐ Exercise '\(freshExercise.name ?? "")' favorite status: \(isFavorite)")
                                
                                // 🔄 VARIANT ENGINE: Record favorite for variant rotation
                                // Next time this muscle is trained, show a VARIANT of this exercise
                                let exerciseFamily = freshExercise.value(forKey: "exerciseFamily") as? String ?? ""
                                Task { @MainActor in
                                    if isFavorite {
                                        SmartVariantRotationEngine.shared.recordFavorite(
                                            exerciseName: freshExercise.name ?? "",
                                            family: exerciseFamily
                                        )
                                    } else {
                                        SmartVariantRotationEngine.shared.recordUnfavorite(
                                            exerciseName: freshExercise.name ?? "",
                                            family: exerciseFamily
                                        )
                                    }
                                }
                                
                                // Sync to cloud if authenticated
                                if SupabaseManager.shared.isAuthenticated {
                                    Task {
                                        do {
                                            // Pass exercise name for reliable syncing (IDs change, names don't)
                                            try await SupabaseManager.shared.toggleFavorite(
                                                exerciseId: exerciseId.uuidString,
                                                exerciseType: "default",
                                                exerciseName: freshExercise.name
                                            )
                                            print("☁️ Favorite synced to cloud: \(freshExercise.name ?? "unknown")")
                                        } catch {
                                            print("⚠️ Failed to sync favorite to cloud: \(error)")
                                        }
                                    }
                                }
                                
                                // Notify exercise library to refresh
                                NotificationCenter.default.post(name: NSNotification.Name("FavoriteExerciseChanged"), object: nil)
                            }
                        } catch {
                            print("❌ Error saving favorite status: \(error)")
                        }
                    }
                }) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundColor(isFavorite ? .yellow : .secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Single menu button for all actions
                Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(.systemGray6))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .fixedSize() // Keep icons at their natural size
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 42) // Fixed height for header
    }
    
    private var workoutSummary: String {
        return "\(workoutDuration)"
    }
    
    private var workoutDuration: String {
        let totalTime = sets.reduce(0) { $0 + $1.restTime }
        let minutes = Int(totalTime) / 60
        let seconds = Int(totalTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var setsTable: some View {
        VStack(spacing: 0) {
            // Table header - check if we have smart recommendations
            let hasSmartRecs = previousSets.first?.isSmartRecommendation ?? false
            
            HStack(spacing: 8) {
                Text("SET")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                
                HStack(spacing: 3) {
                    if hasSmartRecs {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("SUGGESTED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    } else {
                        Text("PREVIOUS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("LB")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .center)
                
                Text("REPS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .center)
                
                Spacer()
                    .frame(width: 34)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.cardBackgroundSecondary)
            
            // Sets
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, setItem in
                SwipeableSetRow(
                    onDelete: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            // Stop any active timer for this set
                            if activeTimerSetNumber == index + 1 {
                                activeTimerSetNumber = nil
                            }
                            // If this is the only set, replace with fresh set instead of deleting
                            if sets.count == 1 {
                                sets[0] = WorkoutSetData()
                            } else {
                                sets.remove(at: index)
                            }
                        }
                    }
                ) {
                    SetRowView(
                        setNumber: index + 1,
                        setData: setItem,  // Pass the object directly, not a binding
                        previousSet: getPreviousSetData(for: index + 1),
                        onSetCompleted: {
                            // Timer starts automatically in SetRowView
                            // DO NOT auto-add new set - user must tap "Add Set" button
                            print("✅ Set \(index + 1) completed - timer started, waiting for user to add next set")
                        },
                        isLastSet: index == sets.count - 1,
                        restDuration: customRestTimer ?? restDuration,
                        onTimerShouldStop: { setNumberToStop in
                            // This callback is used to stop a specific set's timer
                            // The logic is now handled by the activeTimerSetNumber binding
                        },
                        onNewExerciseInteraction: onNewExerciseInteraction,
                        activeTimerSetNumber: $activeTimerSetNumber,
                        exerciseWithActiveTimer: $exerciseWithActiveTimer,
                        exerciseId: exerciseId,
                        onShowAd: onShowAd,
                        shouldAutoFocus: (isFirstExercise && index == 0 && !setItem.isCompleted) || (index == sets.count - 1 && index > 0 && !setItem.isCompleted), // Auto-focus first set of first exercise OR newly added sets after ad
                        onFocusChanged: onFocusChanged
                    )
                }
                
                if index < sets.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var addSetButton: some View {
        Button(action: onAddSet) {
            Text("ADD SET")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.08)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(
            RoundedCorner(radius: 12, corners: [.bottomLeft, .bottomRight])
        )
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Get previous set data for a given set number
    /// If the set number exceeds previous workout's sets, use the last previous set
    private func getPreviousSetData(for setNumber: Int) -> PreviousSetData? {
        // First, try to find exact match for the set number
        if let exactMatch = previousSets.first(where: { $0.setNumber == setNumber }) {
            return exactMatch
        }
        
        // If no exact match and we have previous sets, use the last one
        // This handles the case where user does more sets than last time
        if !previousSets.isEmpty {
            return previousSets.max(by: { $0.setNumber < $1.setNumber })
        }
        
        return nil
    }
}

// MARK: - Swipeable Set Row Wrapper
struct SwipeableSetRow<Content: View>: View {
    let onDelete: () -> Void
    let content: Content
    
    @State private var offset: CGFloat = 0
    @State private var isShowingDelete = false
    
    private let deleteButtonWidth: CGFloat = 80
    
    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button (revealed when swiping)
            if isShowingDelete || offset < 0 {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = 0
                        isShowingDelete = false
                    }
                    onDelete()
                }) {
                    ZStack {
                        Color.red
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 20))
                            Text("Delete")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                    }
                    .frame(width: deleteButtonWidth)
                }
            }
            
            // Main content
            content
                .background(Color.cardBackgroundSecondary)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20) // Require 20pt drag before triggering (less sensitive)
                        .onChanged { value in
                            // Only allow left swipe (negative translation) and must be mostly horizontal
                            let isHorizontalSwipe = abs(value.translation.width) > abs(value.translation.height)
                            if value.translation.width < 0 && isHorizontalSwipe {
                                offset = max(value.translation.width, -deleteButtonWidth)
                            } else if isShowingDelete {
                                // Allow dragging back to close
                                offset = min(0, -deleteButtonWidth + value.translation.width)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                // If swiped more than 60% of delete button width, show delete button
                                if value.translation.width < -deleteButtonWidth * 0.6 {
                                    offset = -deleteButtonWidth
                                    isShowingDelete = true
                                } else {
                                    offset = 0
                                    isShowingDelete = false
                                }
                            }
                        }
                )
        }
        .clipped()
    }
}

struct SetRowView: View {
    let setNumber: Int
    @ObservedObject var setData: WorkoutSetData  // Changed from @Binding to @ObservedObject
    let previousSet: PreviousSetData? // Previous workout's set data
    let onSetCompleted: () -> Void
    let isLastSet: Bool
    let restDuration: TimeInterval
    let onTimerShouldStop: (Int) -> Void // Callback to stop other timers
    let onNewExerciseInteraction: () -> Void // Callback when user starts new exercise
    @Binding var activeTimerSetNumber: Int? // Which set currently has an active timer
    @Binding var exerciseWithActiveTimer: String? // Track which exercise has the active timer globally
    var exerciseId: String = "" // This exercise's ID for timer tracking
    let onShowAd: (@escaping () -> Void) -> Void // Callback to show ad between sets
    let shouldAutoFocus: Bool // Whether this set should auto-focus (newly added)
    var onFocusChanged: ((Bool) -> Void)? = nil // Callback when focus changes
    
    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @FocusState private var isWeightFocused: Bool
    @FocusState private var isRepsFocused: Bool
    @StateObject private var restTimer = RestTimer()
    @State private var hasInitialized = false
    
    // Debounce timer for weight/reps updates to prevent excessive re-renders
    @State private var weightDebounceTask: Task<Void, Never>?
    @State private var repsDebounceTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Set number/type indicator - tap to change set type
                Menu {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Button(action: {
                            HapticManager.selectionChanged()
                            withAnimation(.easeInOut(duration: 0.15)) {
                                setData.setType = type
                            }
                        }) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(type.rawValue)
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: type.icon)
                            }
                        }
                    }
                } label: {
                    // Display letter for special types, or number for normal
                    Text(setData.setType.displayLetter ?? "\(setNumber)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(setData.setType.color)
                        .frame(width: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                
                // Previous set info - show last workout's data or smart recommendation
                HStack(spacing: 4) {
                    if let prev = previousSet {
                        if prev.isSmartRecommendation {
                            // Smart recommendation with special styling
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("\(Int(prev.weight))×\(prev.reps)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
                        } else {
                            // Historical data
                            Text(prev.displayString)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("-")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            // Weight input - use previous workout's weight as placeholder
            // Uses SelectAllTextField for better editing UX (selects all on focus)
            SelectAllTextField(
                placeholder: previousSet != nil ? "\(Int(previousSet!.weight))" : "45",
                text: $weightText,
                keyboardType: .numberPad,
                font: .systemFont(ofSize: 17, weight: .semibold),
                textAlignment: .center,
                textColor: setData.isCompleted ? .white : .label, // White when completed
                onFocusChange: { isFocused in
                    isWeightFocused = isFocused
                    if isFocused {
                        onNewExerciseInteraction()
                        // Notify parent to scroll to this card and set it as active
                        onFocusChanged?(true)
                    } else {
                        // Update setData when focus is lost
                        if let weight = Double(weightText) {
                            setData.weight = weight
                        }
                    }
                }
            )
            .frame(width: 70, height: 38)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                // Glow border when this field is focused
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: isWeightFocused ? 2 : 0)
            )
            .shadow(color: isWeightFocused ? Color.blue.opacity(0.4) : Color.clear, radius: 4)
            .onChange(of: weightText) { _, newValue in
                // Cancel previous debounce task
                weightDebounceTask?.cancel()
                
                // Debounce: wait 150ms before updating setData to prevent lag
                weightDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                    guard !Task.isCancelled else { return }
                    if let weight = Double(newValue) {
                        setData.weight = weight
                    }
                }
            }
                
            // Reps input - use previous workout's reps as placeholder
            // Uses SelectAllTextField for better editing UX (selects all on focus)
            SelectAllTextField(
                placeholder: previousSet != nil ? "\(previousSet!.reps)" : "8",
                text: $repsText,
                keyboardType: .numberPad,
                font: .systemFont(ofSize: 17, weight: .semibold),
                textAlignment: .center,
                textColor: setData.isCompleted ? .white : .label, // White when completed
                onFocusChange: { isFocused in
                    isRepsFocused = isFocused
                    if isFocused {
                        onNewExerciseInteraction()
                        // Notify parent to scroll to this card and set it as active
                        onFocusChanged?(true)
                    } else {
                        // Update setData when focus is lost
                        if let reps = Int(repsText) {
                            setData.reps = reps
                        }
                    }
                }
            )
            .frame(width: 70, height: 38)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                // Glow border when this field is focused
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: isRepsFocused ? 2 : 0)
            )
            .shadow(color: isRepsFocused ? Color.blue.opacity(0.4) : Color.clear, radius: 4)
            .onChange(of: repsText) { _, newValue in
                // Cancel previous debounce task
                repsDebounceTask?.cancel()
                
                // Debounce: wait 150ms before updating setData to prevent lag
                repsDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                    guard !Task.isCancelled else { return }
                    if let reps = Int(newValue) {
                        setData.reps = reps
                    }
                }
            }
                
                // Completion checkmark
                Button(action: {
                    // IMPORTANT: Flush any pending debounce tasks before completing set
                    // This ensures the latest weight/reps values are captured
                    weightDebounceTask?.cancel()
                    repsDebounceTask?.cancel()
                    
                    // Determine final weight: user input > pre-filled data > placeholder > default
                    let finalWeight: Double
                    if let weight = Double(weightText), weight > 0 {
                        finalWeight = weight
                    } else if setData.weight > 0 {
                        // Use pre-filled value from previous set
                        finalWeight = setData.weight
                    } else if let prev = previousSet {
                        // Use placeholder from previous workout
                        finalWeight = prev.weight
                    } else {
                        finalWeight = 45 // Default
                    }
                    
                    // Determine final reps: user input > pre-filled data > placeholder > default
                    let finalReps: Int
                    if let reps = Int(repsText), reps > 0 {
                        finalReps = reps
                    } else if setData.reps > 0 {
                        // Use pre-filled value from previous set
                        finalReps = setData.reps
                    } else if let prev = previousSet {
                        // Use placeholder from previous workout
                        finalReps = prev.reps
                    } else {
                        finalReps = 8 // Default
                    }
                    
                    // Update setData with final values
                    setData.weight = finalWeight
                    setData.reps = finalReps
                    
                    // Update text fields to show the confirmed values (turns them white)
                    weightText = "\(Int(finalWeight))"
                    repsText = "\(finalReps)"
                    
                    // If already completed, allow unchecking
                    if setData.isCompleted {
                        #if DEBUG
                        print("🔄 Set \(setNumber): Unchecked - stopping timer")
                        #endif
                        setData.isCompleted = false
                        restTimer.stop()
                        if activeTimerSetNumber == setNumber {
                            activeTimerSetNumber = nil
                        }
                        return
                    }
                    
                    // Set is being completed - show ad FIRST, then mark complete
                    #if DEBUG
                    print("🔥 Set \(setNumber): Initiating completion...")
                    #endif
                    
                    // IMMEDIATELY stop ALL other timers by setting this as the active timer
                    activeTimerSetNumber = setNumber
                    // Also mark THIS exercise as having the active timer (stops other exercises' timers)
                    exerciseWithActiveTimer = exerciseId
                    
                    let finalRestDuration = restDuration > 0 ? restDuration : 90.0
                    
                    // Capture references to persist across ad display
                    let theSetData: WorkoutSetData = setData
                    let theRestTimer: RestTimer = restTimer
                    let theSetNumber: Int = setNumber
                    let theRestDuration: TimeInterval = finalRestDuration
                    let theOnSetCompleted: () -> Void = onSetCompleted
                    
                    #if DEBUG
                    print("✅ Set \(setNumber) completed - \(Int(setData.weight))lbs × \(setData.reps) reps")
                    #endif
                    
                    // IMMEDIATELY mark set complete and start timer BEFORE ad shows
                    // This way timer runs in background during ad - no delay when ad closes
                    theSetData.isCompleted = true
                    theRestTimer.startWithAdOffset(
                        duration: theRestDuration,
                        originalTotal: theRestDuration,
                        adTime: 0
                    )
                    
                    // Show ad between sets (timer continues running in background)
                    onShowAd { [theSetData, theRestTimer] in
                        DispatchQueue.main.async {
                            // Enable smooth animation now that ad is done
                            theRestTimer.enableAnimation()
                            
                            // DO NOT auto-add next set - user must tap "Add Set"
                            // theOnSetCompleted()  // REMOVED - no longer auto-adding sets
                        }
                    }
                }) {
                    Image(systemName: setData.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(setData.isCompleted ? .green : .gray)
                }
                .frame(width: 40)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                // Subtle alternating row highlight
                setNumber % 2 == 0 ? Color(.systemGray6) : Color.clear
            )
            
            // Live rest timer indicator (shown after completing a set)
            if setData.isCompleted && restTimer.isActive {
                // Progress bar that shrinks as timer counts down
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Text(formatTime(restTimer.timeRemaining))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(
                        // Background container
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.15))
                            .overlay(
                                // Animated progress bar
                                HStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.blue, Color.purple.opacity(0.8)]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(0, (restTimer.timeRemaining / restTimer.originalTotalTime) * UIScreen.main.bounds.width * 0.85))
                                    Spacer(minLength: 0)
                                }
                            )
                    )
                    // Only animate when shouldAnimate is true (after ad ends)
                    .animation(restTimer.shouldAnimate ? .linear(duration: 1.0) : nil, value: restTimer.timeRemaining)
                }
                .padding(.horizontal)
                .padding(.top, 2)
            }
        }
        .onChange(of: activeTimerSetNumber) { _, newActiveSet in
            // ALWAYS stop this set's timer if another set becomes active
            if newActiveSet != setNumber {
                if restTimer.isActive {
                    print("🛑 Set \(setNumber): Stopping active timer because set \(newActiveSet ?? 0) took over")
                    restTimer.stop()
                } else {
                    print("🛑 Set \(setNumber): No active timer to stop (set \(newActiveSet ?? 0) took over)")
                }
            } else if newActiveSet == setNumber {
                print("✅ Set \(setNumber): Confirmed as active timer")
            }
        }
        .onAppear {
            // Initialize text fields from setData (for pre-filled sets)
            if !hasInitialized {
                hasInitialized = true
                
                // Pre-fill weight if setData has a value > 0
                if setData.weight > 0 {
                    weightText = "\(Int(setData.weight))"
                }
                
                // Pre-fill reps if setData has a value > 0
                if setData.reps > 0 {
                    repsText = "\(setData.reps)"
                }
            }
        }
        .onChange(of: isWeightFocused) { _, isFocused in
            if isFocused {
                onFocusChanged?(true)
            }
        }
        .onChange(of: isRepsFocused) { _, isFocused in
            if isFocused {
                onFocusChanged?(true)
            }
        }
        .onAppear {
            // Auto-focus the weight field for the first set of first exercise
            if shouldAutoFocus && !hasInitialized {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isWeightFocused = true
                }
            }
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct RestTimerIndicator: View {
    @ObservedObject var restTimer: RestTimer
    
    var body: some View {
        HStack(spacing: 12) {
            // Progress bar
            VStack(spacing: 4) {
                HStack {
                    Text("Rest")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Text(formatTime(restTimer.timeRemaining))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                ProgressView(value: 1 - (restTimer.timeRemaining / restTimer.totalTime))
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
            }
            
            // Control buttons
            HStack(spacing: 8) {
                Button(action: {
                    if restTimer.isActive {
                        restTimer.pause()
                    } else {
                        restTimer.resume()
                    }
                }) {
                    Image(systemName: restTimer.isActive ? "pause.fill" : "play.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .frame(width: 20, height: 20)
                }
                
                Button(action: {
                    restTimer.stop()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Data models
struct PreviousSetData {
    let setNumber: Int
    let weight: Double
    let reps: Int
    var isSmartRecommendation: Bool = false  // True if this is an AI-generated recommendation
    var recommendationNote: String? = nil    // Optional note about the recommendation
    
    var displayString: String {
        if weight > 0 && reps > 0 {
            if isSmartRecommendation {
                return "💡 \(Int(weight))×\(reps)"  // Smart recommendation indicator
            }
            return "\(Int(weight))×\(reps)"
        }
        return "-"
    }
    
    /// Initialize from historical data
    init(setNumber: Int, weight: Double, reps: Int) {
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.isSmartRecommendation = false
        self.recommendationNote = nil
    }
    
    /// Initialize from smart recommendation
    init(setNumber: Int, recommendation: StrengthProfileRecommendationEngine.SmartRecommendation) {
        self.setNumber = setNumber
        self.weight = recommendation.weight
        self.reps = recommendation.reps
        self.isSmartRecommendation = true
        self.recommendationNote = recommendation.adjustmentNote
    }
}

// MARK: - Set Type Enum
enum SetType: String, CaseIterable, Codable {
    case normal = "Normal"
    case warmup = "Warmup"
    case dropset = "Dropset"
    case failure = "Failure"
    case amrap = "AMRAP"       // As Many Reps As Possible
    case pause = "Pause Rep"   // Pause at bottom/top
    case tempo = "Tempo"       // Slow/controlled tempo
    
    /// Display letter for the set row
    var displayLetter: String? {
        switch self {
        case .normal: return nil  // Show number instead
        case .warmup: return "W"
        case .dropset: return "D"
        case .failure: return "F"
        case .amrap: return "A"
        case .pause: return "P"
        case .tempo: return "T"
        }
    }
    
    /// Color for the set type indicator
    var color: Color {
        switch self {
        case .normal: return .primary
        case .warmup: return .orange
        case .dropset: return .purple
        case .failure: return .red
        case .amrap: return .green
        case .pause: return .cyan
        case .tempo: return .blue
        }
    }
    
    /// Icon for the menu
    var icon: String {
        switch self {
        case .normal: return "number.circle"
        case .warmup: return "flame"
        case .dropset: return "arrow.down.circle"
        case .failure: return "exclamationmark.triangle"
        case .amrap: return "infinity.circle"
        case .pause: return "pause.circle"
        case .tempo: return "metronome"
        }
    }
    
    /// Description for the menu
    var description: String {
        switch self {
        case .normal: return "Standard working set"
        case .warmup: return "Light weight warm-up"
        case .dropset: return "Reduce weight, continue reps"
        case .failure: return "Push to muscle failure"
        case .amrap: return "As many reps as possible"
        case .pause: return "Pause at bottom/top"
        case .tempo: return "Slow controlled tempo"
        }
    }
}

class WorkoutSetData: ObservableObject, Identifiable {
    let id = UUID()
    @Published var weight: Double = 0
    @Published var reps: Int = 0
    @Published var isCompleted: Bool = false
    @Published var setType: SetType = .normal
    @Published var restTime: TimeInterval = 0
    
    // Legacy computed properties for backwards compatibility
    var isFailure: Bool {
        get { setType == .failure }
        set { if newValue { setType = .failure } else if setType == .failure { setType = .normal } }
    }
    
    var isDropset: Bool {
        get { setType == .dropset }
        set { if newValue { setType = .dropset } else if setType == .dropset { setType = .normal } }
    }
    
    var isWarmup: Bool {
        get { setType == .warmup }
        set { if newValue { setType = .warmup } else if setType == .warmup { setType = .normal } }
    }
}

class RestTimer: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    @Published var isActive: Bool = false
    @Published var totalTime: TimeInterval = 0
    
    // Track the original total time (before ad time was subtracted)
    // This is used for visual progress calculation
    @Published var originalTotalTime: TimeInterval = 0
    @Published var adElapsedTime: TimeInterval = 0
    
    // Controls whether the progress bar should animate
    // Set to false during ad, true after ad ends to prevent "catch up" animation
    @Published var shouldAnimate: Bool = true
    
    private var timer: Timer?
    
    /// Standard start - no ad time offset
    func start(duration: TimeInterval) {
        startWithAdOffset(duration: duration, originalTotal: duration, adTime: 0)
    }
    
    /// Start timer with ad time already counted as elapsed
    /// - Parameters:
    ///   - duration: The remaining time to count down
    ///   - originalTotal: The original full rest duration (before ad)
    ///   - adTime: How many seconds the ad consumed
    func startWithAdOffset(duration: TimeInterval, originalTotal: TimeInterval, adTime: TimeInterval) {
        totalTime = duration
        timeRemaining = duration
        originalTotalTime = originalTotal
        adElapsedTime = adTime
        isActive = true
        shouldAnimate = false  // Start with no animation (during ad)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.stop()
            }
        }
    }
    
    /// Call this when ad ends to enable smooth animation
    func enableAnimation() {
        // Small delay to let the view settle at current position first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.shouldAnimate = true
        }
    }
    
    /// Calculate progress including ad time for visual display
    /// Returns value from 0.0 (just started) to 1.0 (complete)
    var visualProgress: CGFloat {
        guard originalTotalTime > 0 else { return 0 }
        let timeElapsed = (originalTotalTime - timeRemaining)
        return CGFloat(timeElapsed / originalTotalTime)
    }
    
    /// Calculate remaining progress (for progress bar width)
    /// Returns value from 1.0 (just started) to 0.0 (complete)
    var visualRemainingProgress: CGFloat {
        return 1.0 - visualProgress
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        timeRemaining = 0
        adElapsedTime = 0
        originalTotalTime = 0
    }
    
    func pause() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }
    
    func resume() {
        guard timeRemaining > 0 else { return }
        isActive = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.stop()
            }
        }
    }
}

struct RestTimerView: View {
    @Binding var restTimer: RestTimer
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // Timer display
                Text(formatTime(restTimer.timeRemaining))
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundColor(.blue)
                
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(1 - (restTimer.timeRemaining / restTimer.totalTime)))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                }
                
                // Control buttons
                HStack(spacing: 30) {
                    Button(action: {
                        if restTimer.isActive {
                            restTimer.pause()
                        } else {
                            restTimer.resume()
                        }
                    }) {
                        Image(systemName: restTimer.isActive ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        restTimer.stop()
                        isPresented = false
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
            }
                .navigationTitle("Rest Timer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Rest Timer Setup View
struct RestTimerSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let onSetTimer: (TimeInterval) -> Void
    
    @State private var selectedMinutes: Int = 2
    @State private var selectedSeconds: Int = 0
    
    private let minuteOptions = Array(0...10)
    private let secondOptions = Array(stride(from: 0, to: 60, by: 15))
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Set Rest Timer")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Choose how long to rest between sets for this exercise")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Time picker
                HStack(spacing: 20) {
                    VStack {
                        Text("Minutes")
                            .font(.headline)
                        Picker("Minutes", selection: $selectedMinutes) {
                            ForEach(minuteOptions, id: \.self) { minute in
                                Text("\(minute)").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100, height: 150)
                    }
                    
                    VStack {
                        Text("Seconds")
                            .font(.headline)
                        Picker("Seconds", selection: $selectedSeconds) {
                            ForEach(secondOptions, id: \.self) { second in
                                Text("\(second)").tag(second)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100, height: 150)
                    }
                }
                
                // Preview
                Text("Rest Time: \(selectedMinutes):\(String(format: "%02d", selectedSeconds))")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                
                Spacer()
            }
            .padding()
                .navigationTitle("Rest Timer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Set") {
                        let totalSeconds = TimeInterval(selectedMinutes * 60 + selectedSeconds)
                        onSetTimer(totalSeconds)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Exercise Replacement View
struct ExerciseReplacementView: View {
    @Environment(\.dismiss) private var dismiss
    let currentExercise: Exercise
    let onReplaceExercise: () -> Void
    
    @State private var similarExercises: [Exercise] = []
    @State private var selectedExercise: Exercise?
    
    var body: some View {
        NavigationView {
            VStack {
                if similarExercises.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Finding similar exercises...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(similarExercises, id: \.id) { exercise in
                        ExerciseReplacementRow(
                            exercise: exercise,
                            isSelected: selectedExercise?.id == exercise.id
                        ) {
                            selectedExercise = exercise
                        }
                    }
                }
            }
            .navigationTitle("Replace Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LinearGradient(
                    gradient: Gradient(colors: [Color.green.opacity(0.1), Color.blue.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Replace") {
                        if selectedExercise != nil {
                            onReplaceExercise()
                            dismiss()
                        }
                    }
                    .disabled(selectedExercise == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadSimilarExercises()
            }
        }
    }
    
    private func loadSimilarExercises() {
        // Use smart alternative engine for intelligent matching
        Task {
            let userEquipment = UserManager.shared.currentUser?.getEquipment() ?? []
            
            let alternatives = await AlternativeExerciseEngine.shared.getAlternatives(
                for: currentExercise,
                userEquipment: userEquipment,
                excludeIds: [],
                maxResults: 15
            )
            
            await MainActor.run {
                similarExercises = alternatives.map { $0.exercise }
                print("🔄 Loaded \(alternatives.count) smart alternatives for replacement")
                if let top = alternatives.first {
                    print("   Top: \(top.exercise.name ?? "") (score: \(top.score))")
                }
            }
        }
    }
}

struct ExerciseReplacementRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack {
                        if let category = exercise.category {
                            Text(category)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        if let equipment = exercise.equipment {
                            Text(equipment)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Custom Shapes

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Marquee Text Component
// Continuous scroll like a rotating gear - always scrolls left, pauses, repeats

struct MarqueeText: View {
    let text: String
    let font: Font
    let weight: Font.Weight
    let shouldAnimate: Bool // Only scroll when card is active
    
    // Animation configuration
    private let scrollSpeed: CGFloat = 20 // Points per second - slow steady scroll
    private let gapBetweenCopies: CGFloat = 100 // Large gap between text copies
    private let pauseDuration: Double = 3.0 // Pause after each full rotation
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var needsScrolling = false
    @State private var xOffset: CGFloat = 0
    
    init(text: String, font: Font = .headline, weight: Font.Weight = .semibold, shouldAnimate: Bool = true) {
        self.text = text
        self.font = font
        self.weight = weight
        self.shouldAnimate = shouldAnimate
    }
    
    // One full rotation distance
    private var cycleWidth: CGFloat {
        textWidth + gapBetweenCopies
    }
    
    // How long one scroll cycle takes
    private var scrollTime: Double {
        guard scrollSpeed > 0, cycleWidth > 0 else { return 5.0 }
        return Double(cycleWidth) / Double(scrollSpeed)
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Always show both copies of text for smooth looping
            HStack(spacing: gapBetweenCopies) {
                Text(text)
                    .font(font)
                    .fontWeight(weight)
                    .fixedSize()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .onAppear {
                                    textWidth = textGeo.size.width
                                    containerWidth = geometry.size.width
                                    needsScrolling = textWidth > containerWidth - 10
                                    
                                    // Start animation if needed
                                    if needsScrolling && shouldAnimate {
                                        startScrolling()
                                    }
                                }
                        }
                    )
                
                // Second copy for seamless loop (only visible during scroll)
                if needsScrolling {
                    Text(text)
                        .font(font)
                        .fontWeight(weight)
                        .fixedSize()
                }
            }
            .offset(x: xOffset)
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: 22)
        .clipped()
        .onChange(of: shouldAnimate) { _, animate in
            if animate && needsScrolling {
                startScrolling()
            } else if !animate {
                resetPosition()
            }
        }
    }
    
    private func startScrolling() {
        guard needsScrolling && shouldAnimate else { return }
        
        // Reset to start position
        xOffset = 0
        
        // Wait a moment, then start the scroll cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard shouldAnimate && needsScrolling else { return }
            performScrollCycle()
        }
    }
    
    private func performScrollCycle() {
        guard shouldAnimate && needsScrolling else { 
            resetPosition()
            return 
        }
        
        // Animate scroll to the left (one full cycle)
        withAnimation(.linear(duration: scrollTime)) {
            xOffset = -cycleWidth
        }
        
        // After scroll completes: reset instantly, pause, then repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollTime) {
            guard shouldAnimate && needsScrolling else {
                resetPosition()
                return
            }
            
            // Instant reset (second copy is now at start position - seamless)
            withAnimation(.none) {
                xOffset = 0
            }
            
            // Pause, then scroll again
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                performScrollCycle()
            }
        }
    }
    
    private func resetPosition() {
        withAnimation(.easeOut(duration: 0.2)) {
            xOffset = 0
        }
    }
}

// MARK: - Add Exercise During Workout View
struct AddExerciseDuringWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Binding var exercises: [Exercise]
    let onExercisesAdded: ([Exercise]) -> Void
    
    @State private var selectedExercises: [Exercise] = []
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var availableExercises: [Exercise] = []
    @State private var selectedExerciseForDetail: Exercise?
    
    // ⚡️ SNAPPY SEARCH: Focus state for instant keyboard dismiss
    @FocusState private var isSearchFocused: Bool
    
    // ⚡️ HIGH-PERFORMANCE: Cached results
    @State private var cachedFilteredExercises: [Exercise] = []
    @State private var preFilteredExercises: [Exercise] = []
    @State private var lastFilterKey: String = ""
    @State private var searchCache: [String: [Exercise]] = [:]
    
    private let categories = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
    private let equipmentTypes = ["All", "Bodyweight", "Dumbbells", "Barbell", "Cable", "Machine"]
    
    var filteredExercises: [Exercise] {
        cachedFilteredExercises
    }
    
    private func updateFilteredExercises() {
        let filterKey = "\(selectedCategory)|\(selectedEquipment)"
        
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchCache.removeAll()
            preFilteredExercises = applyFiltersOnly(to: availableExercises)
        }
        
        if !searchText.isEmpty {
            let searchKey = searchText.lowercased()
            if let cached = searchCache[searchKey] {
                cachedFilteredExercises = cached
                return
            }
            let results = ultraFastSearch(query: searchKey, in: preFilteredExercises)
            searchCache[searchKey] = results
            cachedFilteredExercises = results
        } else {
            cachedFilteredExercises = preFilteredExercises
        }
    }
    
    private func ultraFastSearch(query: String, in exercises: [Exercise]) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        
        // Split query into words and correct typos for each
        let queryWords = query.split(separator: " ").map { correctCommonTypos(String($0)) }
        let isMultiWord = queryWords.count > 1
        let variations = isMultiWord ? [query] : getQuickVariations(query)
        
        // Build corrected query for direct substring matching
        let correctedQuery = queryWords.joined(separator: " ")
        
        // Priority buckets (highest to lowest):
        // 1. exactMatches: name equals query exactly
        // 2. startsWithPhraseMatches: name STARTS with the exact phrase (e.g., "front raise" → "Front Raise (Dumbbell)")
        // 3. containsPhraseMatches: name CONTAINS the exact phrase (e.g., "front raise" → "Seated Front Raise")
        // 4. allWordsMatches: all words found but not as contiguous phrase (e.g., "front raise" → "Front Lat Raise")
        var exactMatches: [Exercise] = []
        var startsWithPhraseMatches: [Exercise] = []
        var containsPhraseMatches: [Exercise] = []
        var allWordsMatches: [Exercise] = []
        
        for exercise in exercises {
            guard let name = exercise.name?.lowercased() else { continue }
            
            var matched = false
            
            // SINGLE-WORD: Use variations for typo tolerance
            if !isMultiWord {
                for variation in variations {
                    if name == variation { exactMatches.append(exercise); matched = true; break }
                    else if name.hasPrefix(variation) { startsWithPhraseMatches.append(exercise); matched = true; break }
                    else if name.contains(variation) { containsPhraseMatches.append(exercise); matched = true; break }
                }
            }
            
            // MULTI-WORD: Check for exact phrase match first (preserves word order)
            if !matched && isMultiWord {
                if name == correctedQuery {
                    exactMatches.append(exercise)
                    matched = true
                } else if name.hasPrefix(correctedQuery) {
                    // Name STARTS with the exact phrase - highest priority
                    startsWithPhraseMatches.append(exercise)
                    matched = true
                } else if name.contains(correctedQuery) {
                    // Name CONTAINS the exact phrase - second priority
                    containsPhraseMatches.append(exercise)
                    matched = true
                }
            }
            
            // MULTI-WORD: Word-order-independent matching (lowest priority)
            if !matched && isMultiWord {
                let allWordsFound = queryWords.allSatisfy { word in
                    let wordVariations = getQuickVariations(word)
                    return wordVariations.contains { variation in name.contains(variation) }
                }
                if allWordsFound {
                    allWordsMatches.append(exercise)
                }
            }
        }
        
        // Return in priority order: exact phrase ordering is prioritized
        return exactMatches + startsWithPhraseMatches + containsPhraseMatches + allWordsMatches
    }
    
    private func getQuickVariations(_ query: String) -> [String] {
        let corrected = correctCommonTypos(query)
        var variations = corrected == query ? [query] : [query, corrected]
        
        let baseWord = corrected
        switch baseWord {
        case "fly": variations += ["flye", "flyes", "flies"]
        case "flye": variations += ["fly", "flyes", "flies"]
        case "curl": variations += ["curls"]
        case "curls": variations += ["curl"]
        case "press": variations += ["presses"]
        case "presses": variations += ["press"]
        case "row": variations += ["rows"]
        case "rows": variations += ["row"]
        case "raise": variations += ["raises"]
        case "raises": variations += ["raise"]
        case "bicep": variations += ["biceps"]
        case "biceps": variations += ["bicep"]
        case "tricep": variations += ["triceps"]
        case "triceps": variations += ["tricep"]
        case "pulldown": variations += ["pull-down", "pull down", "pulldowns"]
        case "pushdown": variations += ["push-down", "push down", "pushdowns"]
        case "dumbbell": variations += ["dumbell", "dumbells", "dumbbells"]
        case "dumbbells": variations += ["dumbbell", "dumbell"]
        case "barbell": variations += ["barbel", "barbells"]
        case "extension": variations += ["extensions"]
        case "extensions": variations += ["extension"]
        case "squat": variations += ["squats"]
        case "squats": variations += ["squat"]
        case "lunge": variations += ["lunges"]
        case "lunges": variations += ["lunge"]
        default:
            if baseWord.hasSuffix("s") && baseWord.count > 3 { variations.append(String(baseWord.dropLast())) }
            else if !baseWord.hasSuffix("s") && baseWord.count > 2 { variations.append(baseWord + "s") }
        }
        return variations
    }
    
    private func correctCommonTypos(_ query: String) -> String {
        // Only do EXACT matches - no substring replacement which causes bugs
        // e.g., "decline" was becoming "declinee" because it contains "declin"
        let typoMap: [String: String] = [
            "dumbell": "dumbbell", "dumbel": "dumbbell", "dumble": "dumbbell",
            "dumbells": "dumbbells", "dumbels": "dumbbells",
            "barbel": "barbell", "barble": "barbell",
            "kettleball": "kettlebell", "kettlebel": "kettlebell",
            "cabel": "cable", "cabels": "cables",
            "machien": "machine", "mashine": "machine",
            "flye": "fly", "flyes": "flies",
            "pres": "press", "presss": "press", "curle": "curl",
            "rwo": "row", "sqaut": "squat", "sqat": "squat",
            "deadlif": "deadlift", "dedlift": "deadlift",
            "extention": "extension", "extenstion": "extension",
            "pullup": "pull up", "pushup": "push up", "chinup": "chin up",
            "bycep": "bicep", "byceps": "biceps", "bicept": "bicep",
            "trycep": "tricep", "tryceps": "triceps", "tricept": "tricep",
            "sholder": "shoulder", "sholders": "shoulders",
            "inclin": "incline", "inclien": "incline",
            "declin": "decline", "declien": "decline",
            "laterl": "lateral", "latral": "lateral",
            "revers": "reverse", "bensh": "bench", "banch": "bench", "benc": "bench"
        ]
        
        // Only return correction for EXACT match
        return typoMap[query] ?? query
    }
    
    private func applyFiltersOnly(to exercises: [Exercise]) -> [Exercise] {
        var filtered = exercises
        
        if selectedCategory != "All" {
            let categoryLower = selectedCategory.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseCategory = (exercise.category ?? "").lowercased()
                return exerciseCategory == categoryLower || exerciseCategory.contains(categoryLower)
            }
        }
        
        if selectedEquipment != "All" {
            let equipmentLower = selectedEquipment.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseEquipment = (exercise.equipment ?? "").lowercased()
                return exerciseEquipment.contains(equipmentLower) || equipmentLower.contains(exerciseEquipment)
            }
        }
        
        return filtered
    }
    
    private func categoryColor(for category: String?) -> Color {
        switch category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        default: return .gray
        }
    }
    
    private func categoryIcon(for category: String?) -> String {
        switch category?.lowercased() {
        case "chest": return "heart.fill"
        case "back": return "person.fill"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "hand.raised.fill"
        case "core": return "circle.circle.fill"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Adaptive gradient background
                AdaptiveGradient.workout(for: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
                
                VStack(spacing: 0) {
                    // Search & Filter Card
                    VStack(spacing: 12) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search exercises...", text: $searchText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($isSearchFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    // ⚡️ INSTANT keyboard dismiss on return
                                    isSearchFocused = false
                                }
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        // Categories row
                        HStack(spacing: 8) {
                            Text("Categories")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(categories, id: \.self) { category in
                                        AddExerciseFilterChip(
                                            text: category,
                                            isSelected: selectedCategory == category,
                                            color: .blue,
                                            onTap: { selectedCategory = category }
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Equipment row
                        HStack(spacing: 8) {
                            Text("Equipment")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(equipmentTypes, id: \.self) { equipment in
                                        AddExerciseFilterChip(
                                            text: equipment,
                                            isSelected: selectedEquipment == equipment,
                                            color: .orange,
                                            onTap: { selectedEquipment = equipment }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Exercise list
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredExercises, id: \.id) { exercise in
                                let isSelected = selectedExercises.contains(where: { $0.id == exercise.id })
                                
                                HStack(spacing: 12) {
                                    // Selection circle
                                    Button(action: {
                                        if isSelected {
                                            selectedExercises.removeAll { $0.id == exercise.id }
                                        } else {
                                            selectedExercises.append(exercise)
                                        }
                                    }) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundColor(isSelected ? .blue : .secondary.opacity(0.5))
                                    }
                                    
                                    // Category icon
                                    ZStack {
                                        Circle()
                                            .fill(categoryColor(for: exercise.category).opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: categoryIcon(for: exercise.category))
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(categoryColor(for: exercise.category))
                                    }
                                    
                                    // Exercise info
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        HStack(spacing: 4) {
                                            Text(exercise.category ?? "")
                                                .font(.caption)
                                                .foregroundColor(categoryColor(for: exercise.category))
                                            
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            Text(exercise.equipment ?? "")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Info button
                                    Button(action: {
                                        selectedExerciseForDetail = exercise
                                    }) {
                                        Image(systemName: "info.circle")
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.cardBackground)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
                }
                
                // Bottom add button
                VStack {
                    Button(action: {
                        exercises.append(contentsOf: selectedExercises)
                        onExercisesAdded(selectedExercises)
                        
                        // 🧠 BEHAVIOR LEARNING: Track exercises user manually adds
                        for exercise in selectedExercises {
                            if let name = exercise.name {
                                UserBehaviorLearningEngine.shared.recordCustomWorkoutAddition(exerciseName: name)
                            }
                        }
                        
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add \(selectedExercises.count) Exercise\(selectedExercises.count == 1 ? "" : "s")")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.cardBackground)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(selectedExercises.isEmpty)
                    .opacity(selectedExercises.isEmpty ? 0.6 : 1.0)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(item: $selectedExerciseForDetail) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
        }
        .onAppear {
            loadExercises()
            updateFilteredExercises()
        }
        // ⚡️ HIGH-PERFORMANCE: Instant filter updates
        .onChange(of: searchText) { _, _ in updateFilteredExercises() }
        .onChange(of: selectedCategory) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .onChange(of: selectedEquipment) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .onChange(of: availableExercises) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
    }
    
    private func loadExercises() {
        availableExercises = ExerciseLibraryService.shared.getAllExercises()
    }
}

// MARK: - Add Exercise Filter Chip
struct AddExerciseFilterChip: View {
    let text: String
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color : Color(.systemGray5))
                )
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    
    // Create sample workout and exercises
    let workout = Workout(context: context)
    workout.name = "Push Day"
    workout.date = Date()
    
    let exercise1 = Exercise(context: context)
    exercise1.name = "Bench Press (Barbell)"
    exercise1.category = "Chest"
    exercise1.equipment = "Barbell"
    
    let exercise2 = Exercise(context: context)
    exercise2.name = "Incline Bench Press (Dumbbell)"
    exercise2.category = "Chest"
    exercise2.equipment = "Dumbbells"
    
    return ActiveWorkoutView(
        isPresented: .constant(true),
        workout: workout,
        exercises: [exercise1, exercise2]
    )
    .environment(\.managedObjectContext, context)
    .environmentObject(UserManager())
}

// MARK: - Select All TextField (cursor at end on focus)
struct SelectAllTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .numberPad
    var font: UIFont = .systemFont(ofSize: 17, weight: .semibold)
    var textAlignment: NSTextAlignment = .center
    var textColor: UIColor = .label // Default to system label color
    var onFocusChange: ((Bool) -> Void)? = nil
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.font = font
        textField.textAlignment = textAlignment
        textField.delegate = context.coordinator
        textField.backgroundColor = .clear
        textField.textColor = textColor
        textField.tintColor = .systemBlue
        
        // Add done button to number pad
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.donePressed))
        toolbar.items = [flexSpace, doneButton]
        textField.inputAccessoryView = toolbar
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        // Update text color dynamically (for completion state changes)
        uiView.textColor = textColor
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField
        
        init(_ parent: SelectAllTextField) {
            self.parent = parent
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange?(true)
            
            // Select all text after a brief delay to ensure field is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textField.selectAll(nil)
            }
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange?(false)
            parent.text = textField.text ?? ""
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Allow only numbers
            let allowedCharacters = CharacterSet.decimalDigits
            let characterSet = CharacterSet(charactersIn: string)
            
            if allowedCharacters.isSuperset(of: characterSet) {
                // Update binding with new text
                if let currentText = textField.text,
                   let textRange = Range(range, in: currentText) {
                    let newText = currentText.replacingCharacters(in: textRange, with: string)
                    parent.text = newText
                }
                return true
            }
            return false
        }
        
        @objc func donePressed() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - Rename Exercise View
struct RenameExerciseView: View {
    let exercise: Exercise
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var nickname: String = ""
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @FocusState private var isTextFieldFocused: Bool
    
    private var officialName: String {
        exercise.displayName
    }
    
    private var hasExistingNickname: Bool {
        ExerciseNicknameService.shared.hasNickname(for: officialName)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "pencil.line")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                .padding(.top, 20)
                
                // Official name display
                VStack(spacing: 4) {
                    Text("Official Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(officialName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Nickname input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Custom Name")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter nickname...", text: $nickname)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color(.systemGray6))
                        )
                        .focused($isTextFieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            saveNickname()
                        }
                    
                    Text("This name will appear everywhere in your app")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    // Save button
                    Button(action: saveNickname) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark")
                                Text("Save Nickname")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(nickname.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                        )
                    }
                    .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    
                    // Reset to official name (only show if there's an existing nickname)
                    if hasExistingNickname {
                        Button(action: resetToOfficialName) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Official Name")
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                        }
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("Rename Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Pre-fill with existing nickname if one exists
                if let existingNickname = ExerciseNicknameService.shared.nicknames[officialName.lowercased()] {
                    nickname = existingNickname
                }
                
                // Focus text field after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveNickname() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        guard !trimmedNickname.isEmpty else { return }
        
        isSaving = true
        
        Task {
            do {
                try await ExerciseNicknameService.shared.setNickname(
                    trimmedNickname,
                    for: officialName,
                    exerciseId: exercise.id
                )
                
                await MainActor.run {
                    HapticManager.notification(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                    HapticManager.notification(.error)
                }
            }
        }
    }
    
    private func resetToOfficialName() {
        isSaving = true
        
        Task {
            do {
                try await ExerciseNicknameService.shared.removeNickname(for: officialName)
                
                await MainActor.run {
                    HapticManager.notification(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}
