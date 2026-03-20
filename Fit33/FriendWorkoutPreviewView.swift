import SwiftUI

struct FriendWorkoutPreviewView: View {
    let workoutId: String
    let friendName: String
    let metadata: ActivityMetadata
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var exercises: [WorkoutExerciseDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Workout header
                        workoutHeader
                        
                        // Exercise list
                        if isLoading {
                            ProgressView()
                                .padding(.top, Spacing.xl)
                        } else if let error = errorMessage {
                            errorView(error)
                        } else if exercises.isEmpty {
                            emptyExercisesList
                        } else {
                            exercisesList
                        }
                        
                        // Action buttons
                        actionButtons
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            await loadWorkout()
        }
    }
    
    // MARK: - Header
    
    private var workoutHeader: some View {
        VStack(spacing: Spacing.sm) {
            Text(friendName + "'s Workout")
                .font(.ds_heading2)
                .foregroundColor(.primary)
            
            Text(metadata.workoutName ?? "Workout")
                .font(.ds_heading3)
                .foregroundColor(.secondary)
            
            // Stats row
            HStack(spacing: Spacing.lg) {
                statBubble(icon: "clock.fill", value: formatDuration(metadata.durationSeconds ?? 0), color: .blue)
                statBubble(icon: "figure.strengthtraining.traditional", value: "\(metadata.exerciseCount ?? 0) exercises", color: .green)
                statBubble(icon: "repeat", value: "\(metadata.totalSets ?? 0) sets", color: .purple)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.vertical, Spacing.md)
    }
    
    private func statBubble(icon: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.ds_heading3)
                .foregroundColor(color)
            Text(value)
                .font(.ds_labelMedium)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Exercises List
    
    private var exercisesList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Exercises", icon: "list.bullet", iconColor: .blue)
            
            ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                HStack(spacing: Spacing.sm) {
                    // Exercise number
                    Text("\(index + 1)")
                        .font(.ds_labelMedium)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(LinearGradient.ds_primaryAccent)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.exerciseName)
                            .font(.ds_bodyLarge)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Text("\(exercise.sets.count) sets")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.cardBackground)
                )
            }
        }
    }
    
    private var emptyExercisesList: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "dumbbell.fill")
                .font(.ds_heading1)
                .foregroundColor(.secondary)
            Text("Exercise details not available")
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, Spacing.xl)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.ds_heading1)
                .foregroundColor(.orange)
            Text(message)
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xl)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            if !exercises.isEmpty {
                Button {
                    HapticManager.notification(.success)
                    // Save exercises as a new custom workout template
                    saveWorkoutForLater()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "bookmark.fill")
                        Text("Save for Later")
                    }
                    .font(.ds_labelLarge)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        LinearGradient.ds_primaryAccent
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                    )
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadWorkout() async {
        do {
            let result: [WorkoutHistoryDTO] = try await SupabaseManager.shared.supabaseClient
                .from("workout_history")
                .select("*, exercises:workout_exercises(*)")
                .eq("id", value: workoutId)
                .execute()
                .value
            
            await MainActor.run {
                self.exercises = result.first?.exercises ?? []
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.exercises = []
                self.isLoading = false
            }
        }
    }
    
    private func saveWorkoutForLater() {
        // Placeholder — would save the exercise list as a favorite routine template
        print("✅ Workout saved for later: \(workoutId)")
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}
