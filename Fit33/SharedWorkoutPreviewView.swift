import SwiftUI

// MARK: - Shared Workout Preview View
/// Preview a workout before sending it to a friend

struct SharedWorkoutPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    let friend: Friend
    let workoutName: String
    let workoutDescription: String
    let exercises: [SelectedExerciseForFriend]
    let message: String
    let onSent: () -> Void
    
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Preview Header
                    previewHeader
                    
                    // Workout Card
                    workoutCard
                    
                    // Exercise List
                    exerciseList
                    
                    // Message Preview
                    if !message.isEmpty {
                        messagePreview
                    }
                    
                    // Send Button
                    sendButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    dismiss()
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Preview Header
    
    private var previewHeader: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Ready to Send")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Review your workout before sending to \(friend.displayName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Workout Card
    
    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Recipient
            HStack(spacing: 12) {
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
                    
                    Text(friend.initials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sending to")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(friend.displayName)
                        .font(.headline)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Workout info
            VStack(alignment: .leading, spacing: 8) {
                Text(workoutName)
                    .font(.title3)
                    .fontWeight(.bold)
                
                if !workoutDescription.isEmpty {
                    Text(workoutDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Stats
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.caption)
                        Text("\(exercises.count) exercises")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                        Text("\(totalSets) total sets")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .sleekCard(cornerRadius: 20, accentColor: .blue)
    }
    
    // MARK: - Exercise List
    
    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISES")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(spacing: 12) {
                        // Number badge
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 32, height: 32)
                            
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("\(exercise.sets) sets × \(exercise.reps) reps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    
                    if index < exercises.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
        }
    }
    
    // MARK: - Message Preview
    
    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MESSAGE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
        }
    }
    
    // MARK: - Send Button
    
    private var sendButton: some View {
        Button(action: sendWorkout) {
            HStack(spacing: 10) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                
                Text(isSending ? "Sending..." : "Send Workout")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: isSending ? [Color.gray] : [Color.blue, Color.purple.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: isSending ? .clear : .blue.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .disabled(isSending)
        .padding(.top, 16)
    }
    
    // MARK: - Computed Properties
    
    private var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets }
    }
    
    // MARK: - Actions
    
    private func sendWorkout() {
        isSending = true
        HapticManager.impact(.medium)
        
        Task {
            do {
                let sharedExercises = exercises.map { exercise in
                    SharedExerciseDTO(
                        name: exercise.name,
                        sets: exercise.sets,
                        reps: exercise.reps,
                        notes: exercise.notes.isEmpty ? nil : exercise.notes
                    )
                }
                
                try await FriendService.shared.sendWorkout(
                    to: friend.friendId.uuidString,
                    workoutName: workoutName,
                    description: workoutDescription.isEmpty ? nil : workoutDescription,
                    exercises: sharedExercises,
                    message: message.isEmpty ? nil : message
                )
                
                HapticManager.notification(.success)
                onSent()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                HapticManager.notification(.error)
            }
            
            isSending = false
        }
    }
}

#Preview {
    NavigationStack {
        SharedWorkoutPreviewView(
            friend: Friend(
                friendshipId: UUID(),
                friendId: UUID(),
                friendName: "John Doe",
                friendEmail: "john@example.com",
                friendUsername: "johndoe",
                fitnessGoal: nil,
                experienceLevel: nil,
                profilePhotoUrl: nil,
                friendsSince: Date(),
                totalWorkoutsShared: 0
            ),
            workoutName: "Chest Day",
            workoutDescription: "A great chest workout to build strength",
            exercises: [
                SelectedExerciseForFriend(name: "Bench Press", category: "Chest", sets: 4, reps: "8-10"),
                SelectedExerciseForFriend(name: "Incline Dumbbell Press", category: "Chest", sets: 3, reps: "10-12"),
                SelectedExerciseForFriend(name: "Cable Flyes", category: "Chest", sets: 3, reps: "12-15")
            ],
            message: "Try this chest workout! It's been working great for me 💪",
            onSent: {}
        )
    }
}
