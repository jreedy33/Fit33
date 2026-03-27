import SwiftUI

// MARK: - Training Hub View
// A dedicated page for the new sleek training insights widget

struct TrainingHubView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == YES"),
        animation: .default)
    private var workouts: FetchedResults<Workout>
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Active Program Widget
                if cloudProgramService.activeProgram != nil {
                    TrainingInsightsWidget(
                        workouts: Array(workouts),
                        onViewProgram: {
                            // Navigate to program schedule
                        }
                    )
                } else {
                    // No active program state
                    noProgramCard
                }
                
                // Additional sections can be added here in the future
                // - Muscle recovery heatmap
                // - PR tracking
                // - Weekly summary
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(
            AnimatedOrbBackground.home(colorScheme: colorScheme)
                .ignoresSafeArea()
        )
        .navigationTitle("Training Hub")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var noProgramCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("No Active Program")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Start a training program to see your insights here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Training Insights Widget (Sleek Design)
struct TrainingInsightsWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    let workouts: [Workout]
    let onViewProgram: () -> Void
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    
    // MARK: - Computed Properties
    
    private var todayWorkoutInfo: (day: Int, name: String, exerciseCount: Int)? {
        guard let progress = cloudProgramService.activeProgram,
              let dayDetails = cloudProgramService.getDayDetails(for: progress.currentDay) else {
            return nil
        }
        return (day: Int(progress.currentDay), name: dayDetails.day.name, exerciseCount: dayDetails.exercises.count)
    }
    
    private var programName: String {
        cloudProgramService.activeProgramDetails?.program.name ?? "Training Program"
    }
    
    private var workoutsThisWeek: Int {
        workouts.filter {
            guard let date = $0.date else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }.count
    }
    
    /// Smart streak calculation that respects rest days
    /// Counts workouts, not consecutive days - rest days don't break streak!
    private var currentStreak: Int {
        // Use the user's stored streak value (which uses smart logic)
        return Int(UserManager.shared.currentUser?.currentStreak ?? 0)
    }
    
    /// Calculate streak from workout history (backup/verification)
    /// This counts workout sessions while allowing gaps based on user's schedule
    private var calculatedStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get user's max allowed gap (defaults to 3 if not available)
        let maxAllowedGap = UserManager.shared.getMaxAllowedRestDays() + 1  // +1 because we measure gap
        
        // Sort workouts by date (newest first)
        let sortedWorkouts = workouts
            .compactMap { $0.date }
            .map { calendar.startOfDay(for: $0) }
            .sorted(by: >)  // Newest first
        
        guard !sortedWorkouts.isEmpty else { return 0 }
        
        var streak = 0
        var lastWorkoutDate: Date? = nil
        
        for workoutDate in sortedWorkouts {
            if let lastDate = lastWorkoutDate {
                let daysBetween = calendar.dateComponents([.day], from: workoutDate, to: lastDate).day ?? 0
                
                // If gap is too large, streak ends here
                if daysBetween > maxAllowedGap {
                    break
                }
            } else {
                // First workout - check if it's recent enough to count
                let daysFromToday = calendar.dateComponents([.day], from: workoutDate, to: today).day ?? 0
                if daysFromToday > maxAllowedGap {
                    // Last workout was too long ago - no active streak
                    return 0
                }
            }
            
            streak += 1
            lastWorkoutDate = workoutDate
        }
        
        return streak
    }
    
    private var recentPRCount: Int {
        var prs: [(exercise: String, weight: Double, reps: Int, date: Date)] = []
        var bestSets: [String: (weight: Double, reps: Int)] = [:]
        
        let sortedWorkouts = workouts.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        for workout in sortedWorkouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for workoutExercise in exercises {
                let exerciseName = workoutExercise.safeDisplayName
                guard exerciseName != "Loading...",
                      let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { continue }
                
                for set in sets where set.isCompleted {
                    let currentBest = bestSets[exerciseName]
                    let isNewPR: Bool
                    if let best = currentBest {
                        isNewPR = set.weight > best.weight || (set.weight == best.weight && set.reps > best.reps)
                    } else {
                        isNewPR = true
                    }
                    
                    if isNewPR {
                        bestSets[exerciseName] = (weight: set.weight, reps: Int(set.reps))
                        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                        if let date = workout.date, date > twoWeeksAgo {
                            prs.removeAll { $0.exercise == exerciseName }
                            prs.append((exercise: exerciseName, weight: set.weight, reps: Int(set.reps), date: date))
                        }
                    }
                }
            }
        }
        
        return prs.count
    }
    
    private var trainingScore: Int {
        var score = 0
        
        if workoutsThisWeek >= 5 { score += 30 }
        else if workoutsThisWeek >= 4 { score += 25 }
        else if workoutsThisWeek >= 3 { score += 20 }
        else if workoutsThisWeek >= 2 { score += 10 }
        else if workoutsThisWeek >= 1 { score += 5 }
        
        score += min(recentPRCount * 8, 25)
        
        if currentStreak >= 7 { score += 25 }
        else if currentStreak >= 3 { score += 15 }
        else if currentStreak >= 1 { score += 5 }
        
        return min(score, 100)
    }
    
    private var scoreColor: Color {
        if trainingScore >= 80 { return .green }
        else if trainingScore >= 60 { return .yellow }
        else if trainingScore >= 40 { return .orange }
        else { return .red }
    }
    
    private var greeting: String {
        if trainingScore >= 80 {
            return "Outstanding performance! 🏆"
        } else if trainingScore >= 60 {
            return "Solid progress this week! 💪"
        } else if workoutsThisWeek == 0 {
            return "Ready to get back at it? 🎯"
        } else {
            return "Keep building momentum! 🚀"
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header section
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(programName)
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if let today = todayWorkoutInfo {
                            HStack(spacing: 6) {
                                Text("Day \(today.day)")
                                    .font(.ds_bodySmall).fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                                            )
                                    )
                                
                                Text(today.name)
                                    .font(.ds_bodySmall).fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Text(greeting)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    // Score ring
                    ZStack {
                        Circle()
                            .stroke(scoreColor.opacity(0.15), lineWidth: 5)
                            .frame(width: 56, height: 56)
                        
                        Circle()
                            .trim(from: 0, to: Double(trainingScore) / 100.0)
                            .stroke(
                                LinearGradient(
                                    colors: [scoreColor, scoreColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 0) {
                            Text("\(trainingScore)")
                                .font(.ds_statSmall)
                                .foregroundColor(scoreColor)
                            Text("pts")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
                .padding(.horizontal, 20)
            
            // Stats row
            HStack(spacing: 0) {
                WidgetStat(value: "\(workoutsThisWeek)", label: "This Week", icon: "flame.fill", color: workoutsThisWeek >= 3 ? .green : .gray)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 36)
                
                WidgetStat(value: "\(recentPRCount)", label: "PRs", icon: "trophy.fill", color: recentPRCount > 0 ? .yellow : .gray)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 36)
                
                WidgetStat(value: "\(currentStreak)", label: "Streak", icon: "bolt.fill", color: currentStreak >= 3 ? .orange : .gray)
            }
            .padding(.vertical, Spacing.md)
            
            Divider()
                .padding(.horizontal, 20)
            
            // View schedule button
            Button(action: onViewProgram) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.ds_labelLarge)
                        .foregroundColor(.green)
                    
                    Text("View Full Schedule")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.md)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.1), radius: 15, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    colorScheme == .dark
                        ? LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [scoreColor.opacity(0.2), scoreColor.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Widget Stat
struct WidgetStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_caption)
                    .foregroundColor(color)
                Text(value)
                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        TrainingHubView()
    }
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

