import SwiftUI
import CoreData

// MARK: - Send Workout To Friend View
//
// "Create a workout and send it to a friend." Tab-shell-aligned redesign of
// the legacy `CreateWorkoutForFriendView` (extracted out of `FriendProfileView.swift`):
//   • `AnimatedOrbBackground.friends` shell + cyan/blue social gradient.
//   • All typography / spacing / corner radii sourced from design tokens.
//   • Exercise picker is a `NavigationLink` push of `CustomWorkoutBuilderView`
//     in `.pickMultiple` mode — same poster-ring cards, recommended filter,
//     suggested-swaps, search, and overdue-muscle nudge as the workout-tab
//     build flow. (See `PRODUCT_ENGINEER_AGENT.md` invariant 24c.)
//   • Inline expandable per-exercise config (sets / reps / rest / notes).
//   • Final commit goes through `SharedWorkoutPreviewView` → `FriendService.sendWorkout`.
//
// Rage-shake screen tracking via `SessionLogManager.Screen.sendWorkoutToFriend`
// + `ScreenCodeMap` entry for `"send workout to friend"`. See
// `swiftui-rules.mdc` → "Rage-shake screen tracking".

// MARK: - Per-Exercise Configuration

struct ExerciseConfig {
    var sets: Int = 3
    var reps: String = "8-12"
    var restSeconds: Int? = 90
    var notes: String? = nil
}

// MARK: - Create Workout For Friend View

