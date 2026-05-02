import SwiftUI
import CoreData

// Q2-78 (Sprint 8): file-level hoisted formatters shared by `RecentWorkoutCard`
// + `RecentCardioWorkoutCard`. Avoids allocating a new `DateFormatter` for
// every row render on the dashboard history list.
private let dashboardCardDayOfWeekFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE"
    return f
}()
private let dashboardCardMonthDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()
private let dashboardCardTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
}()
private let dashboardCardFullMonthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM"
    return f
}()
private let dashboardCardOrdinalNumberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .ordinal
    return f
}()

struct RecentWorkoutCard: View {
    let workout: Workout
    var isMostRecent: Bool = false // Whether this is the most recent workout (gets special outline)
    /// Wearable cardio row (WHOOP / Apple Watch / Oura / Fitbit / Garmin)
    /// that overlapped this Fit33 workout — populated by
    /// `WorkoutWearableMerger`. When non-nil, the card renders a small
    /// origin chip so the user knows their wearable corroborated the
    /// session (full HR / strain lives on `WorkoutHistoryDetailView`).
    var wearableEnrichment: CardioWorkoutDTO? = nil
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
        // Prefer wearable-measured calories when one recorded this session —
        // optical HR beats the Fit33 MET formula by a wide margin. Falls back
        // to the stored formula value otherwise. See `WorkoutWearableMerger.effectiveCalories`.
        let cal = Int(WorkoutWearableMerger.effectiveCalories(workout: workout, wearable: wearableEnrichment))
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
                        
                        if !topMuscles.isEmpty || wearableEnrichment != nil {
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
                                if let wearable = wearableEnrichment {
                                    wearableOriginChip(for: wearable)
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
            .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: workoutGradient[0])
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
            return "\(dashboardCardDayOfWeekFormatter.string(from: date)) · \(formatTime(date))"
        } else {
            return "\(dashboardCardMonthDayFormatter.string(from: date)) · \(formatTime(date))"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        return dashboardCardTimeFormatter.string(from: date)
    }
    
