import Foundation

class RecoveryDayEngine {
    static let shared = RecoveryDayEngine()
    private init() {}
    
    func generateRoutine() -> RecoveryRoutine {
        let tracker = ProgramMuscleRecoveryTracker.shared
        
        // Get muscles below full recovery, sorted by lowest recovery first
        var muscleRecovery: [(muscle: String, recovery: Double)] = []
        let trackedMuscles = ["Chest", "Back", "Shoulders", "Quads", "Hamstrings", "Glutes",
                              "Biceps", "Triceps", "Core", "Calves", "Lats", "Traps"]
        
        for muscle in trackedMuscles {
            let pct = tracker.getRecoveryPercentage(for: muscle)
            if pct < 100 {
                muscleRecovery.append((muscle, pct))
            }
        }
        
        muscleRecovery.sort { $0.recovery < $1.recovery }
        
        var selectedExercises: [RecoveryExercise] = []
        var targetMuscles: [String] = []
        
        // Start with breathing warm-up
        if let warmup = RecoveryExerciseDatabase.breathingExercises.first {
            selectedExercises.append(warmup)
        }
        
        if muscleRecovery.isEmpty {
            // No specific recovery needed: build a general full-body routine
            selectedExercises.append(contentsOf: RecoveryExerciseDatabase.fullBodyExercises.prefix(2))
            selectedExercises.append(contentsOf: RecoveryExerciseDatabase.backExercises.filter { $0.category == .stretch }.prefix(1))
            selectedExercises.append(contentsOf: RecoveryExerciseDatabase.legExercises.filter { $0.category == .stretch }.prefix(1))
            selectedExercises.append(contentsOf: RecoveryExerciseDatabase.shoulderExercises.filter { $0.category == .mobility }.prefix(1))
            targetMuscles = ["Full Body"]
        } else {
            // Target the 3 most fatigued muscle groups
            let priorityMuscles = muscleRecovery.prefix(3)
            targetMuscles = priorityMuscles.map { $0.muscle }
            
            for (muscle, _) in priorityMuscles {
                let available = RecoveryExerciseDatabase.exercises(for: muscle)
                
                // Pick 1 stretch + 1 foam roll or mobility per muscle
                if let stretch = available.first(where: { $0.category == .stretch && !selectedExercises.contains($0) }) {
                    selectedExercises.append(stretch)
                }
                if let foamOrMobility = available.first(where: { ($0.category == .foamRolling || $0.category == .mobility) && !selectedExercises.contains($0) }) {
                    selectedExercises.append(foamOrMobility)
                }
            }
            
            // Add a general mobility drill if under 6 exercises
            if selectedExercises.count < 6 {
                if let mobility = RecoveryExerciseDatabase.backExercises.first(where: { $0.category == .mobility && !selectedExercises.contains($0) }) {
                    selectedExercises.append(mobility)
                }
            }
        }
        
        // End with cool-down breathing
        if let cooldown = RecoveryExerciseDatabase.breathingExercises.last,
           !selectedExercises.contains(cooldown) {
            selectedExercises.append(cooldown)
        }
        
        let totalSeconds = selectedExercises.reduce(0) { $0 + $1.durationSeconds }
        let totalMinutes = max(1, Int(ceil(Double(totalSeconds) / 60.0)))
        
        let title: String
        if targetMuscles.count == 1 && targetMuscles.first == "Full Body" {
            title = "Full Body Recovery"
        } else {
            title = "Recovery: \(targetMuscles.prefix(2).joined(separator: " & ")) Focus"
        }
        
        return RecoveryRoutine(
            title: title,
            targetMuscles: targetMuscles,
            exercises: selectedExercises,
            totalDurationMinutes: totalMinutes,
            difficulty: .beginner,
            generatedAt: Date()
        )
    }
    
    var shouldShowRecoveryWidget: Bool {
        let tracker = ProgramMuscleRecoveryTracker.shared
        let trackedMuscles = ["Chest", "Back", "Shoulders", "Quads", "Hamstrings", "Glutes",
                              "Biceps", "Triceps", "Core"]
        
        for muscle in trackedMuscles {
            if tracker.getRecoveryPercentage(for: muscle) < 85 {
                return true
            }
        }
        return false
    }
    
    var topRecoveringMuscles: [(muscle: String, recovery: Double)] {
        let tracker = ProgramMuscleRecoveryTracker.shared
        let trackedMuscles = ["Chest", "Back", "Shoulders", "Quads", "Hamstrings", "Glutes",
                              "Biceps", "Triceps", "Core"]
        
        return trackedMuscles
            .map { (muscle: $0, recovery: tracker.getRecoveryPercentage(for: $0)) }
            .filter { $0.recovery < 100 }
            .sorted { $0.recovery < $1.recovery }
    }
}
