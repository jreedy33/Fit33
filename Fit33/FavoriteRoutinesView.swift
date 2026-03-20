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
            // Animated orb background (consistent with workout screens)
            AnimatedOrbBackground.workout(colorScheme: colorScheme)
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
                    .padding(.horizontal, Spacing.md)
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
                    .padding(.horizontal, Spacing.xl)
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

// MARK: - Favorite Workout Card (Identical to RecentWorkoutCard styling + expandable exercises)
struct FavoriteWorkoutCard: View {
    let workout: Workout
    let onStart: () -> Void
    let onUnfavorite: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var showingDeleteConfirmation = false
    @State private var isFavorite: Bool = true
    @State private var isProcessing: Bool = false
    @State private var isExpanded: Bool = false
    
    // Get exercises from workout
    private var workoutExercises: [WorkoutExercise] {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        return exercises.sorted { ($0.order) < ($1.order) }
    }
    
    // Smart workout name based on muscle groups
    private var smartWorkoutName: String {
        if let name = workout.name, !name.isEmpty {
            let cleanName = cleanWorkoutName(name)
            if !cleanName.lowercased().contains("workout") || cleanName.count > 15 {
                return cleanName
            }
        }
        return generateMuscleBasedName()
    }
    
    private func generateMuscleBasedName() -> String {
        var muscleCount: [String: Int] = [:]
        
        for workoutExercise in workoutExercises {
            for muscle in workoutExercise.safeMuscleGroups {
                muscleCount[muscle.lowercased(), default: 0] += 1
            }
        }
        
        let sortedMuscles = muscleCount.sorted { $0.value > $1.value }
        let timeOfDay = getTimeOfDay(for: workout.date ?? Date())
        
        if sortedMuscles.isEmpty {
            return "\(timeOfDay) Workout"
        }
        
        let total = sortedMuscles.reduce(0) { $0 + $1.value }
        if let topMuscle = sortedMuscles.first, total > 0, Double(topMuscle.value) / Double(total) > 0.5 {
            return "\(timeOfDay) \(topMuscle.key.capitalized)"
        }
        
        if sortedMuscles.count >= 2 {
            return "\(sortedMuscles[0].key.capitalized) & \(sortedMuscles[1].key.capitalized)"
        }
        
        return "\(timeOfDay) \(sortedMuscles[0].key.capitalized)"
    }
    
    private func getTimeOfDay(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 5 && hour < 12 { return "Morning" }
        else if hour >= 12 && hour < 17 { return "Afternoon" }
        else { return "Evening" }
    }
    
    private var workoutGradient: [Color] {
        let muscles = workoutExercises.compactMap { $0.safeMuscleGroups.first?.lowercased() }
        let primaryMuscle = muscles.first ?? ""
        
        switch primaryMuscle {
        case "chest": return [.red, .orange]
        case "back": return [.blue, .cyan]
        case "legs", "quads", "hamstrings", "glutes": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "biceps", "triceps", "arms": return [.purple, .pink]
        case "core", "abs": return [.yellow, .orange]
        default:
            let hour = Calendar.current.component(.hour, from: workout.date ?? Date())
            if hour >= 5 && hour < 12 { return [.orange, .yellow] }
            else if hour >= 12 && hour < 17 { return [.blue, .cyan] }
            else { return [.purple, .pink] }
        }
    }
    
