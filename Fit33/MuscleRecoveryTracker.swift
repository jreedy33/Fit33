import Foundation

// MARK: - Program Muscle Recovery Tracker
/// Tracks muscle strain and recovery to intelligently schedule workouts
/// Prevents overtraining and ensures optimal muscle group rotation

class ProgramMuscleRecoveryTracker {
    static let shared = ProgramMuscleRecoveryTracker()
    
    private let userDefaultsKey = "muscleRecoveryData"
    
    private init() {
        loadRecoveryData()
    }
    
    // MARK: - Data Models
    
    struct MuscleState: Codable {
        let muscleGroup: String
        let lastWorkoutDate: Date
        let intensity: Intensity
        let volume: Int // Total sets
        var recoveryPercentage: Double // 0-100%
        
        enum Intensity: String, Codable {
            case light = "Light"
            case moderate = "Moderate"
            case heavy = "Heavy"
        }
        
        // Recovery time in hours based on intensity
        var recoveryHours: Int {
            switch intensity {
            case .light: return 24
            case .moderate: return 48
            case .heavy: return 72
            }
        }
        
        // Calculate current recovery percentage
        func currentRecovery(at date: Date = Date()) -> Double {
            let hoursSinceWorkout = date.timeIntervalSince(lastWorkoutDate) / 3600
            let recoveryProgress = hoursSinceWorkout / Double(recoveryHours)
            return min(100, recoveryProgress * 100)
        }
    }
    
    struct MuscleWorkoutRecord: Codable {
        let date: Date
        let muscleGroups: [String]
        let exercises: [String]
        let totalVolume: [String: Int] // Muscle -> sets
        let intensity: [String: MuscleState.Intensity]
    }
    
    // MARK: - Stored Data
    
    private(set) var muscleStates: [String: MuscleState] = [:]
    private(set) var workoutHistory: [MuscleWorkoutRecord] = []
    
    // All tracked muscle groups
    static let allMuscleGroups: [String] = [
        "Chest", "Upper Chest", "Lower Chest",
        "Back", "Lats", "Upper Back", "Lower Back",
        "Shoulders", "Front Delts", "Side Delts", "Rear Delts", "Rotator Cuff",
        "Biceps", "Triceps", "Forearms",
        "Quads", "Hamstrings", "Glutes", "Calves",
        "Core", "Abs", "Obliques", "Hip Flexors",
        "Traps", "Inner Thighs", "Neck"
    ]
    
    // MARK: - Recovery Status
    
    /// Get recovery status for a specific muscle group
    func getRecoveryStatus(for muscle: String) -> RecoveryStatus {
        guard let state = muscleStates[muscle] else {
            return .fullyRecovered // Never trained = fully recovered
        }
        
        let recovery = state.currentRecovery()
        
        if recovery >= 100 {
            return .fullyRecovered
        } else if recovery >= 75 {
            return .mostlyRecovered
        } else if recovery >= 50 {
            return .partiallyRecovered
        } else {
            return .stillRecovering
        }
    }
    
    enum RecoveryStatus: String {
        case fullyRecovered = "Fully Recovered"
        case mostlyRecovered = "Mostly Recovered"
        case partiallyRecovered = "Partially Recovered"
        case stillRecovering = "Still Recovering"
        
        var canTrain: Bool {
            switch self {
            case .fullyRecovered, .mostlyRecovered: return true
            case .partiallyRecovered, .stillRecovering: return false
            }
        }
        
        var color: String {
            switch self {
            case .fullyRecovered: return "green"
            case .mostlyRecovered: return "yellow"
            case .partiallyRecovered: return "orange"
            case .stillRecovering: return "red"
            }
        }
    }
    
    /// Get all muscles ready to train
    func getMusclesReadyToTrain() -> [String] {
        return Self.allMuscleGroups.filter { muscle in
            getRecoveryStatus(for: muscle).canTrain
        }
    }
    
    /// Get muscles that should be avoided
    func getMusclesNeedingRest() -> [String] {
        return Self.allMuscleGroups.filter { muscle in
            !getRecoveryStatus(for: muscle).canTrain
        }
    }
    
    /// Get recovery percentage for a muscle
    func getRecoveryPercentage(for muscle: String) -> Double {
        return muscleStates[muscle]?.currentRecovery() ?? 100.0
    }
    
    // MARK: - Record Workout
    
    /// Record a completed workout
    func recordWorkout(
        muscles: [String],
        exercises: [String],
        volumePerMuscle: [String: Int],
        intensityPerMuscle: [String: MuscleState.Intensity]
    ) {
        let now = Date()
        
        // Update muscle states
        for muscle in muscles {
            let volume = volumePerMuscle[muscle] ?? 0
            let intensity = intensityPerMuscle[muscle] ?? .moderate
            
            muscleStates[muscle] = MuscleState(
                muscleGroup: muscle,
                lastWorkoutDate: now,
                intensity: intensity,
                volume: volume,
                recoveryPercentage: 0
            )
        }
        
        // Add to history
        let record = MuscleWorkoutRecord(
            date: now,
            muscleGroups: muscles,
            exercises: exercises,
            totalVolume: volumePerMuscle,
            intensity: intensityPerMuscle
        )
        workoutHistory.append(record)
        
        // Keep only last 30 days of history
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        workoutHistory = workoutHistory.filter { $0.date > thirtyDaysAgo }
        
        saveRecoveryData()
        
        print("💪 Recorded workout for: \(muscles.joined(separator: ", "))")
    }
    
