import Foundation

// MARK: - Exercise Filter Service
/// Centralized filtering logic for exercises across the app
/// Handles category mapping, equipment normalization, and muscle group matching
/// Updated for 7000+ exercise library with video code matching

final class ExerciseFilterService {
    static let shared = ExerciseFilterService()
    
    private init() {}
    
    // MARK: - Exercise Types (Top Level Filter)
    /// High-level exercise type classification
    enum ExerciseType: String, CaseIterable {
        case strength = "Strength"
        case cardio = "Cardio"
        case plyometrics = "Plyometrics"
        case stretching = "Stretching"
        
        var icon: String {
            switch self {
            case .strength: return "dumbbell.fill"
            case .cardio: return "heart.fill"
            case .plyometrics: return "bolt.fill"
            case .stretching: return "figure.flexibility"
            }
        }
        
        var color: String {
            switch self {
            case .strength: return "blue"
            case .cardio: return "red"
            case .plyometrics: return "orange"
            case .stretching: return "green"
            }
        }
        
        /// Categories that belong to this exercise type
        var categories: [String] {
            switch self {
            case .strength:
                return ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body", "Neck"]
            case .cardio:
                return ["Cardio"]
            case .plyometrics:
                return ["Plyometrics"]
            case .stretching:
                return ["Stretching"]
            }
        }
    }
    
    /// Determine exercise type from category
    static func exerciseType(for category: String?) -> ExerciseType {
        guard let category = category?.lowercased().replacingOccurrences(of: "_", with: " ") else { return .strength }
        
        switch category {
        case "cardio":
            return .cardio
        case "plyometrics":
            return .plyometrics
        case "stretching":
            return .stretching
        default:
            return .strength
        }
    }
    
