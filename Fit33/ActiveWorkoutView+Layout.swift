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
                // Tell the watch the live workout is over so it can
                // tear down the WatchLiveWorkoutView fullScreenCover.
                PhoneToWatchLiveWorkoutBridge.shared.clearLive()
            }
            .overlay { settingsPanelOverlay }
            // Music player lives in `.safeAreaInset(edge: .bottom)` (NOT
            // a floating `.overlay`) so the underlying `ScrollView` shrinks
            // its content area to leave clean space above it. This is the
            // load-bearing piece behind "the bottom set always sits cleanly
            // above the keyboard or music player when adding a set" —
            // SwiftUI's automatic keyboard avoidance reduces the visible
            // scroll area by both the keyboard height AND any safeAreaInset,
            // so `scrollProxy.scrollTo(card, anchor: .bottom)` lands the
            // card's bottom edge cleanly above keyboard + music player.
            // Previously the music player was a floating overlay, which
            // visually covered the bottom of tall exercise cards
            // (2026-05-04).
            .safeAreaInset(edge: .bottom, spacing: 0) {
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
                
                // Music player is a `.safeAreaInset(edge: .bottom)` (see mainWorkoutContent),
                // so the ScrollView below already accounts for its height.
                
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
                
                // Exercise list - transparent container.
                //
                // SCROLL CUSHION (2026-05-10): the LazyVStack uses `spacing: 0`
                // and each card carries its own `.padding(.bottom, 16)` BELOW
                // the `.id(exerciseId)` modifier. This is intentional and load-
                // bearing for the "add set" scroll behavior — see comment on
                // `.padding(.bottom, 16).id(exerciseId)` below. The visible
                // 16pt inter-card gap is preserved (provided by the per-card
                // bottom padding instead of LazyVStack spacing), so users see
                // no layout change.
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
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

                                        // Suppress the focus-driven scroll-to-top that
                                        // the new set's auto-focus will fire on the
                                        // next layout pass (otherwise it would yank the
                                        // card back to `anchor: .top` and hide the new
                                        // last set behind the keyboard + music player).
                                        // Set BEFORE the mutation so the suppression is
                                        // already in place when the focus event arrives.
                                        suppressFocusScrollForExerciseId = exerciseId

                                        // Mark this exercise as having just had a set
                                        // added by the user. ExerciseCard reads this
                                        // (via `isJustAddedSet`) to decide whether the
                                        // new last set should auto-focus its REPS
                                        // field. Without this gate, EVERY exercise's
                                        // last set on workout open would qualify for
                                        // reps-auto-focus and race for first responder,
                                        // making the cursor jump around (user feedback
                                        // 2026-05-10 PM).
                                        justAddedSetForExerciseId = exerciseId

                                        // SEAMLESS GROW + SCROLL (2026-05-10, snappier
                                        // 2026-05-10 PM): wrap BOTH the data mutation
                                        // and the scrollTo in a single `withAnimation`
                                        // transaction. SwiftUI batches the "card grows
                                        // by one row" layout change and the "scroll up
                                        // to keep the new bottom cushioned above the
                                        // music player / keyboard" scroll into ONE
                                        // 0.2s `.snappy` interpolation — the card
                                        // visibly slides up as the new set row appears
                                        // in lock-step.
                                        //
                                        // Tuning notes:
                                        //   • `.snappy(duration: 0.2)` (was
                                        //     `.easeInOut(duration: 0.3)`) — `.snappy`
                                        //     is a built-in spring tuned for crisp UI
                                        //     motion with effectively zero overshoot,
                                        //     and the shorter duration removes the
                                        //     "sluggish" feel without losing
                                        //     smoothness.
                                        //   • `HapticManager.impact(.rigid)` fires
                                        //     alongside the animation — `.rigid` is
                                        //     iOS's "snapped into place" haptic
                                        //     (used in segmented controls, picker
                                        //     detents, etc.), which reinforces the
                                        //     visual snap. The ADD SET button's own
                                        //     `.light` haptic still fires for tap
                                        //     confirmation; the two register as one
                                        //     decisive event on-device.
                                        //
                                        // Why no `Task.sleep(50ms)` between mutation
                                        // and scrollTo: the sleep deferred scrollTo
                                        // to a later runloop so LazyVStack geometry
                                        // was settled before the proxy computed its
                                        // target. That delay was the root cause of
                                        // an earlier "drop behind music player → pop
                                        // up" two-stage glitch. With both calls in
                                        // the same `withAnimation` block,
                                        // ScrollViewReader tracks the moving target
                                        // throughout the animation (it follows the
                                        // `.id`-bearing frame as the card's height
                                        // animates), so the scroll target is correct
                                        // from frame 1.
                                        HapticManager.impact(.rigid)
                                        withAnimation(.snappy(duration: 0.2)) {
                                            workoutManager.addSetToExercise(id: exerciseId, set: newSet)
                                            scrollProxy.scrollTo(exerciseId, anchor: .bottom)
                                        }

                                        // Clear the focus-scroll suppression after the
                                        // scroll animation finishes (200ms) plus a
                                        // small buffer for keyboard appearance.
                                        // Shortened from 500ms → 350ms to match the
                                        // new faster `.snappy(0.2)` curve — the
                                        // window must cover the animation but not
                                        // linger past it (a stale suppress flag would
                                        // swallow legitimate user taps on other sets
                                        // during the residual window).
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .milliseconds(350))
                                            if suppressFocusScrollForExerciseId == exerciseId {
                                                suppressFocusScrollForExerciseId = nil
                                            }
                                        }

                                        // Clear the `justAddedSetForExerciseId` flag
                                        // after the auto-focus window finishes. Budget:
                                        //   200ms scroll animation
                                        // + 300ms SetRowView settle delay
                                        // + 1 main-actor hop for becomeFirstResponder
                                        // + buffer for re-renders
                                        // → 1200ms is comfortable. We leave it
                                        // intentionally longer than the scroll-suppress
                                        // clear (350ms) because this flag drives the
                                        // EXISTING `if shouldAutoFocus` block inside
                                        // `SetRowView.onAppear`, which runs after the
                                        // 0.3s sleep — clearing too early would race
                                        // the focus push and we'd be back to no
                                        // auto-focus. A stale flag here is harmless:
                                        // SetRowView's `hasInitialized` guard prevents
                                        // its onAppear from firing twice on the same
                                        // row, so a long-lived flag can't retrigger
                                        // auto-focus on existing rows.
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .milliseconds(1200))
                                            if justAddedSetForExerciseId == exerciseId {
                                                justAddedSetForExerciseId = nil
                                            }
                                        }
                                    },
                                    onRemoveExercise: {
                                        removeExercise(at: index)
                                    },
                                    onReplaceExercise: { newExercise in
                                        // Load historical data for the replaced exercise
                                        loadHistoricalDataForExercise(newExercise)
                                        // Auto-select the new exercise and snap it cleanly
                                        // to the top of the screen so the user can start
                                        // logging without any extra scroll/tap (per user
                                        // request 2026-04-29). The new exercise sits at
                                        // the same `index` as the old one, so we read its
                                        // id from the freshly-mutated `exercises` array
                                        // rather than relying on the caller's reference.
                                        let newExerciseId = newExercise.id?.uuidString ?? ""
                                        if !newExerciseId.isEmpty {
                                            activeExerciseId = newExerciseId
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                scrollProxy.scrollTo(newExerciseId, anchor: .top)
                                            }
                                        }
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
                                    isJustAddedSet: justAddedSetForExerciseId == exerciseId,
                                    exerciseWithActiveTimer: $exerciseWithActiveTimer,
                                    exerciseId: exerciseId,
                                    onFocusChanged: { isFocused, isLastSet in
                                        if isFocused {
                                            activeExerciseId = exerciseId
                                            // Anchor selection:
                                            //   • LAST set focused → `.bottom`. The card's
                                            //     bottom (last set + ADD SET button + the
                                            //     16pt cushion baked into the `.id` wrapper)
                                            //     sits cleanly above the keyboard + music
                                            //     player, with no clipping. Mirrors what
                                            //     `onAddSet` does so newly-added sets and
                                            //     manually-tapped last sets behave the same
                                            //     (user feedback 2026-05-10).
                                            //   • Any other set (or card-level tap) →
                                            //     `.top`. The user is working on an earlier
                                            //     set in a tall card, so the natural view
                                            //     puts the card's top at the visible top.
                                            //
                                            // Animation + haptic:
                                            //   • `.snappy(duration: 0.2)` — crisp, fast,
                                            //     no overshoot. Replaced the older
                                            //     `.easeInOut(0.3)` which felt sluggish on
                                            //     this scroll path (user feedback
                                            //     2026-05-10 PM).
                                            //   • `HapticManager.impact(.rigid)` ONLY on
                                            //     the last-set bottom snap — `.rigid` is
                                            //     iOS's "snapped into place" haptic and
                                            //     reinforces the special visual snap to
                                            //     the keyboard cushion. We deliberately
                                            //     skip the haptic on the `.top` branch:
                                            //     that's a routine scroll, not a snap.
                                            //
                                            // Suppression: when the new set's auto-focus
                                            // event fires DURING `onAddSet`'s in-flight
                                            // scroll animation, both would target `.bottom`
                                            // — same destination, no visible difference —
                                            // but skipping the redundant `scrollTo` keeps
                                            // SwiftUI from interrupting its own animation
                                            // (and prevents a doubled `.rigid` haptic).
                                            if suppressFocusScrollForExerciseId != exerciseId {
                                                if isLastSet {
                                                    HapticManager.impact(.rigid)
                                                }
                                                withAnimation(.snappy(duration: 0.2)) {
                                                    scrollProxy.scrollTo(
                                                        exerciseId,
                                                        anchor: isLastSet ? .bottom : .top
                                                    )
                                                }
                                            }
                                        }
                                    },
                                    onDragChanged: { targetIdx in
                                        // ⚡️ SCROLL PERF (2026-05-04): no logging in
                                        // this hot path — it fires on every drag
                                        // tick once reorder mode is active. Per
                                        // QUALITY_PERFORMANCE_AGENT invariant #29,
                                        // gesture handlers must be silent.
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
                                    autoStartTimer: autoStartRestTimer,
                                    workoutExerciseIds: Set(exercises.compactMap { $0.id })
                                )
                                // 16pt transparent bottom cushion is applied
                                // BEFORE `.id(exerciseId)` on purpose. The id
                                // modifier captures the frame at this point in
                                // the chain — including the cushion — so when
                                // `onAddSet` calls
                                // `scrollProxy.scrollTo(exerciseId, anchor: .bottom)`
                                // the cushion's bottom lines up with the
                                // visible scroll bottom, leaving the card
                                // content (last set + ADD SET button) sitting
                                // 16pt above the keyboard / music player.
                                // Without the cushion, the card's bottom edge
                                // sat flush against the keyboard / music
                                // player top with no breathing room (user
                                // feedback 2026-05-10).
                                //
                                // The matching `LazyVStack(spacing: 0)` above
                                // ensures the visible inter-card gap stays at
                                // 16pt overall — provided here by each card's
                                // bottom padding instead of LazyVStack
                                // spacing.
                                .padding(.bottom, 16)
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
                        // Music player no longer needs a manual `+ 80pt` shim —
                        // it's a `.safeAreaInset(edge: .bottom)` on `mainWorkoutContent`,
                        // so the ScrollView's bottom inset already includes it.
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
                ZStack(alignment: .topTrailing) {
                    BannerAdView()

                    // Always-visible "Remove ads" pill in the upper-right
                    // corner of every banner — turns the banner itself
                    // into a paywall surface (Phase 1 cheat-code:
                    // every ad impression is also a Pro upsell impression).
                    Button {
                        HapticManager.impact(.light)
                        showingPremiumUpsell = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .heavy))
                            Text("Remove Ads")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Remove ads")
                    .accessibilityHint("Open Pro upgrade to remove all ads")
                }
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
