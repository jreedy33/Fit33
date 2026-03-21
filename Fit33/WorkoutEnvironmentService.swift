import Foundation

// MARK: - Workout Environment Service
// Classifies exercises by workout environment and adjusts recommendations accordingly

final class WorkoutEnvironmentService {
    static let shared = WorkoutEnvironmentService()
    
    // MARK: - Environment Types
    
    enum WorkoutEnvironment: String, CaseIterable, Codable {
        case gym = "Gym"
        case home = "Home"
        case outdoor = "Outdoor"
        case hybrid = "Hybrid"
        
        var displayName: String { rawValue }
        
        var description: String {
            switch self {
            case .gym: return "Full gym with machines, racks & cables"
            case .home: return "Home setup with limited equipment"
            case .outdoor: return "Parks, playgrounds, outdoor spaces"
            case .hybrid: return "Mix of gym and home workouts"
            }
        }
        
        var icon: String {
            switch self {
            case .gym: return "building.2.fill"
            case .home: return "house.fill"
            case .outdoor: return "sun.max.fill"
            case .hybrid: return "arrow.triangle.2.circlepath"
            }
        }
        
        var color: String {
            switch self {
            case .gym: return "purple"
            case .home: return "blue"
            case .outdoor: return "green"
            case .hybrid: return "orange"
            }
        }
    }
    
    // MARK: - Exercise Environment Classification
    
    struct ExerciseEnvironmentRating {
        let gymScore: Int       // 0-100: How suitable for gym
        let homeScore: Int      // 0-100: How suitable for home
        let outdoorScore: Int   // 0-100: How suitable for outdoor
        
        func scoreFor(_ environment: WorkoutEnvironment) -> Int {
            switch environment {
            case .gym: return gymScore
            case .home: return homeScore
            case .outdoor: return outdoorScore
            case .hybrid: return max(gymScore, homeScore, outdoorScore)
            }
        }
        
        var bestEnvironment: WorkoutEnvironment {
            if gymScore >= homeScore && gymScore >= outdoorScore {
                return .gym
            } else if homeScore >= outdoorScore {
                return .home
            } else {
                return .outdoor
            }
        }
    }
    
    // MARK: - Equipment Classification
    
    // Equipment that's gym-specific
    private let gymOnlyEquipment: Set<String> = [
        "cable", "cables", "machine", "machines", "smith machine", "leg press",
        "hack squat", "pec deck", "lat pulldown", "cable crossover", "seated row machine",
        "leg extension machine", "leg curl machine", "chest press machine",
        "shoulder press machine", "preacher curl bench", "roman chair",
        "assisted pull up machine", "power rack", "squat rack"
    ]
    
    // Equipment suitable for home
    private let homeEquipment: Set<String> = [
        "dumbbells", "dumbbell", "bodyweight", "resistance bands", "band", "bands",
        "kettlebell", "kettlebells", "stability ball", "medicine ball",
        "pull up bar", "dip station", "bench", "adjustable bench",
        "trx", "suspension trainer", "foam roller", "yoga mat"
    ]
    
    // Equipment suitable for outdoor
    private let outdoorEquipment: Set<String> = [
        "bodyweight", "pull up bar", "parallel bars", "park bench",
        "resistance bands", "band", "bands", "kettlebell", "sandbag"
    ]
    
    // MARK: - Exercise Name Patterns for Classification
    
    // Exercises that are specifically gym-oriented
    private let gymExercisePatterns: [String] = [
        "cable", "machine", "smith", "lever", "assisted", "pec deck",
        "lat pulldown", "leg press", "hack squat", "seated row",
        "chest press machine", "shoulder press machine", "preacher",
        "decline bench", "incline bench", "cable crossover", "fly machine"
    ]
    
    // Exercises perfect for home/bodyweight
    private let homeExercisePatterns: [String] = [
        "push up", "pushup", "push-up", "plank", "crunch", "sit up", "situp",
        "lunge", "squat", "bodyweight", "air squat", "jumping jack",
        "mountain climber", "burpee", "chair", "wall sit", "glute bridge",
        "bird dog", "dead bug", "superman", "hollow body", "pike",
        "dip", "tricep dip", "step up", "calf raise", "floor"
    ]
    
