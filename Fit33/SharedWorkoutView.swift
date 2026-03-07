import SwiftUI
import CoreData

// MARK: - Shared Workout View
/// Displays a shared workout when user opens a share link
/// Shows options to: Start Workout, Save for Later, or Download App (if not installed)

struct SharedWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let workoutId: String
    let previewData: SharedWorkoutData?
    
    @State private var isLoading = true
    @State private var workoutDetails: SharedWorkoutDetails?
    @State private var error: String?
    @State private var showingStartConfirmation = false
    @State private var savedForLater = false
    
    // Gradient colors based on workout type
    private var accentGradient: [Color] {
        if let details = workoutDetails,
           let exercises = details.workout.exercises?.allObjects as? [WorkoutExercise],
           let firstExercise = exercises.first?.exercise {
            return categoryGradient(for: firstExercise.category ?? "")
        }
        return [.blue, .cyan]
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)]
                        : [Color(white: 0.96), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if let error = error {
                    errorView(message: error)
                } else if let details = workoutDetails {
                    workoutContentView(details: details)
                } else {
                    errorView(message: "Workout not found")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadWorkout()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading workout...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let preview = previewData {
                VStack(spacing: 8) {
                    Text(preview.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 16) {
                        Label("\(preview.exerciseCount) exercises", systemImage: "dumbbell.fill")
                        Label("\(preview.duration) min", systemImage: "clock.fill")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            }
        }
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Couldn't Load Workout")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: { dismiss() }) {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(CornerRadius.md)
            }
            .padding(.horizontal, 32)
        }
    }
    
    // MARK: - Workout Content View
    
    private func workoutContentView(details: SharedWorkoutDetails) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Card
                headerCard(details: details)
                
                // Stats Grid
                statsGrid(details: details)
                
                // Exercise List
                exerciseList(details: details)
                
                // Action Buttons
                actionButtons(details: details)
                
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
    
    // MARK: - Header Card
    
    private func headerCard(details: SharedWorkoutDetails) -> some View {
        VStack(spacing: 16) {
            // Shared badge
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                Text("Shared Workout")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(accentGradient[0])
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(accentGradient[0].opacity(0.15))
            )
            
            // Workout icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: accentGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: accentGradient[0].opacity(0.4), radius: 10, x: 0, y: 5)
                
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Workout name
            VStack(spacing: 6) {
                Text(cleanWorkoutName(details.workout.name ?? "Workout"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                if let date = details.workout.date {
                    Text("Completed \(formatRelativeDate(date))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Stats Grid
    
    private func statsGrid(details: SharedWorkoutDetails) -> some View {
        let exercises = details.workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        let totalSets = exercises.reduce(0) { total, we in
            let sets = we.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
        let duration = Int(details.workout.duration) / 60
        
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            SharedWorkoutStatCard(
                icon: "clock.fill",
                value: "\(duration)",
                label: "Minutes",
                color: .blue
            )
            
            SharedWorkoutStatCard(
                icon: "figure.strengthtraining.traditional",
                value: "\(exercises.count)",
                label: "Exercises",
                color: .green
            )
            
            SharedWorkoutStatCard(
                icon: "repeat",
                value: "\(totalSets)",
                label: "Sets",
                color: .orange
            )
        }
    }
    
    // MARK: - Exercise List
    
    private func exerciseList(details: SharedWorkoutDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exercises")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 10) {
                ForEach(Array(details.exercises.enumerated()), id: \.element.id) { index, exercise in
                    SharedExerciseRow(index: index + 1, exercise: exercise)
                }
            }
        }
        .padding(20)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
    }
    
    // MARK: - Action Buttons
    
    private func actionButtons(details: SharedWorkoutDetails) -> some View {
        VStack(spacing: 12) {
            // Start Workout Button
            Button(action: {
                showingStartConfirmation = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.headline)
                    Text("Start This Workout")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: accentGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .shadow(color: accentGradient[0].opacity(0.4), radius: 8, x: 0, y: 4)
            }
            
            // Save for Later Button
            Button(action: {
                saveWorkoutForLater(details: details)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: savedForLater ? "bookmark.fill" : "bookmark")
                        .font(.headline)
                    Text(savedForLater ? "Saved!" : "Save for Later")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(savedForLater ? .orange : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(savedForLater ? Color.orange : Color.gray.opacity(0.3), lineWidth: 1.5)
                )
            }
            .disabled(savedForLater)
        }
        .alert("Start Workout?", isPresented: $showingStartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start") {
                startWorkout(details: details)
            }
        } message: {
            Text("This will create a new workout based on '\(cleanWorkoutName(details.workout.name ?? "Workout"))' with the same exercises.")
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadWorkout() async {
        isLoading = true
        
        // Use WorkoutSharingService which tries local first, then cloud fallback
        if let details = await WorkoutSharingService.shared.loadSharedWorkout(workoutId: workoutId) {
            workoutDetails = details
        } else {
            error = "This workout could not be found. The link may have expired or the workout was removed."
        }
        
        isLoading = false
    }
    
    private func startWorkout(details: SharedWorkoutDetails) {
        // Create a new workout based on the shared one
        let newWorkout = Workout(context: viewContext)
        newWorkout.id = UUID()
        newWorkout.name = cleanWorkoutName(details.workout.name ?? "Workout")
        newWorkout.date = Date()
        newWorkout.isCompleted = false
        
        // Start the workout with the same exercises
        workoutManager.startWorkout(workout: newWorkout, exercises: details.exercises)
        
        dismiss()
    }
    
    private func saveWorkoutForLater(details: SharedWorkoutDetails) {
        // Mark the original workout as favorite
        details.workout.isFavorite = true
        
        do {
            try viewContext.save()
            savedForLater = true
            HapticManager.notification(.success)
        } catch {
            print("❌ Error saving workout: \(error)")
        }
    }
    
    private func cleanWorkoutName(_ name: String) -> String {
        if let range = name.range(of: " - ", options: .backwards) {
            let potentialDate = String(name[range.upperBound...])
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if months.contains(where: { potentialDate.contains($0) }) || potentialDate.first?.isNumber == true {
                return String(name[..<range.lowerBound])
            }
        }
        return name
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: date, to: now)
        
        if let days = components.day {
            if days == 0 {
                return "today"
            } else if days == 1 {
                return "yesterday"
            } else if days < 7 {
                return "\(days) days ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return "on \(formatter.string(from: date))"
            }
        }
        return ""
    }
    
    private func categoryGradient(for category: String) -> [Color] {
        switch category.lowercased() {
        case "chest": return [.purple, .pink]
        case "back": return [.blue, .cyan]
        case "legs": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "arms": return [.purple, .indigo]
        case "core": return [.yellow, .orange]
        case "full body": return [.pink, .red]
        default: return [.blue, .cyan]
        }
    }
}

// MARK: - Stat Card

struct SharedWorkoutStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Exercise Row

struct SharedExerciseRow: View {
    let index: Int
    let exercise: Exercise
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var categoryGradient: [Color] {
        switch exercise.category?.lowercased() {
        case "chest": return [.purple, .pink]
        case "back": return [.blue, .cyan]
        case "legs": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "arms": return [.purple, .indigo]
        case "core": return [.yellow, .orange]
        default: return [.gray, .gray.opacity(0.7)]
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Index badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: categoryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Exercise info
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let category = exercise.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(categoryGradient[0])
                    }
                    
                    if let equipment = exercise.equipment {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(equipment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Preview

#Preview {
    SharedWorkoutView(
        workoutId: "test-id",
        previewData: SharedWorkoutData(
            workoutId: "test-id",
            name: "Push Day",
            exerciseCount: 5,
            duration: 45
        )
    )
    .environmentObject(WorkoutManager.shared)
}
