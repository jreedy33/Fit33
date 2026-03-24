import SwiftUI
import CoreData

struct WorkoutCreationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let workoutType: WorkoutCreationType
    
    @State private var workoutName = ""
    @State private var selectedExercises: [Exercise] = []
    @State private var suggestedExercises: [Exercise] = []
    @State private var isGeneratingWorkout = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content based on workout type
            if workoutType == .generated {
                VStack(spacing: 0) {
                    // Header only for generated workouts
                    headerView
                    generatedWorkoutView
                    Spacer()
                    startWorkoutButton
                }
            } else {
                // For custom workouts, embed ExerciseSelectionView directly with start button
                VStack(spacing: 0) {
                    customWorkoutView
                    if !selectedExercises.isEmpty {
                        startWorkoutButton
                    }
                }
            }
        }
        .onAppear {
            if workoutType == .generated {
                generateWorkout()
            }
            setupDefaultWorkoutName()
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: workoutType == .generated ? "brain.head.profile" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text(workoutType == .generated ? "Generated Workout" : "Build Your Workout")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            TextField("Workout Name", text: $workoutName)
                .font(.title3)
                .fontWeight(.medium)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding()
        .background(Color.blue.opacity(0.05))
    }
    
    private var generatedWorkoutView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isGeneratingWorkout {
                    generateWorkoutLoadingView
                } else if suggestedExercises.isEmpty {
                    emptyGeneratedView
                } else {
                    generatedExercisesView
                }
            }
            .padding()
        }
    }
    
    private var generateWorkoutLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.blue)
            
            Text("Creating your perfect workout...")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Based on your goals and equipment")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var emptyGeneratedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Unable to Generate Workout")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("We couldn't create a workout with your current settings. Try updating your equipment or goals.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Regenerate") {
                generateWorkout()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var generatedExercisesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recommended Exercises")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Regenerate") {
                    generateWorkout()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            ForEach(Array(suggestedExercises.enumerated()), id: \.element.id) { index, exercise in
                GeneratedExerciseCard(exercise: exercise, number: index + 1)
            }
        }
    }
    
    private var customWorkoutView: some View {
        // Show exercise selection interface directly
        ExerciseSelectionView(selectedExercises: $selectedExercises)
    }
    
    
    private var startWorkoutButton: some View {
        VStack(spacing: 12) {
            let exercises = workoutType == .generated ? suggestedExercises : selectedExercises
            
            if !exercises.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to start")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(exercises.count) exercises")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    Button("Start Workout") {
                        startWorkout()
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    private func setupDefaultWorkoutName() {
        if workoutName.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let dateString = formatter.string(from: Date())
            
            if workoutType == .generated {
                workoutName = "Generated Workout - \(dateString)"
            } else {
                workoutName = "Custom Workout - \(dateString)"
            }
        }
    }
    
    private func generateWorkout() {
        guard let user = userManager.currentUser else { return }
        
        isGeneratingWorkout = true
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            let recentMuscleGroups = userManager.getRecentMuscleGroups(days: 7)
            
            suggestedExercises = ExerciseLibraryService.shared.getSuggestedExercises(
                for: (user.equipment as? [String]) ?? [],
                goal: user.fitnessGoal ?? "General Fitness",
                experience: user.experienceLevel ?? "Beginner",
                recentMuscleGroups: recentMuscleGroups
            )
            
            isGeneratingWorkout = false
        }
    }
    
    private func startWorkout() {
        let exercises = workoutType == .generated ? suggestedExercises : selectedExercises
        
        AppLogger.debug("🏋️‍♂️ Starting workout with \(exercises.count) exercises", category: .workout)
        
        guard !exercises.isEmpty else { 
            AppLogger.error("❌ No exercises selected", category: .workout)
            return 
        }
        
        // Use default name if empty
        let finalWorkoutName = workoutName.isEmpty ? "My Workout" : workoutName
        
        // Create new workout
        let newWorkout = Workout(context: viewContext)
        newWorkout.id = UUID()
        newWorkout.name = finalWorkoutName
        newWorkout.date = Date()
        newWorkout.isCompleted = false
        newWorkout.user = userManager.currentUser
        
        AppLogger.debug("🏋️‍♂️ Starting workout: \(finalWorkoutName) with \(exercises.count) exercises", category: .workout)
        
        // Start workout using WorkoutManager
        workoutManager.startWorkout(workout: newWorkout, exercises: exercises)
        
        // Dismiss this view
        dismiss()
        
        AppLogger.info("✅ Workout started successfully and navigating to Workout tab", category: .workout)
    }
    
    private func createTempWorkout() -> Workout {
        let tempWorkout = Workout(context: viewContext)
        tempWorkout.id = UUID()
        tempWorkout.name = workoutName.isEmpty ? "My Workout" : workoutName
        tempWorkout.date = Date()
        tempWorkout.isCompleted = false
        return tempWorkout
    }
}

struct GeneratedExerciseCard: View {
    let exercise: Exercise
    let number: Int
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon (matching exercise library style)
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: categoryIcon)
                    .font(.ds_labelMedium)
                    .foregroundColor(categoryColor)
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name ?? "Exercise")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(exercise.category ?? "")
                        .font(.caption)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(exercise.equipment ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.ds_bodySmall).fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

struct CustomExerciseCard: View {
    let exercise: Exercise
    let number: Int
    let onRemove: () -> Void
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon (matching exercise library style)
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: categoryIcon)
                    .font(.ds_labelMedium)
                    .foregroundColor(categoryColor)
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name ?? "Exercise")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(exercise.category ?? "")
                        .font(.caption)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(exercise.equipment ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.ds_heading3)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

#Preview {
    WorkoutCreationView(workoutType: .custom)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}