    /// Record workout from completed exercises
    func recordWorkoutFromExercises(_ exercises: [DynamicProgramGenerator.GeneratedExercise], intensity: MuscleState.Intensity = .moderate) {
        var volumePerMuscle: [String: Int] = [:]
        var intensityPerMuscle: [String: MuscleState.Intensity] = [:]
        var allMuscles: Set<String> = []
        
        // Map exercises to muscles (simplified - would need exercise database lookup for accuracy)
        for exercise in exercises {
            let muscles = inferMusclesFromExercise(exercise.exerciseName)
            for muscle in muscles {
                allMuscles.insert(muscle)
                volumePerMuscle[muscle, default: 0] += exercise.sets
                intensityPerMuscle[muscle] = intensity
            }
        }
        
        recordWorkout(
            muscles: Array(allMuscles),
            exercises: exercises.map { $0.exerciseName },
            volumePerMuscle: volumePerMuscle,
            intensityPerMuscle: intensityPerMuscle
        )
    }
    
    // MARK: - Muscle Inference
    
    private func inferMusclesFromExercise(_ exerciseName: String) -> [String] {
        let name = exerciseName.lowercased()
        var muscles: [String] = []
        
        // Chest
        if name.contains("bench") || name.contains("chest") || name.contains("push-up") || name.contains("pushup") || name.contains("fly") || name.contains("dip") {
            muscles.append("Chest")
        }
        
        // Back
        if name.contains("row") || name.contains("pull") || name.contains("lat") || name.contains("back") || name.contains("deadlift") {
            muscles.append("Back")
        }
        
        // Shoulders
        if name.contains("shoulder") || name.contains("press") && !name.contains("bench") || name.contains("raise") || name.contains("delt") {
            muscles.append("Shoulders")
        }
        
        // Biceps
        if name.contains("curl") || name.contains("bicep") {
            muscles.append("Biceps")
        }
        
        // Triceps
        if name.contains("tricep") || name.contains("extension") || name.contains("pushdown") || name.contains("skull") || name.contains("dip") {
            muscles.append("Triceps")
        }
        
        // Legs
        if name.contains("squat") || name.contains("leg") || name.contains("quad") {
            muscles.append("Quads")
        }
        if name.contains("hamstring") || name.contains("curl") && name.contains("leg") || name.contains("deadlift") {
            muscles.append("Hamstrings")
        }
        if name.contains("glute") || name.contains("hip thrust") || name.contains("squat") || name.contains("lunge") {
            muscles.append("Glutes")
        }
        if name.contains("calf") || name.contains("calves") {
            muscles.append("Calves")
        }
        
        // Core
        if name.contains("plank") || name.contains("crunch") || name.contains("ab") || name.contains("core") || name.contains("twist") {
            muscles.append("Core")
        }
        
        // Default to general if nothing matched
        if muscles.isEmpty {
            muscles.append("General")
        }
        
        return muscles
    }
    
    // MARK: - Weekly Volume Tracking
    