struct CreateWorkoutForFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    let friend: Friend
    
    @State private var workoutName = ""
    @State private var personalMessage = ""
    @State private var selectedExercises: [Exercise] = []
    @State private var exerciseConfigs: [UUID: ExerciseConfig] = [:]
    @State private var estimatedDuration: Int = 45
    @State private var difficulty: String = "Custom"
    
    @State private var showingPreview = false
    @State private var isMessageExpanded = false
    @FocusState private var nameFieldFocused: Bool
    
    private var canSend: Bool {
        !workoutName.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectedExercises.isEmpty
    }
    
    private var firstName: String {
        friend.friendName?.components(separatedBy: " ").first ?? friend.displayName
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        recipientHeader
                        workoutDetailsCard
                        exercisesSection
                        personalMessageCard
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, 120) // breathing room above the bottom dock
                }
                
                VStack(spacing: 0) {
                    Spacer()
                    bottomDock
                }
            }
            .navigationTitle("Send Workout")
            .navigationBarTitleDisplayMode(.inline)
            .adaptiveToolbarBackground()
            .trackScreen(.sendWorkoutToFriend, metadata: [
                "friend_id": friend.friendId.uuidString
            ])
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticManager.selectionChanged()
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Discard workout and close")
                }
            }
            .navigationDestination(isPresented: $showingPreview) {
                SharedWorkoutPreviewView(
                    friend: friend,
                    workoutName: workoutName,
                    workoutDescription: "",
                    exercises: buildSelectedExercises(),
                    message: personalMessage,
                    onSent: {
                        // Hop out of the entire flow once the send succeeds.
                        dismiss()
                    }
                )
            }
        }
    }
    
    // MARK: - Recipient Header
    
    private var recipientHeader: some View {
        HStack(spacing: Spacing.sm) {
            CachedFriendPhoto(
                friendId: friend.friendId.uuidString,
                photoUrl: friend.profilePhotoUrl,
                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                size: 52,
                showGradientRing: true,
                gradientColors: [.cyan, .blue]
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Sending to")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(friend.displayName)
                    .font(.ds_heading3)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: Spacing.xs)
            
            Image(systemName: "paperplane.fill")
                .font(.ds_heading3)
                .foregroundStyle(LinearGradient.ds_socialAccent)
        }
        .padding(Spacing.md)
        .adaptiveSleekCard(cornerRadius: CornerRadius.lg, accentColor: .cyan)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sending workout to \(friend.displayName)")
    }
    
    // MARK: - Workout Details Card (name + duration + difficulty)
    
    private var workoutDetailsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Workout Name")
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            TextField("e.g. Push Day Burner", text: $workoutName)
                .focused($nameFieldFocused)
                .font(.ds_bodyLarge)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(Color.cardBackgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .stroke(
                            nameFieldFocused
                                ? Color.blue.opacity(0.45)
                                : Color.adaptiveDivider.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .accessibilityLabel("Workout name")
            
            HStack(spacing: Spacing.sm) {
                metadataPill(
                    icon: "clock.fill",
                    iconColor: .blue,
                    label: "Duration"
                ) {
                    Picker("Duration", selection: $estimatedDuration) {
                        ForEach([15, 30, 45, 60, 75, 90], id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                    .labelsHidden()
                }
                
                metadataPill(
                    icon: "flame.fill",
                    iconColor: .orange,
                    label: "Difficulty"
                ) {
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Beginner").tag("Beginner")
                        Text("Intermediate").tag("Intermediate")
                        Text("Advanced").tag("Advanced")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                    .labelsHidden()
                }
            }
        }
        .padding(Spacing.md)
        .adaptiveSleekCard(cornerRadius: CornerRadius.lg)
    }
    
    private func metadataPill<Content: View>(
        icon: String,
        iconColor: Color,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.ds_labelMedium)
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                content()
                    .font(.ds_labelMedium)
                    .foregroundColor(.primary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(Color.cardBackgroundSecondary)
        )
    }
    
    // MARK: - Exercises Section
    
    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(title: "Exercises", icon: "dumbbell.fill", iconColor: .cyan)
                Spacer(minLength: Spacing.xs)
                if !selectedExercises.isEmpty {
                    Text("\(selectedExercises.count)")
                        .font(.ds_labelSmall)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.ds_socialAccent))
                        .accessibilityLabel("\(selectedExercises.count) exercises selected")
                }
            }
            
            if selectedExercises.isEmpty {
                emptyExercisesCard
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(selectedExercises, id: \.objectID) { exercise in
                        SendWorkoutExerciseRow(
                            exercise: exercise,
                            config: configBinding(for: exercise),
                            onRemove: { removeExercise(exercise) }
                        )
                    }
                }
                
                addExercisesPill
            }
        }
    }
    
    private var emptyExercisesCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "dumbbell")
                .font(.ds_heading1)
                .foregroundStyle(LinearGradient.ds_socialAccent)
                .accessibilityHidden(true)
            
            Text("No exercises yet")
                .font(.ds_heading3)
                .foregroundColor(.primary)
            
            Text("Pick from your library to build the workout")
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)
            
            addExercisesPill
                .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.md)
        .adaptiveSleekCard(cornerRadius: CornerRadius.lg)
    }
    
    private var addExercisesPill: some View {
        NavigationLink {
            CustomWorkoutBuilderView(
                initialSelection: selectedExercises,
                onConfirm: { picked in
                    applyPickedExercises(picked)
                }
            )
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.ds_bodyMedium)
                Text(selectedExercises.isEmpty ? "Add Exercises" : "Edit Exercises")
                    .font(.ds_labelMedium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(LinearGradient.ds_socialAccent))
        }
        // `scaleButtonStyle(_:)` is declared only on `Button`; NavigationLink
        // needs the underlying `.buttonStyle(...)` directly.
        .buttonStyle(UniversalScaleButtonStyle(scale: .subtle))
        .accessibilityLabel(selectedExercises.isEmpty ? "Add exercises" : "Edit exercises")
        .accessibilityHint("Open the exercise library to pick exercises")
    }
    
    // MARK: - Personal Message
    
    private var personalMessageCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                HapticManager.selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isMessageExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.ds_labelLarge)
                        .foregroundStyle(LinearGradient.ds_socialAccent)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add a Note")
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                        Text(personalMessage.isEmpty
                             ? "Optional note to \(firstName)"
                             : personalMessage)
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: Spacing.xs)
                    
                    Image(systemName: isMessageExpanded ? "chevron.up" : "chevron.down")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a note")
            .accessibilityHint("Optional message that goes to \(firstName)")
            
            if isMessageExpanded {
                TextField(
                    "Try this — it's been crushing me lately 💪",
                    text: $personalMessage,
                    axis: .vertical
                )
                .lineLimit(3...5)
                .font(.ds_bodyMedium)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(Color.cardBackgroundSecondary)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Personal message")
            }
        }
        .padding(Spacing.md)
        .adaptiveSleekCard(cornerRadius: CornerRadius.lg)
    }
    
    // MARK: - Bottom Dock
    
    private var bottomDock: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedExercises.isEmpty
                     ? "Add exercises to continue"
                     : "\(selectedExercises.count) \(selectedExercises.count == 1 ? "exercise" : "exercises")")
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)
                Text("~\(estimatedDuration) min · \(difficulty)")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: Spacing.xs)
            
            Button(action: {
                HapticManager.impact(.medium)
                showingPreview = true
            }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "paperplane.fill")
                        .font(.ds_labelMedium)
                    Text("Preview & Send")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    Capsule()
                        .fill(canSend
                              ? LinearGradient.ds_socialAccent
                              : LinearGradient(
                                  colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                                  startPoint: .leading,
                                  endPoint: .trailing
                              ))
                )
            }
            .scaleButtonStyle(.standard)
            .disabled(!canSend)
            .accessibilityLabel("Preview and send")
            .accessibilityHint(canSend
                               ? "Open the final review before sending"
                               : "Add a name and at least one exercise first")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            // Subtle elevated dock so the orb doesn't bleed into action area.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.adaptiveDivider.opacity(0.4)),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: - Helpers
    
    private func configBinding(for exercise: Exercise) -> Binding<ExerciseConfig> {
        let key = exercise.id ?? UUID()
        return Binding(
            get: { exerciseConfigs[key] ?? ExerciseConfig() },
            set: { exerciseConfigs[key] = $0 }
        )
    }
    
    private func removeExercise(_ exercise: Exercise) {
        HapticManager.selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            selectedExercises.removeAll { $0.objectID == exercise.objectID }
        }
        if let id = exercise.id {
            exerciseConfigs.removeValue(forKey: id)
        }
    }
    
    /// Apply the multi-select picker's confirmed list. We preserve any existing
    /// per-exercise configs (sets/reps/notes) for exercises the user kept,
    /// drop configs for exercises they removed, and leave new picks at the
    /// `ExerciseConfig` defaults.
    private func applyPickedExercises(_ picked: [Exercise]) {
        let pickedIds = Set(picked.compactMap { $0.id })
        for staleKey in exerciseConfigs.keys where !pickedIds.contains(staleKey) {
            exerciseConfigs.removeValue(forKey: staleKey)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedExercises = picked
        }
    }
    
    private func buildSelectedExercises() -> [SelectedExerciseForFriend] {
        selectedExercises.map { exercise in
            let config = exerciseConfigs[exercise.id ?? UUID()] ?? ExerciseConfig()
            return SelectedExerciseForFriend(
                exerciseId: exercise.id?.uuidString,
                name: exercise.name ?? "Unknown",
                category: exercise.category,
                sets: config.sets,
                reps: config.reps,
                restSeconds: config.restSeconds ?? 90,
                notes: config.notes ?? ""
            )
        }
    }
}

