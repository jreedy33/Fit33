import SwiftUI

// MARK: - Friend Profile View
/// Shows a friend's profile with option to create and send workouts
struct FriendProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var friendService = FriendService.shared
    
    let friend: FriendDTO
    
    @State private var showingCreateWorkout = false
    @State private var showingUnfriendConfirmation = false
    @State private var isUnfriending = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.92, green: 0.95, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Header
                        profileHeader
                        
                        // Stats
                        statsSection
                        
                        // Create Workout Button
                        createWorkoutButton
                        
                        // Shared Workouts History
                        sharedHistorySection
                        
                        // Unfriend Button
                        unfriendButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreateWorkout) {
                CreateWorkoutForFriendView(friend: friend)
            }
            .alert("Unfriend \(friend.displayName)?", isPresented: $showingUnfriendConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Unfriend", role: .destructive) {
                    unfriend()
                }
            } message: {
                Text("You will no longer be able to share workouts with each other.")
            }
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Large Avatar
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                    .blur(radius: 20)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Text(friend.initials)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Name
            Text(friend.displayName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Friends since
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Friends since \(formatDate(friend.friendsSince))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        HStack(spacing: 12) {
            // Fitness Goal
            VStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text(friend.fitnessGoal ?? "Not set")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("Goal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
            )
            
            // Experience Level
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text(friend.experienceLevel ?? "Not set")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("Level")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
            )
            
            // Workouts Shared
            VStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text("\(friend.workoutsShared)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Shared")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
            )
        }
    }
    
    // MARK: - Create Workout Button
    
    private var createWorkoutButton: some View {
        Button(action: { showingCreateWorkout = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create Workout for \(friend.name?.components(separatedBy: " ").first ?? "Friend")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Build and send a custom workout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Shared History Section
    
    private var sharedHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.secondary)
                Text("Shared History")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 4)
            
            if friend.workoutsShared == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No workouts shared yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Create a workout to get started!")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
            } else {
                // Show recent shared workouts
                VStack(spacing: 0) {
                    ForEach(recentSharedWorkouts) { workout in
                        SharedWorkoutHistoryRow(workout: workout)
                        
                        if workout.id != recentSharedWorkouts.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
            }
        }
    }
    
    private var recentSharedWorkouts: [SentWorkout] {
        friendService.sentWorkouts.filter { $0.toUserId == friend.friendId }
    }
    
    // MARK: - Unfriend Button
    
    private var unfriendButton: some View {
        Button(action: { showingUnfriendConfirmation = true }) {
            HStack {
                if isUnfriending {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "person.badge.minus")
                    Text("Unfriend")
                }
            }
            .font(.subheadline)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .disabled(isUnfriending)
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func unfriend() {
        isUnfriending = true
        Task {
            let success = await friendService.removeFriend(friendshipId: friend.friendshipId)
            if success {
                dismiss()
            }
            isUnfriending = false
        }
    }
}

// MARK: - Shared Workout History Row

struct SharedWorkoutHistoryRow: View {
    let workout: SentWorkout
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.statusIcon)
                .font(.system(size: 18))
                .foregroundColor(workout.statusColor)
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(formatDate(workout.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(workout.status.capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(workout.statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(workout.statusColor.opacity(0.15))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Create Workout For Friend View

struct CreateWorkoutForFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    let friend: Friend
    
    @State private var workoutName = ""
    @State private var workoutDescription = ""
    @State private var personalMessage = ""
    @State private var selectedExercises: [Exercise] = []
    @State private var exerciseConfigs: [UUID: ExerciseConfig] = [:]
    @State private var estimatedDuration: Int = 45
    @State private var difficulty: String = "Custom"
    
    @State private var showingExercisePicker = false
    @State private var showingPreview = false
    @State private var isSending = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.92, green: 0.95, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Recipient Header
                        recipientHeader
                        
                        // Workout Details
                        workoutDetailsSection
                        
                        // Exercise List
                        exerciseListSection
                        
                        // Personal Message
                        personalMessageSection
                        
                        // Duration & Difficulty
                        metadataSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
                
                // Bottom Bar
                VStack {
                    Spacer()
                    bottomBar
                }
            }
            .navigationTitle("Create Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(selectedExercises: $selectedExercises)
            }
            .sheet(isPresented: $showingPreview) {
                SharedWorkoutPreviewView(
                    friend: friend,
                    workoutName: workoutName,
                    description: workoutDescription,
                    message: personalMessage,
                    exercises: buildSharedExercises(),
                    duration: estimatedDuration,
                    difficulty: difficulty,
                    onSend: sendWorkout
                )
            }
        }
    }
    
    // MARK: - Recipient Header
    
    private var recipientHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Text(friend.initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Creating for")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(friend.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Image(systemName: "paperplane.fill")
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Workout Details Section
    
    private var workoutDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Details")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.leading, 4)
            
            VStack(spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., Full Body Blast", text: $workoutName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                }
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (Optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("What's this workout about?", text: $workoutDescription, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .lineLimit(2...4)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
            )
        }
    }
    
    // MARK: - Exercise List Section
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingExercisePicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 4)
            
            if selectedExercises.isEmpty {
                emptyExercisesView
            } else {
                VStack(spacing: 0) {
                    ForEach(selectedExercises, id: \.objectID) { exercise in
                        ExerciseConfigRow(
                            exercise: exercise,
                            config: binding(for: exercise),
                            onRemove: { removeExercise(exercise) }
                        )
                        
                        if exercise.objectID != selectedExercises.last?.objectID {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
            }
        }
    }
    
    private var emptyExercisesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No exercises added")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: { showingExercisePicker = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercises")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
        )
    }
    
    // MARK: - Personal Message Section
    
    private var personalMessageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Message")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.leading, 4)
            
            VStack(spacing: 8) {
                Text("Optional note for \(friend.friendName?.components(separatedBy: " ").first ?? "your friend")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                TextEditor(text: $personalMessage)
                    .frame(height: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                    )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
            )
        }
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                    
                    Picker("Duration", selection: $estimatedDuration) {
                        ForEach([15, 30, 45, 60, 75, 90], id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
            )
            
            // Difficulty
            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "flame")
                        .foregroundColor(.orange)
                    
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Beginner").tag("Beginner")
                        Text("Intermediate").tag("Intermediate")
                        Text("Advanced").tag("Advanced")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
            )
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Exercise count
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedExercises.count) exercises")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("~\(estimatedDuration) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Preview Button
            Button(action: { showingPreview = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                    Text("Preview & Send")
                }
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: canSend ? [.blue, .purple] : [.gray, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }
    
    // MARK: - Helpers
    
    private var canSend: Bool {
        !workoutName.isEmpty && !selectedExercises.isEmpty
    }
    
    private func binding(for exercise: Exercise) -> Binding<ExerciseConfig> {
        Binding(
            get: {
                exerciseConfigs[exercise.id ?? UUID()] ?? ExerciseConfig()
            },
            set: { newValue in
                exerciseConfigs[exercise.id ?? UUID()] = newValue
            }
        )
    }
    
    private func removeExercise(_ exercise: Exercise) {
        selectedExercises.removeAll { $0.objectID == exercise.objectID }
        if let id = exercise.id {
            exerciseConfigs.removeValue(forKey: id)
        }
    }
    
    private func buildSharedExercises() -> [SharedExercise] {
        selectedExercises.map { exercise in
            let config = exerciseConfigs[exercise.id ?? UUID()] ?? ExerciseConfig()
            return SharedExercise(
                name: exercise.name ?? "Unknown",
                sets: config.sets,
                reps: config.reps,
                restSeconds: config.restSeconds,
                notes: config.notes
            )
        }
    }
    
    private func sendWorkout() {
        dismiss()
    }
}

