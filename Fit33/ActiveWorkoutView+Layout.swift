import SwiftUI
import CoreData

extension ActiveWorkoutView {
    // MARK: - Main Content (extracted to reduce body type-check complexity)
    /// Active workout background: blue/cyan orb look (matches the rest of the
    /// app per DESIGN_AGENT "Every full-page screen must have AnimatedOrbBackground")
    /// rendered STATIC (no easing animation loop). Static orbs leverage
    /// `.drawingGroup()` to rasterize once and then sit idle — zero per-frame
    /// CPU/GPU cost while rest timers / audio / screen-stays-on do real work.
    ///
    /// IMPORTANT — opaque base layer required:
    /// `ActiveWorkoutView` is rendered as a `zIndex(10)` overlay on top of
    /// `WorkoutTabView` (see `WorkoutTabView.swift` Layer 3), which has its
    /// own orb background, "Workout" header, exercise list, and tab bar.
    /// `AnimatedOrbBackground.workoutStatic` uses `AdaptiveGradient.universalDark`
    /// in dark mode, which starts with `purple.opacity(0.2)` + `blue.opacity(0.1)`
    /// — translucent at the top. Without an opaque base, the underlying tab
    /// bleeds through visibly. The previous flat `LinearGradient` was fully
    /// opaque, which is why this regression appeared after the orb migration.
    var workoutBackground: some View {
        ZStack {
            (colorScheme == .dark
                ? Color(red: 0.04, green: 0.04, blue: 0.06)
                : Color(.systemGroupedBackground))
                .ignoresSafeArea()
            AnimatedOrbBackground.workoutStatic(colorScheme: colorScheme)
        }
    }
    
    var mainWorkoutContent: some View {
        workoutGeometryContent
            .onChange(of: horizontalSizeClass) { _, _ in OrientationManager.shared.updateScreenDimensions() }
            .onChange(of: verticalSizeClass) { _, _ in OrientationManager.shared.updateScreenDimensions() }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.1))
                    OrientationManager.shared.updateScreenDimensions()
                }
            }
            .onAppear { handleWorkoutAppear() }
            .onChange(of: defaultSetCount) { _, newCount in
                workoutManager.padAllExercisesToSetCount(newCount)
            }
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
    
    var workoutGeometryContent: some View {
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
                                    .font(.ds_bodyMedium)
                                    .foregroundColor(.secondary)
                                Text(notesPlaceholder)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.ds_bodySmall)
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
                                            AppLogger.debug("🔀 Shuffle \(shuffleCount) - showing ad", category: .workout)
                                            showShuffleAd {
                                                shuffleExercise(at: index, with: newExercise)
                                            }
                                        } else {
                                            AppLogger.debug("🔀 Shuffle \(shuffleCount) - no ad", category: .workout)
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
                                        AppLogger.debug("🔄 Drag changed: index=\(index), target=\(targetIdx), current draggingIndex=\(String(describing: draggingIndex))", category: .workout)
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
                                            syncExercisesToWorkoutManager()
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
                                    .font(.ds_heading3)
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
                        .padding(.bottom, showMusicPlayer ? 80 : 24)
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
        .fullScreenCover(isPresented: $showingExerciseSelection) {
            NavigationStack {
                CustomWorkoutBuilderView(currentExercises: exercises, onAddExercise: { newExercise in
                    exercises.append(newExercise)
                    let exerciseId = newExercise.id?.uuidString ?? ""
                    if workoutManager.getSetsForExercise(id: exerciseId).isEmpty {
                        let count = WorkoutManager.userDefaultSetCount
                        workoutManager.exerciseSetsData[exerciseId] = (0..<count).map { _ in WorkoutSetData() }
                    }
                    syncExercisesToWorkoutManager()
                    UserBehaviorLearningEngine.shared.recordCustomWorkoutAddition(exerciseName: newExercise.name ?? "")
                })
                .environmentObject(workoutManager)
                .environmentObject(UserManager.shared)
            }
        }
            .safeAreaInset(edge: .top) { workoutHeaderBar }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Workout Header Bar (extracted to reduce body complexity)
    var workoutHeaderBar: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(workoutDuration)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityLabel("Workout timer: \(Int(elapsedTime) / 60) minutes \(Int(elapsedTime) % 60) seconds")
                
                HStack {
                    Button(action: {
                        HapticManager.selectionChanged()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingSettingsPanel.toggle()
                        }
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.ds_heading3)
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                    }
                    .accessibilityLabel("Workout settings")
                    .accessibilityHint("Adjust rest timer, weight unit, and other options")
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        if workoutManager.workoutInsights != nil {
                            Button(action: { showingWorkoutInsights = true }) {
                                Image(systemName: "info.circle")
                                    .font(.ds_heading2)
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
                                                AppLogger.error("⚠️ Failed to sync workout favorite to cloud: \(error)", category: .network)
                                            }
                                        }
                                    }
                                } catch {
                                    AppLogger.error("❌ Error saving workout favorite status: \(error)", category: .workout)
                                }
                            }
                        }) {
                            Image(systemName: isWorkoutFavorite ? "star.fill" : "star")
                                .font(.ds_heading2)
                                .foregroundColor(isWorkoutFavorite ? .yellow : (colorScheme == .dark ? .white : .primary))
                                .scaleEffect(isWorkoutFavorite ? 1.1 : 1.0)
                        }
                        .accessibilityLabel(isWorkoutFavorite ? "Remove from favorites" : "Add to favorites")
                        .accessibilityHint("Save this workout for quick access later")
                        
                        Button("FINISH") {
                            let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
                            heavyImpact.impactOccurred()
                            finishWorkout()
                        }
                        .font(.ds_labelLarge)
                        .foregroundColor(.blue)
                        .accessibilityLabel("Finish workout")
                        .accessibilityHint("End your current workout and save results")
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
    var settingsPanelOverlay: some View {
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

    func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: Date())
    }
    
    @ViewBuilder
    func programDayBadge(dayNumber: Int, focus: String) -> some View {
        HStack(spacing: 8) {
            // Day badge
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                
                Text("Day \(dayNumber)")
                    .font(.ds_bodySmall)
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
                    .font(.ds_bodySmall)
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
