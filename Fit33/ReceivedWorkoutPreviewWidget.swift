import SwiftUI

// MARK: - Received Workout Preview Widget
/// Shows a preview of pending received workouts on the home screen
/// Styled to match GroupChallengeInviteWidget for unified notification carousel

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
            headerSection
            
            Divider().padding(.horizontal, Spacing.md)
            
            detailsSection
            
            if isExpanded {
                exerciseListSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Divider().padding(.horizontal, Spacing.md)
            
            actionButtonsSection
        }
        .background(staticCardBackground(accentColor: themeColor, secondaryColor: secondaryThemeColor))
        .shadow(color: themeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: themeColor.opacity(0.08), radius: 25, x: 0, y: 4)
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteWorkout() }
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
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                CachedFriendPhoto(
                    friendId: workout.senderId.uuidString,
                    photoUrl: workout.senderProfilePhotoUrl,
                    name: workout.senderName,
                    size: 48,
                    showGradientRing: true,
                    gradientColors: [themeColor, secondaryThemeColor]
                )
                if workout.viewedAt == nil {
                    PulsingRedDot(size: 10)
                        .offset(x: 2, y: -2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Received Workout")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themeColor)
                    
                    if workout.isPending && workout.viewedAt == nil {
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(themeColor))
                    }
                    
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
                
                HStack(spacing: 4) {
                    Text(workout.senderName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if workout.senderIsVerified == true || workout.senderIsGoldVerified == true {
                        VerifiedBadge(size: 13, isGold: workout.senderIsGoldVerified == true)
                    }
                }
                
                Text("sent you a workout")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "dumbbell.fill")
                .font(.ds_heading1)
                .foregroundColor(themeColor)
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Details Section
    
    private var detailsSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workoutName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill")
                            .font(.caption2)
                        Text("\(workout.exerciseCount) exercises")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("~\(estimatedMinutes)m")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if !topMuscleGroups.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(topMuscleGroups, id: \.self) { muscle in
                            Text(muscle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(themeColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().stroke(themeColor.opacity(0.4), lineWidth: 1).background(Capsule().fill(themeColor.opacity(0.1))))
                        }
                    }
                }
            }
            
            Spacer()
            
            Button {
                HapticManager.impact(.light)
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Exercise List Section
    
    private var exerciseListSection: some View {
        VStack(spacing: 2) {
            Divider().padding(.horizontal, Spacing.md)
            
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
                    
                    if workout.exerciseSets.indices.contains(index) {
                        let sets = workout.exerciseSets[index]
                        let reps = workout.exerciseReps.indices.contains(index) ? workout.exerciseReps[index] : "10"
                        Text("\(sets)×\(reps)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 3)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: saveForLater) {
                HStack(spacing: 4) {
                    if isSaving {
                        ProgressView().scaleEffect(0.7).tint(.secondary)
                    } else {
                        Image(systemName: "bookmark")
                            .font(.ds_labelMedium)
                    }
                    Text("Save")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.12))
                )
            }
            .disabled(isSaving || isDeleting)
            
            Button(action: {
                guard premiumManager.isPremiumUser else {
                    HapticManager.impact(.light)
                    showingPremiumUpgrade = true
                    return
                }
                HapticManager.impact(.heavy)
                onStart()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.ds_labelMedium)
                    Text("Start Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [themeColor, secondaryThemeColor], startPoint: .leading, endPoint: .trailing))
                )
            }
            .disabled(isSaving || isDeleting)
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Actions
    
    private func saveForLater() {
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
    
    private func normalizeMuscleGroup(_ muscle: String) -> String {
        let lowercased = muscle.lowercased()
        if lowercased.contains("pectoralis") || lowercased.contains("chest") { return "Chest" }
        else if lowercased.contains("bicep") || lowercased.contains("brachialis") { return "Biceps" }
        else if lowercased.contains("tricep") { return "Triceps" }
        else if lowercased.contains("deltoid") || lowercased.contains("delt") || lowercased.contains("shoulder") { return "Shoulders" }
        else if lowercased.contains("lat") || lowercased.contains("latissimus") { return "Lats" }
        else if lowercased.contains("rhomboid") || lowercased.contains("upper back") { return "Upper Back" }
        else if lowercased.contains("erector") || lowercased.contains("lower back") { return "Lower Back" }
        else if lowercased.contains("trap") { return "Traps" }
        else if lowercased.contains("quad") || lowercased.contains("vastus") { return "Quads" }
        else if lowercased.contains("hamstring") || lowercased.contains("biceps femoris") { return "Hamstrings" }
        else if lowercased.contains("glute") { return "Glutes" }
        else if lowercased.contains("calf") || lowercased.contains("gastrocnemius") || lowercased.contains("soleus") { return "Calves" }
        else if lowercased.contains("rectus abdominis") || lowercased.contains("abs") { return "Abs" }
        else if lowercased.contains("oblique") { return "Obliques" }
        else if lowercased.contains("forearm") || lowercased.contains("wrist") { return "Forearms" }
        else if lowercased.contains("core") || lowercased.contains("abdominal") { return "Core" }
        return muscle.prefix(1).uppercased() + muscle.dropFirst().lowercased()
    }
    
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

// MARK: - Static Card Background (shared pattern for all notification cards)

struct StaticCardBackground: View {
    let accentColor: Color
    let secondaryColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xl + 4)
                .fill(accentColor.opacity(colorScheme == .dark ? 0.08 : 0.04))
                .offset(y: 5)
                .blur(radius: 3)
            
            RoundedRectangle(cornerRadius: CornerRadius.xl + 2)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04))
                .offset(y: 3)
            
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.15), Color(white: 0.11)]
                            : [Color.white, Color(white: 0.98)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2),
                            secondaryColor.opacity(colorScheme == .dark ? 0.15 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

func staticCardBackground(accentColor: Color, secondaryColor: Color) -> some View {
    StaticCardBackground(accentColor: accentColor, secondaryColor: secondaryColor)
}

// MARK: - Container (kept for backward compat, carousel replaces this on dashboard)

struct ReceivedWorkoutPreviewContainer: View {
    @ObservedObject private var friendService = FriendService.shared
    
    @State private var selectedWorkout: ReceivedWorkoutDTO?
    @State private var navigateToDetail = false
    @State private var selectedPage: Int = 0
    
    private var pendingWorkouts: [ReceivedWorkoutDTO] {
        friendService.receivedWorkouts.filter { $0.isPending }
    }
    
    var body: some View {
        ZStack {
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
            
            if !pendingWorkouts.isEmpty {
                let workouts = Array(pendingWorkouts.prefix(3))
                let safeIndex = min(max(0, selectedPage), workouts.count - 1)
                
                VStack(spacing: 4) {
                    if workouts.count > 1 {
                        ZStack {
                            ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                                if safeIndex == index {
                                    ReceivedWorkoutPreviewWidget(
                                        workout: workout,
                                        onStart: {
                                            selectedWorkout = workout
                                            navigateToDetail = true
                                            Task {
                                                try? await Task.sleep(nanoseconds: 200_000_000)
                                                await friendService.markWorkoutStarted(workoutId: workout.id)
                                            }
                                        },
                                        onDismiss: {
                                            if selectedPage >= workouts.count - 1 {
                                                selectedPage = max(0, selectedPage - 1)
                                            }
                                        }
                                    )
                                    .transition(.opacity)
                                }
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: safeIndex)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 25)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && selectedPage < workouts.count - 1 {
                                            selectedPage += 1
                                        } else if horizontalAmount > 0 && selectedPage > 0 {
                                            selectedPage -= 1
                                        }
                                    }
                                }
                        )
                        
                        HStack(spacing: 6) {
                            ForEach(0..<workouts.count, id: \.self) { index in
                                Capsule()
                                    .fill(safeIndex == index ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: safeIndex == index ? 20 : 8, height: 6)
                                    .animation(.easeOut(duration: 0.2), value: safeIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        selectedPage = index
                                    }
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    } else {
                        ReceivedWorkoutPreviewWidget(
                            workout: workouts[0],
                            onStart: {
                                selectedWorkout = workouts[0]
                                navigateToDetail = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 200_000_000)
                                    await friendService.markWorkoutStarted(workoutId: workouts[0].id)
                                }
                            },
                            onDismiss: {}
                        )
                    }
                }
                .onChange(of: pendingWorkouts.count) { _, _ in
                    selectedPage = 0
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
