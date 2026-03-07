import SwiftUI
import CoreData

// MARK: - Insight Models

enum ReplayInsightType: String {
    case volumeComparison
    case progressiveOverload
    case plateauDetection
    case muscleBalance
    case restTimeCoaching
    case personalRecord
    case recoveryAdvisory
    case consistencyStreak
    case workoutDuration
}

enum ReplayInsightPriority: Int, Comparable {
    case highlight = 0
    case coaching = 1
    case info = 2
    
    static func < (lhs: ReplayInsightPriority, rhs: ReplayInsightPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WorkoutInsightCard: Identifiable {
    let id = UUID()
    let type: ReplayInsightType
    let priority: ReplayInsightPriority
    let icon: String
    let iconColor: Color
    let headline: String
    let detail: String
    let actionTip: String?
}

// MARK: - Replay Engine

class WorkoutReplayEngine {
    static let shared = WorkoutReplayEngine()
    private init() {}
    
    func generateInsights(
        workout: Workout,
        exercises: [Exercise],
        exerciseSets: [String: [WorkoutSetData]],
        workoutDuration: TimeInterval
    ) -> [WorkoutInsightCard] {
        var insights: [WorkoutInsightCard] = []
        let context = PersistenceController.shared.container.viewContext
        let recentWorkouts = fetchRecentWorkouts(context: context, excluding: workout, limit: 30)
        
        insights.append(contentsOf: generateVolumeInsights(
            exercises: exercises,
            exerciseSets: exerciseSets,
            recentWorkouts: recentWorkouts
        ))
        
        insights.append(contentsOf: generateProgressInsights(
            exercises: exercises,
            exerciseSets: exerciseSets,
            recentWorkouts: recentWorkouts
        ))
        
        insights.append(contentsOf: generatePlateauInsights(
            exercises: exercises,
            exerciseSets: exerciseSets,
            recentWorkouts: recentWorkouts
        ))
        
        insights.append(contentsOf: generateMuscleBalanceInsights(recentWorkouts: recentWorkouts))
        
        insights.append(contentsOf: generateRestTimeInsights(exerciseSets: exerciseSets))
        
        insights.append(contentsOf: generateRecoveryInsights(exercises: exercises))
        
        insights.append(contentsOf: generateConsistencyInsights(
            recentWorkouts: recentWorkouts,
            currentDuration: workoutDuration
        ))
        
        return insights.sorted { $0.priority < $1.priority }
    }
    
    // MARK: - Data Fetching
    
    private func fetchRecentWorkouts(context: NSManagedObjectContext, excluding current: Workout, limit: Int) -> [Workout] {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isCompleted == YES"),
            NSPredicate(format: "id != %@", (current.id ?? UUID()) as CVarArg)
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }
    
    private func findPreviousWorkoutsWithExercise(named exerciseName: String, in workouts: [Workout]) -> [(workout: Workout, workoutExercise: WorkoutExercise)] {
        var results: [(Workout, WorkoutExercise)] = []
        for workout in workouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for we in exercises {
                if we.exercise?.name?.lowercased() == exerciseName.lowercased() {
                    results.append((workout, we))
                }
            }
        }
        return results
    }
    
    private func completedSets(from workoutExercise: WorkoutExercise) -> [WorkoutSet] {
        (workoutExercise.sets?.allObjects as? [WorkoutSet] ?? [])
            .filter { $0.isCompleted }
            .sorted { $0.setNumber < $1.setNumber }
    }
    
    private func totalVolume(sets: [WorkoutSetData]) -> Double {
        sets.filter { $0.isCompleted }.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }
    
    private func totalVolumeFromSets(_ sets: [WorkoutSet]) -> Double {
        sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }
    
    private func bestSet(from sets: [WorkoutSetData]) -> WorkoutSetData? {
        sets.filter { $0.isCompleted }.max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }
    }
    
