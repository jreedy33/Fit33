import SwiftUI
import MapKit

/// Cardio workout detail view - matches WorkoutHistoryDetailView style
/// Displays cardio-specific stats: duration, distance, pace, calories, heart rate, etc.
struct CardioWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let cardioWorkout: CardioWorkoutDTO
    
    // MARK: - Computed Properties
    
    private var completedDate: Date {
        ISO8601Parser.parse(cardioWorkout.completedAt, fallback: Date())
    }
    
    private var startedDate: Date {
        ISO8601Parser.parse(cardioWorkout.startedAt, fallback: Date())
    }
    
    private var activityInfo: (name: String, icon: String, color: Color, gradient: [Color]) {
        let type = cardioWorkout.activityType.lowercased().replacingOccurrences(of: "_", with: " ")
        switch type {
        case "outdoor run", "run":
            return ("Outdoor Run", "figure.run", .green, [.green, .teal])
        case "treadmill":
            return ("Treadmill", "figure.walk.motion", .orange, [.orange, .yellow])
        case "walk":
            return ("Walk", "figure.walk", .blue, [.blue, .cyan])
        case "indoor cycle", "indoor_cycle":
            return ("Indoor Cycle", "bicycle", .cyan, [.cyan, .blue])
        case "outdoor cycle", "outdoor_cycle":
            return ("Outdoor Cycle", "bicycle", .green, [.green, .teal])
        case "rowing":
            return ("Rowing", "figure.rower", .blue, [.blue, .indigo])
        case "elliptical":
            return ("Elliptical", "figure.elliptical", .purple, [.purple, .pink])
        case "stair climber", "stair_climber":
            return ("Stair Climber", "figure.stairs", .orange, [.orange, .red])
        case "hiit":
            return ("HIIT", "flame.fill", .red, [.red, .orange])
        case "swimming":
            return ("Swimming", "figure.pool.swim", .cyan, [.cyan, .blue])
        default:
            return (type.capitalized, "figure.run", .green, [.green, .teal])
        }
    }
    
    private var accentColor: Color { activityInfo.color }
    private var accentGradient: [Color] { activityInfo.gradient }
    
    // MARK: - Formatters
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        if km < 1 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.2f km", km)
        }
    }
    
    private func formatPace(_ pace: Double?) -> String {
        guard let pace = pace, pace > 0 else { return "--:--" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatSpeed(_ speed: Double?) -> String {
        guard let speed = speed, speed > 0 else { return "--" }
        return String(format: "%.1f km/h", speed)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header section
                VStack(spacing: 20) {
                    headerSection
                    statsGrid
                        .padding(.horizontal, Spacing.md)
                }
                .padding(.bottom, 8)
                
                // Content cards
                VStack(spacing: 20) {
                    // Goal Progress
                    goalCard
                    
                    // Performance Highlights
                    highlightsCard
                    
                    // Detailed Stats
                    detailedStatsCard
                    
                    // Equipment Info (if available)
                    if cardioWorkout.equipmentName != nil {
                        equipmentCard
                    }
                    
                    // Actions
                    actionsCard
                }
                .padding(.horizontal, Spacing.md)
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
        .navigationTitle(activityInfo.name)
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Activity icon with gradient ring
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
                
                Image(systemName: activityInfo.icon)
                    .font(.ds_heading2)
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
                Text(formatFullDate(completedDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Goal badge
                if cardioWorkout.goalAchieved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.ds_caption)
                            .foregroundStyle(
                                LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        Text("Goal Achieved!")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.12))
                    )
                }
            }
            
            Spacer()
            
            // Share button
            Button(action: shareWorkout) {
                Image(systemName: "square.and.arrow.up")
                    .font(.ds_heading3)
                    .foregroundColor(accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(accentColor.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 12)
    }
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Duration
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(accentColor)
                        Text(formatDuration(cardioWorkout.durationSeconds))
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
                
                // Distance
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(accentColor)
                        Text(formatDistance(cardioWorkout.distanceMeters))
                            .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(.primary)
                    }
                    Text("Distance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // Calories
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.orange)
                        Text("\(Int(cardioWorkout.caloriesBurned))")
                            .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(.primary)
                    }
                    Text("Calories")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // Pace
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.ds_bodySmall)
                            .foregroundColor(.purple)
                        Text(formatPace(cardioWorkout.averagePace))
                            .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(.primary)
                    }
                    Text("/km")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, Spacing.md)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color(white: 0.96), Color(white: 0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.lg)
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
                
                RoundedRectangle(cornerRadius: CornerRadius.lg)
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
    
    // MARK: - Goal Card
    
    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.ds_labelMedium)
                    .foregroundColor(cardioWorkout.goalAchieved ? .green : accentColor)
                Text("Goal Progress")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                if cardioWorkout.goalAchieved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cardioWorkout.goalType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let goalValue = cardioWorkout.goalValue {
                        Text(formatGoalValue(goalValue, type: cardioWorkout.goalType))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(accentColor)
                    }
                }
                
                Spacer()
                
                // Progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: calculateGoalProgress())
                        .stroke(
                            LinearGradient(colors: cardioWorkout.goalAchieved ? [.green, .teal] : accentGradient,
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(calculateGoalProgress() * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
        }
        .padding(Spacing.md)
        .background(glassCard)
    }
    
    private func formatGoalValue(_ value: Double, type: String) -> String {
        switch type.lowercased() {
        case "time", "duration":
            let minutes = Int(value)
            return "\(minutes) min"
        case "distance":
            return String(format: "%.2f km", value / 1000)
        case "calories":
            return "\(Int(value)) cal"
        default:
            return "\(Int(value))"
        }
    }
    
    private func calculateGoalProgress() -> CGFloat {
        guard let goalValue = cardioWorkout.goalValue, goalValue > 0 else { return 1.0 }
        
        let achieved: Double
        switch cardioWorkout.goalType.lowercased() {
        case "time", "duration":
            achieved = Double(cardioWorkout.durationSeconds) / 60.0 // convert to minutes
        case "distance":
            achieved = cardioWorkout.distanceMeters
        case "calories":
            achieved = cardioWorkout.caloriesBurned
        default:
            achieved = goalValue
        }
        
        return min(CGFloat(achieved / goalValue), 1.0)
    }
    
    // MARK: - Highlights Card
    
    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(.orange)
                Text("Performance Highlights")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(spacing: 8) {
                // Best Pace
                if let bestPace = cardioWorkout.bestPace, bestPace > 0 {
                    highlightRow(title: "Best Pace", value: "\(formatPace(bestPace)) /km", icon: "bolt.fill", color: .orange)
                }
                
                // Max Speed
                if let maxSpeed = cardioWorkout.maxSpeed, maxSpeed > 0 {
                    highlightRow(title: "Top Speed", value: formatSpeed(maxSpeed), icon: "gauge.with.needle.fill", color: .red)
                }
                
                // Max Heart Rate
                if let maxHR = cardioWorkout.maxHeartRate, maxHR > 0 {
                    highlightRow(title: "Peak Heart Rate", value: "\(maxHR) bpm", icon: "heart.fill", color: .red)
                }
                
                // Peak Power
                if let power = cardioWorkout.averagePower, power > 0 {
                    highlightRow(title: "Avg Power", value: "\(power) W", icon: "bolt.circle.fill", color: .yellow)
                }
            }
        }
        .padding(Spacing.md)
        .background(glassCard)
    }
    
    private func highlightRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
    
    // MARK: - Detailed Stats Card
    
    private var detailedStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(accentColor)
                Text("Detailed Stats")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Average Pace
                detailStatCell(title: "Avg Pace", value: formatPace(cardioWorkout.averagePace) + " /km", icon: "speedometer", color: .purple)
                
                // Average Speed
                detailStatCell(title: "Avg Speed", value: formatSpeed(cardioWorkout.averageSpeed), icon: "gauge.with.needle", color: .blue)
                
                // Heart Rate
                if let hr = cardioWorkout.averageHeartRate, hr > 0 {
                    detailStatCell(title: "Avg Heart Rate", value: "\(hr) bpm", icon: "heart.fill", color: .red)
                }
                
                // Cadence
                if let cadence = cardioWorkout.cadence, cadence > 0 {
                    detailStatCell(title: "Cadence", value: "\(cadence) spm", icon: "metronome.fill", color: .cyan)
                }
            }
        }
        .padding(Spacing.md)
        .background(glassCard)
    }
    
    private func detailStatCell(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.ds_heading3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(color.opacity(0.08))
        )
    }
    
    // MARK: - Equipment Card
    
    private var equipmentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(.blue)
                Text("Equipment Used")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let name = cardioWorkout.equipmentName {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    if let type = cardioWorkout.equipmentType {
                        Text(type.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.ds_bodyRegular)
                    .foregroundColor(.blue)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                    )
            }
        }
        .padding(Spacing.md)
        .background(glassCard)
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(spacing: 12) {
            // Share button
            Button(action: shareWorkout) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.ds_bodyMedium)
                    Text("Share Workout")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: accentGradient),
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
                                gradient: Gradient(colors: accentGradient),
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
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(
                    LinearGradient(
                        colors: Color.cardGradientStops(for: colorScheme),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.clear]
                            : [Color.white, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Actions
    
    private func shareWorkout() {
        HapticManager.impact(.light)
        
        let activityName = activityInfo.name
        let duration = formatDuration(cardioWorkout.durationSeconds)
        let distance = formatDistance(cardioWorkout.distanceMeters)
        let calories = Int(cardioWorkout.caloriesBurned)
        let pace = formatPace(cardioWorkout.averagePace)
        
        var shareText = """
        🏃 \(activityName) Complete!
        
        ⏱️ Duration: \(duration)
        📏 Distance: \(distance)
        🔥 Calories: \(calories)
        ⚡ Avg Pace: \(pace) /km
        """
        
        if cardioWorkout.goalAchieved {
            shareText += "\n\n🎯 Goal Achieved! ✅"
        }
        
        shareText += "\n\n#Fit33 #Cardio"
        
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var topController = rootViewController
            while let presentedVC = topController.presentedViewController {
                topController = presentedVC
            }
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(x: topController.view.bounds.midX,
                                           y: topController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topController.present(activityVC, animated: true)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CardioWorkoutDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CardioWorkoutDetailView(cardioWorkout: CardioWorkoutDTO(
                id: "preview-1",
                activityType: "outdoor_run",
                workoutName: "Morning Run",
                goalType: "distance",
                goalValue: 5000,
                goalAchieved: true,
                durationSeconds: 1800,
                distanceMeters: 5234,
                caloriesBurned: 320,
                averagePace: 5.5,
                bestPace: 4.8,
                averageSpeed: 10.5,
                maxSpeed: 12.3,
                averageHeartRate: 145,
                maxHeartRate: 175,
                cadence: 165,
                averagePower: nil,
                equipmentName: nil,
                equipmentType: nil,
                startedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1800)),
                completedAt: ISO8601DateFormatter().string(from: Date()),
                source: nil,
                externalId: nil,
                externalUrl: nil,
                totalElevationGain: nil,
                originApp: nil
            ))
        }
    }
}
#endif
