import SwiftUI
import CoreData

struct FavoriteRoutinesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isFavorite == YES AND isCompleted == YES"),
        animation: .none  // Disable animation for faster list
    )
    private var favoriteWorkouts: FetchedResults<Workout>
    
    // Filter to show only unique workout names (most recent of each)
    private var uniqueFavoriteWorkouts: [Workout] {
        var seen = Set<String>()
        var unique: [Workout] = []
        
        for workout in favoriteWorkouts {
            let fullName = workout.name ?? "Workout"
            // Clean the name by removing date suffixes like " - Dec 7"
            let cleanName = cleanWorkoutName(fullName)
            
            if !seen.contains(cleanName) {
                seen.insert(cleanName)
                unique.append(workout)
            }
        }
        
        return unique
    }
    
    // Remove date suffix from workout name (e.g., "Workout - Dec 7" -> "Workout")
    private func cleanWorkoutName(_ name: String) -> String {
        // Remove patterns like " - Dec 7", " - January 15", etc.
        if let range = name.range(of: " - ", options: .backwards) {
            let potentialDate = String(name[range.upperBound...])
            // Check if it looks like a date (contains a month abbreviation or number)
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if months.contains(where: { potentialDate.contains($0) }) || potentialDate.first?.isNumber == true {
                return String(name[..<range.lowerBound])
            }
        }
        return name
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.04, green: 0.04, blue: 0.06)]
                    : [Color.orange.opacity(0.15), Color.yellow.opacity(0.08), Color(.systemGroupedBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if uniqueFavoriteWorkouts.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(uniqueFavoriteWorkouts, id: \.id) { workout in
                            FavoriteWorkoutCard(
                                workout: workout,
                                onStart: {
                                    startFavoriteWorkout(workout)
                                },
                                onUnfavorite: {
                                    unfavoriteWorkout(workout)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("Favorite Routines")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !uniqueFavoriteWorkouts.isEmpty {
                    Text("\(uniqueFavoriteWorkouts.count) routine\(uniqueFavoriteWorkouts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange.opacity(0.2), Color.yellow.opacity(0.1)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "star.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 12) {
                Text("No Favorite Routines")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("During a workout, tap the star icon in the header to save it as a favorite routine for quick access later.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding()
    }
    
    private func startFavoriteWorkout(_ workout: Workout) {
        // Get exercises from the favorite workout
        guard let workoutExercises = workout.exercises?.allObjects as? [WorkoutExercise] else {
            print("❌ No exercises found in favorite workout")
            return
        }
        
        // Sort by order and extract the Exercise entities
        let sortedExercises = workoutExercises
            .sorted { $0.order < $1.order }
            .compactMap { $0.exercise }
        
        guard !sortedExercises.isEmpty else {
            print("❌ No valid exercises in favorite workout")
            return
        }
        
        // Create a new workout based on the favorite
        let newWorkout = Workout(context: viewContext)
        newWorkout.id = UUID()
        newWorkout.name = workout.name ?? "Favorite Workout"
        newWorkout.date = Date()
        newWorkout.isCompleted = false
        newWorkout.isFavorite = true // Keep it favorited
        newWorkout.user = userManager.currentUser
        
        print("⭐ Starting favorite workout: \(newWorkout.name ?? "") with \(sortedExercises.count) exercises")
        
        // Start workout using WorkoutManager
        workoutManager.startWorkout(workout: newWorkout, exercises: sortedExercises)
        
        // Dismiss this view
        dismiss()
    }
    
    private func unfavoriteWorkout(_ workout: Workout) {
        withAnimation {
            let workoutName = workout.name ?? ""
            let cleanName = cleanWorkoutName(workoutName)
            
            // Unfavorite ALL workouts with the same cleaned name
            for favoriteWorkout in favoriteWorkouts {
                let favoriteCleanName = cleanWorkoutName(favoriteWorkout.name ?? "")
                if favoriteCleanName == cleanName {
                    favoriteWorkout.isFavorite = false
                    
                    // Sync to cloud if authenticated
                    if SupabaseManager.shared.isAuthenticated, let workoutId = favoriteWorkout.id?.uuidString {
                        Task {
                            do {
                                try await SupabaseManager.shared.removeFavoriteWorkout(
                                    originalWorkoutId: workoutId
                                )
                            } catch {
                                print("⚠️ Failed to sync workout unfavorite to cloud: \(error)")
                            }
                        }
                    }
                }
            }
            
            do {
                try viewContext.save()
                print("⭐ Unfavorited all workouts named: \(cleanName)")
            } catch {
                print("❌ Error unfavoriting workout: \(error)")
            }
        }
    }
}

struct FavoriteWorkoutCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let workout: Workout
    let onStart: () -> Void
    let onUnfavorite: () -> Void
    
    @State private var showingDeleteConfirmation = false
    @State private var isExpanded = false
    
    private var workoutExercises: [WorkoutExercise] {
        guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else {
            return []
        }
        return exercises.sorted { $0.order < $1.order }
    }
    
    private var exerciseCount: Int {
        workoutExercises.count
    }
    
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.count
        }
    }
    
    private var muscleGroups: [String] {
        var groups = Set<String>()
        for we in workoutExercises {
            if let muscleGroupsArray = we.exercise?.muscleGroups as? [String] {
                for group in muscleGroupsArray {
                    groups.insert(group)
                }
            }
        }
        return Array(groups).sorted()
    }
    
    private var categoryColor: Color {
        let firstMuscle = muscleGroups.first?.lowercased() ?? ""
        switch firstMuscle {
        case "chest": return .red
        case "back": return .blue
        case "legs", "quads", "hamstrings", "glutes": return .green
        case "shoulders": return .orange
        case "arms", "biceps", "triceps": return .purple
        case "core", "abs": return .yellow
        default: return .cyan
        }
    }
    
    // Clean workout name by removing date suffix
    private var cleanWorkoutName: String {
        let name = workout.name ?? "Workout"
        // Remove patterns like " - Dec 7", " - January 15", etc.
        if let range = name.range(of: " - ", options: .backwards) {
            let potentialDate = String(name[range.upperBound...])
            // Check if it looks like a date (contains a month abbreviation or number)
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if months.contains(where: { potentialDate.contains($0) }) || potentialDate.first?.isNumber == true {
                return String(name[..<range.lowerBound])
            }
        }
        return name
    }
    
    var body: some View {
        Button(action: {
            HapticManager.selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            VStack(spacing: 0) {
                // Main card content
                VStack(alignment: .leading, spacing: 16) {
                    // Header: Icon + Title + Date + Chevron + Star
                    HStack(spacing: 12) {
                        // Hollow transparent icon with gradient ring and star
                        ZStack {
                            // Hollow circle with gradient stroke - fully transparent inside
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [categoryColor, categoryColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 52, height: 52)
                            
                            // Gradient star floating inside
                            Image(systemName: "star.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [categoryColor, categoryColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        // Title and date
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cleanWorkoutName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            if let date = workout.date {
                                Text("Last performed: \(formatShortDate(date))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Chevron and unfavorite star
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            
                            Button(action: {
                                HapticManager.selectionChanged()
                                showingDeleteConfirmation = true
                            }) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.yellow)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 12)
                    
                    // Stats grid (matching Recent Activity style)
                    HStack(spacing: 0) {
                        // Duration
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(categoryColor)
                                Text(formatDuration(Int(workout.duration)))
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
                                    .foregroundColor(categoryColor)
                                Text("\(exerciseCount)")
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
                                    .foregroundColor(categoryColor)
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
                        
                        // XP
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                Text("+\(Int(workout.xpEarned))")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("XP")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Muscle group tags (like Recent Activity)
                    if !muscleGroups.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(muscleGroups.prefix(2), id: \.self) { group in
                                Text(group)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(categoryColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(categoryColor.opacity(0.12))
                                    )
                            }
                            Spacer()
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(16)
                
                // Expandable exercises list
                if isExpanded && !workoutExercises.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        
                        VStack(spacing: 8) {
                            ForEach(Array(workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                                if let exercise = workoutExercise.exercise {
                                    ZStack(alignment: .trailing) {
                                        // Exercise card using same styling as library
                                        CompactExerciseRowContent(exercise: exercise, showChevron: false)
                                        
                                        // Set count badge overlay
                                        if let sets = workoutExercise.sets?.allObjects as? [WorkoutSet], !sets.isEmpty {
                                            Text("\(sets.count)")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(categoryColor)
                                                .frame(width: 24, height: 24)
                                                .background(
                                                    Circle()
                                                        .fill(categoryColor.opacity(0.15))
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(categoryColor.opacity(0.3), lineWidth: 1)
                                                )
                                                .padding(.trailing, 20)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                }
                
                // Start Routine button
                Button(action: { HapticManager.impact(.medium); onStart() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Start Routine")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [categoryColor, categoryColor.opacity(0.8)]),
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
                                    gradient: Gradient(colors: [categoryColor, categoryColor.opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            ZStack {
                // Bottom shadow layer - category colored
                RoundedRectangle(cornerRadius: 20)
                    .fill(categoryColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 18)
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
                            colors: [categoryColor.opacity(0.3), categoryColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: categoryColor.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 8, x: 0, y: 4)
        .confirmationDialog(
            "Remove from Favorites?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                onUnfavorite()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This routine will be removed from your favorites, but the workout history will be preserved.")
        }
    }

    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes == 0 {
            return "0m"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
    
    private func formatShortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today · \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    NavigationStack {
        FavoriteRoutinesView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environmentObject(UserManager())
            .environmentObject(WorkoutManager.shared)
    }
}