    /// Get total weekly volume for a muscle group
    func getWeeklyVolume(for muscle: String) -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        
        return workoutHistory
            .filter { $0.date > weekAgo }
            .compactMap { $0.totalVolume[muscle] }
            .reduce(0, +)
    }
    
    /// Get recommended weekly volume targets
    func getRecommendedWeeklyVolume(for muscle: String, experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel) -> ClosedRange<Int> {
        let baseVolume: ClosedRange<Int>
        
        switch muscle {
        case "Chest", "Back":
            baseVolume = 10...20
        case "Shoulders", "Biceps", "Triceps":
            baseVolume = 8...16
        case "Quadriceps", "Hamstrings", "Glutes":
            baseVolume = 10...18
        case "Calves", "Core", "Forearms":
            baseVolume = 6...12
        default:
            baseVolume = 8...15
        }
        
        let multiplier: Double
        switch experience {
        case .beginner: multiplier = 0.7
        case .intermediate: multiplier = 1.0
        case .advanced: multiplier = 1.3
        }
        
        return Int(Double(baseVolume.lowerBound) * multiplier)...Int(Double(baseVolume.upperBound) * multiplier)
    }
    
    /// Check if muscle is under or over trained this week
    func getVolumeStatus(for muscle: String, experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel) -> VolumeStatus {
        let current = getWeeklyVolume(for: muscle)
        let recommended = getRecommendedWeeklyVolume(for: muscle, experience: experience)
        
        if current < recommended.lowerBound {
            return .underTrained
        } else if current > recommended.upperBound {
            return .overTrained
        } else {
            return .optimal
        }
    }
    
    enum VolumeStatus: String {
        case underTrained = "Under Trained"
        case optimal = "Optimal"
        case overTrained = "Over Trained"
        
        var description: String {
            switch self {
            case .underTrained: return "Could use more volume"
            case .optimal: return "Perfect volume"
            case .overTrained: return "Consider reducing volume"
            }
        }
    }
    
    // MARK: - Smart Recommendations
    
    /// Get priority muscles that need training
    func getPriorityMuscles(experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel) -> [String] {
        let readyMuscles = getMusclesReadyToTrain()
        
        // Sort by: 1) Under-trained muscles, 2) Longest since last workout
        return readyMuscles.sorted { m1, m2 in
            let v1 = getVolumeStatus(for: m1, experience: experience)
            let v2 = getVolumeStatus(for: m2, experience: experience)
            
            if v1 == .underTrained && v2 != .underTrained {
                return true
            } else if v1 != .underTrained && v2 == .underTrained {
                return false
            }
            
            // Then by recovery (higher = needs training more)
            let r1 = getRecoveryPercentage(for: m1)
            let r2 = getRecoveryPercentage(for: m2)
            return r1 > r2
        }
    }
    
    /// Get complementary muscles that work well together
    func getComplementaryMuscles(for primaryMuscle: String) -> [String] {
        let complementMap: [String: [String]] = [
            "Chest": ["Triceps", "Shoulders"],
            "Back": ["Biceps", "Rear Delts"],
            "Shoulders": ["Triceps", "Traps"],
            "Quads": ["Hamstrings", "Glutes", "Calves"],
            "Hamstrings": ["Glutes", "Lower Back"],
            "Glutes": ["Hamstrings", "Core"],
            "Biceps": ["Forearms"],
            "Triceps": ["Chest", "Shoulders"],
            "Front Delts": ["Chest", "Triceps"],
            "Rear Delts": ["Back", "Upper Back"],
            "Lats": ["Biceps", "Rear Delts"],
            "Core": ["Glutes", "Lower Back"]
        ]
        
        return complementMap[primaryMuscle] ?? []
    }
    
    /// Get antagonist muscles for supersets
    func getAntagonistMuscles(for muscle: String) -> [String] {
        let antagonistMap: [String: [String]] = [
            "Chest": ["Back"],
            "Back": ["Chest"],
            "Biceps": ["Triceps"],
            "Triceps": ["Biceps"],
            "Quads": ["Hamstrings"],
            "Hamstrings": ["Quads"],
            "Front Delts": ["Rear Delts"],
            "Rear Delts": ["Front Delts"]
        ]
        
        return antagonistMap[muscle] ?? []
    }
    
    // MARK: - Persistence
    
    private func saveRecoveryData() {
        let encoder = JSONEncoder()
        
        if let statesData = try? encoder.encode(muscleStates) {
            UserDefaults.standard.set(statesData, forKey: "\(userDefaultsKey)_states")
        }
        
        if let historyData = try? encoder.encode(workoutHistory) {
            UserDefaults.standard.set(historyData, forKey: "\(userDefaultsKey)_history")
        }
    }
    
    private func loadRecoveryData() {
        let decoder = JSONDecoder()
        
        if let statesData = UserDefaults.standard.data(forKey: "\(userDefaultsKey)_states"),
           let states = try? decoder.decode([String: MuscleState].self, from: statesData) {
            muscleStates = states
        }
        
        if let historyData = UserDefaults.standard.data(forKey: "\(userDefaultsKey)_history"),
           let history = try? decoder.decode([MuscleWorkoutRecord].self, from: historyData) {
            workoutHistory = history
        }
    }
    
    /// Clear all recovery data (for testing or reset)
    func clearAllData() {
        muscleStates = [:]
        workoutHistory = []
        UserDefaults.standard.removeObject(forKey: "\(userDefaultsKey)_states")
        UserDefaults.standard.removeObject(forKey: "\(userDefaultsKey)_history")
        print("🗑️ Cleared all recovery tracking data")
    }
}

// MARK: - Recovery Summary View Model

extension ProgramMuscleRecoveryTracker {
    
    struct RecoverySummary {
        let muscleGroup: String
        let recoveryPercentage: Double
        let status: RecoveryStatus
        let weeklyVolume: Int
        let recommendedVolume: ClosedRange<Int>
        let lastWorkout: Date?
        let hoursSinceWorkout: Int?
    }
    
    func getRecoverySummary(experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel) -> [RecoverySummary] {
        return Self.allMuscleGroups.map { muscle in
            let state = muscleStates[muscle]
            let hoursSince = state.map { Int(Date().timeIntervalSince($0.lastWorkoutDate) / 3600) }
            
            return RecoverySummary(
                muscleGroup: muscle,
                recoveryPercentage: getRecoveryPercentage(for: muscle),
                status: getRecoveryStatus(for: muscle),
                weeklyVolume: getWeeklyVolume(for: muscle),
                recommendedVolume: getRecommendedWeeklyVolume(for: muscle, experience: experience),
                lastWorkout: state?.lastWorkoutDate,
                hoursSinceWorkout: hoursSince
            )
        }
    }
}

