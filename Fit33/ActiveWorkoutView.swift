import SwiftUI
import CoreData
import Foundation

struct ActiveWorkoutView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    // AdManager accessed lazily via .shared to avoid blocking view init
    @Binding var isPresented: Bool
    
    // 📱 Orientation tracking - ensures proper layout on rotation
    @StateObject private var orientationManager = OrientationManager.shared
    
    // ⚡️ PERFORMANCE: Use centralized HapticManager (pre-warmed generators)
    
    let workout: Workout
    @State private var exercises: [Exercise]
    
    // exerciseSets is now stored in workoutManager.exerciseSetsData to survive view rebuilds during ads
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    // ⚡️ PERFORMANCE: Use workoutManager.workoutStartTime instead of local state
    // This ensures accurate timing even if the view takes time to render
    // The timer calculation uses the ACTUAL start time (when GO was tapped)
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
    
    // Workout notes/journal
    @State private var workoutNotes: String = ""
    @State private var showingNotesField = false
    
    // Weight unit toggle (lb/kg) — persists across sessions
    @AppStorage("workoutWeightUnit") private var useKg: Bool = false
    @AppStorage("workoutPerSideMode") private var isPerSideGlobal: Bool = false
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds: Int = 90
    @AppStorage("autoStartRestTimer") private var autoStartRestTimer: Bool = true
    @AppStorage("keepScreenOnDuringWorkout") private var keepScreenOn: Bool = true
    @AppStorage("workoutSoundEffects") private var soundEffects: Bool = true
    @AppStorage("showMusicPlayer") private var showMusicPlayer: Bool = true
    
    // Settings panel
    @State private var showingSettingsPanel = false
    @State private var showingPremiumUpsell = false
    
    // ⚡️ PERFORMANCE: Two-phase rendering for instant load
    // MARK: - Ad Logic
    
    /// Determine if inline ads should show based on workout source
    private var shouldShowInlineAds: Bool {
        // Show ads only for free users with ads enabled
        return !PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled
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

    /// Live workout name based on current exercises' muscle groups
    /// Stable sort: ties broken alphabetically so the name never flickers
    private var liveWorkoutName: String {
        var muscleGroupCounts: [String: Int] = [:]
        for exercise in exercises {
            let groups = parseMuscleGroups(from: exercise)
            for group in groups {
                muscleGroupCounts[group, default: 0] += 1
            }
        }
        let sorted = muscleGroupCounts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        if sorted.count == 1 {
            return sorted[0].key
        } else if sorted.count >= 2 {
            let primary = sorted[0].key
            let secondary = sorted[1].key
            if sorted[0].value > sorted[1].value * 2 {
                return "\(primary) Focus"
            }
            return "\(primary) & \(secondary)"
        } else if exercises.count == 1 {
            return exercises[0].name ?? "Workout"
        }
        return "Workout"
    }

    private var notesPlaceholder: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        let dateStr = formatter.string(from: Date())
        return "\(liveWorkoutName) - \(dateStr)"
    }
    
    var body: some View {
        mainWorkoutContent
    }
    
    // MARK: - Main Content (extracted to reduce body type-check complexity)
    private var workoutBackground: some View {
        let darkColors = [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.04, green: 0.04, blue: 0.06)]
        let lightColors = [Color.blue.opacity(0.15), Color.purple.opacity(0.08), Color(.systemGroupedBackground)]
        return LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark ? darkColors : lightColors),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var mainWorkoutContent: some View {
        workoutGeometryContent
            .onChange(of: horizontalSizeClass) { _, _ in OrientationManager.shared.updateScreenDimensions() }
            .onChange(of: verticalSizeClass) { _, _ in OrientationManager.shared.updateScreenDimensions() }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { OrientationManager.shared.updateScreenDimensions() }
            }
            .onAppear { handleWorkoutAppear() }
            .onChange(of: workoutManager.currentExercises) { oldExercises, newExercises in
                let oldIds = Set(oldExercises.compactMap { $0.id })
                let newIds = Set(newExercises.compactMap { $0.id })
                if oldIds != newIds { exercises = newExercises }
            }
            .onDisappear {
                stopTimer()
                UIApplication.shared.isIdleTimerDisabled = false
                for task in initTasks { task.cancel() }
                initTasks.removeAll()
            }
            .overlay { settingsPanelOverlay }
            .overlay(alignment: .bottom) {
                if showMusicPlayer {
                    NowPlayingBar()
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingPremiumUpsell) { PremiumUpgradeView(triggeringFeature: .removeAds) }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingCompletionView, onDismiss: { handleCompletionDismiss() }) {
                WorkoutCompletionView(workout: workout, exercises: exercises, exerciseSets: workoutManager.exerciseSetsData, workoutDuration: elapsedTime)
                    .environmentObject(workoutManager)
            }
            .sheet(isPresented: $showingWorkoutInsights) { WorkoutInsightsView(insights: workoutManager.workoutInsights) }
    }
    
    private var workoutGeometryContent: some View {
        GeometryReader { geometry in
            ZStack {
                workoutBackground
                
                VStack(spacing: 0) {
                // Program Day Badge - only show if this is a program workout
                if let dayNumber = workoutManager.currentProgramDayNumber,
                   let dayFocus = workoutManager.currentProgramDayFocus {
                    programDayBadge(dayNumber: dayNumber, focus: dayFocus)
                        .padding(.top, 8)
                }
                
                // Music player is a floating overlay at the bottom (see mainWorkoutContent)
                
                // Workout Notes
                HStack(spacing: Spacing.xs) {
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingNotesField.toggle()
                            }
                            HapticManager.impact(.light)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: workoutNotes.isEmpty ? "note.text" : "note.text.badge.plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(notesPlaceholder)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(showingNotesField ? 180 : 0))
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        
                        if showingNotesField {
                            Divider()
                                .opacity(0.3)
                                .padding(.horizontal, Spacing.sm)
                            
                            ZStack(alignment: .topLeading) {
                                if workoutNotes.isEmpty {
                                    Text("Add notes...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .padding(.horizontal, Spacing.md + 5)
                                        .padding(.vertical, Spacing.sm)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $workoutNotes)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 44, maxHeight: 100)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xxs)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    
                    
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 2)
                .padding(.bottom, Spacing.xs)
                
                // Exercise list - transparent container
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                let exerciseId = exercise.id?.uuidString ?? ""
                                
                                // ⚡️ PERFORMANCE: LazyVStack + minimal card construction = instant render
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
                                            activeExerciseId = exerciseId
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                scrollProxy.scrollTo(exerciseId, anchor: .top)
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
                                    isActiveCard: activeExerciseId == exerciseId || (activeExerciseId == nil && index == 0),
                                    useKg: useKg,
                                    autoStartTimer: autoStartRestTimer
                                )
                                .id(exerciseId) // For ScrollViewReader
                            }
                        }
                        
                        // Add Exercise button
                        Button(action: {
                            HapticManager.impact(.light)
                            showingExerciseSelection = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20, weight: .medium))
                                Text("Add Exercise")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(Color.clear)
                            .overlay(
                                Capsule()
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                            .clipShape(Capsule())
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, Spacing.md + 8)
                    .padding(.top, 8)
                    .background(Color.clear)
                }
                .padding(.horizontal, -8)
                .background(Color.clear)
                .scrollDismissesKeyboard(.immediately)
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
            .safeAreaInset(edge: .top) { workoutHeaderBar }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    /// ⚡️ INSTANT: Apply warmup data SYNCHRONOUSLY before first render
    /// This is FAST (< 1ms) - just dictionary lookups and assignments
    private func applyWarmupDataInstantly() {
        let warmupService = PreviewWarmupService.shared
        
        // Only proceed if warmup completed on the preview screen
        guard warmupService.isWarmedUp else {
            #if DEBUG
            print("⚡️ [INSTANT] Warmup not ready - will apply in deferred init")
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
        print("⚡️ [INSTANT] Applied \(appliedCount)/\(exercises.count) exercises in \(String(format: "%.2f", elapsed))ms")
        #endif
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
        print("🚀 [PERF] initializeWorkout() - Scheduling deferred work")
        #endif
        
        // Defer SLOW operations (analytics, network, smart recs) to next frame
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
        print("🚀 [PERF] Deferred cache check: \(String(format: "%.1f", syncTime))ms")
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
                    let progWeek = workoutManager.currentProgramWeek
                    let recs = await MainActor.run {
                        StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: 3,
                            context: context,
                            programWeek: progWeek
                        )
                    }
                    
                    let smartPreviousData = recs.enumerated().map { index, rec in
                        PreviousSetData(setNumber: index + 1, recommendation: rec)
                    }
                    
                    var smartSets: [WorkoutSetData]? = nil
                    if !recs.isEmpty {
                        // Pre-populate sets with recommended weight/reps so fields aren't empty
                        smartSets = recs.map { rec in
                            let setData = WorkoutSetData()
                            setData.weight = rec.weight
                            setData.reps = rec.reps
                            return setData
                        }
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
                    let progWeek2 = workoutManager.currentProgramWeek
                    let recommendations = await MainActor.run {
                        StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                            exerciseName: exerciseName,
                            user: user,
                            numberOfSets: 3,
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
    
    /// Load historical data for a newly replaced/shuffled exercise
    /// Also adjusts set count to match previous workout and pre-populates weight/reps
    private func loadHistoricalDataForExercise(_ exercise: Exercise) {
        guard let exerciseId = exercise.id?.uuidString,
              let exerciseName = exercise.name else { return }

        #if DEBUG
        print("🔄 Loading historical data for replaced exercise: \(exerciseName)")
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
                    self.syncSetsWithPreviousData(exerciseId: exerciseId, previousData: previousData, wm: wm)
                    #if DEBUG
                    print("✅ Loaded cloud historical data for '\(exerciseName)': \(previousData.count) sets")
                    #endif
                }
            } else if let user = currentUser {
                // No historical data - generate smart recommendations
                let progWeek3 = await MainActor.run { workoutManager.currentProgramWeek }
                let recommendations = await MainActor.run {
                    StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                        exerciseName: exerciseName,
                        user: user,
                        numberOfSets: 3,
                        context: ctx,
                        programWeek: progWeek3
                    )
                }

                let smartPreviousData = recommendations.enumerated().map { index, rec in
                    PreviousSetData(setNumber: index + 1, recommendation: rec)
                }

                await MainActor.run {
                    previousExerciseSets[exerciseId] = smartPreviousData
                    // Pre-populate sets with smart recommendation values
                    let currentSets = wm.getSetsForExercise(id: exerciseId)
                    if currentSets.allSatisfy({ $0.weight == 0 && $0.reps == 0 && !$0.isCompleted }) {
                        let smartSets = recommendations.map { rec in
                            let setData = WorkoutSetData()
                            setData.weight = rec.weight
                            setData.reps = rec.reps
                            return setData
                        }
                        wm.updateSetsForExercise(id: exerciseId, sets: smartSets)
                    }
                    #if DEBUG
                    print("💡 Generated smart recommendations for '\(exerciseName)'")
                    #endif
                }
            }
        }
    }

    /// Sync the exercise's set count and pre-fill values from previous workout data
    private func syncSetsWithPreviousData(exerciseId: String, previousData: [PreviousSetData], wm: WorkoutManager) {
        let currentSets = wm.getSetsForExercise(id: exerciseId)
        let allEmpty = currentSets.allSatisfy { $0.weight == 0 && $0.reps == 0 && !$0.isCompleted }

        guard allEmpty else { return } // Don't overwrite user's in-progress data

        // Create sets matching the previous workout's count with pre-filled weight/reps
        let newSets = previousData.map { prev in
            let setData = WorkoutSetData()
            setData.weight = prev.weight
            setData.reps = prev.reps
            return setData
        }

        if !newSets.isEmpty {
            wm.updateSetsForExercise(id: exerciseId, sets: newSets)
        }
    }
    
    // MARK: - Workout Header Bar (extracted to reduce body complexity)
    private var workoutHeaderBar: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(workoutDuration)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack {
                    Button(action: {
                        HapticManager.selectionChanged()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingSettingsPanel.toggle()
                        }
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                    }
                    .accessibilityLabel("Workout Settings")
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        if workoutManager.workoutInsights != nil {
                            Button(action: { showingWorkoutInsights = true }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: {
                            HapticManager.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isWorkoutFavorite.toggle()
                                workout.isFavorite = isWorkoutFavorite
                                do {
                                    try viewContext.save()
                                    if SupabaseManager.shared.isAuthenticated, let workoutId = workout.id?.uuidString {
                                        Task {
                                            do {
                                                if isWorkoutFavorite {
                                                    let exerciseNames = exercises.compactMap { $0.name }
                                                    try await SupabaseManager.shared.saveFavoriteWorkout(
                                                        workoutName: workout.name ?? "Workout",
                                                        exerciseNames: exerciseNames,
                                                        originalWorkoutId: workoutId
                                                    )
                                                } else {
                                                    try await SupabaseManager.shared.removeFavoriteWorkout(originalWorkoutId: workoutId)
                                                }
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
                                .font(.system(size: 22))
                                .foregroundColor(isWorkoutFavorite ? .yellow : (colorScheme == .dark ? .white : .primary))
                                .scaleEffect(isWorkoutFavorite ? 1.1 : 1.0)
                        }
                        
                        Button("FINISH") {
                            let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
                            heavyImpact.impactOccurred()
                            finishWorkout()
                        }
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            if shouldShowInlineAds {
                BannerAdView()
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 4)
            }
        }
        .background(Color.clear)
    }
    
    // MARK: - Settings Panel Overlay (extracted to reduce body complexity)
    @ViewBuilder
    private var settingsPanelOverlay: some View {
        if showingSettingsPanel {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingSettingsPanel = false
                        }
                    }
                
                WorkoutSettingsPanel(
                    isPresented: $showingSettingsPanel,
                    showingPremiumUpsell: $showingPremiumUpsell,
                    onMinimize: {
                        workoutManager.navigateToHomeTab()
                    }
                )
                .frame(width: UIScreen.main.bounds.width * 0.72)
                .transition(.move(edge: .leading))
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }
    
    private func handleWorkoutAppear() {
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
    
    private func handleCompletionDismiss() {
        isFinishingWorkout = false
        if workout.isCompleted {
            workout.isCompleted = false
            try? viewContext.save()
        }
    }
    
    private func startTimer() {
        // ⚡️ PERFORMANCE: Use workoutManager's start time (set when GO was tapped)
        // This ensures accurate timing even if view render was delayed
        guard let startTime = workoutManager.workoutStartTime else {
            print("⚠️ [TIMER] No workout start time available, using current time")
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
                elapsedTime += 1
            }
            return
        }
        
        // ⚡️ INSTANT: Set initial elapsed time immediately (no waiting for first tick)
        elapsedTime = Date().timeIntervalSince(startTime)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            elapsedTime = Date().timeIntervalSince(startTime)
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
        // Use user-configured default rest seconds (0 = timer off)
        return TimeInterval(defaultRestSeconds)
    }
    
    private func cleanupPreviousExercises(currentExerciseId: String) {
        print("🧹 Cleaning up previous exercises. Current: \(currentExerciseId)")
        print("🧹 Last interacted exercise: \(lastInteractedExerciseId ?? "none")")
        print("🧹 All exercise sets before cleanup: \(workoutManager.exerciseSetsData.mapValues { $0.count })")
        
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
                    print("🧹 Exercise \(exerciseId): Had \(sets.count) sets, keeping \(validSets.count) sets")
                    print("🧹 Removed \(sets.count - validSets.count) extra blank sets")
                    workoutManager.exerciseSetsData[exerciseId] = validSets.isEmpty ? [WorkoutSetData()] : validSets
                } else {
                    print("🧹 Exercise \(exerciseId): All \(sets.count) sets preserved")
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

        // Sync kg values on all sets before saving
        for (_, sets) in workoutManager.exerciseSetsData {
            for set in sets where set.isCompleted {
                set.syncWeightUnits(fromLbs: true)
            }
        }
        
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
            // No meaningful data - initialize with proper set count (match old exercise or default 3)
            let setCount = max(existingSets.count, 3)
            workoutManager.exerciseSetsData[newExerciseId] = (0..<setCount).map { _ in WorkoutSetData() }
        } else {
            // Transfer existing sets to new exercise
            workoutManager.exerciseSetsData[newExerciseId] = existingSets
        }

        // Clean up old exercise data
        workoutManager.exerciseSetsData.removeValue(forKey: oldExerciseId)
        previousExerciseSets.removeValue(forKey: oldExerciseId) // Clear old previous data
        exerciseRestTimers.removeValue(forKey: oldExerciseId)

        // Transfer rest timer preference if set
        if let customRest = exerciseRestTimers[oldExerciseId] {
            exerciseRestTimers[newExerciseId] = customRest
        }

        print("🔀 Shuffled '\(oldExerciseName)' → '\(newExerciseName)'")

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
        
        // Save workout notes
        if !workoutNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workout.notes = workoutNotes
        }
        
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
                workoutSet.weight = setData.weight  // Double - preserves decimals like 187.5
                workoutSet.reps = Int16(setData.reps)
                workoutSet.isCompleted = setData.isCompleted
                workoutSet.restTime = Int32(setData.restTime)
                workoutSet.setType = setData.setType.rawValue  // Save set type (Warmup, Dropset, Failure, etc.)
                workoutSet.workoutExercise = workoutExercise
                
                #if DEBUG
                print("💾 Saving set \(setIndex + 1): weight=\(setData.weight) (Double), reps=\(setData.reps)")
                #endif
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
                .filter { $0.isCompleted && $0.weight > 0 && ($0.setType ?? "Normal") != "Warmup" }
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
        return "\(liveWorkoutName) - \(formatDate())"
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
                    .font(.ds_labelSmall)
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
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
            
            // Focus badge
            HStack(spacing: 4) {
                Image(systemName: "target")
                    .font(.ds_labelSmall)
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
    var shouldShift: Int = 0
    var isActiveCard: Bool = false
    var useKg: Bool = false
    var autoStartTimer: Bool = true
    
    @State private var showingExerciseDetail = false
    @State private var shuffledExerciseIds: Set<UUID> = [] // Track which exercises we've already shuffled to
    @State private var prefetchedExercises: [Exercise] = [] // Prefetched similar exercises ready to shuffle
    @State private var showingRestTimerSheet = false
    @State private var showingReplaceExercise = false
    @State private var showingRenameExercise = false
    @State private var activeTimerSetNumber: Int? = nil // Track which set currently has an active timer
    @State private var isFavorite: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasAppeared: Bool = false
    @AppStorage("workoutPerSideMode") private var isPerSideMode: Bool = false
    @State private var showingPlateCalculator: Bool = false
    @State private var plateCalcSetIndex: Int = 0
    @AppStorage("defaultBarWeight") private var barWeight: Double = 45
    @StateObject private var cardRestTimer = RestTimer()
    
    private let cardHeight: CGFloat = 180 // Approximate card height for drag calculations
    
    // Computed property to determine if this exercise is currently being worked on
    private var isExerciseActive: Bool {
        // Exercise is active ONLY if there's an active rest timer running
        // This ensures only the exercise with a live timer has scrolling text
        return activeTimerSetNumber != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Exercise header + column headers — gray
            VStack(spacing: 0) {
                exerciseHeader
                columnHeaders
            }
            .background(Color.cardBackground)
            
            // Sets — dark
            setsRows
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
            
            // Add set button — dark
            addSetButton
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        }
        .background(SleekCardBackground(cornerRadius: CornerRadius.xl, accentColor: isActiveCard ? Color(red: 0.0, green: 0.7, blue: 1.0) : Color(white: 0.5)))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .shadow(color: isActiveCard ? Color(red: 0.0, green: 0.7, blue: 1.0).opacity(0.25) : .clear, radius: 16, x: 0, y: 0)
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .onTapGesture {
            HapticManager.selectionChanged()
            onFocusChanged?(true)
        }
        .overlay(alignment: .bottomTrailing) {
            if cardRestTimer.isActive {
                Text(formatCountdownTime(cardRestTimer.timeRemaining))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.0, green: 0.7, blue: 1.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.0, green: 0.7, blue: 1.0).opacity(0.15))
                    )
                    .padding(10)
            }
        }
        .overlay {
            if cardRestTimer.isActive {
                // Timer countdown glow — stays visible even if another card is selected
                TimerBorderShape(cornerRadius: CornerRadius.xl)
                    .trim(from: cardRestTimer.visualProgress, to: 1)
                    .stroke(
                        Color(red: 0.0, green: 0.7, blue: 1.0),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .padding(1.5)
            } else if isActiveCard {
                // Selected card — full electric blue glow
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .strokeBorder(
                        Color(red: 0.0, green: 0.7, blue: 1.0),
                        lineWidth: 2.5
                    )
            }
        }
        // Drag offset for card being dragged, shift offset for other cards making room
        .offset(y: isBeingDragged ? dragOffset : CGFloat(shouldShift) * cardHeight)
        .scaleEffect(isBeingDragged ? 1.02 : 1.0)
        .zIndex(isBeingDragged ? 100 : (isActiveCard ? 50 : 0))
        .animation(.easeInOut(duration: 0.2), value: shouldShift)
        .animation(hasAppeared ? .easeInOut(duration: 0.2) : nil, value: isActiveCard)
        .animation(nil, value: isBeingDragged)
        .sheet(isPresented: $showingExerciseDetail) {
            NavigationStack {
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
        .sheet(isPresented: $showingRestTimerSheet) {
            RestTimerSetupView(onSetTimer: onSetRestTimer)
        }
        .sheet(isPresented: $showingReplaceExercise) {
            NavigationStack {
                CustomWorkoutBuilderView(
                    replacing: exercise,
                    onSelect: { newExercise in
                        WorkoutManager.shared.replaceExercise(exercise, with: newExercise)
                        onReplaceExercise(newExercise)
                    }
                )
                .environmentObject(WorkoutManager.shared)
                .environmentObject(UserManager.shared)
            }
        }
        .sheet(isPresented: $showingRenameExercise) {
            RenameExerciseView(exercise: exercise)
        }
        .sheet(isPresented: $showingPlateCalculator) {
            PlateCalculatorView(barWeight: $barWeight) { totalWeight in
                if plateCalcSetIndex < sets.count {
                    sets[plateCalcSetIndex].weight = totalWeight
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            // ⚡ PERF: Minimal work in onAppear for instant rendering
            guard !exercise.isFault else { return }
            isFavorite = exercise.isFavorite
            
            // Enable animations after first render (glow appears instantly)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
            
            // ⚡️ PERF: Do NOT prefetch alternatives here - it's lazy now
            // Alternatives are only fetched when user actually taps shuffle
        }
        .onChange(of: exercise.id) { _, newId in
            // Clear prefetch cache when exercise changes (after shuffle)
            // Next shuffle tap will re-fetch fresh alternatives
            prefetchedExercises = []
        }
        .onChange(of: exerciseWithActiveTimer) { _, _ in
            // Timer continues running even when user selects a different card
        }
    }
    
    // ⚡ PERF: Cache exercise name to avoid repeated property access
    private var exerciseName: String {
        exercise.name ?? "Exercise"
    }
    
    private func formatCountdownTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Shuffle to Similar Exercise (Smart Tiered Swap)
    // Tier 1 (swaps 1-2): Equipment variants (Dumbbell Bench → Barbell Bench)
    // Tier 2 (swap 3+): Complementary exercises (Bench Press → Chest Fly)
    // Fallback: Algorithmic match via AlternativeExerciseEngine
    @State private var perExerciseSwapCount: Int = 0

    private func shuffleToSimilarExercise() {
        let userEquipment = UserManager.shared.currentUser?.getEquipment() ?? []
        let userGoal = UserManager.shared.currentUser?.fitnessGoal ?? "Build Muscle"
        var excludeIds = shuffledExerciseIds
        if let currentId = exercise.id {
            excludeIds.insert(currentId)
        }

        // Use ExerciseSwapService tiered logic:
        // swapCount < 3 → equipment variants first (same movement, different equipment)
        // swapCount >= 3 → complementary exercises (different movement that complements workout)
        if let newExercise = ExerciseSwapService.shared.getQuickSwap(
            for: exercise,
            swapCount: perExerciseSwapCount,
            userGoal: userGoal,
            userEquipment: userEquipment,
            previousSwapIds: excludeIds
        ) {
            HapticManager.impact(.medium)
            perExerciseSwapCount += 1

            if let newId = newExercise.id {
                shuffledExerciseIds.insert(newId)
            }

            let tier = perExerciseSwapCount <= 2 ? "equipment variant" : "complementary"
            print("🔄 Shuffle #\(perExerciseSwapCount) (\(tier)): \(exercise.name ?? "") → \(newExercise.name ?? "")")
            onShuffleExercise(newExercise)
        } else {
            // Fallback to SmartExercisePairingEngine if swap service has no results
            let fallbackAlts = SmartExercisePairingEngine.shared.getAlternatives(
                for: exercise,
                userEquipment: userEquipment,
                excludeIds: excludeIds,
                maxResults: 1
            )
            if let alt = fallbackAlts.first {
                HapticManager.impact(.medium)
                perExerciseSwapCount += 1

                if let newId = alt.exercise.id {
                    shuffledExerciseIds.insert(newId)
                }

                print("🔄 Shuffle #\(perExerciseSwapCount) (fallback): \(exercise.name ?? "") → \(alt.exercise.name ?? "")")
                onShuffleExercise(alt.exercise)
            } else {
                HapticManager.notification(.warning)
                print("⚠️ No alternatives found for: \(exercise.name ?? "")")
            }
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
                        HapticManager.impact(.light)
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
                    HapticManager.impact(.light)
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
                
                // Contextual menu for exercise actions
                Menu {
                    Button(role: .destructive) {
                        onRemoveExercise()
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                    Button {
                        showingReplaceExercise = true
                    } label: {
                        Label("Replace Exercise", systemImage: "arrow.triangle.swap")
                    }
                    Button {
                        showingRenameExercise = true
                    } label: {
                        Label("Rename Exercise", systemImage: "pencil")
                    }
                    Button {
                        showingRestTimerSheet = true
                    } label: {
                        Label("Add Rest Timer", systemImage: "timer")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(.systemGray6))
                        )
                }
            }
            .fixedSize() // Keep icons at their natural size
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 10)
        .padding(.bottom, 4)
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
    
    private var columnHeaders: some View {
        let hasSmartRecs = previousSets.first?.isSmartRecommendation ?? false
        return HStack(spacing: 8) {
            Text("SET")
                .font(.system(size: 11, weight: .bold))
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(useKg ? "KG" : "LB")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .center)
            
            Text("REPS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .center)
            
            Spacer()
                .frame(width: 34)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
    
    private var setsRows: some View {
        VStack(spacing: 0) {
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
                        setData: setItem,
                        previousSet: getPreviousSetData(for: index + 1),
                        onSetCompleted: {
                            print("✅ Set \(index + 1) completed - timer started, waiting for user to add next set")
                        },
                        isLastSet: index == sets.count - 1,
                        restDuration: customRestTimer ?? restDuration,
                        onTimerShouldStop: { _ in },
                        onNewExerciseInteraction: onNewExerciseInteraction,
                        activeTimerSetNumber: $activeTimerSetNumber,
                        exerciseWithActiveTimer: $exerciseWithActiveTimer,
                        exerciseId: exerciseId,
                        onShowAd: onShowAd,
                        shouldAutoFocus: (isFirstExercise && index == 0 && !setItem.isCompleted) || (index == sets.count - 1 && index > 0 && !setItem.isCompleted),
                        onFocusChanged: onFocusChanged,
                        isPerSideMode: $isPerSideMode,
                        barWeight: barWeight,
                        onOpenPlateCalculator: {
                            plateCalcSetIndex = index
                            showingPlateCalculator = true
                        },
                        useKg: useKg,
                        restTimer: cardRestTimer,
                        autoStartTimer: autoStartTimer
                    )
                }
                
                if index < sets.count - 1 {
                    Divider()
                        .padding(.horizontal, Spacing.md)
                }
            }
        }
    }
    
    private var addSetButton: some View {
        Button(action: { HapticManager.impact(.light); onAddSet() }) {
            Text("ADD SET")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
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
                    HapticManager.notification(.warning)
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
    @ObservedObject var setData: WorkoutSetData
    let previousSet: PreviousSetData?
    let onSetCompleted: () -> Void
    let isLastSet: Bool
    let restDuration: TimeInterval
    let onTimerShouldStop: (Int) -> Void
    let onNewExerciseInteraction: () -> Void
    @Binding var activeTimerSetNumber: Int?
    @Binding var exerciseWithActiveTimer: String?
    var exerciseId: String = ""
    let onShowAd: (@escaping () -> Void) -> Void
    let shouldAutoFocus: Bool
    var onFocusChanged: ((Bool) -> Void)? = nil
    @Binding var isPerSideMode: Bool
    var barWeight: Double = 45
    var onOpenPlateCalculator: (() -> Void)? = nil
    var useKg: Bool = false
    @ObservedObject var restTimer: RestTimer
    var autoStartTimer: Bool = true
    
    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @FocusState private var isWeightFocused: Bool
    @FocusState private var isRepsFocused: Bool
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
                    HStack(alignment: .center, spacing: 2) {
                        Text(setData.setType.displayLetter ?? "\(setNumber)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(setData.setType == .normal ? .primary : setData.setType.color)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(setData.setType == .normal ? .secondary.opacity(0.4) : setData.setType.color.opacity(0.5))
                            .offset(x: 2, y: 1.5)
                    }
                    .frame(width: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                
                // Previous set info - show last workout's data or smart recommendation
                HStack(spacing: 4) {
                    if let prev = previousSet {
                        let displayWeight = useKg
                            ? (prev.weight * WorkoutSetData.lbsToKg * 10).rounded() / 10
                            : prev.weight
                        if prev.isSmartRecommendation {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("\(formatWeightPlaceholder(displayWeight))×\(prev.reps)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
                        } else {
                            Text("\(formatWeightPlaceholder(displayWeight))×\(prev.reps)")
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
                
            VStack(spacing: 2) {
                SelectAllTextField(
                    placeholder: weightPlaceholder,
                    text: $weightText,
                    keyboardType: .decimalPad,
                    font: .systemFont(ofSize: 17, weight: .semibold),
                    textAlignment: .center,
                    textColor: setData.isCompleted ? .white : .label,
                    onFocusChange: { isFocused in
                        isWeightFocused = isFocused
                        if isFocused {
                            HapticManager.selectionChanged()
                            onNewExerciseInteraction()
                            onFocusChanged?(true)
                        } else {
                            if let weight = parseWeight(weightText) {
                                applyWeight(weight)
                            }
                        }
                    }
                )
                .frame(width: 70, height: 38)
                .background(Color(.systemGray6))
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.blue, lineWidth: isWeightFocused ? 2 : 0)
                )
                .shadow(color: isWeightFocused ? Color.blue.opacity(0.4) : Color.clear, radius: 4)
                .onLongPressGesture(minimumDuration: 0.5) {
                    HapticManager.impact(.medium)
                    onOpenPlateCalculator?()
                }
                
                
            }
            .onChange(of: weightText) { _, newValue in
                weightDebounceTask?.cancel()
                weightDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    if let weight = parseWeight(newValue) {
                        applyWeight(weight)
                    }
                }
            }
            .onChange(of: useKg) { _, _ in
                let storedLbs = setData.weight
                guard storedLbs > 0 else { return }
                let bar = useKg ? barWeight * WorkoutSetData.lbsToKg : barWeight
                var displayValue: Double
                if isPerSideMode {
                    let totalDisplay = useKg ? storedLbs * WorkoutSetData.lbsToKg : storedLbs
                    displayValue = max(0, (totalDisplay - bar) / 2)
                } else {
                    displayValue = useKg ? storedLbs * WorkoutSetData.lbsToKg : storedLbs
                }
                weightText = formatWeightPlaceholder((displayValue * 10).rounded() / 10)
            }
                
            // Reps input
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
                        HapticManager.selectionChanged()
                        onNewExerciseInteraction()
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
            .cornerRadius(CornerRadius.sm)
            .overlay(
                // Glow border when this field is focused
                RoundedRectangle(cornerRadius: CornerRadius.sm)
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
                    HapticManager.impact(.medium)
                    // IMPORTANT: Flush any pending debounce tasks before completing set
                    // This ensures the latest weight/reps values are captured
                    weightDebounceTask?.cancel()
                    repsDebounceTask?.cancel()
                    
                    // Determine final weight: user input > pre-filled data > placeholder > default
                    let finalWeight: Double
                    if let weight = parseWeight(weightText), weight > 0 {
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
                    
                    // Update text fields to show the confirmed values (preserve decimals like 187.5)
                    weightText = formatWeightPlaceholder(finalWeight)
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
                    
                    // Cancel any pending debounce and sync weight/reps immediately
                    weightDebounceTask?.cancel()
                    repsDebounceTask?.cancel()
                    if let weight = parseWeight(weightText) {
                        setData.weight = weight
                    }
                    if let reps = Int(repsText) {
                        setData.reps = reps
                    }
                    
                    let shouldStartTimer = autoStartTimer && restDuration > 0
                    
                    if shouldStartTimer {
                        activeTimerSetNumber = setNumber
                        exerciseWithActiveTimer = exerciseId
                    }
                    
                    let finalRestDuration = restDuration > 0 ? restDuration : 90.0
                    
                    let theSetData: WorkoutSetData = setData
                    let theRestTimer: RestTimer = restTimer
                    let theSetNumber: Int = setNumber
                    let theRestDuration: TimeInterval = finalRestDuration
                    let theOnSetCompleted: () -> Void = onSetCompleted
                    
                    #if DEBUG
                    print("✅ Set \(setNumber) completed - Weight: \(setData.weight) (\(formatWeightPlaceholder(setData.weight))lbs) × \(setData.reps) reps")
                    print("   Raw weightText: '\(weightText)' | Parsed: \(parseWeight(weightText) ?? -1)")
                    #endif
                    
                    theSetData.isCompleted = true
                    
                    if shouldStartTimer {
                        theRestTimer.startWithAdOffset(
                            duration: theRestDuration,
                            originalTotal: theRestDuration,
                            adTime: 0
                        )
                    }
                    
                    onShowAd { [theSetData, theRestTimer] in
                        DispatchQueue.main.async {
                            if shouldStartTimer {
                                theRestTimer.enableAnimation()
                            }
                        }
                    }
                }) {
                    Image(systemName: setData.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(setData.isCompleted ? .blue : .gray)
                }
                .frame(width: 40)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(Color.clear)
            
            // Timer countdown is now shown as a glow border on ExerciseCard
        }
        .onChange(of: activeTimerSetNumber) { _, newActiveSet in
            if newActiveSet == setNumber {
                print("✅ Set \(setNumber): Confirmed as active timer")
            }
        }
        .onAppear {
            // ⚡️ PERF: Single onAppear combining all initialization
            guard !hasInitialized else { return }
            hasInitialized = true
            
            // Pre-fill weight if setData has a value > 0 (preserve decimals like 27.5)
            if setData.weight > 0 && weightText.isEmpty {
                weightText = formatWeightPlaceholder(setData.weight)
            }
            
            // Pre-fill reps if setData has a value > 0
            if setData.reps > 0 && repsText.isEmpty {
                repsText = "\(setData.reps)"
            }
            
            // Auto-focus the weight field for the first set of first exercise
            // Delay slightly to allow layout to complete
            if shouldAutoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isWeightFocused = true
                }
            }
        }
        .onChange(of: isWeightFocused) { _, isFocused in
            if isFocused { HapticManager.selectionChanged(); onFocusChanged?(true) }
        }
        .onChange(of: isRepsFocused) { _, isFocused in
            if isFocused { HapticManager.selectionChanged(); onFocusChanged?(true) }
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var weightPlaceholder: String {
        if let prev = previousSet {
            var displayWeight = prev.weight
            if useKg { displayWeight = (displayWeight * WorkoutSetData.lbsToKg * 10).rounded() / 10 }
            if isPerSideMode {
                let bar = useKg ? (barWeight * WorkoutSetData.lbsToKg) : barWeight
                let perSide = max(0, (displayWeight - bar) / 2)
                return formatWeightPlaceholder(perSide)
            }
            return formatWeightPlaceholder(displayWeight)
        }
        return isPerSideMode ? (useKg ? "20" : "45") : (useKg ? "60" : "135")
    }
    
    private func applyWeight(_ inputWeight: Double) {
        var totalLbs: Double
        let bar = useKg ? (barWeight * WorkoutSetData.lbsToKg) : barWeight
        
        if isPerSideMode {
            totalLbs = useKg
                ? ((inputWeight * 2 + bar) * WorkoutSetData.kgToLbs)
                : (inputWeight * 2 + barWeight)
        } else {
            totalLbs = useKg ? (inputWeight * WorkoutSetData.kgToLbs) : inputWeight
        }
        
        setData.weight = (totalLbs * 10).rounded() / 10
        setData.syncWeightUnits(fromLbs: true)
    }
    
    private func formatWeightPlaceholder(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        } else {
            return String(format: "%.1f", weight)
        }
    }
    
    /// Parse weight text handling both period and comma as decimal separator
    private func parseWeight(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
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
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(CornerRadius.sm)
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
            // Format weight to preserve decimals (e.g., 187.5)
            let weightStr = weight.truncatingRemainder(dividingBy: 1) == 0 
                ? "\(Int(weight))" 
                : String(format: "%.1f", weight)
            if isSmartRecommendation {
                return "💡 \(weightStr)×\(reps)"  // Smart recommendation indicator
            }
            return "\(weightStr)×\(reps)"
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
    @Published var weight: Double = 0       // Always stored in lbs
    @Published var weightKg: Double = 0     // Always stored in kg
    @Published var reps: Int = 0
    @Published var isCompleted: Bool = false
    @Published var setType: SetType = .normal
    @Published var restTime: TimeInterval = 0
    
    static let lbsToKg = 0.453592
    static let kgToLbs = 2.20462
    
    func syncWeightUnits(fromLbs: Bool = true) {
        if fromLbs {
            weightKg = (weight * Self.lbsToKg * 10).rounded() / 10
        } else {
            weight = (weightKg * Self.kgToLbs * 10).rounded() / 10
        }
    }
    
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

struct TimerBorderShape: InsettableShape {
    let cornerRadius: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> TimerBorderShape {
        TimerBorderShape(cornerRadius: cornerRadius, inset: inset + amount)
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let cr = min(cornerRadius - inset, min(r.width, r.height) / 2)
        let k: CGFloat = 0.62 * cr

        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))

        p.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + cr),
                    control1: CGPoint(x: r.maxX - cr + k, y: r.minY),
                    control2: CGPoint(x: r.maxX, y: r.minY + cr - k))

        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cr))
        p.addCurve(to: CGPoint(x: r.maxX - cr, y: r.maxY),
                    control1: CGPoint(x: r.maxX, y: r.maxY - cr + k),
                    control2: CGPoint(x: r.maxX - cr + k, y: r.maxY))

        p.addLine(to: CGPoint(x: r.minX + cr, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - cr),
                    control1: CGPoint(x: r.minX + cr - k, y: r.maxY),
                    control2: CGPoint(x: r.minX, y: r.maxY - cr + k))

        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        p.addCurve(to: CGPoint(x: r.minX + cr, y: r.minY),
                    control1: CGPoint(x: r.minX, y: r.minY + cr - k),
                    control2: CGPoint(x: r.minX + cr - k, y: r.minY))

        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        return p
    }
}

class RestTimer: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    @Published var isActive: Bool = false
    @Published var totalTime: TimeInterval = 0
    @Published var originalTotalTime: TimeInterval = 0
    @Published var adElapsedTime: TimeInterval = 0
    @Published var shouldAnimate: Bool = true
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    
    var visualProgress: CGFloat {
        guard originalTotalTime > 0 else { return 0 }
        return CGFloat((originalTotalTime - timeRemaining) / originalTotalTime)
    }
    
    var visualRemainingProgress: CGFloat {
        1.0 - visualProgress
    }
    
    func start(duration: TimeInterval) {
        startWithAdOffset(duration: duration, originalTotal: duration, adTime: 0)
    }
    
    func startWithAdOffset(duration: TimeInterval, originalTotal: TimeInterval, adTime: TimeInterval) {
        stop()
        
        totalTime = duration
        timeRemaining = duration
        originalTotalTime = originalTotal
        adElapsedTime = adTime
        isActive = true
        shouldAnimate = true
        lastTimestamp = 0
        
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func enableAnimation() {
        shouldAnimate = true
    }
    
    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        
        guard dt > 0, dt < 0.5 else { return }
        
        timeRemaining -= dt
        if timeRemaining <= 0 {
            timeRemaining = 0
            stop()
        }
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
        isActive = false
        timeRemaining = 0
        adElapsedTime = 0
        originalTotalTime = 0
    }
    
    func pause() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
        isActive = false
    }
    
    func resume() {
        guard timeRemaining > 0 else { return }
        isActive = true
        lastTimestamp = 0
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }
}

