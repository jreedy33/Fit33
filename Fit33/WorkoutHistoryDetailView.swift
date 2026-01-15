import SwiftUI
import CoreData

struct WorkoutHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let workout: Workout
    
    @State private var showingRepeatPreview = false
    @State private var showingShareSheet = false
    
    private var workoutExercises: [WorkoutExercise] {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        let sorted = exercises.sorted { ($0.order) < ($1.order) }
        
        // Deduplicate exercises based on exercise ID and order
        // This handles the bug where finishWorkout() was called multiple times
        var seen: Set<String> = []
        var deduplicated: [WorkoutExercise] = []
        
        for workoutExercise in sorted {
            let exerciseId = workoutExercise.exercise?.id?.uuidString ?? workoutExercise.id?.uuidString ?? "unknown"
            let key = "\(exerciseId)_\(workoutExercise.order)"
            if !seen.contains(key) {
                seen.insert(key)
                deduplicated.append(workoutExercise)
            } else {
                #if DEBUG
                print("⚠️ [HISTORY] Skipping duplicate exercise: \(workoutExercise.safeDisplayName) at position \(workoutExercise.order)")
                #endif
            }
        }
        
        return deduplicated
    }
    
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
    }
    
    private var totalReps: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.reduce(0) { $0 + Int($1.reps) }
        }
    }
    
    private var totalVolume: Double {
        workoutExercises.reduce(0.0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            let exerciseVolume = sets.filter { $0.isCompleted }.reduce(0.0) { setTotal, set in
                return setTotal + (set.weight * Double(set.reps))
            }
            return total + exerciseVolume
        }
    }
    
    private var personalRecords: [(exercise: String, weight: Double, reps: Int)] {
        var prs: [(exercise: String, weight: Double, reps: Int)] = []
        for workoutExercise in workoutExercises {
            let exerciseName = workoutExercise.safeDisplayName
            guard exerciseName != "Loading...",
                  let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { continue }
            
            if let bestSet = sets.filter({ $0.isCompleted }).max(by: { first, second in
                if first.weight != second.weight {
                    return first.weight < second.weight
                }
                return first.reps < second.reps
            }) {
                if bestSet.weight >= 100 || bestSet.reps >= 12 {
                    prs.append((exercise: exerciseName, weight: bestSet.weight, reps: Int(bestSet.reps)))
                }
            }
        }
        return prs.prefix(3).map { $0 }
    }
    
    private var muscleBreakdown: [(muscle: String, count: Int, color: Color)] {
        var muscleCount: [String: Int] = [:]
        for workoutExercise in workoutExercises {
            // Use safeMuscleGroups for nil-safety
            for muscle in workoutExercise.safeMuscleGroups {
                muscleCount[muscle.capitalized, default: 0] += 1
            }
        }
        return muscleCount.sorted { $0.value > $1.value }.prefix(4).map { 
            (muscle: $0.key, count: $0.value, color: colorForMuscle($0.key))
        }
    }
    
    private func colorForMuscle(_ muscle: String) -> Color {
        switch muscle.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "shoulders": return .orange
        case "biceps", "triceps", "arms": return .purple
        case "legs", "quads", "hamstrings", "glutes": return .green
        case "core", "abs": return .yellow
        default: return .cyan
        }
    }
    
    private var accentColor: Color {
        if let firstMuscle = muscleBreakdown.first {
            return firstMuscle.color
        }
        return .blue
    }
    
    private var accentGradient: [Color] {
        // Match exact gradient colors from recent activity cards
        let firstMuscle = muscleBreakdown.first?.muscle.lowercased() ?? ""
        
        switch firstMuscle {
        case "chest": return [.red, .orange]
        case "back": return [.blue, .cyan]
        case "legs", "quads", "hamstrings", "glutes": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "biceps", "triceps", "arms": return [.purple, .pink]
        case "core", "abs": return [.yellow, .orange]
        default:
            // Fallback to time-based
            let hour = Calendar.current.component(.hour, from: workout.date ?? Date())
            if hour >= 5 && hour < 12 {
                return [.orange, .yellow]
            } else if hour >= 12 && hour < 17 {
                return [.blue, .cyan]
            } else {
                return [.purple, .pink]
            }
        }
    }
    
    private var smartTitle: String {
        if let name = workout.name, !name.isEmpty {
            let cleanName = cleanWorkoutName(name)
            if !cleanName.lowercased().contains("workout") || cleanName.count > 15 {
                return cleanName
            }
        }
        return generateMuscleBasedName()
    }
    
    private func generateMuscleBasedName() -> String {
        let timeOfDay = getTimeOfDay()
        if let topMuscle = muscleBreakdown.first {
            return "\(timeOfDay) \(topMuscle.muscle)"
        }
        return "\(timeOfDay) Workout"
    }
    
    private func getTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: workout.date ?? Date())
        if hour >= 5 && hour < 12 { return "Morning" }
        else if hour >= 12 && hour < 17 { return "Afternoon" }
        else { return "Evening" }
    }
    
    private func cleanWorkoutName(_ name: String) -> String {
        var cleanName = name
        let patterns = [" - [A-Z][a-z]+ \\d+$", " - [A-Z][a-z]+$", " - \\d{1,2}/\\d{1,2}$"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleanName.startIndex..., in: cleanName)
                cleanName = regex.stringByReplacingMatches(in: cleanName, range: range, withTemplate: "")
            }
        }
        return cleanName.trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Clean header section
                VStack(spacing: 20) {
                    // Compact header with icon and meta info
                    HStack(spacing: 16) {
                        // Compact checkmark icon
                        ZStack {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: accentGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: accentGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            // Date
                            Text(formatFullDate(workout.date ?? Date()))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // XP Badge
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        LinearGradient(colors: accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                Text("+\(Int(workout.xpEarned)) XP")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(accentGradient[0])
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(accentGradient[0].opacity(0.12))
                            )
                        }
                        
                        Spacer()
                        
                        // Share button
                        Button(action: {
                            HapticManager.impact(.light)
                            showingShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(accentColor)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(accentColor.opacity(0.12))
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    // Stats Grid
                    statsGrid
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
                
                // Content
                VStack(spacing: 20) {
                    // Muscle Breakdown
                    if !muscleBreakdown.isEmpty {
                        muscleBreakdownCard
                    }
                    
                    // Highlights
                    if !personalRecords.isEmpty {
                        highlightsCard
                    }
                    
                    // Exercises List
                    exercisesCard
                    
                    // Actions
                    actionsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [Color(red: 0.05, green: 0.05, blue: 0.07), Color(red: 0.08, green: 0.08, blue: 0.10)]
                    : [Color(.systemGroupedBackground), Color.white.opacity(0.95)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(smartTitle)
        .navigationBarTitleDisplayMode(.large)
        .background(
            NavigationLink(
                destination: RepeatWorkoutPreviewView(
                    workout: workout,
                    exercises: workoutExercises.compactMap { $0.exercise },
                    accentColor: accentColor
                )
                .environmentObject(WorkoutManager.shared),
                isActive: $showingRepeatPreview
            ) {
                EmptyView()
            }
            .hidden()
        )
        .sheet(isPresented: $showingShareSheet) {
            ShareWorkoutSheet(workout: workout, accentColor: accentColor)
        }
    }
    
    // MARK: - Stats Grid
    private var statsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Duration
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(accentColor)
                        Text(formatDuration(workout.duration))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Duration")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // Exercises
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 12))
                            .foregroundColor(accentColor)
                        Text("\(workoutExercises.count)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Exercises")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // Sets
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 12))
                            .foregroundColor(accentColor)
                        Text("\(totalSets)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Sets")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // Volume
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 12))
                            .foregroundColor(accentColor)
                        Text(formatVolume(totalVolume))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Volume")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
        }
        .background(
            ZStack {
                // Main card background
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.18), Color(white: 0.12)]
                                : [Color(white: 0.96), Color(white: 0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight
                RoundedRectangle(cornerRadius: 16)
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
                
                // Accent border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.3), accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Muscle Breakdown Card
    private var muscleBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
                Text("Muscles Worked")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            // Muscle tags (matching exercise card style)
            HStack(spacing: 12) {
                ForEach(muscleBreakdown.prefix(4), id: \.muscle) { item in
                    Text(item.muscle)
                        .font(.caption)
                        .foregroundColor(item.color)
                        .fontWeight(.medium)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    // MARK: - Highlights Card
    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Top Lifts")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(spacing: 8) {
                ForEach(personalRecords, id: \.exercise) { pr in
                    HStack {
                        Text(pr.exercise)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(Int(pr.weight)) lbs × \(pr.reps)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    if pr.exercise != personalRecords.last?.exercise {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    // MARK: - Exercises Card
    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
                Text("Exercises")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(workoutExercises.count)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(accentColor)
            }
            
            VStack(spacing: 8) {
                ForEach(Array(workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                    PremiumExerciseRow(
                        index: index + 1,
                        workoutExercise: workoutExercise,
                        accentColor: accentColor
                    )
                }
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    // MARK: - Actions Card
    private var actionsCard: some View {
        VStack(spacing: 12) {
            // Repeat button
            Button(action: {
                repeatWorkout()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .bold))
                    Text("Repeat Workout")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [accentColor, accentColor.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [accentColor, accentColor.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Share button
            Button(action: {
                HapticManager.impact(.light)
                showingShareSheet = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                    Text("Share Workout")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.cyan]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Favorite button
            Button(action: {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                // Toggle favorite
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    workout.isFavorite.toggle()
                }
                
                // Save to Core Data
                do {
                    try workout.managedObjectContext?.save()
                    print("✅ Workout favorite status saved: \(workout.isFavorite)")
                } catch {
                    print("❌ Error saving favorite: \(error)")
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: workout.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .bold))
                    Text(workout.isFavorite ? "Saved to Favorites" : "Save to Favorites")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: workout.isFavorite ? [Color.orange, Color.orange.opacity(0.8)] : [Color.primary, Color.primary.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: workout.isFavorite ? [Color.orange, Color.orange.opacity(0.8)] : [Color.primary, Color.primary.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Glass Card Background
    private var glassCard: some View {
        ZStack {
            // Bottom shadow layer - category colored
            RoundedRectangle(cornerRadius: 16)
                .fill(accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8)
                .blur(radius: 4)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            
            // Main card background
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.18), Color(white: 0.12)]
                            : [Color(white: 0.96), Color(white: 0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Inner highlight
            RoundedRectangle(cornerRadius: 16)
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
            
            // Accent border with category color
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(0.3), accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Helpers
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: Int32) -> String {
        let totalMinutes = Int(duration) / 60
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return "\(hours)h \(minutes)m"
        }
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 10000 {
            return String(format: "%.1fK", volume / 1000)
        } else {
            return String(format: "%.0f", volume)
        }
    }
    
    private func repeatWorkout() {
        // Show preview screen instead of starting directly
        showingRepeatPreview = true
    }
}

// MARK: - Exercise Row with Library Styling
struct PremiumExerciseRow: View {
    let index: Int
    let workoutExercise: WorkoutExercise
    let accentColor: Color
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    private var sets: [WorkoutSet] {
        let allSets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
        return allSets.sorted { $0.setNumber < $1.setNumber }
    }
    
    private var completedSets: [WorkoutSet] {
        sets.filter { $0.isCompleted }
    }
    
    private var bestSet: WorkoutSet? {
        completedSets.max { first, second in
            if first.weight != second.weight {
                return first.weight < second.weight
            }
            return first.reps < second.reps
        }
    }
    
    private var totalVolume: Double {
        completedSets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
    }
    
    // Get previous workout's sets for this exercise
    private var previousSets: [WorkoutSet] {
        guard let exercise = workoutExercise.exercise,
              let allWorkouts = exercise.workoutExercises?.allObjects as? [WorkoutExercise] else {
            return []
        }
        
        let currentWorkoutDate = workoutExercise.workout?.date ?? Date()
        
        // Find the most recent previous workout with this exercise
        let previousWorkouts = allWorkouts
            .filter { we in
                guard let workout = we.workout,
                      workout.isCompleted,
                      let workoutDate = workout.date,
                      workoutDate < currentWorkoutDate else { return false }
                return true
            }
            .sorted { ($0.workout?.date ?? Date.distantPast) > ($1.workout?.date ?? Date.distantPast) }
        
        if let previousWorkout = previousWorkouts.first,
           let sets = previousWorkout.sets?.allObjects as? [WorkoutSet] {
            return sets.sorted { $0.setNumber < $1.setNumber }.filter { $0.isCompleted }
        }
        
        return []
    }
    
    // Check if this is a PR
    private var isPR: Bool {
        guard let exercise = workoutExercise.exercise,
              let best = bestSet,
              let allWorkouts = exercise.workoutExercises?.allObjects as? [WorkoutExercise] else {
            return false
        }
        
        let currentWorkoutDate = workoutExercise.workout?.date ?? Date()
        
        // Get all previous sets
        let allPreviousSets = allWorkouts
            .filter { we in
                guard let workout = we.workout,
                      workout.isCompleted,
                      let workoutDate = workout.date,
                      workoutDate < currentWorkoutDate else { return false }
                return true
            }
            .flatMap { ($0.sets?.allObjects as? [WorkoutSet]) ?? [] }
            .filter { $0.isCompleted }
        
        // Check if current best is better than all previous
        return !allPreviousSets.contains { prevSet in
            prevSet.weight > best.weight || (prevSet.weight == best.weight && prevSet.reps >= best.reps)
        }
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            VStack(spacing: 0) {
                // Main exercise row using library card style
                HStack(spacing: 12) {
                    // Exercise icon matching library style
                    if let exercise = workoutExercise.exercise {
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
                            
                            if exercise.category?.lowercased() == "core" {
                                CoreIcon(size: 22, color: .white)
                            } else {
                                Image(systemName: categoryIcon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    // Exercise details
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(workoutExercise.safeDisplayName)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            // PR Badge
                            if isPR && bestSet != nil {
                                HStack(spacing: 2) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 10))
                                    Text("PR")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.15))
                                )
                            }
                        }
                        
                        HStack(spacing: 8) {
                            let category = workoutExercise.safeCategory
                            Text(category)
                                .font(.caption)
                                .foregroundColor(categoryColor)
                                .fontWeight(.medium)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedSets.count) sets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let best = bestSet, best.weight > 0 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text("\(Int(best.weight)) × \(best.reps)")
                                    .font(.caption)
                                    .foregroundColor(accentColor)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Expanded sets detail
                if isExpanded {
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.horizontal, 16)
                        
                        VStack(spacing: 8) {
                            // Previous workout comparison
                            if !previousSets.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.caption)
                                        Text("Previous Workout")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(Array(previousSets.enumerated()), id: \.offset) { index, set in
                                                VStack(spacing: 4) {
                                                    Text("\(Int(set.weight))")
                                                        .font(.caption)
                                                        .fontWeight(.bold)
                                                    Text("×\(set.reps)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.secondary.opacity(0.1))
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.bottom, 8)
                                
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                            
                            // Current sets
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                    Text("This Workout")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                
                                VStack(spacing: 4) {
                                    ForEach(completedSets, id: \.id) { set in
                                        let isBest = set == bestSet
                                        
                                        HStack {
                                            Text("Set \(set.setNumber)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 50, alignment: .leading)
                                            
                                            Spacer()
                                            
                                            if set.weight > 0 {
                                                Text("\(Int(set.weight)) lbs")
                                                    .font(.caption)
                                                    .fontWeight(isBest ? .bold : .medium)
                                            }
                                            
                                            Text("×")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Text("\(set.reps) reps")
                                                .font(.caption)
                                                .fontWeight(isBest ? .bold : .medium)
                                            
                                            if isBest {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(accentColor)
                                            }
                                        }
                                        .foregroundColor(isBest ? accentColor : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(
                                            isBest ? RoundedRectangle(cornerRadius: 6)
                                                .fill(accentColor.opacity(0.1)) : nil
                                        )
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 25)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.15), Color(white: 0.12)]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
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
        .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
    }
    
    private var categoryColor: Color {
        switch workoutExercise.safeCategory.lowercased() {
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
    
    private var categoryGradient: [Color] {
        switch workoutExercise.safeCategory.lowercased() {
        case "chest":
            return [Color.purple, Color.pink]
        case "back":
            return [Color.blue, Color.cyan]
        case "legs":
            return [Color.green, Color.teal]
        case "shoulders":
            return [Color.orange, Color.yellow]
        case "arms":
            return [Color.purple, Color.indigo]
        case "core":
            return [Color.yellow, Color.orange]
        case "full body":
            return [Color.pink, Color.red]
        default:
            return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
    
    private var categoryIcon: String {
        let exerciseName = workoutExercise.safeDisplayName.lowercased()
        
        if exerciseName.contains("dumbbell") {
            return "dumbbell.fill"
        } else if exerciseName.contains("barbell") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("cable") {
            return "dot.radiowaves.left.and.right"
        } else if exerciseName.contains("push") && exerciseName.contains("up") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("pull") && (exerciseName.contains("up") || exerciseName.contains("chin")) {
            return "figure.climbing"
        } else if exerciseName.contains("squat") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("deadlift") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("row") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("press") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("curl") {
            return "figure.arms.open"
        } else if exerciseName.contains("extension") {
            return "figure.arms.open"
        } else if exerciseName.contains("raise") {
            return "arrow.up"
        } else if exerciseName.contains("fly") || exerciseName.contains("flye") {
            return "arrow.left.and.right"
        } else if exerciseName.contains("plank") {
            return "figure.core.training"
        } else if exerciseName.contains("crunch") || exerciseName.contains("sit") {
            return "figure.core.training"
        } else if exerciseName.contains("leg") {
            return "figure.walk"
        } else if exerciseName.contains("lunge") {
            return "figure.walk"
        } else if exerciseName.contains("run") || exerciseName.contains("jog") {
            return "figure.run"
        } else if exerciseName.contains("jump") {
            return "figure.jumprope"
        } else if exerciseName.contains("bike") || exerciseName.contains("cycle") {
            return "figure.outdoor.cycle"
        }
        
        switch workoutExercise.safeCategory.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.strengthtraining.traditional"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "figure.arms.open"
        case "core": return "figure.core.training"
        case "cardio": return "figure.run"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

// MARK: - Repeat Workout Preview View

struct RepeatWorkoutPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let workout: Workout
    let exercises: [Exercise]
    let accentColor: Color
    
    @State private var showingExerciseDetail = false
    @State private var selectedExercise: Exercise?
    
    private var accentGradient: [Color] {
        [accentColor, accentColor == .green ? .teal : accentColor.opacity(0.7)]
    }
    
    private var workoutExercises: [WorkoutExercise] {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        return exercises.sorted { ($0.order) < ($1.order) }
    }
    
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient matching autogen style
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [accentColor.opacity(0.2), accentColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [accentColor.opacity(0.3), accentColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Workout Header Card (matching autogen style)
                    workoutHeaderCard
                    
                    // Exercise list section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Today's Exercises")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.caption2)
                                Text("to swap")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        
                        VStack(spacing: 10) {
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                Button(action: {
                                    selectedExercise = exercise
                                    showingExerciseDetail = true
                                }) {
                                    RepeatExerciseCard(
                                        number: index + 1,
                                        exercise: exercise,
                                        accentColor: accentColor
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Your Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showingExerciseDetail) {
            if let exercise = selectedExercise {
                NavigationView {
                    ExerciseDetailView(exercise: exercise)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingExerciseDetail = false
                                }
                            }
                        }
                }
            }
        }
        .onChange(of: workoutManager.isWorkoutActive) { oldValue, isActive in
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔁 [REPEAT PREVIEW] isWorkoutActive changed: \(oldValue) → \(isActive)")
            
            if isActive {
                print("🔁 [REPEAT PREVIEW] Workout became active - dismissing IMMEDIATELY")
                // Dismiss immediately to prevent any flicker
                dismiss()
                print("🔁 [REPEAT PREVIEW] Dismiss called")
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
        .onAppear {
            SessionLogManager.shared.logScreen(.workoutHistoryDetail, metadata: [
                "workout_date": workout.date?.description ?? "unknown",
                "exercise_count": workout.exercises?.count ?? 0
            ])
            print("🔁 [REPEAT PREVIEW] View appeared - isWorkoutActive: \(workoutManager.isWorkoutActive)")
            showGoButton()
        }
        .onDisappear {
            print("🔁 [REPEAT PREVIEW] View disappeared")
            GoButtonState.shared.hide()
        }
    }
    
    // MARK: - Workout Header Card
    private var workoutHeaderCard: some View {
        HStack(spacing: 14) {
            // Workout badge with repeat icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: accentGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(cleanWorkoutName(workout.name ?? "Workout"))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Label("\(exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                    if totalSets > 0 {
                        Label("\(totalSets) sets", systemImage: "repeat")
                    }
                    Label("\(formatDuration(Int(workout.duration)))", systemImage: "clock.fill")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 3)
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
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
    
    private func showGoButton() {
        GoButtonState.shared.show(
            primaryColor: accentColor,
            secondaryColor: accentGradient[1]
        ) {
            self.startWorkout()
        }
    }
    
    private func startWorkout() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔁 [REPEAT WORKOUT] START FLOW BEGIN")
        print("🔁 [REPEAT WORKOUT] Current isWorkoutActive: \(workoutManager.isWorkoutActive)")
        print("🔁 [REPEAT WORKOUT] Exercises count: \(exercises.count)")
        
        // Create a new workout for repeating
        let newWorkout = Workout(context: viewContext)
        newWorkout.id = UUID()
        newWorkout.name = workout.name ?? "Repeated Workout"
        newWorkout.date = Date()
        newWorkout.isCompleted = false
        
        print("🔁 [REPEAT WORKOUT] Created new workout: \(newWorkout.name ?? "")")
        print("🔁 [REPEAT WORKOUT] Calling workoutManager.startWorkout()...")
        
        // Start workout - WorkoutManager will automatically show ActiveWorkoutView
        workoutManager.startWorkout(workout: newWorkout, exercises: exercises)
        
        print("🔁 [REPEAT WORKOUT] workoutManager.startWorkout() called")
        print("🔁 [REPEAT WORKOUT] New isWorkoutActive: \(workoutManager.isWorkoutActive)")
        print("🔁 [REPEAT WORKOUT] Current workout: \(workoutManager.currentWorkout?.name ?? "nil")")
        print("🔁 [REPEAT WORKOUT] Navigation should auto-clear - NOT dismissing manually")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - Repeat Exercise Card
struct RepeatExerciseCard: View {
    let number: Int
    let exercise: Exercise
    let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    private var categoryGradient: [Color] {
        switch exercise.category?.lowercased() {
        case "chest": return [.purple, .pink]
        case "back": return [.blue, .cyan]
        case "legs": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "arms": return [.purple, .indigo]
        case "core": return [.yellow, .orange]
        default: return [accentColor, accentColor.opacity(0.7)]
        }
    }
    
    private var categoryIcon: String {
        if let exerciseName = exercise.name?.lowercased() {
            if exerciseName.contains("dumbbell") { return "dumbbell.fill" }
            else if exerciseName.contains("barbell") { return "figure.strengthtraining.traditional" }
            else if exerciseName.contains("cable") { return "dot.radiowaves.left.and.right" }
        }
        
        switch exercise.category?.lowercased() {
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
            // Exercise icon matching library style
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
                
                if exercise.category?.lowercased() == "core" {
                    CoreIcon(size: 22, color: .white)
                } else {
                    Image(systemName: categoryIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let category = exercise.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(categoryGradient[0])
                            .fontWeight(.medium)
                    }
                    
                    if let equipment = exercise.equipment {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(equipment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 25)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.15), Color(white: 0.12)]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
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
        .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
    }
}

