import SwiftUI
import CoreData

struct RecentWorkoutCard: View {
    let workout: Workout
    var isMostRecent: Bool = false // Whether this is the most recent workout (gets special outline)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    // Local state for immediate UI feedback (prevents lag)
    @State private var isFavorite: Bool = false
    @State private var isProcessing: Bool = false
    
    // Get exercises from workout
    private var workoutExercises: [WorkoutExercise] {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        return exercises.sorted { ($0.order) < ($1.order) }
    }
    
    // Smart workout name based on muscle groups
    private var smartWorkoutName: String {
        // First check if it's a program day name (not generic)
        if let name = workout.name, !name.isEmpty {
            let cleanName = cleanWorkoutName(name)
            // If it's a meaningful program name (not just "Workout" or generic)
            if !cleanName.lowercased().contains("workout") || cleanName.count > 15 {
                return cleanName
            }
        }
        
        // Otherwise, generate smart name from muscle groups
        return generateMuscleBasedName()
    }
    
    private func generateMuscleBasedName() -> String {
        var muscleCount: [String: Int] = [:]
        
        for workoutExercise in workoutExercises {
            // Use safeMuscleGroups to handle nil exercise relationships
            for muscle in workoutExercise.safeMuscleGroups {
                muscleCount[muscle.lowercased(), default: 0] += 1
            }
        }
        
        // Sort by count
        let sortedMuscles = muscleCount.sorted { $0.value > $1.value }
        let timeOfDay = getTimeOfDay(for: workout.date ?? Date())
        
        if sortedMuscles.isEmpty {
            return "\(timeOfDay) Workout"
        }
        
        // Check if one muscle dominates (>50% of exercises)
        let total = sortedMuscles.reduce(0) { $0 + $1.value }
        if let topMuscle = sortedMuscles.first, total > 0, Double(topMuscle.value) / Double(total) > 0.5 {
            return "\(timeOfDay) \(topMuscle.key.capitalized)"
        }
        
        // Otherwise, combine top 2 muscles
        if sortedMuscles.count >= 2 {
            return "\(sortedMuscles[0].key.capitalized) & \(sortedMuscles[1].key.capitalized)"
        }
        
        guard !sortedMuscles.isEmpty else { return "\(timeOfDay) Workout" }
        return "\(timeOfDay) \(sortedMuscles[0].key.capitalized)"
    }
    
    private func getTimeOfDay(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 5 && hour < 12 {
            return "Morning"
        } else if hour >= 12 && hour < 17 {
            return "Afternoon"
        } else {
            return "Evening"
        }
    }
    
    private var workoutGradient: [Color] {
        // Color based on primary muscle group (use safeMuscleGroups for nil-safety)
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
    
    // Exercise count
    private var exerciseCount: Int {
        workoutExercises.count
    }
    
    // Total sets completed
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
    }
    