// MARK: - Send Workout Exercise Row
//
// Recycles the canonical `ExercisePosterRingIcon` — same character-clip still
// the build flow shows in `ExerciseCardRow`. Tap-expand reveals sets / reps /
// rest / notes editors so the row stays compact when collapsed.

private struct SendWorkoutExerciseRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let exercise: Exercise
    @Binding var config: ExerciseConfig
    let onRemove: () -> Void
    
    @State private var isExpanded = false
    
    private var categoryGradient: [Color] {
        switch exercise.category?.lowercased() {
        case "chest": return [.purple, .pink]
        case "back": return [.blue, .cyan]
        case "legs": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "arms": return [.purple, .indigo]
        case "core": return [.yellow, .orange]
        case "full body": return [.pink, .red]
        default: return [.gray, Color.gray.opacity(0.7)]
        }
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            collapsedRow
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticManager.selectionChanged()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                }
            
            if isExpanded {
                Divider()
                    .padding(.horizontal, Spacing.sm)
                expandedConfig
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(exercise.displayName), \(config.sets) sets of \(config.reps) reps")
        .accessibilityHint(isExpanded ? "Collapse details" : "Expand to edit sets and reps")
    }
    
    private var collapsedRow: some View {
        HStack(spacing: Spacing.sm) {
            ExercisePosterRingIcon(
                exerciseName: exercise.displayName,
                gradientColors: categoryGradient,
                fallbackSymbol: "figure.strengthtraining.traditional",
                isCoreCategory: exercise.category?.lowercased() == "core",
                size: 48,
                ringWidth: 2
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.ds_bodyLarge)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                HStack(spacing: Spacing.xs) {
                    if let category = exercise.category {
                        Text(category)
                            .font(.ds_bodySmall)
                            .fontWeight(.medium)
                            .foregroundColor(categoryColor)
                    }
                    Text("·")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    Text("\(config.sets) × \(config.reps)")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: Spacing.xs)
            
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.ds_bodyRegular)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(exercise.displayName)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    private var expandedConfig: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                configField(label: "Sets") {
                    Stepper(value: $config.sets, in: 1...10) {
                        Text("\(config.sets)")
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                            .monospacedDigit()
                    }
                    .labelsHidden()
                }
                
                configField(label: "Reps") {
                    TextField("8-12", text: $config.reps)
                        .font(.ds_bodyMedium)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .fill(Color.cardBackgroundSecondary)
                        )
                }
                
                configField(label: "Rest (s)") {
                    TextField(
                        "90",
                        value: Binding(
                            get: { config.restSeconds ?? 90 },
                            set: { config.restSeconds = $0 }
                        ),
                        format: .number
                    )
                    .keyboardType(.numberPad)
                    .font(.ds_bodyMedium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                            .fill(Color.cardBackgroundSecondary)
                    )
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                TextField(
                    "Optional cue (form, tempo…)",
                    text: Binding(
                        get: { config.notes ?? "" },
                        set: { config.notes = $0.isEmpty ? nil : $0 }
                    )
                )
                .font(.ds_bodyMedium)
                .padding(Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(Color.cardBackgroundSecondary)
                )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .padding(.top, Spacing.xs)
    }
    
    private func configField<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    CreateWorkoutForFriendView(
        friend: Friend(
            friendshipId: UUID(),
            friendId: UUID(),
            friendName: "Manuel Test",
            friendEmail: "manuel@example.com",
            friendUsername: "manuel",
            fitnessGoal: nil,
            experienceLevel: nil,
            profilePhotoUrl: nil,
            friendsSince: Date(),
            totalWorkoutsShared: 0,
            isVerified: false,
            isGoldVerified: false
        )
    )
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    .environmentObject(UserManager())
}
