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
            
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                guard !Task.isCancelled else { return }
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
            AppLogger.debug("🔄 Shuffle #\(perExerciseSwapCount) (\(tier)): \(exercise.name ?? "") → \(newExercise.name ?? "")", category: .workout)
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

                AppLogger.debug("🔄 Shuffle #\(perExerciseSwapCount) (fallback): \(exercise.name ?? "") → \(alt.exercise.name ?? "")", category: .workout)
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
                    AppLogger.debug("👆 Long press pressing: \(isPressing)", category: .workout)
                }, perform: {
                    // Long press completed - NOW activate drag mode
                    AppLogger.debug("✅ Long press completed - activating drag mode for index \(currentIndex)", category: .workout)
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onDragChanged?(currentIndex)
                })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { value in
                            guard isBeingDragged else { 
                                AppLogger.warning("⚠️ Drag ignored - not in drag mode", category: .workout)
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
                                AppLogger.warning("⚠️ Drag end ignored - not in drag mode", category: .workout)
                                return 
                            }
                            AppLogger.debug("🏁 Drag gesture ended", category: .workout)
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
                        .font(.caption)
                        .foregroundColor(isFavorite ? .yellow : .secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
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
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color(.systemGray6))
                        )
                        .contentShape(Circle())
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
                            AppLogger.debug("✅ Set \(index + 1) completed - timer started, waiting for user to add next set", category: .workout)
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