struct RestTimerView: View {
    @Binding var restTimer: RestTimer
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
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
        NavigationStack {
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
        NavigationStack {
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
            
            let alternatives = SmartExercisePairingEngine.shared.getAlternatives(
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
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        if let equipment = exercise.equipment {
                            Text(equipment)
                                .font(.caption)
                                .padding(.horizontal, Spacing.xs)
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
            .padding(.vertical, Spacing.xs)
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

struct MarqueeText: View {
    let text: String
    let font: Font
    let weight: Font.Weight
    let shouldAnimate: Bool

    private let scrollSpeed: CGFloat = 40
    private let gap: CGFloat = 60
    private let pauseSeconds: Double = 1.8

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @StateObject private var ticker = MarqueeTicker()

    private var needsScrolling: Bool { textWidth > containerWidth - 10 }
    private var cycleWidth: CGFloat { textWidth + gap }

    init(text: String, font: Font = .headline, weight: Font.Weight = .semibold, shouldAnimate: Bool = true) {
        self.text = text
        self.font = font
        self.weight = weight
        self.shouldAnimate = shouldAnimate
    }

    var body: some View {
        GeometryReader { geometry in
            let cw = geometry.size.width
            HStack(spacing: gap) {
                tickerLabel
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.onAppear {
                                textWidth = textGeo.size.width
                                containerWidth = cw
                            }
                        }
                    )
                if needsScrolling { tickerLabel }
            }
            .offset(x: ticker.offset)
            .frame(width: cw, alignment: .leading)
            .clipped()
        }
        .frame(height: 22)
        .clipped()
        .onChange(of: shouldAnimate) { _, animate in
            if animate && needsScrolling {
                ticker.start(cycleWidth: cycleWidth, speed: scrollSpeed, pause: pauseSeconds)
            } else {
                ticker.stop()
            }
        }
        .onChange(of: textWidth) { _, _ in
            if shouldAnimate && needsScrolling {
                ticker.start(cycleWidth: cycleWidth, speed: scrollSpeed, pause: pauseSeconds)
            } else {
                ticker.stop()
            }
        }
        .onDisappear { ticker.stop() }
    }

    private var tickerLabel: some View {
        Text(text)
            .font(font)
            .fontWeight(weight)
            .fixedSize()
    }
}

private class MarqueeTicker: ObservableObject {
    @Published var offset: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var cycleWidth: CGFloat = 0
    private var speed: CGFloat = 40
    private var pauseDuration: Double = 1.8
    private var pauseRemaining: Double = 0
    private var phase: Phase = .paused
    private var scrollDistance: CGFloat = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var easeElapsed: Double = 0

    private let easeDuration: Double = 0.25
    private enum Phase { case paused, easeIn, cruise, easeOut }

    func start(cycleWidth: CGFloat, speed: CGFloat, pause: Double) {
        stop()
        self.cycleWidth = cycleWidth
        self.speed = speed
        self.pauseDuration = pause
        self.pauseRemaining = pause
        self.phase = .paused
        self.scrollDistance = 0
        self.easeElapsed = 0
        self.offset = 0
        self.lastTimestamp = 0

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        phase = .paused
        scrollDistance = 0
        easeElapsed = 0
        offset = 0
        lastTimestamp = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt: Double
        if lastTimestamp > 0 {
            dt = min(now - lastTimestamp, 0.05)
        } else {
            dt = link.duration
        }
        lastTimestamp = now
        guard dt > 0 else { return }

        switch phase {
        case .paused:
            pauseRemaining -= dt
            if pauseRemaining <= 0 {
                phase = .easeIn
                easeElapsed = 0
                scrollDistance = 0
            }

        case .easeIn:
            easeElapsed += dt
            let t = min(easeElapsed / easeDuration, 1.0)
            let currentSpeed = speed * CGFloat(t * t)
            let delta = CGFloat(dt) * currentSpeed
            scrollDistance += delta
            offset = -scrollDistance
            if t >= 1.0 { phase = .cruise }

        case .cruise:
            let easeOutThreshold = cycleWidth - speed * CGFloat(easeDuration)
            let delta = CGFloat(dt) * speed
            scrollDistance += delta
            offset = -scrollDistance
            if scrollDistance >= easeOutThreshold {
                phase = .easeOut
                easeElapsed = 0
            }

        case .easeOut:
            easeElapsed += dt
            let t = min(easeElapsed / easeDuration, 1.0)
            let currentSpeed = max(speed * CGFloat(1.0 - t * t), speed * 0.08)
            let delta = CGFloat(dt) * currentSpeed
            scrollDistance += delta

            if scrollDistance >= cycleWidth {
                scrollDistance = 0
                offset = 0
                phase = .paused
                pauseRemaining = pauseDuration
            } else {
                offset = -scrollDistance
            }
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
                // Animated blue/cyan orb background
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
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
                        .padding(Spacing.sm)
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
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    )
                    .padding(.horizontal, Spacing.md)
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
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(Color.cardBackground)
                                .cornerRadius(CornerRadius.md)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
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
                        .padding(.vertical, Spacing.md)
                        .background(Color.cardBackground)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(selectedExercises.isEmpty)
                    .opacity(selectedExercises.isEmpty ? 0.6 : 1.0)
                    .padding(.horizontal, Spacing.md)
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
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color : Color(.systemGray5))
                )
        }
    }
}

