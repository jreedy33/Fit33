import SwiftUI

// MARK: - Received Workout Preview Widget
/// Shows a preview of pending received workouts on the home screen
/// Appears above the program widget until user addresses it (start/save/delete)

struct ReceivedWorkoutPreviewWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var premiumManager = PremiumManager.shared
    
    let workout: ReceivedWorkoutDTO
    let onStart: () -> Void
    let onDismiss: () -> Void
    
    @State private var isExpanded = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPremiumUpgrade = false
    @State private var isSaving = false
    @State private var isDeleting = false
    
    // Theme colors (matching ReceivedWorkoutDetailView)
    private let themeColor: Color = .blue
    private let secondaryThemeColor: Color = .purple
    
    private var totalSets: Int {
        workout.exerciseSets.reduce(0, +)
    }
    
    private var estimatedMinutes: Int {
        workout.estimatedDuration ?? max(15, totalSets * 3)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            VStack(spacing: 0) {
                // Header - Sender info
                headerSection
                
                Divider()
                    .padding(.horizontal, Spacing.md)
                
                // Workout preview section
                workoutPreviewSection
                
                // Expandable exercises section
                if isExpanded {
                    Divider()
                        .padding(.horizontal, Spacing.md)
                    
                    exerciseListSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Divider()
                    .padding(.horizontal, Spacing.md)
                
                // Action buttons
                actionButtonsSection
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.cardBackground)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: widgetBorderColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the workout from your inbox.")
        }
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .savedWorkouts)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 10) {
            // Sender avatar
            senderAvatarView
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(workout.senderName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("sent you a workout")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // NEW badge
                    if workout.isPending && workout.viewedAt == nil {
                        Text("NEW")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(themeColor))
                    }
                    
                    // PRO badge for free users
                    if !premiumManager.isPremiumUser {
                        HStack(spacing: 2) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 7))
                            Text("PRO")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.black.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.75, blue: 0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                    }
                }
                
                Text(formatSmartDate(workout.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
            
            // Delete button
            Button(action: {
                HapticManager.impact(.light)
                showingDeleteConfirmation = true
            }) {
                Image(systemName: "xmark")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .disabled(isDeleting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Sender Avatar View
    
    private var senderAvatarView: some View {
        ZStack(alignment: .topTrailing) {
            CachedFriendPhoto(
                friendId: workout.senderId.uuidString,
                photoUrl: workout.senderProfilePhotoUrl,
                name: workout.senderName,
                size: 36,
                showGradientRing: true,
                gradientColors: [themeColor, secondaryThemeColor]
            )
            
            // Pulsing red dot for unviewed workouts
            if workout.viewedAt == nil {
                PulsingRedDot(size: 10)
                    .offset(x: 2, y: -2)
            }
        }
    }
    
    // MARK: - Workout Preview Section
    
    /// Calculate top muscle groups from exercises (max 3)
    private var topMuscleGroups: [String] {
        var muscleCount: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0

        for exerciseName in workout.exerciseNames {
            if let exercise = ExerciseLibraryService.shared.getExercise(byName: exerciseName),
               let muscles = exercise.muscleGroups as? [String] {
                for muscle in muscles {
                    let key = normalizeMuscleGroup(muscle)
                    muscleCount[key, default: 0] += 1
                    if firstSeen[key] == nil {
                        firstSeen[key] = order
                        order += 1
                    }
                }
            }
        }

        let sorted = muscleCount.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return (firstSeen[$0.key] ?? 0) < (firstSeen[$1.key] ?? 0)
        }
        return Array(sorted.prefix(3).map { $0.key })
    }
    
    /// Normalize muscle group names to user-friendly format
    private func normalizeMuscleGroup(_ muscle: String) -> String {
        let lowercased = muscle.lowercased()
        
        // Map specific muscle groups to common display names
        if lowercased.contains("pectoralis") || lowercased.contains("chest") {
            return "Chest"
        } else if lowercased.contains("bicep") || lowercased.contains("brachialis") {
            return "Biceps"
        } else if lowercased.contains("tricep") {
            return "Triceps"
        } else if lowercased.contains("deltoid") || lowercased.contains("delt") || lowercased.contains("shoulder") {
            return "Shoulders"
        } else if lowercased.contains("lat") || lowercased.contains("latissimus") {
            return "Lats"
        } else if lowercased.contains("rhomboid") || lowercased.contains("upper back") {
            return "Upper Back"
        } else if lowercased.contains("erector") || lowercased.contains("lower back") {
            return "Lower Back"
        } else if lowercased.contains("trap") {
            return "Traps"
        } else if lowercased.contains("quad") || lowercased.contains("vastus") {
            return "Quads"
        } else if lowercased.contains("hamstring") || lowercased.contains("biceps femoris") {
            return "Hamstrings"
        } else if lowercased.contains("glute") {
            return "Glutes"
        } else if lowercased.contains("calf") || lowercased.contains("gastrocnemius") || lowercased.contains("soleus") {
            return "Calves"
        } else if lowercased.contains("rectus abdominis") || lowercased.contains("abs") {
            return "Abs"
        } else if lowercased.contains("oblique") {
            return "Obliques"
        } else if lowercased.contains("forearm") || lowercased.contains("wrist") {
            return "Forearms"
        } else if lowercased.contains("core") || lowercased.contains("abdominal") {
            return "Core"
        }
        
        // Capitalize first letter for display
        return muscle.prefix(1).uppercased() + muscle.dropFirst().lowercased()
    }
    
    /// Cohesive color scheme - all badges use the same accent color
    private var muscleAccentColor: Color {
        themeColor // Use consistent blue theme color for all badges
    }
    
    /// Border colors for the widget - cohesive blue/purple gradient
    private var widgetBorderColors: [Color] {
        [themeColor.opacity(0.7), secondaryThemeColor.opacity(0.5)]
    }
    
    private var workoutPreviewSection: some View {
        VStack(spacing: 8) {
            // Workout title row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Description if available (takes priority over message)
                    if let description = workout.workoutDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    // Message preview if available (and no description)
                    else if let message = workout.message, !message.isEmpty {
                        Text("\"\(message)\"")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                            .lineLimit(1)
                    }
                    
                    // Muscle group badges (max 3) - cohesive color scheme
                    if !topMuscleGroups.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(topMuscleGroups, id: \.self) { muscle in
                                Text(muscle)
                                    .font(.ds_caption)
                                    .foregroundColor(muscleAccentColor)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .stroke(muscleAccentColor.opacity(0.4), lineWidth: 1)
                                            .background(
                                                Capsule()
                                                    .fill(muscleAccentColor.opacity(0.1))
                                            )
                                    )
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    // Compact stats inline
                    HStack(spacing: 12) {
                        Label("\(workout.exerciseCount)", systemImage: "dumbbell.fill")
                        Label("\(estimatedMinutes)m", systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    // Expand/collapse chevron
                    Button(action: {
                        HapticManager.impact(.light)
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.ds_labelMedium)
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
    }
    
    // MARK: - Exercise List Section
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(spacing: 2) {
                ForEach(Array(workout.exerciseNames.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Sets x Reps
                        if workout.exerciseSets.indices.contains(index) {
                            let sets = workout.exerciseSets[index]
                            let reps = workout.exerciseReps.indices.contains(index) ? workout.exerciseReps[index] : "10"
                            Text("\(sets)×\(reps)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xxs)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 10) {
            // Save for Later button
            Button(action: saveForLater) {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.primary)
                    } else {
                        Image(systemName: "bookmark")
                            .font(.ds_labelMedium)
                    }
                    Text("Save")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            .disabled(isSaving || isDeleting)
            
            // Start button
            Button(action: {
                // Check if user is premium - free users must upgrade to start received workouts
                guard premiumManager.isPremiumUser else {
                    HapticManager.impact(.light)
                    showingPremiumUpgrade = true
                    return
                }
                
                HapticManager.impact(.heavy)
                onStart()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.ds_caption)
                    Text("Start")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [themeColor, secondaryThemeColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(isSaving || isDeleting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Actions
    
    private func saveForLater() {
        // Free users CAN save workouts - premium check is when starting saved workouts
        HapticManager.impact(.medium)
        isSaving = true
        
        Task {
            do {
                try await friendService.saveSharedWorkout(workoutId: workout.id)
                HapticManager.notification(.success)
                onDismiss()
            } catch {
                AppLogger.error("❌ Error saving workout: \(error)", category: .workout)
                HapticManager.notification(.error)
            }
            isSaving = false
        }
    }
    
    private func deleteWorkout() {
        HapticManager.impact(.medium)
        isDeleting = true
        
        Task {
            let success = await friendService.deleteReceivedWorkout(workoutId: workout.id)
            if success {
                HapticManager.notification(.success)
                onDismiss()
            } else {
                HapticManager.notification(.error)
            }
            isDeleting = false
        }
    }
    
    // MARK: - Helpers
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today at \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Container View for Multiple Pending Workouts
/// Shows the most recent pending workout, with ability to show more

struct ReceivedWorkoutPreviewContainer: View {
    @ObservedObject private var friendService = FriendService.shared
    
    @State private var selectedWorkout: ReceivedWorkoutDTO?
    @State private var navigateToDetail = false
    
    // Filter for pending workouts only (not saved or completed)
    private var pendingWorkouts: [ReceivedWorkoutDTO] {
        friendService.receivedWorkouts.filter { $0.isPending }
    }
    
    var body: some View {
        // CRITICAL: NavigationLink must be at root level, outside any conditional
        // This ensures it persists even when pendingWorkouts changes
        ZStack {
            // Hidden navigation link - ALWAYS present at root level
            NavigationLink(
                destination: Group {
                    if let workout = selectedWorkout {
                        ReceivedWorkoutDetailView(workout: workout)
                    }
                },
                isActive: $navigateToDetail
            ) {
                EmptyView()
            }
            .hidden()
            
            // Visible content - only shows when there are pending workouts
            if let firstPending = pendingWorkouts.first {
                VStack(spacing: 12) {
                    ReceivedWorkoutPreviewWidget(
                        workout: firstPending,
                        onStart: {
                            // CRITICAL: Set navigation state FIRST, THEN mark as started
                            // Store workout reference before any async operations
                            selectedWorkout = firstPending
                            
                            // Trigger navigation immediately
                            navigateToDetail = true
                            
                            // Mark as started with a delay so navigation happens first
                            Task {
                                // Wait for navigation animation to begin
                                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                                await friendService.markWorkoutStarted(workoutId: firstPending.id)
                            }
                        },
                        onDismiss: {
                            // Widget will auto-refresh via FriendService
                        }
                    )
                    
                    // If there are more pending workouts, show count
                    if pendingWorkouts.count > 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.full.fill")
                                .font(.ds_bodySmall)
                                .foregroundColor(.secondary)
                            Text("\(pendingWorkouts.count - 1) more workout\(pendingWorkouts.count > 2 ? "s" : "") waiting")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

#Preview {
    ReceivedWorkoutPreviewContainer()
        .padding()
        .environmentObject(WorkoutManager.shared)
        .environmentObject(UserManager())
}
