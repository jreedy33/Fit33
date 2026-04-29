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
                
                // Tier stat tile — replaces the legacy "Level N" tile
                // (League Redesign Plan, Sprint 1 §B1). Tier IS the user's
                // identity now; the value reads `WeeklyLeagueService.shared`
                // directly because dashboard StatCards live outside the
                // service-owning navigation stack and don't justify an
                // @StateObject (PE invariant 9 — keeps the stat row from
                // recomputing on every league fetch). Falls back through
                // standing → notPlacedTierName → "Bronze" so the slot is
                // never empty.
                StatCard(
                    title: "Tier",
                    value: WeeklyLeagueService.shared.standing?.tierName
                        ?? WeeklyLeagueService.shared.notPlacedTierName
                        ?? "Bronze",
                    icon: "trophy.fill",
                    color: WeeklyLeagueService.shared.standing?.tierSwiftUIColor ?? .yellow
                )
            }

            // 2026-04-29 — League Redesign Plan §A5.
            // Peak Day Bonus widget. Renders below the stat row when the
            // user has been placed at least once after migration #148. The
            // server picks one ISO weekday per user per week; League Points
            // earned that day count 3×. The widget shows the day name plus
            // a live "Today!" badge when `peakDay == today`.
            if let standing = WeeklyLeagueService.shared.standing,
               let peakDayName = standing.peakDayName {
                peakDayBonusCard(
                    dayName: peakDayName,
                    isToday: standing.isPeakDayToday
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

    /// Peak Day Bonus inline widget. Shown inside the activity stats card
    /// once the server has assigned a peak day to the user (post-migration
    /// #148). Today-state has a brighter gradient + pulsing label so the
    /// user can't miss the 3× window.
    @ViewBuilder
    private func peakDayBonusCard(dayName: String, isToday: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isToday ? "bolt.fill" : "bolt")
                .font(.title3)
                .foregroundColor(isToday ? .yellow : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(isToday ? "Peak Day — TODAY" : "Peak Day")
                        .font(.ds_labelMedium)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    if isToday {
                        Text("3×")
                            .font(.ds_labelSmall)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.yellow.opacity(0.18))
                            )
                    }
                }
                Text(isToday
                     ? "Every league point you earn today counts 3×"
                     : "On \(dayName), every league point counts 3×")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(
                    isToday
                        ? LinearGradient(
                            colors: [Color.yellow.opacity(0.20), Color.orange.opacity(0.12)],
                            startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(
                            colors: [Color.secondary.opacity(0.08), Color.secondary.opacity(0.04)],
                            startPoint: .leading, endPoint: .trailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(isToday ? Color.yellow.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isToday
            ? "Peak Day is today. Every league point you earn counts three times."
            : "Peak Day is \(dayName). On that weekday, every league point counts three times.")
    }
}