    private var exerciseCount: Int { workoutExercises.count }
    
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
    }
    
    private var topMuscles: [String] {
        var muscleCount: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0
        for workoutExercise in workoutExercises {
            for muscle in workoutExercise.safeMuscleGroups {
                let key = muscle.lowercased()
                muscleCount[key, default: 0] += 1
                if firstSeen[key] == nil {
                    firstSeen[key] = order
                    order += 1
                }
            }
        }
        return muscleCount.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return (firstSeen[$0.key] ?? 0) < (firstSeen[$1.key] ?? 0)
        }.prefix(2).map { $0.key }
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
    
    private func toggleFavorite() {
        guard !isProcessing else { return }
        isProcessing = true
        
        HapticManager.impact(.light)
        showingDeleteConfirmation = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isProcessing = false
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content - tappable to expand
            Button(action: {
                HapticManager.selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top section - Title and Date
                    HStack(alignment: .top, spacing: 12) {
                        // Hollow transparent icon with gradient ring and checkmark
                        ZStack {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: workoutGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: workoutGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(smartWorkoutName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Text(formatSmartDate(workout.date ?? Date()))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Favorite star button - always yellow (these are favorites)
                        Button(action: { toggleFavorite() }) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.yellow)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isProcessing)
                        .padding(.trailing, 8)
                        
                        // Expand/collapse chevron
                        Image(systemName: "chevron.down")
                            .font(.ds_labelMedium)
                            .foregroundColor(.secondary.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    
                    Divider()
                        .padding(.vertical, Spacing.sm)
                    
                    // Bottom section - Stats
                    HStack(spacing: 0) {
                        // Duration
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.ds_bodySmall)
                                    .foregroundColor(workoutGradient[0])
                                Text(formatDuration(Int(workout.duration)))
                                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                                    .font(.ds_bodySmall)
                                    .foregroundColor(workoutGradient[0])
                                Text("\(exerciseCount)")
                                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                                    .font(.ds_bodySmall)
                                    .foregroundColor(workoutGradient[0])
                                Text("\(totalSets)")
                                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                                    .font(.ds_bodySmall)
                                    .foregroundColor(.orange)
                                Text("+\(Int(workout.xpEarned))")
                                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                                    .foregroundColor(.primary)
                            }
                            Text("XP")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Muscle tags (if available)
                    if !topMuscles.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(topMuscles, id: \.self) { muscle in
                                Text(muscle)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(workoutGradient[0])
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(
                                        Capsule()
                                            .fill(workoutGradient[0].opacity(0.12))
                                    )
                            }
                            Spacer()
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(Spacing.md)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expandable exercise list
            if isExpanded && !workoutExercises.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, Spacing.md)
                    
                    // Exercise list - matching ExerciseLibrary card style
                    VStack(spacing: 10) {
                        ForEach(Array(workoutExercises.prefix(8).enumerated()), id: \.element.id) { index, workoutExercise in
                            if let exercise = workoutExercise.exercise {
                                // Use the exact same style as ExerciseLibrary
                                FavoriteExerciseCard(
                                    exercise: exercise,
                                    setCount: (workoutExercise.sets?.allObjects as? [WorkoutSet])?.count ?? 0
                                )
                            } else {
                                // Fallback for exercises without relationship - match library style
                                FavoriteExerciseFallbackCard(
                                    exerciseName: workoutExercise.safeDisplayName,
                                    setCount: (workoutExercise.sets?.allObjects as? [WorkoutSet])?.count ?? 0
                                )
                            }
                        }
                        
                        // Show more indicator if there are more exercises
                        if workoutExercises.count > 8 {
                            Text("+\(workoutExercises.count - 8) more exercises")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    
                    // Start Routine button
                    Button(action: {
                        HapticManager.impact(.medium)
                        onStart()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.ds_bodySmall).fontWeight(.bold)
                            Text("Start Routine")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: workoutGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .shadow(color: workoutGradient[0].opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - color glow
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(workoutGradient[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 6)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 3)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [workoutGradient[0].opacity(colorScheme == .dark ? 0.4 : 0.3), workoutGradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: workoutGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
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
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today · \(formatTime(date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday · \(formatTime(date))"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes == 0 { return "0m" }
        else if minutes < 60 { return "\(minutes)m" }
        else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// MARK: - Favorite Exercise Card (Matches ExerciseLibrary CompactExerciseRowContent exactly)
struct FavoriteExerciseCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let exercise: Exercise
    var setCount: Int = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // Compact exercise icon with vibrant gradient (matches library)
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
                        .font(.ds_labelLarge)
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
                            .foregroundColor(categoryColor)
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
            
            // Sets count badge (instead of chevron)
            if setCount > 0 {
                Text("\(setCount) sets")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(categoryColor)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(categoryColor.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
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
        switch exercise.category?.lowercased() {
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
    
    // Exact gradients matching the exercise library style
    private var categoryGradient: [Color] {
        switch exercise.category?.lowercased() {
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
            return [Color.gray, Color.secondary]
        }
    }
    
    private var categoryIcon: String {
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

// MARK: - Fallback Exercise Card (for exercises without Core Data relationship)
struct FavoriteExerciseFallbackCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let exerciseName: String
    var setCount: Int = 0
    
    // Try to get exercise from library
    private var libraryExercise: Exercise? {
        ExerciseLibraryService.shared.getExercise(byName: exerciseName)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Compact exercise icon with vibrant gradient
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
                
                if categoryName.lowercased() == "core" {
                    CoreIcon(size: 22, color: .white)
                } else {
                    Image(systemName: categoryIcon)
                        .font(.ds_labelLarge)
                        .foregroundColor(.white)
                }
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(categoryName)
                        .font(.caption)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                    
                    if let equipment = equipmentName {
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
            
            // Sets count badge
            if setCount > 0 {
                Text("\(setCount) sets")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(categoryColor)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(categoryColor.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                // Bottom shadow layer
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight
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
    
    private var categoryName: String {
        libraryExercise?.category ?? "Exercise"
    }
    
    private var equipmentName: String? {
        libraryExercise?.equipment
    }
    
    private var categoryColor: Color {
        switch categoryName.lowercased() {
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
        switch categoryName.lowercased() {
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
            return [Color.gray, Color.secondary]
        }
    }
    
    private var categoryIcon: String {
        switch categoryName.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
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

