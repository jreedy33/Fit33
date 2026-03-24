import SwiftUI
import CoreData

struct FriendWorkoutPreviewView: View {
    let workoutId: String
    let friendName: String
    let metadata: ActivityMetadata
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    
    @State private var exercises: [WorkoutExerciseDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNoExercisesAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        workoutHeader
                        
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
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 140)
                }
                
                if !exercises.isEmpty && !isLoading {
                    VStack {
                        Spacer()
                        FloatingGoButton(
                            action: { startFriendWorkout() },
                            primaryColor: .cyan,
                            secondaryColor: .blue,
                            accessibilityText: "Do this workout"
                        )
                        .padding(.bottom, 30)
                    }
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
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            if isActive {
                dismiss()
            }
        }
        .alert("Couldn't Start Workout", isPresented: $showNoExercisesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("None of the exercises in this workout could be found in your exercise library.")
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
                FriendExerciseCard(
                    number: index + 1,
                    exerciseName: exercise.exerciseName
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
    
    // MARK: - Start Workout
    
    private func startFriendWorkout() {
        var resolvedExercises: [Exercise] = []
        
        for dto in exercises {
            if let exercise = ExerciseLibraryService.shared.getExercise(byName: dto.exerciseName) {
                resolvedExercises.append(exercise)
            } else {
                AppLogger.warning("Could not resolve friend exercise: \(dto.exerciseName)", category: .workout)
            }
        }
        
        guard !resolvedExercises.isEmpty else {
            showNoExercisesAlert = true
            return
        }
        
        AppLogger.info("Starting friend workout with \(resolvedExercises.count)/\(exercises.count) exercises", category: .workout)
        
        let newWorkout = Workout(context: viewContext)
        newWorkout.id = UUID()
        newWorkout.name = metadata.workoutName ?? "\(friendName)'s Workout"
        newWorkout.date = Date()
        newWorkout.isCompleted = false
        
        HapticManager.notification(.success)
        workoutManager.startWorkout(workout: newWorkout, exercises: resolvedExercises)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}

// MARK: - Friend Exercise Card

private struct FriendExerciseCard: View {
    let number: Int
    let exerciseName: String
    @Environment(\.colorScheme) private var colorScheme
    
    private var libraryExercise: Exercise? {
        ExerciseLibraryService.shared.getExercise(byName: exerciseName)
    }
    
    private var categoryGradient: [Color] {
        switch libraryExercise?.category?.lowercased() {
        case "chest": return [.purple, .pink]
        case "back": return [.blue, .cyan]
        case "legs": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "arms": return [.purple, .indigo]
        case "core": return [.yellow, .orange]
        default: return [.cyan, .blue]
        }
    }
    
    private var categoryIcon: String {
        switch libraryExercise?.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.strengthtraining.traditional"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "figure.arms.open"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: categoryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: categoryGradient[0].opacity(0.25), radius: 4, x: 0, y: 2)
                
                Image(systemName: categoryIcon)
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let category = libraryExercise?.category {
                    HStack(spacing: 6) {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(categoryGradient[0])
                            .fontWeight(.medium)
                        
                        if let equipment = libraryExercise?.equipment {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(equipment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        LinearGradient(
                            colors: [
                                categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
    }
}
