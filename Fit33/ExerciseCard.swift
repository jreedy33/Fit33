import SwiftUI
import CoreData

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
    // True when the user just tapped "ADD SET" on THIS exercise and the
    // resulting auto-focus + grow + scroll cycle is still in flight.
    // Parent (`ActiveWorkoutView`) sets `justAddedSetForExerciseId =
    // exerciseId` inside `onAddSet` and clears it ~1.2s later. We use it
    // to gate REPS-auto-focus on the new last set so workout-open with
    // multi-set exercises doesn't trigger reps-focus on every card's
    // last row simultaneously (the cause of the "cursor jumps
    // everywhere" bug, 2026-05-10 PM).
    var isJustAddedSet: Bool = false
    @Binding var exerciseWithActiveTimer: String? // Track which exercise has the active timer globally
    var exerciseId: String = "" // This exercise's ID
    // (isFocused, isLastSet) — second flag tells the parent that focus
    // landed specifically on the LAST set's input, so it should anchor the
    // scroll to .bottom (clean cushion above the keyboard / music player)
    // rather than the default .top. Card-level taps pass `false` because
    // they don't target a specific set.
    var onFocusChanged: ((_ isFocused: Bool, _ isLastSet: Bool) -> Void)? = nil
    var onDragChanged: ((Int) -> Void)? = nil // Callback when drag position changes with target index
    var onDragEnded: (() -> Void)? = nil // Callback when drag ends
    var currentIndex: Int = 0
    var totalCount: Int = 1
    var isBeingDragged: Bool = false
    var shouldShift: Int = 0
    var isActiveCard: Bool = false
    var useKg: Bool = false
    var autoStartTimer: Bool = true
    // Ids of ALL exercises currently in the workout (passed from
    // ActiveWorkoutView, which owns `exercises`). Seeds the shuffle
    // exclusion set so a swap can never pick an exercise that's already
    // another slot in this workout — which would wipe that slot's logged
    // sets (both slots share one `exerciseSetsData` key) and duplicate
    // ForEach ids.
    var workoutExerciseIds: Set<UUID> = []
    // Finding U (2026-07-31): fired after a set is checked off so the
    // parent can mirror the new "next set" state to the Apple Watch.
    var onSetCheckedOff: (() -> Void)? = nil
    
    @State private var showingExerciseDetail = false
    @State private var prefetchedExercises: [Exercise] = [] // Prefetched similar exercises ready to shuffle
    @State private var showingRestTimerSheet = false
    @State private var showingReplaceExercise = false
    @State private var showingRenameExercise = false
    // Drives the "..." action sheet (replaces the previous SwiftUI `Menu`).
    // See the comment on the trigger button below for why we moved off `Menu`.
    @State private var showingActionSheet = false
    @State private var activeTimerSetNumber: Int? = nil // Track which set currently has an active timer
    @State private var isFavorite: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasAppeared: Bool = false
    @State private var recentSessions: [ExerciseSessionSummary] = []
    @State private var didLoadRecentSessions: Bool = false
    @AppStorage("workoutPerSideMode") private var isPerSideMode: Bool = false
    @State private var showingPlateCalculator: Bool = false
    @State private var plateCalcSetIndex: Int = 0
    @AppStorage("defaultBarWeight") private var barWeight: Double = 45
    @StateObject private var cardRestTimer = RestTimer()
    
    private let cardHeight: CGFloat = 180 // Approximate card height for drag calculations

    // ⚡️ SCROLL PERF: Lift per-render Color allocations to `static let` so the
    // body closure doesn't re-allocate them every frame. `Color(red:green:blue:)`
    // is *not* free — it boxes into an `UIColor` the first time SwiftUI rasterizes
    // it, and re-allocating per re-eval defeats SwiftUI's color identity diff.
    // (See QUALITY_PERFORMANCE_AGENT.md invariant #20 — same rule, generalized
    // beyond formatters: any reusable value used inside a hot SwiftUI body that
    // doesn't depend on view state belongs in a `static let`.)
    private static let activeAccentColor = Color(red: 0.0, green: 0.7, blue: 1.0)
    private static let inactiveAccentColor = Color(white: 0.5)
    private static let setsBackgroundColor = Color(red: 0.08, green: 0.08, blue: 0.10)
    private static let activeAccentShadowColor = Color(red: 0.0, green: 0.7, blue: 1.0).opacity(0.25)
    private static let activeAccentTintColor = Color(red: 0.0, green: 0.7, blue: 1.0).opacity(0.15)
    private static let baseShadowColor = Color.black.opacity(0.3)
    
    // Computed property to determine if this exercise is currently being worked on
    private var isExerciseActive: Bool {
        // Exercise is active ONLY if there's an active rest timer running
        // This ensures only the exercise with a live timer has scrolling text
        return activeTimerSetNumber != nil
    }

    // True when this exercise uses per-implement weight equipment — i.e.
    // the user enters the weight of ONE piece (one bell), not the total
    // across both hands. Covers dumbbells AND kettlebells (and is named
    // `isDumbbellExercise` for historical reasons — see bug 996ca300 /
    // Joe Reed feedback, build 1.38, which originally covered only
    // dumbbells; kettlebells added 2026-05-10 per user request to apply
    // the same "each" treatment across all bell-style equipment).
    //
    // Drives:
    //   • the inline "each" suffix INSIDE the weight box (SetRowView)
    //   • the "Nea. × R" formatting in the PREVIOUS / SUGGESTED column
    //   • the VoiceOver "Weight each" accessibility label
    //
    // Case-insensitive substring match handles combined equipment strings
    // like "Dumbbells / Bench" or "Kettlebell (Single)".
    private var isDumbbellExercise: Bool {
        guard let equipment = exercise.equipment?.lowercased() else { return false }
        return equipment.contains("dumbbell")
            || equipment.contains("kettlebell")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Exercise header + column headers — gray
            VStack(spacing: 0) {
                exerciseHeader
                RecentSessionsTilesRow(sessions: recentSessions, useKg: useKg)
                columnHeaders
            }
            .background(Color.cardBackground)
            
            // Sets — dark
            setsRows
                .background(Self.setsBackgroundColor)
            
            // Add set button — dark
            addSetButton
                .background(Self.setsBackgroundColor)
        }
        // ⚡️ SCROLL PERF (2026-05-04): the active-workout scroll was visibly
        // laggy vs. the Exercise Library scroll. The dominant cost was THIS
        // exact modifier chain — `SleekCardBackground` is a 5-layer ZStack
        // (4 RoundedRectangle gradient/stroke layers + 1 with `.blur(radius: 4)`),
        // and the dual `.shadow(...)` modifiers below each independently
        // re-rasterized that entire 5-layer composite + all card content
        // (sets, buttons, headers) to compute a shadow alpha — TWO offscreen
        // passes per scroll frame per visible card.
        //
        // Two surgical fixes flatten this:
        //   1. `.drawingGroup()` on the background: the background is pure
        //      shapes/gradients (no text — `.drawingGroup()`'s usual gotcha
        //      doesn't apply), so it's safe to rasterize the 5 layers into
        //      a single Metal texture once per (size, accent, colorScheme)
        //      change. SleekCardBackground only re-rasterizes when
        //      `isActiveCard` flips — never per scroll frame.
        //   2. `.compositingGroup()` AFTER `.clipShape(...)` and BEFORE the
        //      shadows: this flattens the (already-rasterized background +
        //      content) into a single offscreen buffer ONCE, so both
        //      `.shadow()` modifiers operate on that flat buffer instead of
        //      re-rasterizing the full subtree twice. Canonical SwiftUI
        //      shadow-stacking optimization (see QUALITY_PERFORMANCE_AGENT
        //      invariant #28).
        //
        // We also drop `.contentShape(RoundedRectangle(... .continuous))` —
        // it computed a continuous-corner Bezier hit-test path on every
        // render (and the default rectangular hit area covers the entire
        // card just fine), and we lift all `Color(red:...)` literals to
        // `static let` so the body doesn't re-allocate them per re-eval.
        .background(
            SleekCardBackground(
                cornerRadius: CornerRadius.xl,
                accentColor: isActiveCard ? Self.activeAccentColor : Self.inactiveAccentColor
            )
            .drawingGroup()
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .compositingGroup()
        .shadow(color: Self.baseShadowColor, radius: 10, x: 0, y: 5)
        .shadow(color: isActiveCard ? Self.activeAccentShadowColor : .clear, radius: 16, x: 0, y: 0)
        // Plain `.onTapGesture` (NOT `.simultaneousGesture`) so the embedded
        // `Menu` ("..." actions) and `Button`s (shuffle / favorite) cleanly
        // absorb their own taps without ALSO firing this card-level focus
        // change. A previous `.simultaneousGesture` here caused the menu items
        // to flicker on open: tapping the "..." would simultaneously open the
        // Menu AND toggle `isActiveCard`, which animated the card's shadow /
        // accent and triggered `scrollProxy.scrollTo(...)` in the parent — all
        // happening UNDERNEATH the just-presented Menu, which jittered the
        // menu's anchor and made the rows visibly flash on appearance
        // (2026-04-29).
        //
        // Menu tap reliability is preserved by the `Color.clear` 44pt overlay
        // on the Menu's label (see below) — that's the real fix for "menu
        // doesn't always open on first tap"; the simultaneousGesture was a
        // redundant addition that has now been reverted.
        .onTapGesture {
            HapticManager.selectionChanged()
            // Card-level tap (not on a specific field). Pass isLastSet=false
            // so the parent uses its default anchor: .top scroll — the user
            // didn't focus a particular row, so there's no last-set context.
            onFocusChanged?(true, false)
        }
        .overlay(alignment: .bottomTrailing) {
            if cardRestTimer.isActive {
                Text(formatCountdownTime(cardRestTimer.timeRemaining))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(Self.activeAccentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Self.activeAccentTintColor)
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
                        Self.activeAccentColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .padding(1.5)
            } else if isActiveCard {
                // Selected card — full electric blue glow
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .strokeBorder(
                        Self.activeAccentColor,
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
        .fullScreenCover(isPresented: $showingReplaceExercise) {
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
            cardRestTimer.syncToWallClock()
            isFavorite = exercise.isFavorite
            
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                guard !Task.isCancelled else { return }
                hasAppeared = true
            }
            loadRecentSessionsIfNeeded()
        }
        .onChange(of: exercise.id) { _, newId in
            // Clear prefetch cache when exercise changes (after shuffle)
            // Next shuffle tap will re-fetch fresh alternatives
            prefetchedExercises = []
            // Reload tile row for the new exercise
            didLoadRecentSessions = false
            recentSessions = []
            loadRecentSessionsIfNeeded()
        }
        .onChange(of: exerciseWithActiveTimer) { _, _ in
            // Timer continues running even when user selects a different card
        }
    }
    
    // ⚡ PERF: Cache exercise name to avoid repeated property access
    private var exerciseName: String {
        exercise.name ?? "Exercise"
    }

    /// Lazy-load the "last 2 sessions" tile row.
    ///
    /// Reads through `ExerciseHistoryService.shared.recentSessionsByIdCache` —
    /// strict-id match against `exercise_performance_history.exercise_id`
    /// (migration #164). The id-based read guarantees the rendered history
    /// belongs to THIS specific exercise and not a name-collision sibling.
    /// If `exercise.id` is missing OR no id-tagged history exists yet, the
    /// tile row hides — never falls back to name-based matching, which is
    /// the user-visible bug this read path replaces (2026-04-29).
    private func loadRecentSessionsIfNeeded() {
        guard !didLoadRecentSessions else { return }
        guard !exercise.isFault else { return }
        guard let exerciseUUID = exercise.id else { return }
        let name = exerciseName
        guard !name.isEmpty, name != "Exercise" else { return }
        didLoadRecentSessions = true
        Task { @MainActor in
            let summaries = await ExerciseHistoryService.shared.fetchRecentSessions(forExerciseId: exerciseUUID, limit: 2)
            guard !Task.isCancelled else { return }
            // Guard against the exercise having been swapped while the fetch was in flight.
            guard exercise.id == exerciseUUID else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.recentSessions = summaries
            }
        }
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
    //
    // Finding Q (2026-07-31): the swap counter + already-offered set live on
    // WorkoutManager keyed by slot index (`currentIndex`), NOT as @State —
    // this card's ForEach identity changes on every swap, which reset the
    // @State to 0 and made tier 2 unreachable.

    private func shuffleToSimilarExercise() {
        let userEquipment = UserManager.shared.currentUser?.getEquipment() ?? []
        let userGoal = UserManager.shared.currentUser?.fitnessGoal ?? "Build Muscle"
        let manager = WorkoutManager.shared
        let swapCount = manager.slotSwapCounts[currentIndex] ?? 0
        var excludeIds = manager.slotShuffledExerciseIds[currentIndex] ?? []
        excludeIds.formUnion(workoutExerciseIds)
        if let currentId = exercise.id {
            excludeIds.insert(currentId)
        }
        
        func recordSwap(to newExercise: Exercise) {
            manager.slotSwapCounts[currentIndex] = swapCount + 1
            if let newId = newExercise.id {
                manager.slotShuffledExerciseIds[currentIndex, default: []].insert(newId)
            }
        }

        // Use ExerciseSwapService tiered logic:
        // swapCount < 3 → equipment variants first (same movement, different equipment)
        // swapCount >= 3 → complementary exercises (different movement that complements workout)
        if let newExercise = ExerciseSwapService.shared.getQuickSwap(
            for: exercise,
            swapCount: swapCount,
            userGoal: userGoal,
            userEquipment: userEquipment,
            previousSwapIds: excludeIds
        ) {
            HapticManager.impact(.medium)
            recordSwap(to: newExercise)

            let tier = swapCount + 1 <= 2 ? "equipment variant" : "complementary"
            AppLogger.debug("🔄 Shuffle #\(swapCount + 1) (\(tier)): \(exercise.name ?? "") → \(newExercise.name ?? "")", category: .workout)
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
                recordSwap(to: alt.exercise)

                AppLogger.debug("🔄 Shuffle #\(swapCount + 1) (fallback): \(exercise.name ?? "") → \(alt.exercise.name ?? "")", category: .workout)
                onShuffleExercise(alt.exercise)
            } else {
                HapticManager.notification(.warning)
                AppLogger.warning("⚠️ No alternatives found for: \(exercise.name ?? "")", category: .workout)
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
                // Scope the drag-state color animation to JUST `isBeingDragged`.
                // A blanket `.transaction { ... }` here used to clobber MarqueeText's
                // internal linear scroll animation (forcing it into a 0.2s easeInOut
                // every frame), which manifested as "flickery / fast / glitchy"
                // ticker motion. Animating only the value that actually changes
                // keeps the marquee's deterministic linear loop intact.
                .animation(.easeInOut(duration: 0.2), value: isBeingDragged)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isBeingDragged {
                        HapticManager.impact(.light)
                        showingExerciseDetail = true
                    }
                }
                .onLongPressGesture(minimumDuration: 0.75, pressing: { _ in
                    // Pressing-state ticks fire on EVERY touch-down/up over the
                    // exercise title, including innocuous taps that turn into a
                    // vertical scroll. We do NOT log here — see comment on the
                    // simultaneousGesture below for the full performance story.
                }, perform: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onDragChanged?(currentIndex)
                })
                .simultaneousGesture(
                    // ⚡️ SCROLL PERF (2026-05-04): this DragGesture USED to fire
                    // hundreds of `AppLogger.warning("⚠️ Drag ignored …")` calls
                    // PER SECOND while the user was simply scrolling the active
                    // workout. Cause: SwiftUI dispatches `.onChanged` on every
                    // touch movement past `minimumDistance`, and each
                    // `AppLogger.warning` synchronously runs string interpolation
                    // + `AdvancedSessionLogger.log` + extras-dict allocation +
                    // `os.Logger` dispatch on the main thread. At 60+ events/s
                    // that's a multi-second main-thread freeze (the user saw
                    // `0fps for 5622ms` in `ProductionFPSMonitor`). Two fixes:
                    //   1. SILENT no-op when not in drag mode. Hot-path gesture
                    //      handlers must NEVER log — see QUALITY_PERFORMANCE_AGENT
                    //      invariant #29.
                    //   2. Bump `minimumDistance` 5 → 25 to match
                    //      `swiftui-rules.mdc` (sub-25 thresholds compete with
                    //      vertical scroll and fire `.onChanged` for every
                    //      casual scroll touch that originates on the title).
                    DragGesture(minimumDistance: 25, coordinateSpace: .local)
                        .onChanged { value in
                            guard isBeingDragged else { return }
                            dragOffset = value.translation.height

                            let movement = Int(round(value.translation.height / cardHeight))
                            let targetIndex = max(0, min(totalCount - 1, currentIndex + movement))
                            onDragChanged?(targetIndex)
                        }
                        .onEnded { _ in
                            guard isBeingDragged else { return }
                            dragOffset = 0
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
                        .font(.ds_bodyLarge)
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                // Favorite star button
                Button(action: {
                    HapticManager.impact(.light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isFavorite.toggle()
                        
                        // Fetch fresh copy by ID to avoid stale references
                        guard let exerciseId = exercise.id else {
                            AppLogger.error("❌ Cannot favorite: exercise has no ID", category: .workout)
                            return
                        }
                        
                        let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", exerciseId as CVarArg)
                        fetchRequest.fetchLimit = 1
                        
                        do {
                            if let freshExercise = try viewContext.fetch(fetchRequest).first {
                                freshExercise.isFavorite = isFavorite
                                try viewContext.save()
                                AppLogger.debug("⭐ Exercise '\(freshExercise.name ?? "")' favorite status: \(isFavorite)", category: .workout)
                                
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
                                            AppLogger.debug("☁️ Favorite synced to cloud: \(freshExercise.name ?? "unknown")", category: .network)
                                        } catch {
                                            AppLogger.error("⚠️ Failed to sync favorite to cloud: \(error)", category: .network)
                                        }
                                    }
                                }
                                
                                // Notify exercise library to refresh
                                NotificationCenter.default.post(name: NSNotification.Name("FavoriteExerciseChanged"), object: nil)
                            }
                        } catch {
                            AppLogger.error("❌ Error saving favorite status: \(error)", category: .workout)
                        }
                    }
                }) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isFavorite ? .yellow : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                
                // Contextual actions trigger. Opens a `.popover` anchored
                // directly to this Button (so the arrow visibly points at
                // the "..." icon), with `.presentationCompactAdaptation(
                // .popover)` so iPhone keeps the popover style instead of
                // falling back to a sheet.
                //
                // Why we got here (2026-04-29, three iterations):
                //   1. SwiftUI `Menu` — items unreliable to tap because the
                //      Menu's popover anchor was perturbed by this card's
                //      `.shadow` x2 / `.offset` / `.scaleEffect` /
                //      `.animation` x3 / `RestTimer` `CADisplayLink` (60+
                //      FPS republish) modifiers. Items also visibly
                //      flickered when a `.simultaneousGesture` on the card
                //      root double-fired the focus-change handler on Menu
                //      open.
                //   2. `.confirmationDialog` — bulletproof tap reliability,
                //      but presented far from the trigger (centered popover
                //      / bottom sheet depending on iOS adaptation), which
                //      lost the visual connection to the "..." icon.
                //   3. `.popover` (this) — anchored to the Button so the
                //      arrow points at the "..." icon, AND uses regular
                //      SwiftUI Buttons inside (which have reliable tap
                //      recognition unlike Menu items).
                Button {
                    HapticManager.selectionChanged()
                    showingActionSheet = true
                } label: {
                    // 44pt `Color.clear` hit area with a 36pt visible circle
                    // overlay — keeps SwiftUI's hit-testing rectangle == the
                    // visible tap target so the trigger itself stays
                    // reliable (this was the original 2026-04-29 fix for
                    // "tap doesn't always register on first try").
                    Color.clear
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "ellipsis")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color(.systemGray6))
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Exercise actions")
                .accessibilityHint("Remove, replace, rename, or set rest timer")
                .popover(
                    isPresented: $showingActionSheet,
                    attachmentAnchor: .point(.bottom),
                    arrowEdge: .top
                ) {
                    ExerciseActionsPopover(
                        onReplace: {
                            showingActionSheet = false
                            showingReplaceExercise = true
                        },
                        onRename: {
                            showingActionSheet = false
                            showingRenameExercise = true
                        },
                        onAddRestTimer: {
                            showingActionSheet = false
                            showingRestTimerSheet = true
                        },
                        onRemove: {
                            showingActionSheet = false
                            onRemoveExercise()
                        }
                    )
                    .presentationCompactAdaptation(.popover)
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
                .font(.ds_caption)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            
            HStack(spacing: 3) {
                if hasSmartRecs {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                    Text("SUGGESTED")
                        .font(.ds_caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else {
                    Text("PREVIOUS")
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(useKg ? "KG" : "LB")
                .font(.ds_caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .center)

            Text("REPS")
                .font(.ds_caption)
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
                        // CRASH GUARD (2026-05-10, "Index out of range"): the
                        // `index` value captured here is from the ForEach at
                        // RENDER TIME. The `sets` binding can be mutated
                        // out-of-band BEFORE the swipe gesture completes —
                        // most commonly by `WorkoutWearableMerger` rebuilding
                        // the array when a WHOOP / wearable session overlaps
                        // the active workout, but also by the seamless
                        // `onAddSet` flow on another card or by background
                        // sync paths. If the array shrinks, the captured
                        // positional `index` can point past `sets.count`,
                        // and `sets.remove(at: index)` traps.
                        //
                        // The row's stable identity is `setItem.id` (the
                        // `WorkoutSetData` UUID — that's why `ForEach` uses
                        // `id: \.element.id`). Re-resolve the current
                        // position by that identity inside the closure body
                        // so we always operate on the correct row, no
                        // matter what mutated the array in the meantime.
                        // If the row has already been removed by another
                        // path, this becomes a no-op (idempotent).
                        guard let currentIndex = sets.firstIndex(where: { $0.id == setItem.id }) else {
                            AppLogger.debug("⚠️ SwipeableSetRow.onDelete: setItem \(setItem.id.uuidString.prefix(8)) already removed (captured index \(index), current sets.count \(sets.count)) — no-op", category: .workout)
                            return
                        }
                        withAnimation(.easeOut(duration: 0.2)) {
                            // Stop any active timer for this set.
                            // Uses `currentIndex` (1-indexed via +1) — the
                            // SetRowView uses the same convention.
                            if activeTimerSetNumber == currentIndex + 1 {
                                activeTimerSetNumber = nil
                            }
                            // If this is the only set, replace with a fresh
                            // set instead of deleting (preserves the visual
                            // shape of the card; the user expects to see a
                            // single empty set rather than an empty card).
                            if sets.count == 1 {
                                sets[0] = WorkoutSetData()
                            } else {
                                sets.remove(at: currentIndex)
                            }
                        }
                    }
                ) {
                    SetRowView(
                        setNumber: index + 1,
                        setData: setItem,
                        previousSet: getPreviousSetData(for: index + 1),
                        onSetCompleted: {
                            AppLogger.debug("✅ Set \(index + 1) completed - timer started, waiting for user to add next set", category: .workout)
                            // Finding U: advance the watch's live workout view.
                            onSetCheckedOff?()
                        },
                        isLastSet: index == sets.count - 1,
                        restDuration: customRestTimer ?? restDuration,
                        onTimerShouldStop: { _ in },
                        onNewExerciseInteraction: onNewExerciseInteraction,
                        activeTimerSetNumber: $activeTimerSetNumber,
                        exerciseWithActiveTimer: $exerciseWithActiveTimer,
                        exerciseId: exerciseId,
                        onShowAd: onShowAd,
                        // Two — and ONLY two — auto-focus triggers:
                        //   1) The very first set of the very first exercise
                        //      when the workout opens. Drops the cursor on
                        //      WEIGHT (the natural starting point of a fresh
                        //      workout). Gated on `isFirstExercise && index == 0`
                        //      so it only fires for ONE row in the whole list,
                        //      not for every exercise's set 0.
                        //   2) The new last set immediately after the user
                        //      taps "ADD SET" on THIS card. Drops the cursor
                        //      on REPS (weight is already cloned from the
                        //      prior set; reps are what the user actually
                        //      varies). Gated on `isJustAddedSet` so the
                        //      multi-set workout-open case does NOT trip
                        //      every card's last row into reps-auto-focus.
                        //
                        // `!setItem.isCompleted` guards both branches so we
                        // don't yank focus onto a row the user has already
                        // checked off (e.g. resumed workouts where some sets
                        // are pre-completed).
                        shouldAutoFocus: (isFirstExercise && index == 0 && !setItem.isCompleted) || (isJustAddedSet && index == sets.count - 1 && !setItem.isCompleted),
                        autoFocusOnReps: isJustAddedSet && index == sets.count - 1 && !setItem.isCompleted,
                        onFocusChanged: onFocusChanged,
                        isPerSideMode: $isPerSideMode,
                        barWeight: barWeight,
                        onOpenPlateCalculator: {
                            plateCalcSetIndex = index
                            showingPlateCalculator = true
                        },
                        useKg: useKg,
                        restTimer: cardRestTimer,
                        autoStartTimer: autoStartTimer,
                        isDumbbell: isDumbbellExercise
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

// MARK: - Exercise Actions Popover
//
// Anchored popover content for the "..." button on `ExerciseCard`. Lives in
// its own struct (instead of inline `Menu { ... }` content) for two reasons:
//   1. Tap reliability: SwiftUI Buttons inside a popover have rock-solid hit
//      testing, vs. iOS `Menu` items which were flaky on the parent card's
//      animated/shadowed/timer-republishing geometry (see the trigger
//      Button's comment for the full history).
//   2. Identity stability: a dedicated struct's body only re-evaluates when
//      its inputs (the four closures) change identity, not on every parent
//      re-render. This was a contributor to the previous `Menu`'s items
//      "flickering" on open.
//
// Visual: matches iOS popover conventions — rounded vibrancy background
// supplied by the `.popover` presentation, full-width 44pt+ rows with an
// SF Symbol leading icon and trailing chevron-style spacing. Destructive
// "Remove Exercise" row is tinted red via Button(role:).
private struct ExerciseActionsPopover: View {
    let onReplace: () -> Void
    let onRename: () -> Void
    let onAddRestTimer: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(label: "Replace Exercise", systemImage: "arrow.triangle.swap", action: onReplace)
            Divider()
            row(label: "Rename Exercise", systemImage: "pencil", action: onRename)
            Divider()
            row(label: "Add Rest Timer", systemImage: "timer", action: onAddRestTimer)
            Divider()
            row(label: "Remove Exercise", systemImage: "trash", role: .destructive, action: onRemove)
        }
        .frame(minWidth: 240)
    }

    @ViewBuilder
    private func row(
        label: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 22, alignment: .center)
                Text(label)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundColor(role == .destructive ? .red : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