// MARK: - Exercise Config

struct ExerciseConfig {
    var sets: Int = 3
    var reps: String = "8-12"
    var restSeconds: Int? = 90
    var notes: String? = nil
}

// MARK: - Exercise Config Row

struct ExerciseConfigRow: View {
    let exercise: Exercise
    @Binding var config: ExerciseConfig
    let onRemove: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("\(config.sets) sets × \(config.reps) reps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Expand button
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            // Expanded config
            if isExpanded {
                VStack(spacing: 16) {
                    Divider()
                    
                    HStack(spacing: 16) {
                        // Sets
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Stepper("\(config.sets)", value: $config.sets, in: 1...10)
                                .labelsHidden()
                        }
                        
                        // Reps
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("8-12", text: $config.reps)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                        }
                        
                        // Rest
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rest (sec)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("90", value: $config.restSeconds, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 60)
                        }
                    }
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Optional instructions...", text: Binding(
                            get: { config.notes ?? "" },
                            set: { config.notes = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Exercise Picker View

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var selectedExercises: [Exercise]
    
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var localSelection: Set<NSManagedObjectID> = []
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)],
        animation: .default)
    private var allExercises: FetchedResults<Exercise>
    
    private let categories = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    private var filteredExercises: [Exercise] {
        var exercises = Array(allExercises)
        
        if selectedCategory != "All" {
            exercises = exercises.filter { $0.category == selectedCategory }
        }
        
        if !searchText.isEmpty {
            exercises = exercises.filter {
                ($0.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return exercises
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.92, green: 0.95, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search exercises", text: $searchText)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(cardBackground))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Categories
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { category in
                                Button(action: { selectedCategory = category }) {
                                    Text(category)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(selectedCategory == category ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedCategory == category
                                                    ? LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                                                    : LinearGradient(colors: [cardBackground, cardBackground], startPoint: .leading, endPoint: .trailing))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    
                    // Exercise List
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredExercises, id: \.objectID) { exercise in
                                ExercisePickerRow(
                                    exercise: exercise,
                                    isSelected: localSelection.contains(exercise.objectID),
                                    onToggle: {
                                        if localSelection.contains(exercise.objectID) {
                                            localSelection.remove(exercise.objectID)
                                        } else {
                                            localSelection.insert(exercise.objectID)
                                        }
                                    }
                                )
                                
                                if exercise.objectID != filteredExercises.last?.objectID {
                                    Divider().padding(.leading, 50)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(cardBackground)
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add \(localSelection.count)") {
                        addSelectedExercises()
                    }
                    .fontWeight(.semibold)
                    .disabled(localSelection.isEmpty)
                }
            }
            .onAppear {
                // Initialize with already selected exercises
                localSelection = Set(selectedExercises.map { $0.objectID })
            }
        }
    }
    
    private func addSelectedExercises() {
        let newExercises = allExercises.filter { localSelection.contains($0.objectID) }
        selectedExercises = newExercises.sorted { ($0.name ?? "") < ($1.name ?? "") }
        dismiss()
    }
}

// MARK: - Exercise Picker Row

struct ExercisePickerRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(exercise.category ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