// MARK: - Plate Calculator View

struct PlateCalculatorView: View {
    @Binding var barWeight: Double
    let onApply: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPlates: [Double] = []
    
    private let availablePlates: [Double] = [45, 35, 25, 10, 5, 2.5]
    private let barOptions: [Double] = [45, 35, 25]
    
    private var perSideTotal: Double { selectedPlates.reduce(0, +) }
    private var grandTotal: Double { perSideTotal * 2 + barWeight }
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            HStack {
                Text("Plate Calculator")
                    .font(.ds_heading3)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, Spacing.md)
            
            HStack(spacing: Spacing.sm) {
                Text("Bar")
                    .font(.ds_bodyMedium)
                    .foregroundColor(.secondary)
                ForEach(barOptions, id: \.self) { weight in
                    Button {
                        barWeight = weight
                        HapticManager.selectionChanged()
                    } label: {
                        Text("\(Int(weight))")
                            .font(.ds_labelMedium)
                            .foregroundColor(barWeight == weight ? .white : .primary)
                            .frame(width: 48, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .fill(barWeight == weight ? Color.blue : Color(.systemGray5))
                            )
                    }
                }
                Text("lb")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            VStack(spacing: Spacing.sm) {
                Text("Per Side")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: Spacing.xs) {
                    ForEach(availablePlates, id: \.self) { plate in
                        let count = selectedPlates.filter { $0 == plate }.count
                        Button {
                            selectedPlates.append(plate)
                            HapticManager.impact(.light)
                        } label: {
                            VStack(spacing: 2) {
                                Text(plate == 2.5 ? "2.5" : "\(Int(plate))")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(count > 0 ? .white : .primary)
                                if count > 0 {
                                    Text("×\(count)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(count > 0 ? Color.blue : Color(.systemGray5))
                            )
                        }
                    }
                }
                
                if !selectedPlates.isEmpty {
                    let grouped = Dictionary(grouping: selectedPlates) { $0 }
                        .sorted { $0.key > $1.key }
                    let breakdown = grouped.map { plate, arr in
                        arr.count > 1 ? "\(Int(plate))×\(arr.count)" : (plate == 2.5 ? "2.5" : "\(Int(plate))")
                    }.joined(separator: " + ")
                    
                    Text("\(breakdown) = \(formatWeight(perSideTotal))/side")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Total Weight")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                Text("\(formatWeight(grandTotal)) lb")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: Spacing.md) {
                Button {
                    selectedPlates.removeAll()
                    HapticManager.impact(.light)
                } label: {
                    Text("Clear")
                        .font(.ds_labelLarge)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color(.systemGray5))
                        )
                }
                
                Button {
                    onApply(grandTotal)
                    HapticManager.notification(.success)
                    dismiss()
                } label: {
                    Text("Apply \(formatWeight(grandTotal))")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color.blue)
                        )
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
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
        
        textField.inputAccessoryView = nil
        
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
            // Allow numbers and decimal separators (both . and , for international support)
            var allowedCharacters = CharacterSet.decimalDigits
            allowedCharacters.insert(charactersIn: ".,")  // Allow period and comma for decimals
            
            let characterSet = CharacterSet(charactersIn: string)
            
            if allowedCharacters.isSuperset(of: characterSet) {
                // Update binding with new text
                if let currentText = textField.text,
                   let textRange = Range(range, in: currentText) {
                    let newText = currentText.replacingCharacters(in: textRange, with: string)
                    
                    // Prevent multiple decimal points
                    let decimalCount = newText.filter { $0 == "." || $0 == "," }.count
                    if decimalCount > 1 {
                        return false
                    }
                    
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
                            RoundedRectangle(cornerRadius: CornerRadius.md)
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
                        .padding(.vertical, Spacing.md)
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

// MARK: - Workout Settings Side Panel

private struct WorkoutSettingsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    @Binding var showingPremiumUpsell: Bool
    
    @AppStorage("workoutWeightUnit") private var useKg: Bool = false
    @AppStorage("workoutPerSideMode") private var isPerSideGlobal: Bool = false
    @AppStorage("defaultBarWeight") private var barWeight: Double = 45
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds: Int = 90
    @AppStorage("autoStartRestTimer") private var autoStartRestTimer: Bool = true
    @AppStorage("keepScreenOnDuringWorkout") private var keepScreenOn: Bool = true
    @AppStorage("workoutSoundEffects") private var soundEffects: Bool = true
    @AppStorage("showMusicPlayer") private var showMusicPlayer: Bool = true
    
    let onMinimize: () -> Void
    
    private var barWeightOptions: [Double] { useKg ? [20, 15, 10] : [45, 35, 25] }
    private var unitLabel: String { useKg ? "kg" : "lb" }
    
    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    weightSection
                    restTimerSection
                    generalSection
                    removeAdsButton
                    minimizeButton
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxHeight: .infinity)
        .background(
            colorScheme == .dark
                ? Color(red: 0.08, green: 0.08, blue: 0.10)
                : Color(UIColor.systemGroupedBackground)
        )
    }
    
    // MARK: - Header
    
    private var panelHeader: some View {
        HStack {
            Text("Settings")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Spacer()
            Button {
                HapticManager.selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isPresented = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
    
    // MARK: - Weight Section
    
    private var weightSection: some View {
        sectionCard {
            sectionLabel("WEIGHT")
            
            rowWithPicker(title: "Unit") {
                Picker("", selection: $useKg) {
                    Text("lb").tag(false)
                    Text("kg").tag(true)
                }
                .pickerStyle(.segmented)
            }
            
            Divider().opacity(0.3)
            
            rowWithPicker(title: "Entry Mode") {
                Picker("", selection: $isPerSideGlobal) {
                    Text("Total").tag(false)
                    Text("Per Side").tag(true)
                }
                .pickerStyle(.segmented)
            }
            
            Divider().opacity(0.3)
            
            rowWithPicker(title: "Bar Weight") {
                Picker("", selection: $barWeight) {
                    ForEach(barWeightOptions, id: \.self) { w in
                        Text("\(Int(w)) \(unitLabel)").tag(w)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    // MARK: - Rest Timer Section
    
    private var restTimerSection: some View {
        sectionCard {
            sectionLabel("REST TIMER")
            
            VStack(spacing: 6) {
                Text("Default Rest")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Button {
                        if defaultRestSeconds > 0 { defaultRestSeconds -= 15; HapticManager.selectionChanged() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(defaultRestSeconds > 0 ? .blue : .secondary.opacity(0.3))
                    }
                    .disabled(defaultRestSeconds <= 0)
                    
                    Spacer()
                    
                    Text(formatRestTime(defaultRestSeconds))
                        .font(.title2)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        if defaultRestSeconds < 300 { defaultRestSeconds += 15; HapticManager.selectionChanged() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(defaultRestSeconds < 300 ? .blue : .secondary.opacity(0.3))
                    }
                    .disabled(defaultRestSeconds >= 300)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            Divider().opacity(0.3)
            
            toggleRow(title: "Auto-Start Timer", isOn: $autoStartRestTimer)
        }
    }
    
    // MARK: - General Section
    
    private var generalSection: some View {
        sectionCard {
            sectionLabel("GENERAL")
            toggleRow(title: "Keep Screen On", isOn: $keepScreenOn)
                .onChange(of: keepScreenOn) { _, newValue in
                    UIApplication.shared.isIdleTimerDisabled = newValue
                }
            Divider().opacity(0.3)
            toggleRow(title: "Sound Effects", isOn: $soundEffects)
            Divider().opacity(0.3)
            musicPlayerRow
        }
    }
    
    private var musicPlayerRow: some View {
        HStack {
            Text("Music Player")
                .font(.subheadline)
                .foregroundColor(.primary)
            
            if !PremiumManager.shared.isPremiumUser {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
            
            Spacer()
            
            if PremiumManager.shared.isPremiumUser {
                Toggle("", isOn: $showMusicPlayer)
                    .labelsHidden()
                    .tint(.blue)
            } else {
                Button {
                    HapticManager.impact(.medium)
                    showingPremiumUpsell = true
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    // MARK: - Remove Ads
    
    @ViewBuilder
    private var removeAdsButton: some View {
        if !PremiumManager.shared.isPremiumUser {
            Button {
                HapticManager.impact(.medium)
                showingPremiumUpsell = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                    Text("Remove Ads")
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.cardBackground))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Minimize
    
    private var minimizeButton: some View {
        Button {
            HapticManager.impact(.medium)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isPresented = false }
            onMinimize()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.compress.vertical")
                Text("Minimize Workout")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Reusable Components
    
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.cardBackground))
    }
    
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
    
    private func rowWithPicker<Content: View>(title: String, @ViewBuilder picker: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            picker()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    HapticManager.selectionChanged()
                    isOn.wrappedValue = newValue
                }
            ))
                .labelsHidden()
                .tint(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private func formatRestTime(_ seconds: Int) -> String {
        if seconds == 0 { return "Off" }
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 && s > 0 { return "\(m):\(String(format: "%02d", s))" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

// MARK: - Now Playing Mini Bar

import MediaPlayer

private struct NowPlayingBar: View {
    @State private var songTitle: String = ""
    @State private var artistName: String = ""
    @State private var isPlaying: Bool = false
    @State private var hasLoaded: Bool = false
    @State private var pollTimer: Timer?
    @State private var albumArtwork: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if !songTitle.isEmpty {
                HStack(spacing: 10) {
                    if let artwork = albumArtwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(songTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(artistName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button { skipBack() } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        
                        Button { togglePlayPause() } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Button { skipForward() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
            }
        }
        .onAppear {
            let player = MPMusicPlayerController.systemMusicPlayer
            if !hasLoaded {
                hasLoaded = true
                player.beginGeneratingPlaybackNotifications()
            }
            updateFromNowPlaying()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)) { _ in
            updateFromNowPlaying()
        }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)) { _ in
            updateFromNowPlaying()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            updateFromNowPlaying()
        }
    }
    
    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async { updateFromNowPlaying() }
        }
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func togglePlayPause() {
        HapticManager.selectionChanged()
        let player = MPMusicPlayerController.systemMusicPlayer
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }
    
    private func skipForward() {
        HapticManager.selectionChanged()
        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        refreshNowPlaying()
    }
    
    private func skipBack() {
        HapticManager.selectionChanged()
        MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        refreshNowPlaying()
    }
    
    private func refreshNowPlaying() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { updateFromNowPlaying() }
    }
    
    private func updateFromNowPlaying() {
        let player = MPMusicPlayerController.systemMusicPlayer
        let item = player.nowPlayingItem
        
        songTitle = item?.title ?? ""
        artistName = item?.artist ?? ""
        isPlaying = player.playbackState == .playing
        
        // Get artwork — keep existing if new fetch fails (transient nil)
        if let img = item?.artwork?.image(at: CGSize(width: 200, height: 200)) {
            albumArtwork = img
        } else if songTitle != (item?.title ?? "") {
            albumArtwork = nil
        }
        
        // Fallback for non-Apple Music apps (Spotify, etc.)
        if songTitle.isEmpty && AVAudioSession.sharedInstance().isOtherAudioPlaying {
            songTitle = "Now Playing"
            artistName = "External App"
            isPlaying = true
        }
    }
}