    // Exercises great for outdoor
    private let outdoorExercisePatterns: [String] = [
        "pull up", "pullup", "chin up", "chinup", "dip", "parallel bar",
        "sprint", "run", "jog", "walk", "hill", "stair", "jump", "plyometric",
        "box jump", "broad jump", "bear crawl", "crab walk", "farmer walk",
        "park", "outdoor", "playground"
    ]
    
    // "Weird" or obscure exercises to deprioritize
    private let obscureExercisePatterns: [String] = [
        "under table", "couch", "doorway", "towel", "broomstick", "suitcase",
        "grocery bag", "water bottle", "backpack weighted", "gallon jug"
    ]
    
    // MARK: - User Preference
    
    private var _userEnvironment: WorkoutEnvironment = .gym
    var userEnvironment: WorkoutEnvironment {
        get { _userEnvironment }
        set {
            _userEnvironment = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "preferred_workout_environment")
            #if DEBUG
            AppLogger.debug("📍 [ENVIRONMENT] Set to: \(newValue.displayName)", category: .workout)
            #endif
        }
    }
    
    private init() {
        loadUserPreference()
    }
    
    private func loadUserPreference() {
        if let saved = UserDefaults.standard.string(forKey: "preferred_workout_environment"),
           let environment = WorkoutEnvironment(rawValue: saved) {
            _userEnvironment = environment
        }
    }
    
    // MARK: - Classification
    
    /// Get environment rating for an exercise based on name and equipment
    func getEnvironmentRating(exerciseName: String, equipment: String) -> ExerciseEnvironmentRating {
        let nameLower = exerciseName.lowercased()
        let equipLower = equipment.lowercased()
        
        var gymScore = 50
        var homeScore = 50
        var outdoorScore = 30
        
        // Check for obscure/weird exercises - heavily penalize
        for pattern in obscureExercisePatterns {
            if nameLower.contains(pattern) {
                gymScore = max(gymScore - 40, 10)
                homeScore = max(homeScore - 30, 10)
                outdoorScore = max(outdoorScore - 30, 10)
            }
        }
        
        // Equipment-based scoring
        for equip in gymOnlyEquipment {
            if equipLower.contains(equip) {
                gymScore = min(gymScore + 40, 100)
                homeScore = max(homeScore - 30, 10)
                outdoorScore = max(outdoorScore - 40, 5)
            }
        }
        
        for equip in homeEquipment {
            if equipLower.contains(equip) {
                homeScore = min(homeScore + 25, 100)
            }
        }
        
        for equip in outdoorEquipment {
            if equipLower.contains(equip) {
                outdoorScore = min(outdoorScore + 20, 90)
            }
        }
        
        // Name-based scoring
        for pattern in gymExercisePatterns {
            if nameLower.contains(pattern) {
                gymScore = min(gymScore + 30, 100)
                homeScore = max(homeScore - 20, 15)
            }
        }
        
        for pattern in homeExercisePatterns {
            if nameLower.contains(pattern) {
                homeScore = min(homeScore + 30, 100)
                gymScore = min(gymScore + 10, 100) // Still fine at gym
                outdoorScore = min(outdoorScore + 15, 85)
            }
        }
        
        for pattern in outdoorExercisePatterns {
            if nameLower.contains(pattern) {
                outdoorScore = min(outdoorScore + 35, 100)
                gymScore = min(gymScore + 10, 100) // Pull-ups still great at gym
            }
        }
        
        // Bodyweight exercises are universal
        if equipLower == "bodyweight" || equipLower.isEmpty {
            homeScore = max(homeScore, 70)
            outdoorScore = max(outdoorScore, 60)
            gymScore = max(gymScore, 65)
        }
        
        // Barbell/heavy equipment = gym
        if equipLower.contains("barbell") || equipLower.contains("rack") {
            gymScore = min(gymScore + 30, 100)
            homeScore = max(homeScore - 20, 20) // Some home gyms have barbells
        }
        
        return ExerciseEnvironmentRating(
            gymScore: gymScore,
            homeScore: homeScore,
            outdoorScore: outdoorScore
        )
    }
    
    /// Get environment boost/penalty for scoring
    func getEnvironmentScoreAdjustment(exerciseName: String, equipment: String) -> Int {
        let rating = getEnvironmentRating(exerciseName: exerciseName, equipment: equipment)
        let environmentScore = rating.scoreFor(userEnvironment)
        
        // Convert to adjustment: -100 to +100
        // 50 = neutral (0 adjustment)
        // 100 = +100 boost
        // 0 = -100 penalty
        let adjustment = (environmentScore - 50) * 2
        
        return adjustment
    }
    
    /// Check if an exercise is appropriate for the user's environment
    func isAppropriateForUserEnvironment(exerciseName: String, equipment: String) -> Bool {
        let rating = getEnvironmentRating(exerciseName: exerciseName, equipment: equipment)
        let score = rating.scoreFor(userEnvironment)
        return score >= 40 // At least 40% suitable
    }
    
    /// Filter exercises by environment suitability
    func filterByEnvironment(_ exercises: [Exercise], minScore: Int = 40) -> [Exercise] {
        return exercises.filter { exercise in
            let name = exercise.name ?? ""
            let equipment = exercise.equipment ?? "Bodyweight"
            let rating = getEnvironmentRating(exerciseName: name, equipment: equipment)
            return rating.scoreFor(userEnvironment) >= minScore
        }
    }
    
    // MARK: - Equipment Suggestions by Environment
    
    func suggestedEquipment(for environment: WorkoutEnvironment) -> [String] {
        switch environment {
        case .gym:
            return ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell", "EZ Bar", "Smith Machine", "Bench"]
        case .home:
            return ["Dumbbells", "Resistance Bands", "Kettlebell", "Bodyweight", "Pull-Up Bar", "Bench", "Stability Ball"]
        case .outdoor:
            return ["Bodyweight", "Resistance Bands", "Pull-Up Bar", "Kettlebell"]
        case .hybrid:
            return ["Dumbbells", "Barbell", "Cables", "Bodyweight", "Resistance Bands", "Kettlebell", "Machines"]
        }
    }
}

