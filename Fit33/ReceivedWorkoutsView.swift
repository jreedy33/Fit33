import SwiftUI
import CoreData

// MARK: - Received Workouts View
/// View and manage workouts received from friends

struct ReceivedWorkoutsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    
    @StateObject private var friendService = FriendService.shared
    
    @State private var selectedWorkout: SharedWorkoutDTO?
    @State private var showingWorkoutDetail = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ZStack {
            AdaptiveGradient.stats(for: colorScheme)
                .ignoresSafeArea()
            
            if friendService.receivedWorkouts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(friendService.receivedWorkouts) { workout in
                            ReceivedWorkoutCard(workout: workout) {
                                selectedWorkout = workout
                                showingWorkoutDetail = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("Received Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            NavigationView {
                ReceivedWorkoutDetailView(workout: workout)
            }
        }
        .onAppear {
            Task {
                await friendService.loadReceivedWorkouts()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text("No Workouts Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Workouts sent to you by friends\nwill appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Received Workout Card

struct ReceivedWorkoutCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let workout: SharedWorkoutDTO
    let onTap: () -> Void
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    private var isUnread: Bool {
        workout.viewedAt == nil && workout.status == "pending"
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    // Sender avatar
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Text(senderInitials)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(workout.senderName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            if isUnread {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        
                        Text(timeAgoString(from: workout.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Status badge
                    statusBadge
                }
                
                Divider()
                
                // Workout info
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.workoutName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let description = workout.workoutDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Exercise count
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.caption)
                            Text("\(workout.exerciseCount) exercises")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                        
                        if let message = workout.message, !message.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "text.bubble.fill")
                                    .font(.caption)
                                Text("Has message")
                                    .font(.caption)
                            }
                            .foregroundColor(.green)
                        }
                    }
                }
                
                // Quick action hint
                HStack {
                    Spacer()
                    Text("Tap to view details")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isUnread ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var senderInitials: String {
        let components = workout.senderName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "??"
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch workout.status {
        case "pending":
            Text("NEW")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.blue))
        case "saved":
            HStack(spacing: 4) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 10))
                Text("Saved")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().stroke(Color.green, lineWidth: 1))
        default:
            EmptyView()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Received Workout Detail View

struct ReceivedWorkoutDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    
    let workout: SharedWorkoutDTO
    
    @State private var isStartingWorkout = false
    @State private var showingEditView = false
    @State private var showingSavedConfirmation = false
    
    // For editing
    @State private var editedExercises: [SelectedExerciseForFriend] = []
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ZStack {
            AdaptiveGradient.stats(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Sender info
                    senderSection
                    
                    // Message (if any)
                    if let message = workout.message, !message.isEmpty {
                        messageSection(message)
                    }
                    
                    // Workout details
                    workoutDetailsSection
                    
                    // Exercise list
                    exerciseListSection
                    
                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            markAsViewed()
            setupEditedExercises()
        }
        .sheet(isPresented: $showingEditView) {
            NavigationView {
                EditReceivedWorkoutView(
                    workout: workout,
                    exercises: $editedExercises,
                    onStartWorkout: { startWorkout(exercises: editedExercises) }
                )
            }
        }
        .alert("Workout Saved! ✓", isPresented: $showingSavedConfirmation) {
            Button("OK") {}
        } message: {
            Text("This workout has been saved. You can find it in your received workouts anytime.")
        }
    }
    
    // MARK: - Sender Section
    
    private var senderSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Text(senderInitials)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("From \(workout.senderName)")
                    .font(.headline)
                
                Text(formatDate(workout.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Message Section
    
    private func messageSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "quote.bubble.fill")
                    .foregroundColor(.blue)
                Text("Message")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            Text(message)
                .font(.body)
                .foregroundColor(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.08))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Workout Details Section
    
    private var workoutDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(workout.workoutName)
                .font(.title2)
                .fontWeight(.bold)
            
            if let description = workout.workoutDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                StatBubble(
                    icon: "figure.strengthtraining.traditional",
                    value: "\(workout.exerciseCount)",
                    label: "Exercises",
                    color: .blue
                )
                
                StatBubble(
                    icon: "flame.fill",
                    value: "\(totalSets)",
                    label: "Sets",
                    color: .orange
                )
                
                StatBubble(
                    icon: "clock.fill",
                    value: "\(estimatedMinutes)",
                    label: "Minutes",
                    color: .green
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Exercise List Section
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISES")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(workout.exerciseNames.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 36, height: 36)
                            
                            Text("\(index + 1)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            let sets = workout.exerciseSets.indices.contains(index) ? workout.exerciseSets[index] : 3
                            let reps = workout.exerciseReps.indices.contains(index) ? workout.exerciseReps[index] : "10"
                            
                            Text("\(sets) sets × \(reps) reps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    
                    if index < workout.exerciseNames.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Start Workout Button
            Button(action: { startWorkoutFromReceived() }) {
                HStack(spacing: 10) {
                    if isStartingWorkout {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isStartingWorkout ? "Starting..." : "Start Workout")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.mint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .disabled(isStartingWorkout)
            
            HStack(spacing: 12) {
                // Edit Button
                Button(action: {
                    HapticManager.impact(.light)
                    showingEditView = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                }
                
                // Save Button
                Button(action: saveWorkout) {
                    HStack(spacing: 8) {
                        Image(systemName: workout.status == "saved" ? "bookmark.fill" : "bookmark")
                        Text(workout.status == "saved" ? "Saved" : "Save")
                    }
                    .font(.headline)
                    .foregroundColor(workout.status == "saved" ? .green : .orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(workout.status == "saved" ? Color.green : Color.orange, lineWidth: 2)
                    )
                }
                .disabled(workout.status == "saved")
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Computed Properties
    
    private var senderInitials: String {
        let components = workout.senderName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "??"
    }
    
    private var totalSets: Int {
        workout.exerciseSets.reduce(0, +)
    }
    
    private var estimatedMinutes: Int {
        // Rough estimate: 3 min per set
        max(15, totalSets * 3)
    }
    
    // MARK: - Actions
    
    private func markAsViewed() {
        Task {
            await FriendService.shared.markWorkoutViewed(workoutId: workout.id)
        }
    }
    
    private func setupEditedExercises() {
        editedExercises = workout.exerciseNames.enumerated().map { index, name in
            SelectedExerciseForFriend(
                name: name,
                category: nil,
                sets: workout.exerciseSets.indices.contains(index) ? workout.exerciseSets[index] : 3,
                reps: workout.exerciseReps.indices.contains(index) ? workout.exerciseReps[index] : "10",
                notes: workout.exerciseNotes.indices.contains(index) ? workout.exerciseNotes[index] : ""
            )
        }
    }
    
    private func startWorkoutFromReceived() {
        startWorkout(exercises: editedExercises)
    }
    
    private func startWorkout(exercises: [SelectedExerciseForFriend]) {
        isStartingWorkout = true
        HapticManager.impact(.heavy)
        
        // Fetch exercises from Core Data
        let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        let exerciseNames = exercises.map { $0.name }
        fetchRequest.predicate = NSPredicate(format: "name IN %@", exerciseNames)
        
        do {
            let fetchedExercises = try viewContext.fetch(fetchRequest)
            
            // Create a map for quick lookup
            let exerciseMap = Dictionary(uniqueKeysWithValues: fetchedExercises.compactMap { exercise -> (String, Exercise)? in
                guard let name = exercise.name else { return nil }
                return (name, exercise)
            })
            
            // Get exercises in order
            let orderedExercises = exercises.compactMap { exerciseMap[$0.name] }
            
            guard !orderedExercises.isEmpty else {
                print("❌ No exercises found in Core Data")
                isStartingWorkout = false
                return
            }
            
            // Create workout
            let newWorkout = Workout(context: viewContext)
            newWorkout.id = UUID()
            newWorkout.name = workout.workoutName
            newWorkout.date = Date()
            newWorkout.isCompleted = false
            newWorkout.user = userManager.currentUser
            
            // Start workout
            workoutManager.startWorkout(workout: newWorkout, exercises: orderedExercises)
            
            // Mark as completed in friend service
            Task {
                await FriendService.shared.markWorkoutCompleted(workoutId: workout.id)
            }
            
            dismiss()
        } catch {
            print("❌ Error fetching exercises: \(error)")
            isStartingWorkout = false
        }
    }
    
    private func saveWorkout() {
        HapticManager.impact(.medium)
        Task {
            do {
                try await FriendService.shared.saveSharedWorkout(workoutId: workout.id)
                showingSavedConfirmation = true
                HapticManager.notificationOccurred(.success)
            } catch {
                print("❌ Error saving workout: \(error)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Stat Bubble

struct StatBubble: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Edit Received Workout View

struct EditReceivedWorkoutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    let workout: SharedWorkoutDTO
    @Binding var exercises: [SelectedExerciseForFriend]
    let onStartWorkout: () -> Void
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ZStack {
            AdaptiveGradient.stats(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    Text("Customize this workout before starting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    ForEach($exercises) { $exercise in
                        EditableExerciseCard(exercise: $exercise)
                    }
                    
                    // Start button
                    Button(action: {
                        HapticManager.impact(.heavy)
                        dismiss()
                        onStartWorkout()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text("Start Edited Workout")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.green, Color.mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Editable Exercise Card

struct EditableExerciseCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var exercise: SelectedExerciseForFriend
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(exercise.name)
                .font(.headline)
            
            HStack(spacing: 16) {
                // Sets
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            if exercise.sets > 1 { exercise.sets -= 1 }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        Text("\(exercise.sets)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .frame(minWidth: 30)
                        
                        Button(action: {
                            exercise.sets += 1
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                // Reps
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., 10-12", text: $exercise.reps)
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(width: 80)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(.systemGray6))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

#Preview {
    NavigationView {
        ReceivedWorkoutsView()
            .environmentObject(WorkoutManager.shared)
            .environmentObject(UserManager())
    }
}