    private func bestSetFromHistory(_ sets: [WorkoutSet]) -> WorkoutSet? {
        sets.max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }
    }
    
    // MARK: - Volume Insights
    
    private func generateVolumeInsights(
        exercises: [Exercise],
        exerciseSets: [String: [WorkoutSetData]],
        recentWorkouts: [Workout]
    ) -> [WorkoutInsightCard] {
        var totalCurrentVolume: Double = 0
        for exercise in exercises {
            let id = exercise.id?.uuidString ?? ""
            let sets = exerciseSets[id] ?? []
            totalCurrentVolume += totalVolume(sets: sets)
        }
        
        guard totalCurrentVolume > 0 else { return [] }
        
        let currentMuscles = Set(exercises.compactMap { ($0.muscleGroups as? [String])?.first?.lowercased() })
        
        for pastWorkout in recentWorkouts {
            guard let pastExercises = pastWorkout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            let pastMuscles = Set(pastExercises.compactMap { ($0.exercise?.muscleGroups as? [String])?.first?.lowercased() })
            let overlap = currentMuscles.intersection(pastMuscles)
            guard overlap.count >= max(1, currentMuscles.count / 2) else { continue }
            
            let pastVolume = pastExercises.reduce(0.0) { total, we in
                total + totalVolumeFromSets(completedSets(from: we))
            }
            guard pastVolume > 0 else { continue }
            
            let percentChange = ((totalCurrentVolume - pastVolume) / pastVolume) * 100
            let formattedChange = String(format: "%.0f", abs(percentChange))
            
            if percentChange > 5 {
                return [WorkoutInsightCard(
                    type: .volumeComparison,
                    priority: .highlight,

                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .green,
                    headline: "Volume Up \(formattedChange)%",
                    detail: "You lifted \(formatWeight(totalCurrentVolume)) total volume — \(formattedChange)% more than your last similar session (\(formatWeight(pastVolume))).",
                    actionTip: "Keep pushing progressive overload. Your muscles are adapting."
                )]
            } else if percentChange < -10 {
                return [WorkoutInsightCard(
                    type: .volumeComparison,
                    priority: .coaching,
                    icon: "chart.line.downtrend.xyaxis",
                    iconColor: .orange,
                    headline: "Volume Down \(formattedChange)%",
                    detail: "Today's volume was \(formatWeight(totalCurrentVolume)) vs \(formatWeight(pastVolume)) last time.",
                    actionTip: "Low volume days happen — could be recovery, sleep, or nutrition. Track what changed."
                )]
            }
            break
        }
        return []
    }
    
    // MARK: - Progressive Overload
    
    private func generateProgressInsights(
        exercises: [Exercise],
        exerciseSets: [String: [WorkoutSetData]],
        recentWorkouts: [Workout]
    ) -> [WorkoutInsightCard] {
        var insights: [WorkoutInsightCard] = []
        
        for exercise in exercises {
            let id = exercise.id?.uuidString ?? ""
            let currentSets = exerciseSets[id] ?? []
            guard let currentBest = bestSet(from: currentSets) else { continue }
            let name = exercise.name ?? "Exercise"
            
            let history = findPreviousWorkoutsWithExercise(named: name, in: recentWorkouts)
            guard let (_, previousWE) = history.first else { continue }
            let previousSets = completedSets(from: previousWE)
            guard let previousBest = bestSetFromHistory(previousSets) else { continue }
            
            let weightDiff = currentBest.weight - previousBest.weight
            let repsDiff = currentBest.reps - Int(previousBest.reps)
            
            if weightDiff > 0 {
                insights.append(WorkoutInsightCard(
                    type: .progressiveOverload,
                    priority: .highlight,
                    icon: "arrow.up.circle.fill",
                    iconColor: .green,
                    headline: "\(name): +\(formatWeight(weightDiff))",
                    detail: "You increased weight from \(formatWeight(previousBest.weight)) to \(formatWeight(currentBest.weight)).",
                    actionTip: "Great progression. Aim to maintain reps at this new weight before adding more."
                ))
            } else if weightDiff == 0 && repsDiff > 0 {
                insights.append(WorkoutInsightCard(
                    type: .progressiveOverload,
                    priority: .highlight,
                    icon: "plus.circle.fill",
                    iconColor: .blue,
                    headline: "\(name): +\(repsDiff) Reps",
                    detail: "Same weight (\(formatWeight(currentBest.weight))) but \(repsDiff) more reps than last time.",
                    actionTip: "Once you hit 12+ reps consistently, consider adding 5 lbs."
                ))
            }
            
            if insights.count >= 2 { break }
        }
        return insights
    }
    
    // MARK: - Plateau Detection
    
    private func generatePlateauInsights(
        exercises: [Exercise],
        exerciseSets: [String: [WorkoutSetData]],
        recentWorkouts: [Workout]
    ) -> [WorkoutInsightCard] {
        var insights: [WorkoutInsightCard] = []
        
        for exercise in exercises {
            let name = exercise.name ?? "Exercise"
            let id = exercise.id?.uuidString ?? ""
            let currentSets = exerciseSets[id] ?? []
            guard let currentBest = bestSet(from: currentSets) else { continue }
            
            let history = findPreviousWorkoutsWithExercise(named: name, in: recentWorkouts)
            guard history.count >= 3 else { continue }
            
            let lastThree = history.prefix(3)
            var isPlateaued = true
            for (_, we) in lastThree {
                let sets = completedSets(from: we)
                guard let best = bestSetFromHistory(sets) else { isPlateaued = false; break }
                if abs(best.weight - currentBest.weight) > 2.5 || abs(Int(best.reps) - currentBest.reps) > 1 {
                    isPlateaued = false
                    break
                }
            }
            
            if isPlateaued {
                insights.append(WorkoutInsightCard(
                    type: .plateauDetection,
                    priority: .coaching,
                    icon: "arrow.right.circle.fill",
                    iconColor: .orange,
                    headline: "\(name) Plateau",
                    detail: "You've hit \(formatWeight(currentBest.weight)) × \(currentBest.reps) for 4 sessions in a row.",
                    actionTip: "Break through: try adding 5 lbs and dropping to \(max(1, currentBest.reps - 2)) reps, or add a pause rep set."
                ))
            }
            if insights.count >= 1 { break }
        }
        return insights
    }
    
    // MARK: - Muscle Balance
    
    private func generateMuscleBalanceInsights(recentWorkouts: [Workout]) -> [WorkoutInsightCard] {
        let lookback = Array(recentWorkouts.prefix(14))
        var pushVolume: Double = 0
        var pullVolume: Double = 0
        let pushMuscles: Set<String> = ["chest", "shoulders", "triceps", "front delts"]
        let pullMuscles: Set<String> = ["back", "biceps", "rear delts", "lats", "traps"]
        
        for workout in lookback {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for we in exercises {
                guard let muscles = we.exercise?.muscleGroups as? [String] else { continue }
                let primary = muscles.first?.lowercased() ?? ""
                let vol = totalVolumeFromSets(completedSets(from: we))
                if pushMuscles.contains(primary) { pushVolume += vol }
                else if pullMuscles.contains(primary) { pullVolume += vol }
            }
        }
        
        guard pushVolume > 0 && pullVolume > 0 else { return [] }
        let ratio = pushVolume / pullVolume
        
        if ratio > 1.8 {
            return [WorkoutInsightCard(
                type: .muscleBalance,
                priority: .coaching,
                icon: "arrow.left.arrow.right",
                iconColor: .yellow,
                headline: "Push/Pull Imbalance",
                detail: "Over your last 14 workouts, push volume is \(String(format: "%.1f", ratio))× your pull volume. Ideal is 1:1 to 1:1.5.",
                actionTip: "Add an extra rowing or pull-up movement to your next push day."
            )]
        }
        return []
    }
    
    // MARK: - Rest Time Coaching
    
    private func generateRestTimeInsights(exerciseSets: [String: [WorkoutSetData]]) -> [WorkoutInsightCard] {
        var totalRest: TimeInterval = 0
        var restCount = 0
        
        for (_, sets) in exerciseSets {
            for set in sets where set.isCompleted && set.restTime > 0 {
                totalRest += set.restTime
                restCount += 1
            }
        }
        
        guard restCount >= 3 else { return [] }
        let avgRest = totalRest / Double(restCount)
        
        if avgRest < 45 {
            return [WorkoutInsightCard(
                type: .restTimeCoaching,
                priority: .coaching,
                icon: "timer",
                iconColor: .cyan,
                headline: "Short Rest Periods",
                detail: "Your average rest was \(Int(avgRest))s between sets. For strength and hypertrophy, 60-90s is optimal.",
                actionTip: "Try resting 90s between compound lifts and 60s between isolation exercises."
            )]
        } else if avgRest > 240 {
            return [WorkoutInsightCard(
                type: .restTimeCoaching,
                priority: .info,
                icon: "timer",
                iconColor: .cyan,
                headline: "Long Rest Periods",
                detail: "Your average rest was \(Int(avgRest / 60))m \(Int(avgRest) % 60)s. Great for maximal strength but long for hypertrophy.",
                actionTip: nil
            )]
        }
        return []
    }
    
    // MARK: - Recovery Advisory
    
    private func generateRecoveryInsights(exercises: [Exercise]) -> [WorkoutInsightCard] {
        var musclesHit: [String] = []
        for exercise in exercises {
            if let muscles = exercise.muscleGroups as? [String] {
                musclesHit.append(contentsOf: muscles)
            }
        }
        let uniqueMuscles = Array(Set(musclesHit.map { $0.capitalized }))
        guard !uniqueMuscles.isEmpty else { return [] }
        
        let topMuscles = uniqueMuscles.prefix(3).joined(separator: ", ")
        return [WorkoutInsightCard(
            type: .recoveryAdvisory,
            priority: .info,
            icon: "bed.double.fill",
            iconColor: .purple,
            headline: "Recovery Window",
            detail: "You trained \(topMuscles) today. These muscles need 48-72 hours to fully recover.",
            actionTip: "Focus on sleep, protein (0.7-1g per lb bodyweight), and hydration for optimal recovery."
        )]
    }
    
    // MARK: - Consistency
    
    private func generateConsistencyInsights(recentWorkouts: [Workout], currentDuration: TimeInterval) -> [WorkoutInsightCard] {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let workoutsThisWeek = recentWorkouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startOfWeek
        }.count + 1
        
        if workoutsThisWeek >= 3 {
            return [WorkoutInsightCard(
                type: .consistencyStreak,
                priority: .info,
                icon: "flame.fill",
                iconColor: .orange,
                headline: "\(workoutsThisWeek) Workouts This Week",
                detail: "You're building serious momentum. Consistency is the #1 predictor of results.",
                actionTip: nil
            )]
        }
        
        if currentDuration > 3600 {
            let mins = Int(currentDuration / 60)
            return [WorkoutInsightCard(
                type: .workoutDuration,
                priority: .info,
                icon: "clock.fill",
                iconColor: .blue,
                headline: "\(mins) Minute Session",
                detail: "Research shows diminishing returns past 60-75 minutes due to cortisol rise.",
                actionTip: "Try supersets or shorter rest periods to keep sessions under 75 minutes."
            )]
        }
        
        return []
    }
    
    // MARK: - Formatting
    
    private func formatWeight(_ weight: Double) -> String {
        if weight >= 1000 {
            return String(format: "%.0f lbs", weight)
        }
        return weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f lbs", weight)
            : String(format: "%.1f lbs", weight)
    }
}