    /// Normalize category names (handles underscores, etc.)
    static func normalizedCategory(_ category: String?) -> String {
        guard let cat = category else { return "Full Body" }
        return cat.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    /// Determine exercise type from exercise name (for smart classification)
    /// This is the PRIMARY classification method - it overrides category-based classification
    static func classifyExerciseType(name: String?, category: String?, equipment: String?) -> ExerciseType {
        let nameLower = (name ?? "").lowercased()
        let categoryLower = (category ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
        let equipLower = (equipment ?? "").lowercased()
        
        // Check category first (if explicitly set to these types)
        if categoryLower == "cardio" { return .cardio }
        if categoryLower == "plyometrics" { return .plyometrics }
        if categoryLower == "stretching" { return .stretching }
        
        // ===========================================
        // PLYOMETRIC DETECTION (explosive movements)
        // ===========================================
        let plyoKeywords = [
            // Jump variations
            "jump", "jumping", "jumps",
            // Hop variations  
            "hop", "hopping", "hops",
            // Bounds
            "bound", "bounding", "bounds",
            // Explicit plyo
            "plyo", "plyometric", "explosive",
            // Specific exercises
            "burpee", "box jump", "jumping jack", "tuck jump", "broad jump", 
            "depth jump", "power skip", "clap push", "medicine ball throw", 
            "slam", "box step", "leap", "skip", "sprint",
            // Power movements
            "power clean", "power snatch", "hang clean", "hang snatch",
            "push jerk", "split jerk", "clean and jerk",
            // Other explosive
            "throw", "toss", "launch"
        ]
        
        // Check for plyometric keywords
        for keyword in plyoKeywords {
            if nameLower.contains(keyword) {
                // Exclude non-plyometric uses of these words
                let exclusions = ["jumping rope stretch", "box squat", "box press"]
                if !exclusions.contains(where: { nameLower.contains($0) }) {
                    return .plyometrics
                }
            }
        }
        
        // ===========================================
        // CARDIO DETECTION (sustained aerobic)
        // ===========================================
        let cardioKeywords = [
            // Running/locomotion
            "run", "running", "jog", "jogging", "sprint", "sprinting",
            "walk", "walking", "march", "marching",
            // Cycling
            "bike", "biking", "cycle", "cycling", "spin",
            // Rowing (machine, not barbell row)
            "rowing machine", "rower", "erg", "ergometer",
            // Swimming
            "swim", "swimming",
            // Machines
            "elliptical", "treadmill", "stair climber", "stepper", "step machine",
            "stairmaster", "stair mill",
            // Jump rope
            "jump rope", "skipping rope", "rope skip",
            // Other cardio
            "aerobic", "cardio", "hiit", "conditioning",
            "mountain climber", "high knees", "butt kick", "lateral shuffle"
        ]
        
        // Exclude strength exercises that might have cardio-like names
        let isStrengthRow = nameLower.contains("row") && 
            (nameLower.contains("bent") || nameLower.contains("seated") || 
             nameLower.contains("cable") || nameLower.contains("dumbbell") || 
             nameLower.contains("barbell") || nameLower.contains("upright") || 
             nameLower.contains("inverted") || nameLower.contains("t-bar") ||
             nameLower.contains("pendlay") || nameLower.contains("machine"))
        
        if !isStrengthRow {
            for keyword in cardioKeywords {
                if nameLower.contains(keyword) {
                    return .cardio
                }
            }
        }
        
        // ===========================================
        // STRETCHING DETECTION (flexibility/mobility)
        // ===========================================
        let stretchKeywords = [
            // Explicit stretch
            "stretch", "stretching", "stretches",
            // Mobility
            "mobility", "flexible", "flexibility",
            // Yoga poses
            "yoga", "pigeon", "cobra", "child's pose", "cat cow", "cat-cow",
            "downward dog", "upward dog", "warrior", "triangle pose",
            "seated forward", "standing forward",
            // Foam rolling
            "foam roll", "foam roller", "myofascial", "smr",
            // Other flexibility
            "pnf", "static hold", "dynamic stretch", "hip opener",
            "doorway stretch", "wall stretch", "band stretch",
            "shoulder stretch", "chest stretch", "quad stretch",
            "hamstring stretch", "calf stretch", "hip stretch",
            "neck stretch", "back stretch", "arm stretch",
            "thoracic", "t-spine", "spine mobility"
        ]
        
        for keyword in stretchKeywords {
            if nameLower.contains(keyword) {
                return .stretching
            }
        }
        
        // ===========================================
        // DEFAULT: STRENGTH (weight training)
        // ===========================================
        return .strength
    }
    
    // MARK: - Categories
    /// All available exercise categories
    static let allCategories = [
        "All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core", 
        "Full Body", "Plyometrics", "Stretching", "Cardio", "Neck"
    ]
    
    /// Categories filtered by exercise type
    static func categories(for exerciseType: ExerciseType) -> [String] {
        return ["All"] + exerciseType.categories
    }
    
    /// Map CSV category names to app category names
    static func normalizeCategory(_ rawCategory: String?) -> String {
        guard let category = rawCategory?.trimmingCharacters(in: .whitespaces) else { return "Full Body" }
        
        switch category.lowercased() {
        case "chest": return "Chest"
        case "back": return "Back"
        case "legs": return "Legs"
        case "shoulders": return "Shoulders"
        case "arms": return "Arms"
        case "core": return "Core"
        case "full body": return "Full Body"
        case "plyometrics": return "Plyometrics"
        case "stretching": return "Stretching"
        case "cardio": return "Cardio"
        case "neck": return "Neck"
        default:
            // Try to infer from primary muscle
            return "Full Body"
        }
    }
    
    // MARK: - Workout Locations
    enum WorkoutLocation: String, CaseIterable {
        case gym = "Gym"
        case home = "Home"
        case hybrid = "Hybrid"
        case outdoor = "Outdoor"
        
        var displayName: String { rawValue }
        
        var description: String {
            switch self {
            case .gym: return "Commercial gym with full equipment"
            case .home: return "Home workouts with minimal equipment"
            case .hybrid: return "Mix of home and gym equipment"
            case .outdoor: return "Park, outdoor, or travel workouts"
            }
        }
    }
    
    // MARK: - Location-Based Equipment Configuration
    
    /// Primary equipment shown for each location (strategic defaults)
    static let primaryEquipmentByLocation: [WorkoutLocation: [String]] = [
        .gym: [
            "Barbell",           // #1 priority for strength
            "Dumbbells",         // Essential for variety
            "Cables",            // Great for isolation
            "Machines",          // Beginner-friendly, safe
            "Bench",             // Required for many exercises
            "Smith Machine",     // Guided barbell alternative
            "Power Rack",        // For heavy compound lifts
            "Pull-Up Bar",       // Bodyweight strength
        ],
        .home: [
            "Bodyweight",        // Always available
            "Resistance Bands",  // Portable, versatile
            "Dumbbells",         // Most common home equipment
            "Stability Ball",    // Core work
            "TRX/Rings",         // Advanced bodyweight
            "Kettlebell",        // Compact, effective
        ],
        .hybrid: [
            "Dumbbells",         // Bridge between gym and home
            "Bodyweight",        // Always available
            "Resistance Bands",  // Portable
            "Kettlebell",        // Compact power
            "Bench",             // If they have one
            "Pull-Up Bar",       // Door mount option
        ],
        .outdoor: [
            "Bodyweight",        // Primary for outdoor
            "Resistance Bands",  // Portable
            "Kettlebell",        // Park workouts
            "Pull-Up Bar",       // Outdoor bars
            "TRX/Rings",         // Tree/bar suspension
        ]
    ]
    
    /// Secondary equipment (shown in "Show More" dropdown)
    static let secondaryEquipmentByLocation: [WorkoutLocation: [String]] = [
        .gym: [
            "Kettlebell",        // Good but less common in some gyms
            "TRX/Rings",         // Not all gyms have
            "Landmine",          // Specialty attachment
            "Sled",              // Performance gyms only
            "Medicine Ball",     // Often available
            "Battle Ropes",      // Cardio/conditioning
            "Foam Roller",       // Recovery
        ],
        .home: [
            "Barbell",           // Home gym upgrade
            "Cables",            // Home cable machine
            "Bench",             // If they invested
            "Medicine Ball",     // Takes space
            "Foam Roller",       // Recovery
            "Chair",             // Improvised (low priority)
            "Wall",              // Improvised (low priority)
        ],
        .hybrid: [
            "Cables",            // Gym access
            "Machines",          // Gym access
            "Smith Machine",     // Gym access
            "Stability Ball",    // Home option
            "Medicine Ball",     // Either location
            "TRX/Rings",         // Portable
        ],
        .outdoor: [
            "Dumbbells",         // If they carry
            "Medicine Ball",     // Park workouts
            "Bench",             // Park benches
            "Stability Ball",    // Less common outdoors
        ]
    ]
    
    /// Equipment that should NEVER appear for certain locations
    static let excludedEquipmentByLocation: [WorkoutLocation: Set<String>] = [
        .gym: ["Chair", "Wall", "Bottle", "Improvised", "Towel"],
        .home: ["Sled", "Power Rack", "Hack Squat"],  // Too large
        .hybrid: ["Sled"],
        .outdoor: ["Machines", "Cables", "Smith Machine", "Sled"]
    ]
    
    // MARK: - Exercise Context Penalties
    
    /// Exercises that should be deprioritized based on context
    static let floorLyingKeywords: Set<String> = [
        "lying", "supine", "floor press", "floor fly", 
        "on floor", "floor dumbbell", "lying down", "floor "
    ]
    
    /// Equipment considered "improvised" or low-quality for serious training
    static let improvisedEquipment: Set<String> = [
        "chair", "wall", "bottle", "towel", "improvised", "stairs", "step"
    ]
    
    /// Check if exercise is a floor-lying exercise (without bench)
    static func isFloorLyingExercise(_ exerciseName: String, equipment: String) -> Bool {
        let nameLower = exerciseName.lowercased()
        let equipLower = equipment.lowercased()
        
        // If it uses a bench, it's not a floor exercise
        if equipLower.contains("bench") { return false }
        
        // Check for floor-lying indicators
        return floorLyingKeywords.contains { nameLower.contains($0) }
    }
    
    /// Check if exercise uses improvised/low-quality equipment
    static func usesImprovisedEquipment(_ equipment: String) -> Bool {
        let equipLower = equipment.lowercased()
        return improvisedEquipment.contains { equipLower.contains($0) }
    }
    
    /// 🚫 HARD FILTER: Check if exercise should be COMPLETELY EXCLUDED for a location
    /// This is a filter, not a penalty - returns false = DO NOT USE
    static func isExerciseAppropriateForLocation(
        exerciseName: String,
        equipment: String,
        location: WorkoutLocation
    ) -> Bool {
        let equipLower = equipment.lowercased()
        let nameLower = exerciseName.lowercased()
        
        // Get excluded equipment for this location
        guard let excluded = excludedEquipmentByLocation[location] else {
            return true  // No exclusions for this location
        }
        
        // Check if ANY excluded item appears in equipment
        for excludedItem in excluded {
            if equipLower.contains(excludedItem.lowercased()) {
                #if DEBUG
                print("   🚫 [LOCATION] Excluded '\(exerciseName)': uses '\(excludedItem)' which is excluded for \(location.rawValue)")
                #endif
                return false
            }
        }
        
        // === GYM-SPECIFIC EXCLUSIONS ===
        if location == .gym {
            // Exclude home workout patterns in exercise names
            let homePatterns = ["on chair", "chair dip", "wall sit", "against wall", 
                                "couch", "doorway", "under table", "bed supported"]
            for pattern in homePatterns {
                if nameLower.contains(pattern) {
                    #if DEBUG
                    print("   🚫 [LOCATION] Excluded '\(exerciseName)': home workout pattern '\(pattern)'")
                    #endif
                    return false
                }
            }
        }
        
        return true
    }
    
    /// Get penalty score for exercise based on user's workout location
    /// Returns negative value (penalty) or 0 (no penalty)
    static func getLocationContextPenalty(
        exerciseName: String,
        equipment: String,
        location: WorkoutLocation,
        userGoal: String
    ) -> Double {
        var penalty: Double = 0
        
        let equipLower = equipment.lowercased()
        
        // === GYM PENALTIES ===
        if location == .gym {
            // Heavy penalty for improvised equipment in gym
            if usesImprovisedEquipment(equipment) {
                penalty -= 100  // Effectively exclude
            }
            
            // Heavy penalty for floor exercises at the gym - should use gym equipment instead
            // Floor exercises are awkward/inappropriate in a gym setting
            if isFloorLyingExercise(exerciseName, equipment: equipment) {
                penalty -= 120  // Near-exclusion penalty for all gym workouts
            }
        }
        
        // === HOME PENALTIES ===
        if location == .home {
            // Heavy penalty for equipment they definitely don't have
            if equipLower.contains("sled") || equipLower.contains("hack squat") {
                penalty -= 100
            }
        }
        
        // === OUTDOOR PENALTIES ===
        if location == .outdoor {
            // Can't use machines/cables outside
            if equipLower.contains("machine") || equipLower.contains("cable") {
                penalty -= 100
            }
        }
        
        // === GENERAL FLOOR EXERCISE HANDLING ===
        // Slightly deprioritize floor work (already heavily penalized for gym above)
        if location != .gym && isFloorLyingExercise(exerciseName, equipment: equipment) {
            penalty -= 10  // Small baseline penalty for non-gym locations
        }
        
        return penalty
    }
    
    // MARK: - Equipment Types
    /// All available equipment filters (user-selectable)
    static let allEquipment = [
        "All", "Bodyweight", "Dumbbells", "Barbell", "Cables", "Machines",
        "Kettlebell", "Resistance Bands", "Bench", "TRX/Rings", "Stability Ball",
        "Smith Machine", "Power Rack", "Pull-Up Bar", "Landmine", "Sled", 
        "Medicine Ball", "Battle Ropes", "Foam Roller"
    ]
    
    /// Equipment mapping from database format to user-selectable categories
    /// This handles the updated equipment format (e.g., "Cable Machine" → "Cables")
    static let equipmentCategoryMap: [String: String] = [
        // User categories (direct matches)
        "dumbbells": "Dumbbells",
        "barbell": "Barbell",
        "cables": "Cables",
        "machines": "Machines",
        "bodyweight": "Bodyweight",
        "bands": "Bands",
        
        // Database format mappings
        "cable machine": "Cables",
        "lever machine": "Machines",
        "chest press machine": "Machines",
        "hack squat machine": "Machines",
        "leg press machine": "Machines",
        "smith machine": "Smith Machine",
        "resistance band": "Bands",
        "pull-up bar": "Bodyweight",  // Most gyms/homes have this
        "ez bar": "Barbell",
        "trap bar": "Barbell",
        "stability ball": "Stability Ball",
        "swiss ball": "Stability Ball",
        "suspension trainer (trx)": "TRX/Rings",
        "trx": "TRX/Rings",
        "kettlebell": "Kettlebell",
        "medicine ball": "Medicine Ball",
        "plyo box": "Bodyweight",  // Common in gyms
        "step platform": "Bodyweight",
        "flat bench": "Bench",
        "incline bench": "Bench",
        "decline bench": "Bench",
        "adjustable bench": "Bench",
        "chair": "Bodyweight",
        "wall": "Bodyweight",
        "foam roller": "Foam Roller",
        "landmine": "Landmine",
        "sled": "Sled",
        "anchor point": "Bands",
        "weight plate": "Barbell",  // Usually comes with barbell
        "padded stool": "Bench",
        "vibration plate": "Machines",
        "balance pad": "Bodyweight",
        "bottle (improvised)": "Bodyweight"
    ]
    
    // MARK: - Smart Bench Handling with Context Clues
    
    /// Bench types and their default commonality (1 = most common, 4 = specialized)
    /// These scores are ADJUSTED based on user's muscle selection context
    static let benchBaseScores: [String: Int] = [
        "flat bench": 1,           // Most common
        "adjustable bench": 1,     // Can do flat + incline
        "incline bench": 2,        // Common
        "decline bench": 3,        // Less common (but common if targeting lower chest)
        "preacher bench": 4,       // Specialized (but expected for bicep isolation)
        "hyperextension bench": 3, // Specialized (but expected for glutes/lower back)
        "roman chair": 4,          // Specialized
        "glute ham bench": 4,      // Specialized
        "ab bench": 3,             // Somewhat common
    ]
    
    /// Infer what bench types the user likely has based on their muscle selection
    /// Example: "Lower Chest" + "Bench" implies they want/have decline bench
    static func inferBenchTypesFromContext(targetMuscles: [String]) -> Set<String> {
        var inferredBenches: Set<String> = ["flat bench", "adjustable bench"]  // Everyone has these
        
        let musclesLower = targetMuscles.map { $0.lowercased() }
        
        // Upper Chest → Incline bench
        if musclesLower.contains(where: { $0.contains("upper chest") || $0.contains("upper pec") }) {
            inferredBenches.insert("incline bench")
        }
        
        // Lower Chest → Decline bench
        if musclesLower.contains(where: { $0.contains("lower chest") || $0.contains("lower pec") }) {
            inferredBenches.insert("decline bench")
        }
        
        // Glutes / Hip Thrust → Hip thrust setup or hyperextension
        if musclesLower.contains(where: { $0.contains("glute") || $0.contains("hip") }) {
            inferredBenches.insert("hyperextension bench")
            inferredBenches.insert("flat bench")  // Can do hip thrusts on flat bench
        }
        
        // Lower Back → Hyperextension bench
        if musclesLower.contains(where: { $0.contains("lower back") || $0.contains("erector") }) {
            inferredBenches.insert("hyperextension bench")
        }
        
        // Biceps (isolation focus) → Preacher bench might be desired
        if musclesLower.contains(where: { $0.contains("bicep") }) {
            inferredBenches.insert("preacher bench")
        }
        
        // Abs / Core → Ab bench might be desired
        if musclesLower.contains(where: { $0.contains("abs") || $0.contains("core") || $0.contains("abdominal") }) {
            inferredBenches.insert("ab bench")
            inferredBenches.insert("decline bench")  // Decline crunches
        }
        
        // Generic Chest → Include incline (very common movement)
        if musclesLower.contains(where: { $0.contains("chest") && !$0.contains("upper") && !$0.contains("lower") }) {
            inferredBenches.insert("incline bench")
        }
        
        return inferredBenches
    }
    
    /// Get context-aware bench compatibility score
    /// Takes into account user's target muscles to infer what benches they likely have
    static func getBenchCompatibilityScore(_ equipment: String, targetMuscles: [String] = []) -> Int {
        let equipLower = equipment.lowercased()
        
        // Not a bench exercise
        if !equipLower.contains("bench") {
            return 100
        }
        
        // Get inferred bench types from muscle context
        let inferredBenches = inferBenchTypesFromContext(targetMuscles: targetMuscles)
        
        // Check which bench type this exercise needs
        var requiredBenchType = "flat bench"  // default
        
        if equipLower.contains("incline") { requiredBenchType = "incline bench" }
        else if equipLower.contains("decline") { requiredBenchType = "decline bench" }
        else if equipLower.contains("preacher") { requiredBenchType = "preacher bench" }
        else if equipLower.contains("hyperextension") || equipLower.contains("hyper extension") { requiredBenchType = "hyperextension bench" }
        else if equipLower.contains("roman") { requiredBenchType = "roman chair" }
        else if equipLower.contains("glute ham") || equipLower.contains("ghd") { requiredBenchType = "glute ham bench" }
        else if equipLower.contains("ab bench") { requiredBenchType = "ab bench" }
        else if equipLower.contains("flat") { requiredBenchType = "flat bench" }
        else if equipLower.contains("adjustable") { requiredBenchType = "adjustable bench" }
        
        // If the required bench is inferred from context, give it a high score
        if inferredBenches.contains(requiredBenchType) {
            return 95  // User's context implies they have/want this bench type
        }
        
        // Otherwise, use base commonality scores
        let baseScore = benchBaseScores[requiredBenchType] ?? 2
        switch baseScore {
        case 1: return 90   // Flat/adjustable - excellent
        case 2: return 70   // Incline - good
        case 3: return 40   // Decline/specialized - risky without context
        case 4: return 20   // Very specialized - avoid
        default: return 50
        }
    }
    
    /// Check if an exercise requires a specialized bench that user might not have
    /// Takes context into account
    static func requiresSpecializedBench(_ equipment: String, targetMuscles: [String] = []) -> Bool {
        let score = getBenchCompatibilityScore(equipment, targetMuscles: targetMuscles)
        return score < 50
    }
    
    /// Legacy function for backward compatibility (no context)
    static func getBenchCompatibilityScore(_ equipment: String) -> Int {
        return getBenchCompatibilityScore(equipment, targetMuscles: [])
    }
    
    /// Normalize equipment from database to simplified user categories
    /// Handles new equipment format (e.g., "Dumbbells, Incline Bench" → "Dumbbells")
    static func normalizeEquipment(_ rawEquipment: String?) -> String {
        guard let equipment = rawEquipment?.lowercased().trimmingCharacters(in: .whitespaces) else { 
            return "Bodyweight" 
        }
        
        // Check for bodyweight first
        if equipment == "bodyweight" || equipment.isEmpty { return "Bodyweight" }
        
        // Check exact matches in category map first
        if let mapped = equipmentCategoryMap[equipment] {
            return mapped
        }
        
        // Handle combined equipment (e.g., "Dumbbells, Incline Bench")
        // Return the PRIMARY equipment (first one listed)
        let parts = equipment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if let firstPart = parts.first {
            if let mapped = equipmentCategoryMap[firstPart] {
                return mapped
            }
        }
        
        // Fallback to keyword matching for main equipment types
        if equipment.contains("dumbbell") { return "Dumbbells" }
        // Check Smith Machine BEFORE Barbell to ensure proper separation
        if equipment.contains("smith") { return "Smith Machine" }
        if equipment.contains("barbell") || equipment.contains("ez bar") || equipment.contains("trap bar") { return "Barbell" }
        if equipment.contains("cable") { return "Cables" }
        if equipment.contains("lever") || (equipment.contains("machine") && !equipment.contains("smith")) { return "Machines" }
        if equipment.contains("kettlebell") { return "Kettlebell" }
        if equipment.contains("band") || equipment.contains("resistance") { return "Bands" }
        if equipment.contains("trx") || equipment.contains("ring") || equipment.contains("suspension") { return "TRX/Rings" }
        if equipment.contains("stability ball") || equipment.contains("swiss ball") { return "Stability Ball" }
        if equipment.contains("medicine ball") { return "Medicine Ball" }
        if equipment.contains("landmine") { return "Landmine" }
        if equipment.contains("sled") { return "Sled" }
        if equipment.contains("foam roller") { return "Foam Roller" }
        if equipment.contains("bench") { return "Bench" }
        if equipment.contains("pull-up") || equipment.contains("pullup") || equipment.contains("chin-up") { return "Bodyweight" }
        if equipment.contains("chair") || equipment.contains("wall") || equipment.contains("step") || 
           equipment.contains("box") || equipment.contains("floor") || equipment.contains("mat") { return "Bodyweight" }
        
        return "Bodyweight"
    }
    
    /// Check if user has the required equipment for an exercise
    /// Handles combined equipment (e.g., "Dumbbells, Incline Bench" requires both Dumbbells AND Bench)
    static func userHasRequiredEquipment(exerciseEquipment: String?, exerciseName: String? = nil, userEquipment: [String]) -> Bool {
        guard let equipment = exerciseEquipment?.lowercased(), !equipment.isEmpty else {
            // No equipment required = bodyweight, check if user has bodyweight selected
            return userEquipment.contains { $0.lowercased().contains("body") }
        }
        
        if equipment == "bodyweight" {
            return userEquipment.contains { $0.lowercased().contains("body") }
        }
        
        let userEquipLower = Set(userEquipment.map { $0.lowercased() })
        
        // 🛡️ SAFETY CHECK: Check exercise NAME for equipment keywords that might be missing from the equipment field
        // This catches exercises like "Banded Bench Press" where the name indicates bands but equipment field doesn't
        if let name = exerciseName?.lowercased() {
            // Check for band-related keywords in name
            let bandKeywords = ["banded", "band", "resistance band", "(band)"]
            let nameIndicatesBands = bandKeywords.contains { name.contains($0) }
            let userHasBands = userEquipLower.contains { $0.contains("band") || $0.contains("resistance") }
            
            if nameIndicatesBands && !userHasBands {
                #if DEBUG
                print("   🚫 [NAME CHECK] Excluded '\(exerciseName ?? "")': name indicates bands but user doesn't have bands")
                #endif
                return false
            }
            
            // Check for kettlebell keywords
            let kettlebellKeywords = ["kettlebell", "(kettlebell)"]
            let nameIndicatesKettlebell = kettlebellKeywords.contains { name.contains($0) }
            let userHasKettlebell = userEquipLower.contains { $0.contains("kettlebell") }
            
            if nameIndicatesKettlebell && !userHasKettlebell {
                #if DEBUG
                print("   🚫 [NAME CHECK] Excluded '\(exerciseName ?? "")': name indicates kettlebell but user doesn't have kettlebell")
                #endif
                return false
            }
            
            // Check for TRX/suspension keywords
            let suspensionKeywords = ["trx", "suspension", "(trx)"]
            let nameIndicatesSuspension = suspensionKeywords.contains { name.contains($0) }
            let userHasSuspension = userEquipLower.contains { $0.contains("trx") || $0.contains("suspension") }
            
            if nameIndicatesSuspension && !userHasSuspension {
                #if DEBUG
                print("   🚫 [NAME CHECK] Excluded '\(exerciseName ?? "")': name indicates suspension trainer but user doesn't have it")
                #endif
                return false
            }
        }
        
        // Parse combined equipment (e.g., "Dumbbells, Incline Bench")
        let requiredParts = equipment.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        
        // Common items that don't need explicit user selection (truly no equipment)
        // These are accessories/support items, not primary equipment
        // NOTE: "chair", "wall", "step" are NOT included - they are home/improvised equipment
        // and should only be available when user explicitly selects them
        let commonItems: Set<String> = ["floor", "mat", "body weight", "bench", "flat bench", "incline bench", 
                                        "decline bench", "box", "hack squat machine",
                                        "anchor point", "door anchor", "rack", "support"]
        
        // Equipment that requires SPECIFIC selection (not just bodyweight)
        let specializedEquipment: Set<String> = [
            "stability ball", "swiss ball", "medicine ball", "foam roller",
            "kettlebell", "trx", "rings", "suspension", "landmine", "sled",
            "pull-up bar", "pullup bar", "dip bars", "parallel bars"
        ]
        
        // User must have ALL required equipment pieces
        return requiredParts.allSatisfy { requiredPart in
            // Skip common items that are truly equipment-free
            if commonItems.contains(requiredPart) { return true }
            
            // Check if this requires specialized equipment
            let isSpecialized = specializedEquipment.contains { requiredPart.contains($0) }
            
            // Normalize the required equipment to a category
            let requiredCategory = normalizeEquipment(requiredPart).lowercased()
            
            // If user only has bodyweight, they can't use specialized equipment
            let userOnlyHasBodyweight = userEquipLower.allSatisfy { 
                $0.contains("body") || $0.contains("weight") 
            }
            if userOnlyHasBodyweight && isSpecialized {
                return false
            }
            
            // Check if user has this category
            return userEquipLower.contains { userEquip in
                let userCategory = normalizeEquipment(userEquip).lowercased()
                
                // Exact category match
                if userCategory == requiredCategory { return true }
                
                // Smart mappings for equipment variations
                // "Cable Machine" should match "Cables"
                if requiredCategory == "cables" && userCategory == "cables" { return true }
                if requiredPart.contains("cable") && userEquip.contains("cable") { return true }
                
                // "Lever Machine", "Chest Press Machine", etc. should match "Machines"
                if requiredCategory == "machines" && userCategory == "machines" { return true }
                if requiredPart.contains("lever") && userEquip.contains("machine") { return true }
                if requiredPart.contains("machine") && userEquip.contains("machine") && !requiredPart.contains("smith") { return true }
                if requiredPart.contains("sled") && userEquip.contains("machine") { return true }
                if requiredPart.contains("press machine") && userEquip.contains("machine") { return true }
                if requiredPart.contains("leg press") && userEquip.contains("machine") { return true }
                if requiredPart.contains("calf raise machine") && userEquip.contains("machine") { return true }
                if requiredPart.contains("pec deck") && userEquip.contains("machine") { return true }
                
                // Bench variations
                if requiredPart.contains("bench") && userEquip.contains("bench") { return true }
                
                // Other equipment
                if requiredPart.contains("stability") && userEquip.contains("stability") { return true }
                if requiredPart.contains("medicine") && userEquip.contains("medicine") { return true }
                
                // Resistance Band variations
                if requiredCategory == "bands" && (userEquip.contains("band") || userEquip.contains("resistance")) { return true }
                if requiredPart.contains("resistance band") && userEquip.contains("band") { return true }
                
                return false
            }
        }
    }
    
    /// Check if exercise equipment matches filter (for library filtering)
    static func equipmentMatches(_ exerciseEquipment: String?, filter: String) -> Bool {
        if filter == "All" { return true }
        
        let normalized = normalizeEquipment(exerciseEquipment)
        return normalized == filter
    }
    
    // MARK: - Muscle Groups
    /// Muscle groups available for each category
    static func muscleGroupsForCategory(_ category: String) -> [String] {
        switch category {
        case "Chest":
            return ["All", "Upper Chest", "Lower Chest", "Inner Chest", "Outer Chest"]
        case "Back":
            return ["All", "Lats", "Upper Back", "Traps", "Rhomboids", "Lower Back"]
        case "Legs":
            return ["All", "Quads", "Hamstrings", "Glutes", "Calves", "Adductors", "Hip Flexors"]
        case "Shoulders":
            return ["All", "Front Delts", "Side Delts", "Rear Delts", "Rotator Cuff"]
        case "Arms":
            return ["All", "Biceps", "Triceps", "Forearms"]
        case "Core":
            return ["All", "Abs", "Obliques", "Lower Back", "Hip Flexors"]
        case "Full Body":
            return ["All"]
        case "Plyometrics":
            return ["All", "Lower Body", "Upper Body", "Full Body"]
        case "Stretching":
            return ["All", "Upper Body", "Lower Body", "Back", "Hips"]
        case "Cardio":
            return ["All"]
        case "Neck":
            return ["All"]
        default:
            return ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", 
                    "Calves", "Lats", "Traps", "Front Delts", "Side Delts", "Rear Delts", 
                    "Abs", "Obliques"]
        }
    }
    
    // MARK: - Muscle Matching Logic
    /// Check if an exercise targets a specific muscle group
    static func exerciseTargetsMuscle(
        exerciseName: String?,
        category: String?,
        primaryMuscle: String?,
        secondaryMuscles: String?,
        muscleGroups: [String]?,
        targetMuscle: String
    ) -> Bool {
        if targetMuscle == "All" { return true }
        
        let name = exerciseName?.lowercased() ?? ""
        let primary = primaryMuscle?.lowercased() ?? ""
        let secondary = secondaryMuscles?.lowercased() ?? ""
        let groups = muscleGroups?.map { $0.lowercased() } ?? []
        
        switch targetMuscle {
        // Chest
        case "Upper Chest":
            return name.contains("incline") || primary.contains("upper chest") ||
                   groups.contains("upper chest") || groups.contains("clavicular")
        case "Lower Chest":
            return name.contains("decline") || name.contains("dip") ||
                   primary.contains("lower chest") || groups.contains("lower chest")
        case "Inner Chest":
            return name.contains("close grip") || name.contains("squeeze") ||
                   name.contains("crossover") || groups.contains("inner chest")
        case "Outer Chest":
            return name.contains("wide") || name.contains("fly") ||
                   groups.contains("outer chest")
            
        // Back
        case "Lats":
            return primary.contains("lat") || name.contains("pulldown") ||
                   name.contains("pull-up") || name.contains("pullup") ||
                   name.contains("row") || secondary.contains("lat") ||
                   groups.contains("lat")
        case "Upper Back":
            return primary.contains("upper back") || name.contains("row") ||
                   name.contains("face pull") || secondary.contains("upper back") ||
                   groups.contains("upper back") || groups.contains("rhomboid")
        case "Traps":
            return primary.contains("trap") || name.contains("shrug") ||
                   secondary.contains("trap") || groups.contains("trap")
        case "Rhomboids":
            return name.contains("row") || name.contains("squeeze") ||
                   primary.contains("rhomboid") || groups.contains("rhomboid")
        case "Lower Back":
            return primary.contains("lower back") || name.contains("hyperextension") ||
                   name.contains("deadlift") || name.contains("good morning") ||
                   secondary.contains("lower back") || groups.contains("lower back")
            
        // Legs
        case "Quads":
            return primary.contains("quad") || name.contains("squat") ||
                   name.contains("leg press") || name.contains("leg extension") ||
                   name.contains("lunge") || secondary.contains("quad") ||
                   groups.contains("quad")
        case "Hamstrings":
            return primary.contains("hamstring") || name.contains("leg curl") ||
                   name.contains("romanian") || name.contains("stiff leg") ||
                   secondary.contains("hamstring") || groups.contains("hamstring")
        case "Glutes":
            return primary.contains("glute") || name.contains("hip thrust") ||
                   name.contains("glute bridge") || name.contains("kickback") ||
                   secondary.contains("glute") || groups.contains("glute")
        case "Calves":
            return primary.contains("calve") || primary.contains("calf") ||
                   name.contains("calf raise") || name.contains("calve") ||
                   secondary.contains("calve") || groups.contains("calve") || groups.contains("calf")
        case "Adductors":
            return primary.contains("adductor") || name.contains("adductor") ||
                   name.contains("inner thigh") || groups.contains("adductor")
        case "Hip Flexors":
            return primary.contains("hip flexor") || name.contains("leg raise") ||
                   name.contains("knee raise") || secondary.contains("hip flexor") ||
                   groups.contains("hip flexor")
            
        // Shoulders
        case "Front Delts":
            return primary.contains("front delt") || name.contains("front raise") ||
                   name.contains("military press") || name.contains("overhead press") ||
                   secondary.contains("front delt") || groups.contains("front delt") ||
                   groups.contains("anterior delt")
        case "Side Delts", "Lateral Delts":
            return primary.contains("lateral delt") || primary.contains("side delt") ||
                   name.contains("lateral raise") || name.contains("side raise") ||
                   secondary.contains("lateral delt") || groups.contains("lateral delt") ||
                   groups.contains("side delt")
        case "Rear Delts":
            return primary.contains("rear delt") || name.contains("rear delt") ||
                   name.contains("face pull") || name.contains("reverse fly") ||
                   secondary.contains("rear delt") || groups.contains("rear delt") ||
                   groups.contains("posterior delt")
        case "Rotator Cuff":
            return primary.contains("rotator") || name.contains("rotator") ||
                   name.contains("external rotation") || name.contains("internal rotation") ||
                   groups.contains("rotator cuff")
            
        // Arms
        case "Biceps":
            return primary.contains("bicep") || name.contains("curl") ||
                   secondary.contains("bicep") || groups.contains("bicep")
        case "Triceps":
            return primary.contains("tricep") || name.contains("tricep") ||
                   name.contains("pushdown") || name.contains("extension") ||
                   name.contains("skull crusher") || name.contains("dip") ||
                   secondary.contains("tricep") || groups.contains("tricep")
        case "Forearms":
            return primary.contains("forearm") || name.contains("wrist") ||
                   name.contains("forearm") || secondary.contains("forearm") ||
                   groups.contains("forearm")
            
        // Core
        case "Abs":
            return primary.contains("abs") || primary.contains("rectus") ||
                   name.contains("crunch") || name.contains("sit-up") ||
                   name.contains("sit up") || name.contains("plank") ||
                   secondary.contains("abs") || groups.contains("abs") ||
                   groups.contains("rectus abdominis")
        case "Obliques":
            return primary.contains("oblique") || name.contains("oblique") ||
                   name.contains("twist") || name.contains("russian") ||
                   name.contains("woodchop") || name.contains("side bend") ||
                   secondary.contains("oblique") || groups.contains("oblique")
            
        // Plyometrics sub-categories
        case "Lower Body":
            return name.contains("jump") || name.contains("hop") ||
                   name.contains("squat") || name.contains("lunge") ||
                   primary.contains("quad") || primary.contains("glute")
        case "Upper Body":
            return name.contains("push") || name.contains("throw") ||
                   name.contains("clap") || primary.contains("chest") ||
                   primary.contains("shoulder")
            
        // Stretching sub-categories
        case "Hips":
            return name.contains("hip") || name.contains("groin") ||
                   name.contains("pigeon") || primary.contains("hip")
            
        default:
            // Generic muscle name match
            return primary.contains(targetMuscle.lowercased()) ||
                   secondary.contains(targetMuscle.lowercased()) ||
                   groups.contains(targetMuscle.lowercased())
        }
    }
    
    // MARK: - Category Matching
    /// Check if an exercise matches a category filter
    static func exerciseMatchesCategory(
        exerciseName: String?,
        category: String?,
        primaryMuscle: String?,
        targetCategory: String
    ) -> Bool {
        if targetCategory == "All" { return true }
        
        let exerciseCategory = category?.lowercased() ?? ""
        let target = targetCategory.lowercased()
        let primary = primaryMuscle?.lowercased() ?? ""
        let name = exerciseName?.lowercased() ?? ""
        
        // Direct category match
        if exerciseCategory.contains(target) || target.contains(exerciseCategory) {
            return true
        }
        
        // Map by primary muscle
        switch targetCategory {
        case "Chest":
            return exerciseCategory == "chest" || primary.contains("chest") ||
                   primary.contains("pec")
        case "Back":
            return exerciseCategory == "back" || primary.contains("lat") ||
                   primary.contains("upper back") || primary.contains("trap") ||
                   primary.contains("rhomboid")
        case "Legs":
            return exerciseCategory == "legs" || primary.contains("quad") ||
                   primary.contains("hamstring") || primary.contains("glute") ||
                   primary.contains("calve") || primary.contains("calf")
        case "Shoulders":
            return exerciseCategory == "shoulders" || primary.contains("delt") ||
                   primary.contains("shoulder") || primary.contains("rotator")
        case "Arms":
            return exerciseCategory == "arms" || primary.contains("bicep") ||
                   primary.contains("tricep") || primary.contains("forearm")
        case "Core":
            return exerciseCategory == "core" || primary.contains("abs") ||
                   primary.contains("oblique") || primary.contains("core")
        case "Full Body":
            return exerciseCategory == "full body" || primary.contains("full body")
        case "Plyometrics":
            return exerciseCategory == "plyometrics" || name.contains("jump") ||
                   name.contains("plyo") || name.contains("explosive")
        case "Stretching":
            return exerciseCategory == "stretching" || name.contains("stretch") ||
                   name.contains("mobility")
        case "Cardio":
            return exerciseCategory == "cardio" || primary.contains("cardio")
        case "Neck":
            return exerciseCategory == "neck" || primary.contains("neck")
        default:
            return false
        }
    }
    
    // MARK: - Video Code Extraction
    /// Extract video code from video filename (e.g., "44171201-Sumo-Squat.mp4" -> "44171201")
    static func extractVideoCode(from filename: String?) -> String? {
        guard let filename = filename else { return nil }
        
        // Video filename format: CODE-Exercise-Name.mp4
        // Extract everything before the first dash
        let components = filename.components(separatedBy: "-")
        guard let firstComponent = components.first else { return nil }
        
        // Clean and return (remove leading zeros for matching)
        let cleaned = firstComponent.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }
    
    /// Match exercise to video by video code
    static func getVideoFilename(forVideoCode code: String?, gender: String = "Male") -> String? {
        guard let code = code, !code.isEmpty else { return nil }
        
        // Video codes should match the beginning of video filenames
        // Format: {code}-{Exercise-Name}.mp4
        // The actual filename comes from the database
        return nil // Filename comes from database video_filename field
    }
}

// MARK: - Exercise Extension for Filtering
extension Exercise {
    /// Check if exercise matches category filter
    func matchesCategory(_ category: String) -> Bool {
        ExerciseFilterService.exerciseMatchesCategory(
            exerciseName: name,
            category: self.category,
            primaryMuscle: nil, // Would need to add primary_muscle to Exercise model
            targetCategory: category
        )
    }
    
    /// Check if exercise matches equipment filter
    func matchesEquipment(_ filter: String) -> Bool {
        ExerciseFilterService.equipmentMatches(equipment, filter: filter)
    }
    
    /// Check if exercise targets a muscle group
    func targetsMuscle(_ muscle: String) -> Bool {
        ExerciseFilterService.exerciseTargetsMuscle(
            exerciseName: name,
            category: category,
            primaryMuscle: nil,
            secondaryMuscles: nil,
            muscleGroups: muscleGroups as? [String],
            targetMuscle: muscle
        )
    }
}

