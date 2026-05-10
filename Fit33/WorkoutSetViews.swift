import SwiftUI
import CoreData

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
                                .font(.ds_heading3)
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
                // Use simultaneousGesture (not .gesture) so this DragGesture does NOT
                // create a failure-requirement with inner gestures. `.gesture` makes the
                // Menu / Button presses wait for this drag to fail, which manifests as
                // "System gesture gate timed out" in the console and a visibly laggy /
                // stuck-open W/F/D menu on rows that are mid-animation (e.g. a completed
                // set with an active rest-timer border re-rendering every frame).
                .simultaneousGesture(
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
                                if value.translation.width < -deleteButtonWidth * 0.6 {
                                    offset = -deleteButtonWidth
                                    if !isShowingDelete { HapticManager.impact(.medium) }
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
    // (isFocused, isLastSet) — the second flag lets the parent pick a
    // .bottom-anchored scroll (so the card's bottom sits cleanly above the
    // keyboard + music player) when the user focuses the last set, vs the
    // standard .top-anchored scroll for any other set. See
    // ActiveWorkoutView+Layout.swift's `onFocusChanged` closure.
    var onFocusChanged: ((_ isFocused: Bool, _ isLastSet: Bool) -> Void)? = nil
    @Binding var isPerSideMode: Bool
    var barWeight: Double = 45
    var onOpenPlateCalculator: (() -> Void)? = nil
    var useKg: Bool = false
    @ObservedObject var restTimer: RestTimer
    var autoStartTimer: Bool = true
    // True when the parent exercise uses per-implement weight equipment —
    // dumbbell or kettlebell, where the user enters the weight of ONE
    // bell, not the total. The parameter name stayed `isDumbbell` for
    // historical reasons (bug 996ca300, originally dumbbell-only);
    // kettlebells were added 2026-05-10 to share the same treatment.
    //
    // Renders three coordinated affordances when true:
    //   • Inline "each" suffix to the right of the weight number INSIDE
    //     the box (e.g. "70 each"). Number font shrinks 17pt → 14pt and
    //     the suffix is 10pt so both fit in the existing 70×38pt frame
    //     without changing row height (column alignment preserved).
    //   • "Nea. × R" formatting in the PREVIOUS / SUGGESTED column
    //     (e.g. "25ea. × 10"), so users see the per-implement reading
    //     in both their history and their input cell.
    //   • VoiceOver "Weight each" label via `weightAccessibilityLabel`.
    var isDumbbell: Bool = false

    // Convenience: true when we should render the inline "each" suffix
    // alongside the weight value. Per-side mode wins (per-side is barbell-only
    // — defensive: never show two conflicting clarifiers).
    private var showsEachSuffix: Bool {
        isDumbbell && !isPerSideMode
    }

    // Content-sized width for the weight text field when the "each" suffix
    // is showing. We measure the live text (or the placeholder when empty)
    // at the field's actual font, then add a tiny cursor cushion. This is
    // what makes the HStack auto-center the "<number> each" cluster inside
    // the 70pt box: with a fixed-width field, short numbers leave dead
    // space on one side and push the visible cluster off the box's center;
    // with a content-sized field, the HStack centers naturally and the
    // visible cluster's geometric center lands on the box's center
    // regardless of digit count.
    //
    // Capped at 44pt — the maximum 5-char value ("12.55", "99.99",
    // "100.5", etc.) measures ~36–40pt at 14pt semibold, plus a tiny
    // buffer. The 16pt floor handles the focused-but-empty state so the
    // cursor doesn't render in a zero-width frame.
    private var weightFieldWidth: CGFloat {
        let displayText = weightText.isEmpty ? weightPlaceholder : weightText
        guard !displayText.isEmpty else { return 16 }
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let measured = (displayText as NSString).size(withAttributes: [.font: font])
        return min(44, max(16, ceil(measured.width) + 4))
    }
    
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
            // Per QP invariant 44 (compound-card a11y): the set row uses
            // `.accessibilityElement(children: .contain)` (NOT `.combine`)
            // so each interactive child (set-type menu, weight field, reps
            // field, complete button) stays individually focusable +
            // editable. The container announces "Set N" on entry; each
            // child reads its own action label below.
            HStack(spacing: 8) {
                // Set number/type indicator - tap to change set type
                // IMPORTANT: Use the standard `Label(title, systemImage:)` form for
                // every Menu item. SwiftUI Menu items render natively via UIMenu,
                // which only reads `title` + `image` from a Label — custom views
                // inside a Label are dropped (descriptions never showed in the UI)
                // AND hit-testing collapses to a smaller area. Standard Labels give
                // the full row tap target users expect.
                Menu {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Button {
                            HapticManager.selectionChanged()
                            setData.setType = type
                        } label: {
                            Label(type.rawValue, systemImage: type.icon)
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 2) {
                        Text(setData.setType.displayLetter ?? "\(setNumber)")
                            .font(.ds_labelLarge)
                            .foregroundColor(setData.setType == .normal ? .primary : setData.setType.color)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(setData.setType == .normal ? .secondary.opacity(0.4) : setData.setType.color.opacity(0.5))
                            .offset(x: 2, y: 1.5)
                    }
                    // Meet Apple HIG 44pt minimum tap target so the chevron trigger
                    // responds on the first tap regardless of where the user lands.
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Set \(setNumber) type: \(setData.setType.rawValue)")
                .accessibilityHint("Tap to change set type")
                
                // Previous set info - show last workout's data or smart
                // recommendation. For dumbbell / kettlebell exercises the
                // value renders as "25ea. × 10" so users see the
                // per-implement reading in their history (matching the
                // "each" treatment inside the editable weight box).
                // Non-bell equipment keeps the compact "70×8" shorthand.
                HStack(spacing: 4) {
                    if let prev = previousSet {
                        let displayWeight = useKg
                            ? (prev.weight * WorkoutSetData.lbsToKg * 10).rounded() / 10
                            : prev.weight
                        let label = formattedPreviousSetLabel(weight: displayWeight, reps: prev.reps)
                        if prev.isSmartRecommendation {
                            Image(systemName: "sparkles")
                                .font(.ds_bodySmall)
                                .foregroundColor(.orange)
                            Text(label)
                                .font(.ds_labelLarge)
                                .foregroundColor(.orange)
                        } else {
                            Text(label)
                                .font(.ds_bodyLarge)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("-")
                            .font(.ds_bodyLarge)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            // Weight input. For dumbbell exercises (not in per-side mode) we
            // render an inline "each" suffix INSIDE the box — both the number
            // and the suffix are shrunk so they read together as "70 each"
            // cleanly inside the existing 70×38pt frame. Row heights stay
            // identical across exercise types either way, preserving column
            // alignment.
            //
            // Layout details:
            //   • The text field is sized to its CONTENT (see
            //     `weightFieldWidth`) so the HStack auto-centers the
            //     "<number> each" cluster on the box's geometric center for
            //     ANY digit count — short numbers like "75" no longer
            //     leave dead space and shift the cluster off-center.
            //   • `HStack(alignment: .bottom)` + `.padding(.bottom, 12)` on
            //     "each" baseline-aligns the suffix with the bottom of the
            //     digit row. The UITextField centers its 14pt text in the
            //     38pt frame, putting the digit baseline at ~y=25 from the
            //     frame top; the 12pt bottom-padding lifts the 10pt "each"
            //     text up so its baseline lands at the same y. The result
            //     reads as one continuous text run, not two stacked items.
            //   • `maxLength: 5` caps input at the "xx.xx" format the user
            //     specified — "12.55", "99.99", "100.5", or "1000" all fit;
            //     anything longer is rejected by SelectAllTextField's
            //     delegate before reaching the binding.
            HStack(alignment: .bottom, spacing: 2) {
                SelectAllTextField(
                    placeholder: weightPlaceholder,
                    text: $weightText,
                    keyboardType: .decimalPad,
                    font: .systemFont(ofSize: showsEachSuffix ? 14 : 17, weight: .semibold),
                    textAlignment: .center,
                    textColor: setData.isCompleted ? .white : .label,
                    maxLength: 5,
                    onFocusChange: { isFocused in
                        isWeightFocused = isFocused
                        if isFocused {
                            HapticManager.selectionChanged()
                            onNewExerciseInteraction()
                            onFocusChanged?(true, isLastSet)
                        } else {
                            if let weight = parseWeight(weightText) {
                                applyWeight(weight)
                            }
                        }
                    }
                )
                .frame(width: showsEachSuffix ? weightFieldWidth : 70, height: 38)

                if showsEachSuffix {
                    Text("each")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 70, height: 38)
            .background(Color(.systemGray6))
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Color.blue, lineWidth: isWeightFocused ? 2 : 0)
            )
            .shadow(color: isWeightFocused ? Color.blue.opacity(0.4) : Color.clear, radius: 4)
            .accessibilityLabel(weightAccessibilityLabel)
            .accessibilityHint("Enter weight for set \(setNumber)")
            .onLongPressGesture(minimumDuration: 0.5) {
                HapticManager.impact(.medium)
                onOpenPlateCalculator?()
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
                placeholder: previousSet.map { "\($0.reps)" } ?? "8",
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
                        onFocusChanged?(true, isLastSet)
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
            .accessibilityLabel("Reps")
            .accessibilityHint("Enter number of reps for set \(setNumber)")
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
                        AppLogger.debug("🔄 Set \(setNumber): Unchecked - stopping timer", category: .workout)
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
                    AppLogger.debug("🔥 Set \(setNumber): Initiating completion...", category: .workout)
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
                    AppLogger.debug("✅ Set \(setNumber) completed - Weight: \(setData.weight) (\(formatWeightPlaceholder(setData.weight))lbs) × \(setData.reps) reps", category: .workout)
                    AppLogger.debug("   Raw weightText: '\(weightText)' | Parsed: \(parseWeight(weightText) ?? -1)", category: .workout)
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
                .accessibilityLabel(setData.isCompleted ? "Set \(setNumber) completed" : "Mark set \(setNumber) complete")
                .accessibilityHint(setData.isCompleted ? "Tap to uncheck this set" : "Mark this set as done")
                .frame(width: 40)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Set \(setNumber)")
            
            // Timer countdown is now shown as a glow border on ExerciseCard
        }
        .onChange(of: activeTimerSetNumber) { _, newActiveSet in
            if newActiveSet == setNumber {
                AppLogger.debug("✅ Set \(setNumber): Confirmed as active timer", category: .workout)
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
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    guard !Task.isCancelled else { return }
                    isWeightFocused = true
                }
            }
        }
        .onChange(of: isWeightFocused) { _, isFocused in
            if isFocused { HapticManager.selectionChanged(); onFocusChanged?(true, isLastSet) }
        }
        .onChange(of: isRepsFocused) { _, isFocused in
            if isFocused { HapticManager.selectionChanged(); onFocusChanged?(true, isLastSet) }
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

    // PREVIOUS / SUGGESTED column label. Reads "70×8" for normal equipment
    // and "25ea. × 10" for dumbbell / kettlebell exercises — making it
    // clear that the historical / recommended value is per implement, not
    // total. The `× ` form (with spaces) reads as natural shorthand when
    // the "ea." marker is present; the tight `×` form stays as-is for
    // non-dumbbell rows to keep the column compact (user request
    // 2026-05-10).
    private func formattedPreviousSetLabel(weight: Double, reps: Int) -> String {
        let weightStr = formatWeightPlaceholder(weight)
        if isDumbbell && !isPerSideMode {
            return "\(weightStr)ea. × \(reps)"
        }
        return "\(weightStr)×\(reps)"
    }
    
    /// Parse weight text handling both period and comma as decimal separator
    private func parseWeight(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    /// VoiceOver-friendly weight-field label.
    ///
    /// The visible "each" caption under the field is decorative-hidden
    /// (`accessibilityHidden(true)`) so it doesn't double-read; the
    /// disambiguation lives here as part of the field's primary label.
    /// Bug 996ca300 — VoiceOver users must hear the per-dumbbell convention
    /// the same way sighted users see it.
    private var weightAccessibilityLabel: String {
        let unit = useKg ? "kilograms" : "pounds"
        if isDumbbell && !isPerSideMode {
            return "Weight per dumbbell in \(unit)"
        }
        return "Weight in \(unit)"
    }
}
