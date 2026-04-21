import SwiftUI
import CoreData

extension DashboardView {
    var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .font(.title3)
                    Text("Recent Activity")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                
                HStack {
                    Text("\(totalCombinedWorkouts) workouts completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
                    
                    Spacer()
                    
                    NavigationLink(value: DashboardRoute.workoutHistory) {
                        HStack(spacing: 4) {
                            Text("View All")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            
            VStack(spacing: Spacing.sm) {
                ForEach(combinedRecentWorkouts.prefix(3), id: \.id) { item in
                    switch item {
                    case .strength(let workout, let isMostRecent):
                        RecentWorkoutCard(
                            workout: workout,
                            isMostRecent: isMostRecent,
                            wearableEnrichment: workout.id.flatMap { wearableEnrichmentByWorkout[$0] }
                        )
                    case .cardio(let cardioWorkout, let isMostRecent):
                        RecentCardioWorkoutCard(cardioWorkout: cardioWorkout, isMostRecent: isMostRecent)
                    }
                }
            }
        }
    }
    
    // Get the glow color based on the most recent workout's muscle group (kept for card content)
    var recentActivityGlowColor: Color {
        guard let mostRecentWorkout = recentWorkouts.first else {
            return .blue // Default fallback
        }
        
        // Get exercises from most recent workout
        let exercises = mostRecentWorkout.exercises?.allObjects as? [WorkoutExercise] ?? []
        let muscles = exercises.compactMap { ($0.exercise?.muscleGroups as? [String])?.first?.lowercased() }
        let primaryMuscle = muscles.first ?? ""
        
        switch primaryMuscle {
        case "chest": return .red
        case "back": return .blue
        case "legs", "quads", "hamstrings", "glutes": return .green
        case "shoulders": return .orange
        case "biceps", "triceps", "arms": return .purple
        case "core", "abs": return .yellow
        default:
            // Fallback to time-based color
            let hour = Calendar.current.component(.hour, from: mostRecentWorkout.date ?? Date())
            if hour >= 5 && hour < 12 {
                return .orange
            } else if hour >= 12 && hour < 17 {
                return .blue
            } else {
                return .purple
            }
        }
    }
    
    // Helper to convert color string to Color
    func colorFromString(_ colorString: String) -> Color {
        switch colorString.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "teal": return .teal
        case "mint": return .mint
        default: return .blue
        }
    }
    
    /// Combined total: in-app workouts + synced cardio/HealthKit workouts
    var totalCombinedWorkouts: Int {
        let inApp = Int(userManager.currentUser?.totalWorkouts ?? 0)
        return inApp + totalCardioWorkoutCount
    }
    
    var statsOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Progress")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                StatCard(
                    title: "Workouts",
                    value: "\(totalCombinedWorkouts)",
                    icon: "dumbbell.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Best Streak",
                    value: "\(userManager.currentUser?.longestStreak ?? 0)",
                    icon: "flame.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Level",
                    value: "\(userManager.getLevel())",
                    icon: "star.fill",
                    color: .yellow
                )
            }
        }
        .padding(Spacing.lg)
        .background(
            ZStack {
                // Outer container - darker to let inner cards pop (matches Recent Activity)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.11), Color(white: 0.07)]
                                : [Color(white: 0.96), Color(white: 0.94)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.clear]
                                : [Color.white.opacity(0.8), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 16, x: 0, y: 8)
    }
}