// MARK: - Integration with Workout Generation

extension WorkoutEnvironmentService {
    
    /// Classify an exercise for display purposes
    func classifyExercise(_ exerciseName: String, equipment: String) -> (label: String, icon: String) {
        let rating = getEnvironmentRating(exerciseName: exerciseName, equipment: equipment)
        let best = rating.bestEnvironment
        
        switch best {
        case .gym:
            return ("Gym", "building.2.fill")
        case .home:
            return ("Home", "house.fill")
        case .outdoor:
            return ("Outdoor", "sun.max.fill")
        case .hybrid:
            return ("Any", "checkmark.circle.fill")
        }
    }
    
    /// Get exercises ranked by environment suitability
    func rankByEnvironment(_ exercises: [Exercise]) -> [Exercise] {
        return exercises.sorted { ex1, ex2 in
            let score1 = getEnvironmentRating(
                exerciseName: ex1.name ?? "",
                equipment: ex1.equipment ?? ""
            ).scoreFor(userEnvironment)
            
            let score2 = getEnvironmentRating(
                exerciseName: ex2.name ?? "",
                equipment: ex2.equipment ?? ""
            ).scoreFor(userEnvironment)
            
            return score1 > score2
        }
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension WorkoutEnvironmentService {
    func printClassification(for exerciseName: String, equipment: String) {
        let rating = getEnvironmentRating(exerciseName: exerciseName, equipment: equipment)
        AppLogger.debug("""
        📍 Environment Classification: \(exerciseName)
        ├── Equipment: \(equipment)
        ├── Gym Score: \(rating.gymScore)
        ├── Home Score: \(rating.homeScore)
        ├── Outdoor Score: \(rating.outdoorScore)
        └── Best Environment: \(rating.bestEnvironment.displayName)
        """, category: .workout)
    }
}
#endif