    private func getDayName(for date: Date) -> String {
        return dashboardCardDayOfWeekFormatter.string(from: date)
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
        
        let dayName = dashboardCardDayOfWeekFormatter.string(from: date)
        
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
        return dashboardCardMonthDayFormatter.string(from: date)
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
        let day = Calendar.current.component(.day, from: date)
        let ordinalDay = dashboardCardOrdinalNumberFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        let month = dashboardCardFullMonthFormatter.string(from: date)
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

    /// Compact "+ WHOOP" (or Apple Watch / Oura / Fitbit / Garmin) chip
    /// shown when a wearable corroborated this Fit33 session. Tapping the
    /// card still opens the Fit33 detail view, which renders the full
    /// wearable card (HR, calories, origin-branded gradient).
    @ViewBuilder
    private func wearableOriginChip(for wearable: CardioWorkoutDTO) -> some View {
        let origin = wearable.resolvedOrigin
        HStack(spacing: 3) {
            Image(systemName: origin.badgeIcon)
                .font(.system(size: 9, weight: .semibold))
            Text(origin.displayName)
                .font(.ds_caption)
                .fontWeight(.semibold)
            if let hr = wearable.averageHeartRate, hr > 0 {
                Text("· \(hr) bpm")
                    .font(.ds_caption)
            }
        }
        .foregroundColor(origin.badgeForeground)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: origin.badgeGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Recent Cardio Workout Card
struct RecentCardioWorkoutCard: View {
    let cardioWorkout: CardioWorkoutDTO
    var isMostRecent: Bool = false
    /// 2026-05-02 — when set, overrides `activityInfo.color` for the
    /// card's primary accent (icon ring, icon glyph, stat icons, sleek
    /// border). Used by `CardioRecentLogSection` on the cardio landing
    /// where SOURCE coloring (Strava=orange / Fit33=blue / wearables=
    /// white) replaces the per-activity coloring used on the Home tab.
    /// When non-nil, the inline brand badge below the date is
    /// suppressed (the accent stroke already encodes the source); the
    /// WHOOP top-right wordmark still renders because it doubles as the
    /// "white accent" itself for WHOOP-origin rows.
    var accentColorOverride: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    /// Resolved accent — override wins, falls through to the per-activity
    /// color used on the Home tab.
    ///
    /// 2026-05-02 — when no override is provided (Home tab recent
    /// activity rows), Strava-origin cards force `Color.stravaOrange`
    /// (the brand-canonical #FC4C02 used by `DashboardStravaWidget`,
    /// `StravaSettingsView`, and `CardioRecentLogSection.sourceAccent`)
    /// regardless of the per-activity color. Strava's brand identity
    /// IS orange, and a blue "outdoor run" ring next to a "Powered by
    /// Strava" lockup looked off-brand; system `.orange` is also too
    /// muted vs the rest of the Strava surfaces. Fit33-origin rows do
    /// the same with `.fit33Brand` (a single-stop blue used for the
    /// sleek-card border tint; the icon ring / glyph render with the
    /// two-color cyan→blue `accentGradientColors` so they pick up the
    /// "33" wordmark gradient). The cardio landing's
    /// `CardioRecentLogSection` supplies its own override so these
    /// short-circuits never fire there.
    private var effectiveAccent: Color {
        if let override = accentColorOverride { return override }
        if origin == .strava { return Color.stravaOrange }
        if origin == .fit33  { return Color.fit33Brand }
        return activityInfo.color
    }

    /// Two-color gradient stops used for the icon-ring stroke and the
    /// icon-glyph fill. Defaults to a muted opacity ramp around the
    /// single accent (matches the historical look for Strava and
    /// per-activity-colored rows). Fit33-origin rows on the home
    /// dashboard get a true cyan→blue gradient that mirrors the "33"
    /// in the `fit33-logo` wordmark — so a glance at the icon already
    /// tells the user "this run was authored by Fit33". Skipped when
    /// `accentColorOverride` is in play (cardio landing recent log uses
    /// a single-stop source-color treatment).
    private var iconAccentColors: [Color] {
        if origin == .fit33, accentColorOverride == nil {
            return [Color.fit33GradientStart, Color.fit33GradientEnd]
        }
        return [effectiveAccent, effectiveAccent.opacity(0.6)]
    }
    /// Hide the inline brand capsule below the date when the caller is
    /// painting the card with a source-colored accent (cardio recent
    /// log). The WHOOP wordmark logic below is unaffected.
    private var suppressInlineOriginBadge: Bool { accentColorOverride != nil }
    
    // Parse completed date (uses centralized cached formatters)
    private var completedDate: Date {
        return ISO8601Parser.parse(cardioWorkout.completedAt, fallback: Date())
    }
    
    // Activity type display name and icon
    //
    // 2026-05-02 (per-user request): canonical Walk = teal, Run = blue
    // mapping matches `CardioActivityType.color` + `OutdoorCardioActiveView.activityAccent`,
    // so a Fit33 walk on the Home tab card uses the same accent as
    // the active-workout screen and the cardio landing hero tile.
    // Cycling stays cyan, indoor variants pull warm. Default fallback
    // also moves to blue (was green) so unknown activity types don't
    // suddenly land on a "run" green.
    private var activityInfo: (name: String, icon: String, color: Color) {
        let type = cardioWorkout.activityType.lowercased().replacingOccurrences(of: "_", with: " ")
        switch type {
        case "outdoor run", "run":
            return ("Outdoor Run", "figure.run", .blue)
        case "treadmill":
            return ("Treadmill", "figure.walk.motion", .orange)
        case "walk":
            return ("Walk", "figure.walk", .teal)
        case "indoor cycle", "indoor_cycle":
            return ("Indoor Cycle", "bicycle", .cyan)
        case "outdoor cycle", "outdoor_cycle":
            return ("Outdoor Cycle", "bicycle", .cyan)
        case "rowing":
            return ("Rowing", "figure.rower", Color(red: 0.20, green: 0.45, blue: 0.85))
        case "elliptical":
            return ("Elliptical", "figure.elliptical", .purple)
        case "stair climber", "stair_climber":
            return ("Stair Climber", "figure.stairs", .orange)
        case "hiit":
            return ("HIIT", "flame.fill", .red)
        case "swimming":
            return ("Swimming", "figure.pool.swim", .mint)
        default:
            return (type.capitalized, "figure.run", .blue)
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

    /// 2026-05-02 — Strava's `/athlete/activities` list endpoint omits
    /// `average_pace` and reports `calories = null` (calories live only
    /// on the detailed activity endpoint). Both fields are therefore
    /// stored as 0/null for Strava-imported rows, which produced the
    /// "0 calories / -- /mi" gap visible on the Home dashboard. We
    /// derive both at display-time from the data Strava DOES provide
    /// (distance + moving_time + activity_type), keeping rendering
    /// purely client-side and avoiding the per-row detail fetch (which
    /// would cost a Strava read against the 100/15-min rate limit).
    /// The fallback also covers any other origin that omitted these
    /// columns.

    /// Effective pace in min/km — uses the stored value when present,
    /// otherwise derives from `distance_meters / moving_time`.
    private var displayPace: Double? {
        if let pace = cardioWorkout.averagePace, pace > 0 {
            return pace
        }
        let meters = cardioWorkout.distanceMeters
        let seconds = Double(cardioWorkout.durationSeconds)
        guard meters > 0, seconds > 0 else { return nil }
        let km = meters / 1000.0
        let minutes = seconds / 60.0
        return minutes / km
    }

    /// Effective calories — uses the stored value when > 0, otherwise
    /// estimates from MET × weight(kg) × hours. MET coefficients track
    /// the Compendium of Physical Activities (Ainsworth 2011) values
    /// already used by `RunningManager.metForCurrentPace(_:)`.
    private var displayCalories: Int {
        let stored = Int(cardioWorkout.caloriesBurned)
        if stored > 0 { return stored }
        let weightKg = Double(UserManager.shared.currentUser?.weightLbs ?? 160) * 0.453592
        let hours = Double(cardioWorkout.durationSeconds) / 3600.0
        guard hours > 0, weightKg > 0 else { return 0 }
        let met = estimatedMET
        return Int((met * weightKg * hours).rounded())
    }

    /// Activity-appropriate baseline MET coefficient. Pulled from the
    /// same Compendium tables `RunningManager.baseMET` uses; we lean
    /// toward the moderate-intensity end since Strava-imported sessions
    /// are typically tempo-paced.
    private var estimatedMET: Double {
        let type = cardioWorkout.activityType.lowercased().replacingOccurrences(of: "_", with: " ")
        switch type {
        case "outdoor run", "run":              return 9.8
        case "treadmill":                       return 9.0
        case "walk", "hike":                    return 3.8
        case "indoor cycle", "outdoor cycle":   return 8.0
        case "rowing":                          return 7.0
        case "elliptical":                      return 5.0
        case "stair climber":                   return 8.8
        case "hiit":                            return 8.0
        case "swimming":                        return 7.0
        default:                                return 6.0
        }
    }
    
    private var isFromHealthKit: Bool {
        cardioWorkout.source == "healthkit"
    }

    /// Canonical origin (Strava/Nike/Peloton/Garmin/etc.) resolved from
    /// the row's `origin_app` column, or the legacy `source` column for
    /// pre-migration OAuth rows.
    private var origin: WorkoutOrigin { cardioWorkout.resolvedOrigin }

    private var sourceDisplayName: String {
        if origin != .unknown { return origin.displayName }
        if isFromHealthKit { return "Health" }
        return "Cardio"
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if origin != .unknown {
            // Every known third-party origin (Strava, Nike, Peloton, Garmin,
            // Zwift, Apple Watch, Fitbit, WHOOP, Oura, MapMyRun, ...) gets
            // a brand-colored capsule driven by WorkoutOriginMapper.
            HStack(spacing: 3) {
                Image(systemName: origin.badgeIcon)
                    .font(.system(size: 9, weight: .bold))
                Text(origin.displayName)
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(origin.badgeForeground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: origin.badgeGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        } else if isFromHealthKit {
            // Unknown third-party app that wrote to Apple Health — fall
            // back to the generic Apple Health heart so the user still
            // sees the transport source.
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
                .foregroundColor(effectiveAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(effectiveAccent.opacity(0.15))
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
                                    colors: iconAccentColors,
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
                                    colors: iconAccentColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Activity name — now gets the full row width so long
                        // titles ("Strength Training") don't truncate to
                        // "Strength T…" behind a brand chip.
                        Text(cardioWorkout.isFromStrava ? (cardioWorkout.workoutName ?? activityInfo.name) : (isFromHealthKit ? activityInfo.name : activityInfo.name))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // Date row — also hosts the WHOOP wordmark or the
                        // "Powered by Strava" lockup so the brand
                        // attribution travels INLINE with the timestamp
                        // instead of stacking next to the title (per
                        // 2026-05-02 dashboard tweak: the lockup must sit
                        // across from the time, not at the top of the
                        // card). Brand assets keep their canonical sizing
                        // — 14pt WHOOP wordmark (matches the cardio detail
                        // header), 20pt "Powered by Strava" (Strava Brand
                        // Guidelines minimum height).
                        HStack(spacing: 8) {
                            Text(DateFormatUtils.formatSmartDate(completedDate))
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 8)

                            if origin == .whoop {
                                Image("WhoopWordmark")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 14)
                                    .foregroundColor(.white)
                                    .accessibilityLabel("WHOOP")
                            } else if origin == .strava {
                                Image("PoweredByStrava")
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .frame(height: 20)
                                    .accessibilityLabel("Powered by Strava")
                            } else if origin == .fit33 {
                                // Fit33-authored runs (RunningManager /
                                // CardioActiveWorkoutView / CardioRecapView
                                // → `record_cardio_workout` RPC) get the
                                // Fit33 wordmark inline next to the
                                // timestamp so a Fit33 row reads as
                                // unambiguously ours, the same way Strava
                                // / WHOOP rows brand their author. Image
                                // is rendered `.original` because the
                                // wordmark itself carries the cyan→blue
                                // "33" gradient that the icon ring
                                // mirrors.
                                Image("fit33-logo")
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .frame(height: 18)
                                    .accessibilityLabel("Fit33")
                            }
                        }

                        // Third-party origin badge for brands that don't
                        // already get a dedicated wordmark on the date
                        // row above. Suppressed for:
                        //   • .whoop  — white WHOOP wordmark on date row
                        //   • .strava — "Powered by Strava" lockup on date row
                        //   • .fit33  — fit33-logo wordmark on date row
                        //   • when `accentColorOverride` is set (cardio
                        //     landing recent log paints the border with
                        //     a source color, so an inline chip is
                        //     redundant)
                        // Apple Watch / Oura / Fitbit / Garmin / Nike /
                        // Peloton / etc. still render the brand-colored
                        // capsule below the date.
                        if origin != .whoop
                            && origin != .strava
                            && origin != .fit33
                            && !suppressInlineOriginBadge {
                            sourceBadge
                                .padding(.top, 2)
                        }
                    }
                    // VStack must expand to fill so the inner date-row
                    // HStack's `Spacer` can push the brand asset (WHOOP /
                    // Strava lockup) to the trailing edge across from the
                    // timestamp.
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                            iconColor: effectiveAccent,
                            value: formatDuration(cardioWorkout.durationSeconds),
                            label: "Duration"
                        )
                        
                        statDivider
                        
                        cardioStatColumn(
                            icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                            iconColor: effectiveAccent,
                            value: formatDistance(cardioWorkout.distanceMeters),
                            label: distanceLabel
                        )
                        
                        statDivider
                        
                        cardioStatColumn(
                            icon: "flame.fill",
                            iconColor: .orange,
                            value: "\(displayCalories)",
                            label: "Calories"
                        )
                        
                        statDivider
                        
                        // For WHOOP-origin sessions (predominantly strength
                        // training, where pace is meaningless) we surface the
                        // average heart rate in the 4th slot instead of pace.
                        // Other origins show pace, falling back to the
                        // distance/duration-derived value when the source
                        // didn't supply one (Strava list endpoint omits
                        // `average_pace`).
                        if origin == .whoop {
                            cardioStatColumn(
                                icon: "heart.fill",
                                iconColor: .red,
                                value: (cardioWorkout.averageHeartRate ?? 0) > 0
                                    ? "\(cardioWorkout.averageHeartRate ?? 0)"
                                    : "--",
                                label: "bpm"
                            )
                        } else {
                            cardioStatColumn(
                                icon: "speedometer",
                                iconColor: .purple,
                                value: formatPace(displayPace),
                                label: paceLabel
                            )
                        }
                    }

                    // 2026-05-02 — the standalone red "183 bpm" capsule
                    // that used to live below the stats row was removed
                    // per dashboard tweak: average heart rate is already
                    // visible on the cardio detail screen and the row
                    // was visually heavy on the home feed. WHOOP rows
                    // continue to surface bpm in the 4th stat column
                    // instead of pace (handled above).
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 18)
                .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: effectiveAccent)
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