    // Total volume
    private var totalVolume: Double {
        workoutExercises.reduce(0.0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }
    
    private var formattedCalories: String {
        let cal = Int(workout.caloriesBurned)
        return cal > 0 ? "\(cal)" : "--"
    }
    
    // Top muscles worked (for preview)
    private var topMuscles: [String] {
        var muscleCount: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0
        for workoutExercise in workoutExercises {
            for muscle in workoutExercise.safeMuscleGroups {
                let key = muscle.capitalized
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
    
    // Toggle favorite status with debounce protection
    private func toggleFavorite() {
        // Prevent rapid double-taps
        guard !isProcessing else { return }
        isProcessing = true
        
        // Immediate UI feedback
        isFavorite.toggle()
        
        // Haptic feedback immediately
        HapticManager.impact(.light)
        
        // Update Core Data
        workout.isFavorite = isFavorite
        
        do {
            try viewContext.save()
            
            // Log the action
            SessionLogManager.shared.log(.info, category: .userAction, message: isFavorite ? "⭐ Workout favorited" : "☆ Workout unfavorited", metadata: [
                "workout_id": workout.objectID.uriRepresentation().absoluteString,
                "workout_name": smartWorkoutName
            ])
        } catch {
            AppLogger.error("Error saving favorite status: \(error.localizedDescription)", category: .ui)
            // Revert on error
            isFavorite.toggle()
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            isProcessing = false
        }
    }
    
    private func strengthStatColumn(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.ds_caption)
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.subheadline).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    var body: some View {
        NavigationLink(value: workout) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Spacing.sm) {
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
                            .font(.ds_heading3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: workoutGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(smartWorkoutName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(formatSmartDate(workout.date ?? Date()))
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                        
                        if !topMuscles.isEmpty {
                            HStack(spacing: Spacing.xxs) {
                                ForEach(topMuscles, id: \.self) { muscle in
                                    Text(muscle)
                                        .font(.ds_caption)
                                        .foregroundColor(workoutGradient[0])
                                        .padding(.horizontal, Spacing.xs)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(workoutGradient[0].opacity(0.12))
                                        )
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { toggleFavorite() }) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.ds_heading3)
                            .foregroundColor(isFavorite ? .yellow : .gray.opacity(0.4))
                            .animation(.easeInOut(duration: 0.15), value: isFavorite)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isProcessing)
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                Divider()
                    .padding(.vertical, Spacing.sm)
                
                HStack(spacing: 0) {
                    strengthStatColumn(icon: "clock.fill", iconColor: workoutGradient[0], value: formatDuration(workout.duration), label: "Duration")
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 35)
                    strengthStatColumn(icon: "figure.strengthtraining.traditional", iconColor: workoutGradient[0], value: "\(exerciseCount)", label: "Exercises")
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 35)
                    strengthStatColumn(icon: "repeat", iconColor: workoutGradient[0], value: "\(totalSets)", label: "Sets")
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 35)
                    strengthStatColumn(icon: "flame.fill", iconColor: .orange, value: formattedCalories, label: "Calories")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: workoutGradient[0])
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(alignment: .topTrailing) {
            reactionStickerOverlay
        }
        .onAppear {
            isFavorite = workout.isFavorite
        }
        .onChange(of: workout.isFavorite) { _, newValue in
            if isFavorite != newValue {
                isFavorite = newValue
            }
        }
    }
    
    /// Reaction sticker: shows when a friend sent an emoji on this workout
    @ViewBuilder
    private var reactionStickerOverlay: some View {
        let workoutIdStr = workout.objectID.uriRepresentation().lastPathComponent
        let matchingReactions = ActivityFeedService.shared.myReactions.filter { $0.workoutId == workoutIdStr }
        
        if let reaction = matchingReactions.first {
            HStack(spacing: 3) {
                Text(reaction.emoji)
                    .font(.ds_bodyRegular)
                Text("\(reaction.senderFirstName) sent you \(reaction.emoji)")
                    .font(.ds_caption)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .orange.opacity(0.3), radius: 6, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .rotationEffect(.degrees(-3))
            .offset(x: -8, y: -6)
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
            formatter.dateFormat = "EEEE" // Day name
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func getDayName(for date: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Full day name
        return dayFormatter.string(from: date)
    }
    
    private func getWorkoutType(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        // Determine time of day
        let timeOfDay: String
        if hour >= 5 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour >= 12 && hour < 17 {
            timeOfDay = "Afternoon"
        } else {
            timeOfDay = "Evening"
        }
        
        return "\(timeOfDay) workout"
    }
    
    private func generateSmartWorkoutTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        // Get day name
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Full day name
        let dayName = dayFormatter.string(from: date)
        
        // Determine time of day
        let timeOfDay: String
        if hour >= 5 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour >= 12 && hour < 17 {
            timeOfDay = "Afternoon"
        } else {
            timeOfDay = "Evening"
        }
        
        // Create smart title
        return "\(dayName) \(timeOfDay) Workout"
    }
    
    private func formatCompactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func cleanWorkoutName(_ name: String) -> String {
        // Remove any date suffixes like " - Nov 22" or " - Nov"
        var cleanName = name
        
        // Pattern to match " - Month" or " - Month Day" at the end
        let patterns = [
            " - [A-Z][a-z]+ \\d+$",  // Matches " - Nov 22"
            " - [A-Z][a-z]+$",       // Matches " - Nov"
            " - \\d{1,2}/\\d{1,2}$", // Matches " - 11/22"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleanName.startIndex..., in: cleanName)
                cleanName = regex.stringByReplacingMatches(in: cleanName, range: range, withTemplate: "")
            }
        }
        
        return cleanName.trimmingCharacters(in: .whitespaces)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        // Add ordinal suffix
        let day = Calendar.current.component(.day, from: date)
        let ordinalFormatter = NumberFormatter()
        ordinalFormatter.numberStyle = .ordinal
        let ordinalDay = ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)
        let year = Calendar.current.component(.year, from: date)
        
        return "\(month) \(ordinalDay), \(year)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ duration: Int32) -> String {
        let minutes = duration / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// MARK: - Recent Cardio Workout Card
struct RecentCardioWorkoutCard: View {
    let cardioWorkout: CardioWorkoutDTO
    var isMostRecent: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Parse completed date (uses centralized cached formatters)
    private var completedDate: Date {
        return ISO8601Parser.parse(cardioWorkout.completedAt, fallback: Date())
    }
    
    // Activity type display name and icon
    private var activityInfo: (name: String, icon: String, color: Color) {
        let type = cardioWorkout.activityType.lowercased().replacingOccurrences(of: "_", with: " ")
        switch type {
        case "outdoor run", "run":
            return ("Outdoor Run", "figure.run", .green)
        case "treadmill":
            return ("Treadmill", "figure.walk.motion", .orange)
        case "walk":
            return ("Walk", "figure.walk", .blue)
        case "indoor cycle", "indoor_cycle":
            return ("Indoor Cycle", "bicycle", .cyan)
        case "outdoor cycle", "outdoor_cycle":
            return ("Outdoor Cycle", "bicycle", .green)
        case "rowing":
            return ("Rowing", "figure.rower", .blue)
        case "elliptical":
            return ("Elliptical", "figure.elliptical", .purple)
        case "stair climber", "stair_climber":
            return ("Stair Climber", "figure.stairs", .orange)
        case "hiit":
            return ("HIIT", "flame.fill", .red)
        case "swimming":
            return ("Swimming", "figure.pool.swim", .cyan)
        default:
            return (type.capitalized, "figure.run", .green)
        }
    }
    
    // Format duration
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
    
    private var usesMetric: Bool {
        Locale.current.measurementSystem == .metric
    }
    
    // Format distance in locale-appropriate units
    private func formatDistance(_ meters: Double) -> String {
        if usesMetric {
            let km = meters / 1000
            if km < 1 {
                return String(format: "%.0fm", meters)
            }
            return String(format: "%.1fkm", km)
        } else {
            let miles = meters / 1609.344
            if miles < 0.1 {
                let feet = meters * 3.28084
                return String(format: "%.0fft", feet)
            }
            return String(format: "%.1fmi", miles)
        }
    }
    
    private var distanceLabel: String {
        usesMetric ? "Distance" : "Distance"
    }
    
    private var paceLabel: String {
        usesMetric ? "/km" : "/mi"
    }
    
    // Format pace in locale-appropriate units
    private func formatPace(_ pace: Double?) -> String {
        guard let pace = pace, pace > 0 else { return "--" }
        let paceValue = usesMetric ? pace : pace * 1.60934
        let minutes = Int(paceValue)
        let seconds = Int((paceValue - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var isFromHealthKit: Bool {
        cardioWorkout.source == "healthkit"
    }
    
    private var sourceDisplayName: String {
        if cardioWorkout.isFromStrava { return "Strava" }
        if isFromHealthKit {
            if let name = cardioWorkout.workoutName {
                if name.contains("Nike") { return "Nike Run Club" }
                if name.contains("Apple") { return "Apple Watch" }
                if name.contains("Peloton") { return "Peloton" }
            }
            return "Health"
        }
        return "Cardio"
    }
    
    @ViewBuilder
    private var sourceBadge: some View {
        if cardioWorkout.isFromStrava {
            HStack(spacing: 3) {
                Image(systemName: "figure.run")
                    .font(.system(size: 9, weight: .bold))
                Text("Strava")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 252/255, green: 76/255, blue: 2/255), Color(red: 252/255, green: 100/255, blue: 30/255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        } else if isFromHealthKit {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(sourceDisplayName)
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.9), Color.pink.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        } else {
            Text("Cardio")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(activityInfo.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(activityInfo.color.opacity(0.15))
                )
        }
    }
    
    private func cardioStatColumn(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.ds_caption)
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.subheadline).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 35)
    }
    
    var body: some View {
        NavigationLink(value: cardioWorkout) {
            VStack(alignment: .leading, spacing: 0) {
                // Top section - Title and Date
                HStack(alignment: .top, spacing: 12) {
                    // Activity icon with gradient ring
                    ZStack {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [activityInfo.color, activityInfo.color.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 52, height: 52)
                        
                        Image(systemName: activityInfo.icon)
                            .font(.ds_heading2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [activityInfo.color, activityInfo.color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Activity name with source badge (Strava or Cardio)
                        HStack(spacing: 8) {
                            Text(cardioWorkout.isFromStrava ? (cardioWorkout.workoutName ?? activityInfo.name) : (isFromHealthKit ? activityInfo.name : activityInfo.name))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            // Source badge
                            sourceBadge
                        }
                        
                        // Date with relative time
                        Text(DateFormatUtils.formatSmartDate(completedDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Goal achieved badge
                    if cardioWorkout.goalAchieved {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.ds_heading3)
                            .foregroundColor(.green)
                            .padding(.trailing, 8)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary.opacity(0.5))
                    }
                
                    Divider()
                        .padding(.vertical, Spacing.sm)
                
                    // Bottom section - Cardio Stats
                    HStack(spacing: 0) {
                        cardioStatColumn(
                            icon: "clock.fill",
                            iconColor: activityInfo.color,
                            value: formatDuration(cardioWorkout.durationSeconds),
                            label: "Duration"
                        )
                        
                        statDivider
                        
                        cardioStatColumn(
                            icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                            iconColor: activityInfo.color,
                            value: formatDistance(cardioWorkout.distanceMeters),
                            label: distanceLabel
                        )
                        
                        statDivider
                        
                        cardioStatColumn(
                            icon: "flame.fill",
                            iconColor: .orange,
                            value: "\(Int(cardioWorkout.caloriesBurned))",
                            label: "Calories"
                        )
                        
                        statDivider
                        
                        cardioStatColumn(
                            icon: "speedometer",
                            iconColor: .purple,
                            value: formatPace(cardioWorkout.averagePace),
                            label: paceLabel
                        )
                    }
                
                    // Heart rate tag (if available)
                    if let heartRate = cardioWorkout.averageHeartRate, heartRate > 0 {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.ds_caption)
                                Text("\(heartRate) bpm")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.12))
                            )
                            
                            Spacer()
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 18)
                .sleekCard(cornerRadius: CornerRadius.xl, accentColor: activityInfo.color)
            }
            .buttonStyle(PlainButtonStyle())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.sm)
        .background(
            ZStack {
                // Card fill - lighter to pop from container
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.18), Color(white: 0.14)]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.clear]
                                : [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
    }
}

struct WorkoutDetailBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.ds_labelLarge)
                    .foregroundColor(color)
            }
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.ds_bodyMedium)
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
