//
//  FoundationalExerciseDatabase.swift
//  GoFit
//
//  A curated database of foundational exercises that beginners should master first.
//  These are the most common, proven, and beginner-friendly exercises per equipment type.
//  
//  Purpose:
//  - New users get familiar, effective exercises (not "Behind the Back Tricep Cable Extension")
//  - Builds confidence with well-known movements
//  - Gradually introduces variety as users gain experience
//
//  Exercise Selection Criteria:
//  1. Well-known and commonly performed in any gym
//  2. Easy to learn proper form
//  3. Effective for the target muscle group
//  4. Low injury risk when performed correctly
//  5. Available video demonstrations
//

import Foundation

// MARK: - Foundational Exercise Definition

struct FoundationalExercise: Identifiable, Hashable {
    let id: String
    let name: String                    // Exact name match from database
    let alternateNames: [String]        // Other acceptable name variations
    let equipment: FoundationalEquipment
    let muscleGroup: FoundationalMuscleGroup
    let tier: FoundationTier           // How foundational (1 = most basic)
    let isCompound: Bool
    let difficultyLevel: Int           // 1-5 (1 = easiest)
    let description: String            // Why this exercise is foundational
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FoundationalExercise, rhs: FoundationalExercise) -> Bool {
        lhs.id == rhs.id
    }
}

enum FoundationTier: Int, CaseIterable, Comparable, Sendable {
    case essential = 1      // Must-know exercises (show first 1-3 workouts)
    case fundamental = 2    // Core exercises (show after 3-5 workouts)
    case standard = 3       // Common exercises (show after 5-10 workouts)
    case variety = 4        // Good variety exercises (show after 10+ workouts)
    
    static func < (lhs: FoundationTier, rhs: FoundationTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var workoutsRequired: Int {
        switch self {
        case .essential: return 0
        case .fundamental: return 3
        case .standard: return 6
        case .variety: return 12
        }
    }
    
    var displayName: String {
        switch self {
        case .essential: return "Essential"
        case .fundamental: return "Fundamental"
        case .standard: return "Standard"
        case .variety: return "Variety"
        }
    }
}

// MARK: - Equipment & Muscle Group Types (Local to this file)
// Using unique names to avoid conflicts with other files

enum FoundationalEquipment: String, CaseIterable {
    case barbell = "barbell"
    case dumbbell = "dumbbell"
    case cable = "cable"
    case machine = "machine"
    case bodyweight = "bodyweight"
    case kettlebell = "kettlebell"
    case smithMachine = "smith machine"
    case ezBar = "ez bar"
    case resistanceBand = "resistance band"
    
    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbells"
        case .cable: return "Cables"
        case .machine: return "Machines"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .smithMachine: return "Smith Machine"
        case .ezBar: return "EZ Bar"
        case .resistanceBand: return "Resistance Band"
        }
    }
}

enum FoundationalMuscleGroup: String, CaseIterable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case biceps = "biceps"
    case triceps = "triceps"
    case quads = "quads"
    case hamstrings = "hamstrings"
    case glutes = "glutes"
    case calves = "calves"
    case core = "core"
    case fullBody = "full body"
    
    var relatedMuscles: [String] {
        switch self {
        case .chest: return ["chest", "pectorals", "pecs", "upper chest", "lower chest"]
        case .back: return ["back", "lats", "upper back", "lower back", "traps", "rhomboids"]
        case .shoulders: return ["shoulders", "delts", "deltoids", "front delts", "rear delts", "side delts"]
        case .biceps: return ["biceps", "arms"]
        case .triceps: return ["triceps", "arms"]
        case .quads: return ["quads", "quadriceps", "legs", "thighs"]
        case .hamstrings: return ["hamstrings", "legs", "thighs"]
        case .glutes: return ["glutes", "gluteus", "hips"]
        case .calves: return ["calves", "lower legs"]
        case .core: return ["core", "abs", "abdominals", "obliques"]
        case .fullBody: return ["full body", "total body"]
        }
    }
}

// MARK: - Risky Exercise Lists (for Safety Filtering)

/// Exercises that are too risky/complex for foundational users - should be hard blocked
/// These involve high skill, instability, or injury risk that beginners shouldn't face
let RISKY_EXERCISES: Set<String> = [
    // Complex Olympic lifts
    "clean", "snatch", "jerk", "power clean", "hang clean",
    // Advanced gymnastics
    "guillotine bench press", "deep push up and renegade row", "pullover to press",
    "jm bench press", "reverse grip decline press", "hollow back press",
    "one arm pull", "one arm push", "pistol squat", "dragon flag",
    "maltese", "victorian", "planche", "muscle up",
    // Complex combination movements
    "renegade row", "plank row", "plank lateral raise", "plank front raise",
    // High injury risk
    "behind the neck press", "behind neck pulldown", "upright row",
    "good morning"
]

/// Exercises that stress the lower back - should be blocked/penalized for users with back issues
let LOWER_BACK_STRESS_EXERCISES: Set<String> = [
    // Direct lower back stress
    "renegade row", "plank row",  // Anti-rotation under load
    "bent over row", "bent-over row", "pendlay row",  // Unsupported bent position
    "deadlift", "romanian deadlift", "stiff leg deadlift", "rdl",
    "good morning",
    "hyperextension", "back extension",
    // These put the lower back in a compromised position
    "t-bar row"  // Can be okay with chest support but often not
]

/// Exercises that are SAFE alternatives for users with lower back issues
let LOWER_BACK_SAFE_ALTERNATIVES: Set<String> = [
    "chest supported row", "chest-supported row",
    "machine row", "lever row", "seated machine row",
    "seated cable row", "cable row",
    "lat pulldown",
    "leg press",  // vs squats
    "leg curl", "leg extension"  // Isolation instead of compounds
]

// MARK: - Foundational Exercise Database

class FoundationalExerciseDatabase {
    static let shared = FoundationalExerciseDatabase()
    
    private init() {}
    
    // MARK: - Risky Exercise Checks
    
    /// Check if an exercise is risky for foundational/beginner users
    func isRiskyExercise(_ exerciseName: String) -> Bool {
        let nameLower = exerciseName.lowercased()
        return RISKY_EXERCISES.contains { nameLower.contains($0) }
    }
    
    /// Check if an exercise stresses the lower back
    func isLowerBackStressExercise(_ exerciseName: String) -> Bool {
        let nameLower = exerciseName.lowercased()
        return LOWER_BACK_STRESS_EXERCISES.contains { nameLower.contains($0) }
    }
    
    /// Check if an exercise is a safe alternative for lower back issues
    func isLowerBackSafeAlternative(_ exerciseName: String) -> Bool {
        let nameLower = exerciseName.lowercased()
        return LOWER_BACK_SAFE_ALTERNATIVES.contains { nameLower.contains($0) }
    }
    
    /// Get penalty for risky exercises based on user context
    func getRiskyExercisePenalty(
        exerciseName: String,
        userWorkoutCount: Int,
        restrictToFoundational: Bool,
        hasLowerBackIssue: Bool
    ) -> Double {
        let nameLower = exerciseName.lowercased()
        var penalty: Double = 0
        
        // RISKY EXERCISE PENALTY - Block for foundational users
        if isRiskyExercise(nameLower) {
            if restrictToFoundational || userWorkoutCount < 10 {
                penalty -= 400  // Effectively blocks the exercise
            } else {
                penalty -= 150  // Heavy penalty even for experienced users
            }
        }
        
        // LOWER BACK STRESS PENALTY - Block if user has back issues
        if hasLowerBackIssue && isLowerBackStressExercise(nameLower) {
            penalty -= 400  // Block completely for back issues
        }
        
        // LOWER BACK SAFE ALTERNATIVE BOOST - Promote safer options
        if hasLowerBackIssue && isLowerBackSafeAlternative(nameLower) {
            penalty += 120  // Boost safe alternatives
        }
        
        return penalty
    }
    
    // MARK: - 🏋️ BARBELL EXERCISES (Top 15)
    
    let barbellExercises: [FoundationalExercise] = [
        // ESSENTIAL (Tier 1) - First 3 workouts
        FoundationalExercise(
            id: "bb_bench_press",
            name: "Barbell Bench Press",
            alternateNames: ["Bench Press", "Flat Bench Press", "Barbell Flat Bench Press"],
            equipment: .barbell,
            muscleGroup: .chest,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "The king of chest exercises. Every gym-goer should master this."
        ),
        FoundationalExercise(
            id: "bb_squat",
            name: "Barbell Squat",
            alternateNames: ["Back Squat", "Barbell Back Squat", "Squat"],
            equipment: .barbell,
            muscleGroup: .quads,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 3,
            description: "The foundational lower body movement. Builds total leg strength."
        ),
        FoundationalExercise(
            id: "bb_deadlift",
            name: "Barbell Deadlift",
            alternateNames: ["Deadlift", "Conventional Deadlift"],
            equipment: .barbell,
            muscleGroup: .back,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 3,
            description: "Full-body strength builder. Essential for posterior chain development."
        ),
        FoundationalExercise(
            id: "bb_row",
            name: "Barbell Bent Over Row",
            alternateNames: ["Bent Over Row", "Barbell Row", "Bent-Over Barbell Row"],
            equipment: .barbell,
            muscleGroup: .back,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "Classic back builder. Builds thickness and width."
        ),
        
        // FUNDAMENTAL (Tier 2) - After 3-5 workouts
        FoundationalExercise(
            id: "bb_ohp",
            name: "Barbell Overhead Press",
            alternateNames: ["Overhead Press", "Military Press", "Barbell Shoulder Press", "Standing Barbell Press"],
            equipment: .barbell,
            muscleGroup: .shoulders,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 3,
            description: "The standard for shoulder strength. Press overhead with control."
        ),
        FoundationalExercise(
            id: "bb_incline_press",
            name: "Barbell Incline Bench Press",
            alternateNames: ["Incline Press", "Incline Bench Press", "Incline Barbell Press"],
            equipment: .barbell,
            muscleGroup: .chest,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 2,
            description: "Targets upper chest. Great complement to flat bench."
        ),
        FoundationalExercise(
            id: "bb_rdl",
            name: "Barbell Romanian Deadlift",
            alternateNames: ["Romanian Deadlift", "RDL", "Stiff Leg Deadlift"],
            equipment: .barbell,
            muscleGroup: .hamstrings,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 3,
            description: "Excellent hamstring and glute builder. Teaches hip hinge."
        ),
        FoundationalExercise(
            id: "bb_curl",
            name: "Barbell Curl",
            alternateNames: ["Standing Barbell Curl", "Barbell Bicep Curl"],
            equipment: .barbell,
            muscleGroup: .biceps,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Classic bicep builder. Simple and effective."
        ),
        
        // STANDARD (Tier 3) - After 5-10 workouts
        FoundationalExercise(
            id: "bb_hip_thrust",
            name: "Barbell Hip Thrust",
            alternateNames: ["Hip Thrust", "Glute Bridge"],
            equipment: .barbell,
            muscleGroup: .glutes,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Best glute isolation with barbell. Great for building strength."
        ),
        FoundationalExercise(
            id: "bb_close_grip_bench",
            name: "Close Grip Barbell Bench Press",
            alternateNames: ["Close Grip Bench Press", "Close Grip Bench"],
            equipment: .barbell,
            muscleGroup: .triceps,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Tricep-focused pressing. Great for arm strength."
        ),
        FoundationalExercise(
            id: "bb_front_squat",
            name: "Barbell Front Squat",
            alternateNames: ["Front Squat"],
            equipment: .barbell,
            muscleGroup: .quads,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 4,
            description: "Quad-dominant squat variation. Requires mobility."
        ),
        FoundationalExercise(
            id: "bb_shrug",
            name: "Barbell Shrug",
            alternateNames: ["Shrugs", "Standing Barbell Shrug"],
            equipment: .barbell,
            muscleGroup: .back,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Simple trap builder. Easy to learn."
        ),
        
        // VARIETY (Tier 4) - After 10+ workouts
        FoundationalExercise(
            id: "bb_upright_row",
            name: "Barbell Upright Row",
            alternateNames: ["Upright Row"],
            equipment: .barbell,
            muscleGroup: .shoulders,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 2,
            description: "Shoulder and trap builder. Use lighter weight."
        ),
        FoundationalExercise(
            id: "bb_lunge",
            name: "Barbell Lunge",
            alternateNames: ["Lunges", "Walking Lunge"],
            equipment: .barbell,
            muscleGroup: .quads,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 3,
            description: "Unilateral leg exercise. Builds balance and strength."
        ),
        FoundationalExercise(
            id: "bb_skull_crusher",
            name: "Barbell Skull Crusher",
            alternateNames: ["Skull Crushers", "Lying Tricep Extension"],
            equipment: .barbell,
            muscleGroup: .triceps,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 2,
            description: "Tricep isolation classic. Great for arm development."
        ),
    ]
    
    // MARK: - 🏋️ DUMBBELL EXERCISES (Top 20)
    
    let dumbbellExercises: [FoundationalExercise] = [
        // ESSENTIAL (Tier 1)
        FoundationalExercise(
            id: "db_bench_press",
            name: "Dumbbell Bench Press",
            alternateNames: ["Dumbbell Press", "Flat Dumbbell Press", "DB Bench"],
            equipment: .dumbbell,
            muscleGroup: .chest,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "Allows full range of motion. Great chest builder."
        ),
        FoundationalExercise(
            id: "db_row",
            name: "Dumbbell Row",
            alternateNames: ["Single Arm Dumbbell Row", "One Arm Row", "DB Row"],
            equipment: .dumbbell,
            muscleGroup: .back,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "Unilateral back builder. Easy to learn form."
        ),
        FoundationalExercise(
            id: "db_shoulder_press",
            name: "Dumbbell Shoulder Press",
            alternateNames: ["Seated Dumbbell Press", "DB Shoulder Press", "Overhead Dumbbell Press"],
            equipment: .dumbbell,
            muscleGroup: .shoulders,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "Shoulder staple. Build boulder shoulders."
        ),
        FoundationalExercise(
            id: "db_bicep_curl",
            name: "Dumbbell Bicep Curl",
            alternateNames: ["Bicep Curl", "Standing Dumbbell Curl", "DB Curl"],
            equipment: .dumbbell,
            muscleGroup: .biceps,
            tier: .essential,
            isCompound: false,
            difficultyLevel: 1,
            description: "The classic arm exercise. Everyone knows this one."
        ),
        FoundationalExercise(
            id: "db_goblet_squat",
            name: "Dumbbell Goblet Squat",
            alternateNames: ["Goblet Squat"],
            equipment: .dumbbell,
            muscleGroup: .quads,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Best squat for beginners. Teaches proper form."
        ),
        
        // FUNDAMENTAL (Tier 2)
        FoundationalExercise(
            id: "db_lateral_raise",
            name: "Dumbbell Lateral Raise",
            alternateNames: ["Lateral Raise", "Side Raise", "Side Lateral Raise"],
            equipment: .dumbbell,
            muscleGroup: .shoulders,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Builds shoulder width. Essential for deltoid development."
        ),
        FoundationalExercise(
            id: "db_fly",
            name: "Dumbbell Fly",
            alternateNames: ["Dumbbell Chest Fly", "Flat Dumbbell Fly", "DB Fly"],
            equipment: .dumbbell,
            muscleGroup: .chest,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 2,
            description: "Chest isolation movement. Great stretch and contraction."
        ),
        FoundationalExercise(
            id: "db_tricep_extension",
            name: "Dumbbell Tricep Extension",
            alternateNames: ["Overhead Tricep Extension", "DB Tricep Extension"],
            equipment: .dumbbell,
            muscleGroup: .triceps,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Simple tricep isolation. Easy to feel the muscle work."
        ),
        FoundationalExercise(
            id: "db_lunge",
            name: "Dumbbell Lunge",
            alternateNames: ["Walking Lunges", "DB Lunge", "Dumbbell Walking Lunge"],
            equipment: .dumbbell,
            muscleGroup: .quads,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 2,
            description: "Builds leg strength and balance. Great unilateral exercise."
        ),
        FoundationalExercise(
            id: "db_hammer_curl",
            name: "Dumbbell Hammer Curl",
            alternateNames: ["Hammer Curl", "Hammer Curls"],
            equipment: .dumbbell,
            muscleGroup: .biceps,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Targets brachialis and forearms. Easy variation."
        ),
        FoundationalExercise(
            id: "db_rdl",
            name: "Dumbbell Romanian Deadlift",
            alternateNames: ["DB RDL", "Dumbbell RDL", "Single Leg RDL"],
            equipment: .dumbbell,
            muscleGroup: .hamstrings,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 2,
            description: "Hamstring and glute focus. Safer than barbell for beginners."
        ),
        
        // STANDARD (Tier 3)
        FoundationalExercise(
            id: "db_incline_press",
            name: "Dumbbell Incline Press",
            alternateNames: ["Incline Dumbbell Press", "Incline DB Press"],
            equipment: .dumbbell,
            muscleGroup: .chest,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Upper chest emphasis. Great for chest development."
        ),
        FoundationalExercise(
            id: "db_front_raise",
            name: "Dumbbell Front Raise",
            alternateNames: ["Front Raise", "Front Delt Raise"],
            equipment: .dumbbell,
            muscleGroup: .shoulders,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Front deltoid isolation. Simple and effective."
        ),
        FoundationalExercise(
            id: "db_rear_delt_fly",
            name: "Dumbbell Rear Delt Fly",
            alternateNames: ["Rear Delt Fly", "Bent Over Rear Delt Raise", "Reverse Fly"],
            equipment: .dumbbell,
            muscleGroup: .shoulders,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 2,
            description: "Targets rear delts. Important for shoulder balance."
        ),
        FoundationalExercise(
            id: "db_shrug",
            name: "Dumbbell Shrug",
            alternateNames: ["DB Shrug", "Shrugs"],
            equipment: .dumbbell,
            muscleGroup: .back,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Trap builder. Easy to learn and feel."
        ),
        
        // VARIETY (Tier 4)
        FoundationalExercise(
            id: "db_pullover",
            name: "Dumbbell Pullover",
            alternateNames: ["Pullover", "DB Pullover"],
            equipment: .dumbbell,
            muscleGroup: .chest,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 2,
            description: "Classic chest/back exercise. Great for expansion."
        ),
        FoundationalExercise(
            id: "db_arnold_press",
            name: "Arnold Press",
            alternateNames: ["Dumbbell Arnold Press", "Arnold Shoulder Press"],
            equipment: .dumbbell,
            muscleGroup: .shoulders,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 3,
            description: "Named after Arnold. Hits all delt heads."
        ),
        FoundationalExercise(
            id: "db_concentration_curl",
            name: "Dumbbell Concentration Curl",
            alternateNames: ["Concentration Curl"],
            equipment: .dumbbell,
            muscleGroup: .biceps,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 1,
            description: "Isolated bicep work. Great peak contraction."
        ),
        FoundationalExercise(
            id: "db_kickback",
            name: "Dumbbell Tricep Kickback",
            alternateNames: ["Tricep Kickback", "DB Kickback"],
            equipment: .dumbbell,
            muscleGroup: .triceps,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 1,
            description: "Tricep isolation. Good for pump and definition."
        ),
        FoundationalExercise(
            id: "db_calf_raise",
            name: "Dumbbell Calf Raise",
            alternateNames: ["Standing Calf Raise", "Calf Raise"],
            equipment: .dumbbell,
            muscleGroup: .calves,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 1,
            description: "Calf builder. Simple and effective."
        ),
    ]
    
    // MARK: - 🔌 CABLE EXERCISES (Top 15)
    
    let cableExercises: [FoundationalExercise] = [
        // ESSENTIAL (Tier 1)
        FoundationalExercise(
            id: "cable_fly",
            name: "Cable Fly",
            alternateNames: ["Cable Chest Fly", "Cable Crossover", "Cable Pec Fly"],
            equipment: .cable,
            muscleGroup: .chest,
            tier: .essential,
            isCompound: false,
            difficultyLevel: 1,
            description: "Constant tension chest isolation. Easy to learn."
        ),
        FoundationalExercise(
            id: "cable_row",
            name: "Seated Cable Row",
            alternateNames: ["Cable Row", "Seated Row", "Low Row"],
            equipment: .cable,
            muscleGroup: .back,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Back builder with constant tension. Beginner-friendly."
        ),
        FoundationalExercise(
            id: "cable_pushdown",
            name: "Cable Tricep Pushdown",
            alternateNames: ["Tricep Pushdown", "Rope Pushdown", "Cable Pushdown"],
            equipment: .cable,
            muscleGroup: .triceps,
            tier: .essential,
            isCompound: false,
            difficultyLevel: 1,
            description: "Best tricep isolation. Everyone should know this."
        ),
        FoundationalExercise(
            id: "lat_pulldown",
            name: "Lat Pulldown",
            alternateNames: ["Cable Lat Pulldown", "Wide Grip Lat Pulldown"],
            equipment: .cable,
            muscleGroup: .back,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Builds lat width. Perfect for beginners before pull-ups."
        ),
        
        // FUNDAMENTAL (Tier 2)
        FoundationalExercise(
            id: "cable_curl",
            name: "Cable Bicep Curl",
            alternateNames: ["Cable Curl", "Standing Cable Curl"],
            equipment: .cable,
            muscleGroup: .biceps,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Constant tension bicep work. Great for pump."
        ),
        FoundationalExercise(
            id: "cable_lateral_raise",
            name: "Cable Lateral Raise",
            alternateNames: ["Single Arm Cable Lateral Raise"],
            equipment: .cable,
            muscleGroup: .shoulders,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Better tension profile than dumbbells."
        ),
        FoundationalExercise(
            id: "face_pull",
            name: "Cable Face Pull",
            alternateNames: ["Face Pull", "Rope Face Pull"],
            equipment: .cable,
            muscleGroup: .shoulders,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 1,
            description: "Essential for shoulder health. Targets rear delts."
        ),
        FoundationalExercise(
            id: "cable_overhead_extension",
            name: "Cable Overhead Tricep Extension",
            alternateNames: ["Overhead Cable Extension", "Rope Overhead Extension"],
            equipment: .cable,
            muscleGroup: .triceps,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Stretches tricep long head. Great for development."
        ),
        
        // STANDARD (Tier 3)
        FoundationalExercise(
            id: "cable_chest_press",
            name: "Cable Chest Press",
            alternateNames: ["Standing Cable Chest Press"],
            equipment: .cable,
            muscleGroup: .chest,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Pressing with constant tension. Good variety."
        ),
        FoundationalExercise(
            id: "cable_woodchop",
            name: "Cable Woodchop",
            alternateNames: ["Woodchop", "Cable Chop"],
            equipment: .cable,
            muscleGroup: .core,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Rotational core exercise. Functional movement."
        ),
        FoundationalExercise(
            id: "cable_kickback",
            name: "Cable Glute Kickback",
            alternateNames: ["Cable Kickback", "Glute Kickback"],
            equipment: .cable,
            muscleGroup: .glutes,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Glute isolation. Popular and effective."
        ),
        
        // VARIETY (Tier 4)
        FoundationalExercise(
            id: "cable_crunch",
            name: "Cable Crunch",
            alternateNames: ["Kneeling Cable Crunch", "Rope Crunch"],
            equipment: .cable,
            muscleGroup: .core,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 1,
            description: "Weighted ab exercise. Progressive overload for abs."
        ),
        FoundationalExercise(
            id: "straight_arm_pulldown",
            name: "Straight Arm Pulldown",
            alternateNames: ["Cable Straight Arm Pulldown", "Lat Pulldown Straight Arm"],
            equipment: .cable,
            muscleGroup: .back,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 2,
            description: "Lat isolation. Great mind-muscle connection."
        ),
        FoundationalExercise(
            id: "cable_upright_row",
            name: "Cable Upright Row",
            alternateNames: ["Upright Cable Row"],
            equipment: .cable,
            muscleGroup: .shoulders,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 2,
            description: "Shoulder builder with constant tension."
        ),
        FoundationalExercise(
            id: "cable_pull_through",
            name: "Cable Pull Through",
            alternateNames: ["Pull Through"],
            equipment: .cable,
            muscleGroup: .glutes,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 2,
            description: "Hip hinge pattern. Great glute and hamstring work."
        ),
    ]
    
    // MARK: - 🏢 MACHINE EXERCISES (Top 15)
    
    let machineExercises: [FoundationalExercise] = [
        // ESSENTIAL (Tier 1) - Perfect for beginners!
        FoundationalExercise(
            id: "machine_chest_press",
            name: "Machine Chest Press",
            alternateNames: ["Chest Press Machine", "Seated Chest Press", "Lever Chest Press"],
            equipment: .machine,
            muscleGroup: .chest,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Safest chest pressing. Fixed path reduces injury risk."
        ),
        FoundationalExercise(
            id: "machine_shoulder_press",
            name: "Machine Shoulder Press",
            alternateNames: ["Shoulder Press Machine", "Seated Machine Press", "Lever Shoulder Press"],
            equipment: .machine,
            muscleGroup: .shoulders,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Safe shoulder pressing. Great for beginners."
        ),
        FoundationalExercise(
            id: "leg_press",
            name: "Leg Press",
            alternateNames: ["Machine Leg Press", "45 Degree Leg Press", "Lever Leg Press"],
            equipment: .machine,
            muscleGroup: .quads,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Safe leg compound. Can use heavy weight safely."
        ),
        FoundationalExercise(
            id: "machine_row",
            name: "Machine Row",
            alternateNames: ["Seated Machine Row", "Lever Row", "Chest Supported Row"],
            equipment: .machine,
            muscleGroup: .back,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Safe back exercise. Fixed path for beginners."
        ),
        
        // FUNDAMENTAL (Tier 2)
        FoundationalExercise(
            id: "leg_curl",
            name: "Leg Curl",
            alternateNames: ["Machine Leg Curl", "Lying Leg Curl", "Seated Leg Curl", "Lever Leg Curl"],
            equipment: .machine,
            muscleGroup: .hamstrings,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Hamstring isolation. Easy and effective."
        ),
        FoundationalExercise(
            id: "leg_extension",
            name: "Leg Extension",
            alternateNames: ["Machine Leg Extension", "Lever Leg Extension"],
            equipment: .machine,
            muscleGroup: .quads,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Quad isolation. Great for definition."
        ),
        FoundationalExercise(
            id: "pec_deck",
            name: "Pec Deck",
            alternateNames: ["Pec Fly Machine", "Machine Fly", "Lever Pec Deck"],
            equipment: .machine,
            muscleGroup: .chest,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Chest isolation. Safe and effective."
        ),
        FoundationalExercise(
            id: "machine_lateral_raise",
            name: "Machine Lateral Raise",
            alternateNames: ["Lateral Raise Machine", "Lever Lateral Raise"],
            equipment: .machine,
            muscleGroup: .shoulders,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Shoulder isolation with fixed path."
        ),
        
        // STANDARD (Tier 3)
        FoundationalExercise(
            id: "hack_squat",
            name: "Hack Squat",
            alternateNames: ["Machine Hack Squat", "Lever Hack Squat"],
            equipment: .machine,
            muscleGroup: .quads,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Quad-focused leg exercise. Safer than barbell squats."
        ),
        FoundationalExercise(
            id: "hip_abduction",
            name: "Hip Abduction Machine",
            alternateNames: ["Hip Abductor", "Abduction Machine", "Lever Hip Abduction"],
            equipment: .machine,
            muscleGroup: .glutes,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Targets outer glutes. Popular for glute development."
        ),
        FoundationalExercise(
            id: "hip_adduction",
            name: "Hip Adduction Machine",
            alternateNames: ["Hip Adductor", "Adduction Machine", "Lever Hip Adduction"],
            equipment: .machine,
            muscleGroup: .quads,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Inner thigh exercise. Good for leg balance."
        ),
        FoundationalExercise(
            id: "machine_calf_raise",
            name: "Machine Calf Raise",
            alternateNames: ["Seated Calf Raise", "Standing Calf Raise Machine", "Lever Calf Raise"],
            equipment: .machine,
            muscleGroup: .calves,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Calf isolation. Easy to use heavy weight."
        ),
        
        // VARIETY (Tier 4)
        FoundationalExercise(
            id: "machine_rear_delt",
            name: "Machine Rear Delt Fly",
            alternateNames: ["Reverse Pec Deck", "Rear Delt Machine", "Lever Rear Delt"],
            equipment: .machine,
            muscleGroup: .shoulders,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 1,
            description: "Rear delt isolation. Often neglected muscle."
        ),
        FoundationalExercise(
            id: "machine_preacher_curl",
            name: "Machine Preacher Curl",
            alternateNames: ["Preacher Curl Machine", "Lever Preacher Curl"],
            equipment: .machine,
            muscleGroup: .biceps,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 1,
            description: "Bicep isolation with fixed path."
        ),
        FoundationalExercise(
            id: "glute_machine",
            name: "Glute Machine",
            alternateNames: ["Glute Kickback Machine", "Hip Extension Machine"],
            equipment: .machine,
            muscleGroup: .glutes,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 1,
            description: "Targeted glute work. Safe and effective."
        ),
    ]
    
    // MARK: - 🏃 BODYWEIGHT EXERCISES (Top 15)
    
    let bodyweightExercises: [FoundationalExercise] = [
        // ESSENTIAL (Tier 1)
        FoundationalExercise(
            id: "bw_pushup",
            name: "Push Up",
            alternateNames: ["Push-Up", "Pushup", "Press Up"],
            equipment: .bodyweight,
            muscleGroup: .chest,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "The ultimate bodyweight chest exercise. Everyone should master this."
        ),
        FoundationalExercise(
            id: "bw_squat",
            name: "Bodyweight Squat",
            alternateNames: ["Air Squat", "Squat"],
            equipment: .bodyweight,
            muscleGroup: .quads,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Foundation of all squatting. Master form here."
        ),
        FoundationalExercise(
            id: "bw_plank",
            name: "Plank",
            alternateNames: ["Front Plank", "Prone Plank"],
            equipment: .bodyweight,
            muscleGroup: .core,
            tier: .essential,
            isCompound: false,
            difficultyLevel: 1,
            description: "Core stability essential. Everyone should do planks."
        ),
        FoundationalExercise(
            id: "bw_lunge",
            name: "Bodyweight Lunge",
            alternateNames: ["Lunge", "Walking Lunge", "Forward Lunge"],
            equipment: .bodyweight,
            muscleGroup: .quads,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "Unilateral leg movement. Builds balance and strength."
        ),
        
        // FUNDAMENTAL (Tier 2)
        FoundationalExercise(
            id: "bw_pullup",
            name: "Pull Up",
            alternateNames: ["Pull-Up", "Pullup"],
            equipment: .bodyweight,
            muscleGroup: .back,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 4,
            description: "Best back exercise. May need assistance at first."
        ),
        FoundationalExercise(
            id: "bw_dip",
            name: "Dip",
            alternateNames: ["Tricep Dip", "Parallel Bar Dip"],
            equipment: .bodyweight,
            muscleGroup: .triceps,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 3,
            description: "Great for chest and triceps. Classic exercise."
        ),
        FoundationalExercise(
            id: "bw_glute_bridge",
            name: "Glute Bridge",
            alternateNames: ["Hip Bridge", "Bridge"],
            equipment: .bodyweight,
            muscleGroup: .glutes,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Glute activation exercise. Great for beginners."
        ),
        FoundationalExercise(
            id: "bw_crunch",
            name: "Crunch",
            alternateNames: ["Abdominal Crunch", "Ab Crunch"],
            equipment: .bodyweight,
            muscleGroup: .core,
            tier: .fundamental,
            isCompound: false,
            difficultyLevel: 1,
            description: "Basic ab exercise. Everyone knows this."
        ),
        
        // STANDARD (Tier 3)
        FoundationalExercise(
            id: "bw_chinup",
            name: "Chin Up",
            alternateNames: ["Chin-Up", "Chinup"],
            equipment: .bodyweight,
            muscleGroup: .back,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 4,
            description: "More bicep involvement than pull-ups."
        ),
        FoundationalExercise(
            id: "bw_mountain_climber",
            name: "Mountain Climber",
            alternateNames: ["Mountain Climbers"],
            equipment: .bodyweight,
            muscleGroup: .core,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Cardio and core combined. Great for conditioning."
        ),
        FoundationalExercise(
            id: "bw_leg_raise",
            name: "Lying Leg Raise",
            alternateNames: ["Leg Raise", "Lying Leg Raises"],
            equipment: .bodyweight,
            muscleGroup: .core,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 2,
            description: "Lower ab focus. Simple but effective."
        ),
        FoundationalExercise(
            id: "bw_superman",
            name: "Superman",
            alternateNames: ["Back Extension", "Superman Hold"],
            equipment: .bodyweight,
            muscleGroup: .back,
            tier: .standard,
            isCompound: false,
            difficultyLevel: 1,
            description: "Lower back strengthening. Important for posture."
        ),
        
        // VARIETY (Tier 4)
        FoundationalExercise(
            id: "bw_burpee",
            name: "Burpee",
            alternateNames: ["Burpees"],
            equipment: .bodyweight,
            muscleGroup: .fullBody,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 3,
            description: "Full body conditioning. Challenging but effective."
        ),
        FoundationalExercise(
            id: "bw_side_plank",
            name: "Side Plank",
            alternateNames: ["Lateral Plank"],
            equipment: .bodyweight,
            muscleGroup: .core,
            tier: .variety,
            isCompound: false,
            difficultyLevel: 2,
            description: "Oblique and core stability. Important variation."
        ),
        FoundationalExercise(
            id: "bw_step_up",
            name: "Step Up",
            alternateNames: ["Box Step Up", "Step Ups"],
            equipment: .bodyweight,
            muscleGroup: .quads,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 2,
            description: "Unilateral leg exercise. Great for beginners."
        ),
    ]
    
    // MARK: - 🔔 KETTLEBELL EXERCISES (Top 10)
    
    let kettlebellExercises: [FoundationalExercise] = [
        // ESSENTIAL (Tier 1)
        FoundationalExercise(
            id: "kb_swing",
            name: "Kettlebell Swing",
            alternateNames: ["KB Swing", "Russian Swing", "Kettlebell Russian Swing"],
            equipment: .kettlebell,
            muscleGroup: .glutes,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 2,
            description: "The foundational kettlebell movement. Hip hinge power."
        ),
        FoundationalExercise(
            id: "kb_goblet_squat",
            name: "Kettlebell Goblet Squat",
            alternateNames: ["KB Goblet Squat", "Goblet Squat"],
            equipment: .kettlebell,
            muscleGroup: .quads,
            tier: .essential,
            isCompound: true,
            difficultyLevel: 1,
            description: "Perfect for learning squat form. Hold close to chest."
        ),
        
        // FUNDAMENTAL (Tier 2)
        FoundationalExercise(
            id: "kb_deadlift",
            name: "Kettlebell Deadlift",
            alternateNames: ["KB Deadlift", "Single Kettlebell Deadlift"],
            equipment: .kettlebell,
            muscleGroup: .hamstrings,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 2,
            description: "Hip hinge with kettlebell. Great for beginners."
        ),
        FoundationalExercise(
            id: "kb_press",
            name: "Kettlebell Press",
            alternateNames: ["KB Overhead Press", "Kettlebell Overhead Press"],
            equipment: .kettlebell,
            muscleGroup: .shoulders,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 2,
            description: "Shoulder press with kettlebell. Different feel than dumbbells."
        ),
        FoundationalExercise(
            id: "kb_row",
            name: "Kettlebell Row",
            alternateNames: ["KB Row", "Single Arm KB Row"],
            equipment: .kettlebell,
            muscleGroup: .back,
            tier: .fundamental,
            isCompound: true,
            difficultyLevel: 2,
            description: "Back builder with kettlebell. Unilateral focus."
        ),
        
        // STANDARD (Tier 3)
        FoundationalExercise(
            id: "kb_sumo_squat",
            name: "Kettlebell Sumo Squat",
            alternateNames: ["KB Sumo Squat", "Sumo Squat"],
            equipment: .kettlebell,
            muscleGroup: .quads,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Wide stance squat. Hits inner thighs and glutes."
        ),
        FoundationalExercise(
            id: "kb_lunge",
            name: "Kettlebell Lunge",
            alternateNames: ["KB Lunge", "Goblet Lunge"],
            equipment: .kettlebell,
            muscleGroup: .quads,
            tier: .standard,
            isCompound: true,
            difficultyLevel: 2,
            description: "Lunge with weight. Great leg builder."
        ),
        
        // VARIETY (Tier 4)
        FoundationalExercise(
            id: "kb_turkish_getup",
            name: "Turkish Get Up",
            alternateNames: ["KB Turkish Get Up", "TGU"],
            equipment: .kettlebell,
            muscleGroup: .fullBody,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 4,
            description: "Full body movement. Complex but effective."
        ),
        FoundationalExercise(
            id: "kb_clean",
            name: "Kettlebell Clean",
            alternateNames: ["KB Clean"],
            equipment: .kettlebell,
            muscleGroup: .fullBody,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 3,
            description: "Power movement. Transitions into press."
        ),
        FoundationalExercise(
            id: "kb_windmill",
            name: "Kettlebell Windmill",
            alternateNames: ["KB Windmill"],
            equipment: .kettlebell,
            muscleGroup: .core,
            tier: .variety,
            isCompound: true,
            difficultyLevel: 3,
            description: "Core and hip mobility. Unique movement pattern."
        ),
    ]
    
    // MARK: - Public Access Methods
    
    /// Get all foundational exercises for a specific equipment type
    func getFoundationalExercises(for equipment: FoundationalEquipment) -> [FoundationalExercise] {
        switch equipment {
        case .barbell: return barbellExercises
        case .dumbbell: return dumbbellExercises
        case .cable: return cableExercises
        case .machine: return machineExercises
        case .bodyweight: return bodyweightExercises
        case .kettlebell: return kettlebellExercises
        case .smithMachine: return barbellExercises.filter { $0.tier == .essential || $0.tier == .fundamental }
        case .ezBar: return barbellExercises.filter { $0.muscleGroup == .biceps || $0.muscleGroup == .triceps }
        case .resistanceBand: return bodyweightExercises.filter { $0.tier == .essential || $0.tier == .fundamental }
        }
    }
    
    /// Get foundational exercises filtered by tier (for progressive unlocking)
    func getFoundationalExercises(for equipment: FoundationalEquipment, maxTier: FoundationTier) -> [FoundationalExercise] {
        return getFoundationalExercises(for: equipment).filter { $0.tier <= maxTier }
    }
    
    /// Get all foundational exercises for a specific muscle group
    func getFoundationalExercises(for muscleGroup: FoundationalMuscleGroup) -> [FoundationalExercise] {
        return allFoundationalExercises.filter { $0.muscleGroup == muscleGroup }
    }
    
    /// Get foundational exercises matching equipment AND muscle group
    func getFoundationalExercises(for equipment: FoundationalEquipment, muscleGroup: FoundationalMuscleGroup, maxTier: FoundationTier = .variety) -> [FoundationalExercise] {
        return getFoundationalExercises(for: equipment, maxTier: maxTier)
            .filter { $0.muscleGroup == muscleGroup }
    }
    
    /// All foundational exercises combined
    var allFoundationalExercises: [FoundationalExercise] {
        return barbellExercises + dumbbellExercises + cableExercises +
               machineExercises + bodyweightExercises + kettlebellExercises
    }
    
    /// Get essential exercises only (Tier 1) - For brand new users
    var essentialExercises: [FoundationalExercise] {
        return allFoundationalExercises.filter { $0.tier == .essential }
    }
    
    /// Get all exercise names for matching (lowercased)
    var allFoundationalNames: Set<String> {
        var names = Set<String>()
        for exercise in allFoundationalExercises {
            names.insert(exercise.name.lowercased())
            for altName in exercise.alternateNames {
                names.insert(altName.lowercased())
            }
        }
        return names
    }
    
    /// Check if an exercise name matches a foundational exercise
    func isFoundationalExercise(_ exerciseName: String) -> Bool {
        let nameLower = exerciseName.lowercased()
        return allFoundationalNames.contains { nameLower.contains($0) || $0.contains(nameLower) }
    }
    
    /// Get the foundational exercise data if it matches
    func getFoundationalExercise(matching exerciseName: String) -> FoundationalExercise? {
        let nameLower = exerciseName.lowercased()
        return allFoundationalExercises.first { foundational in
            nameLower.contains(foundational.name.lowercased()) ||
            foundational.name.lowercased().contains(nameLower) ||
            foundational.alternateNames.contains { alt in
                nameLower.contains(alt.lowercased()) || alt.lowercased().contains(nameLower)
            }
        }
    }
    
    /// Get the tier of an exercise (returns nil if not foundational)
    func getTier(for exerciseName: String) -> FoundationTier? {
        return getFoundationalExercise(matching: exerciseName)?.tier
    }
    
    // MARK: - Equipment Preference by Experience Level
    
    /// Equipment comfort progression based on experience level from onboarding
    /// 
    /// ALL users start with common equipment (machines/cables preferred), but progress at different rates:
    ///
    /// BEGINNER (10 workout transition):
    ///   - Workouts 1-3:  Heavy machine/cable preference (building confidence)
    ///   - Workouts 4-6:  Moderate preference (introducing dumbbells)
    ///   - Workouts 7-10: Slight preference (almost balanced)
    ///   - Workout 11+:   Normal selection
    ///
    /// INTERMEDIATE (5 workout transition):
    ///   - Workouts 1-2:  Moderate machine/cable preference
    ///   - Workouts 3-5:  Slight preference
    ///   - Workout 6+:    Normal selection
    ///
    /// ADVANCED (2 workout transition):
    ///   - Workouts 1-2:  Slight machine/cable preference (quick orientation)
    ///   - Workout 3+:    Normal selection
    ///
    func getBeginnerEquipmentBoost(
        equipment: String,
        userWorkoutCount: Int,
        experienceLevel: String,
        userEquipment: [String]
    ) -> Double {
        let level = experienceLevel.lowercased()
        let equipLower = equipment.lowercased()
        
        // Check what equipment user has available
        let hasMachines = userEquipment.contains { $0.lowercased().contains("machine") }
        let hasCables = userEquipment.contains { $0.lowercased().contains("cable") }
        
        // Helper to calculate equipment boost
        func equipmentBoost(machineBoost: Double, cableBoost: Double, 
                           dumbbellPenalty: Double = 0, barbellPenalty: Double = 0) -> Double {
            if equipLower.contains("machine") || equipLower.contains("lever") {
                return machineBoost
            } else if equipLower.contains("cable") {
                return cableBoost
            } else if equipLower.contains("dumbbell") {
                return -dumbbellPenalty
            } else if equipLower.contains("barbell") {
                return -barbellPenalty
            }
            return 0
        }
        
        // ═══════════════════════════════════════════════════════════════
        // ADVANCED: Quick 2-workout orientation, then fully open
        // ═══════════════════════════════════════════════════════════════
        if level == "advanced" {
            guard userWorkoutCount < 2 && hasMachines && hasCables else { return 0 }
            // Just a slight preference for first 2 workouts
            return equipmentBoost(machineBoost: 30, cableBoost: 20)
        }
        
        // ═══════════════════════════════════════════════════════════════
        // INTERMEDIATE: 5-workout transition period
        // ═══════════════════════════════════════════════════════════════
        if level == "intermediate" {
            guard userWorkoutCount < 5 && hasMachines && hasCables else { return 0 }
            
            if userWorkoutCount < 2 {
                // Moderate preference
                return equipmentBoost(machineBoost: 80, cableBoost: 60, dumbbellPenalty: 10, barbellPenalty: 20)
            } else {
                // Slight preference
                return equipmentBoost(machineBoost: 30, cableBoost: 20)
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // BEGINNER: Full 10-workout progression to build confidence
        // ═══════════════════════════════════════════════════════════════
        guard userWorkoutCount < 10 else { return 0 }
        
        if hasMachines && hasCables {
            // Workouts 1-3: HEAVY preference for machines/cables
            if userWorkoutCount < 3 {
                return equipmentBoost(machineBoost: 150, cableBoost: 120, dumbbellPenalty: 30, barbellPenalty: 60)
            }
            // Workouts 4-6: Moderate preference, dumbbells now okay
            else if userWorkoutCount < 6 {
                return equipmentBoost(machineBoost: 80, cableBoost: 60, dumbbellPenalty: -20, barbellPenalty: 30)
            }
            // Workouts 7-10: Slight preference
            else {
                return equipmentBoost(machineBoost: 30, cableBoost: 20)
            }
        }
        // If user only has cables (no machines)
        else if hasCables && !hasMachines {
            if userWorkoutCount < 5 {
                if equipLower.contains("cable") { return 100 }
                else if equipLower.contains("dumbbell") { return 20 }
            }
        }
        
        return 0
    }
    
    // MARK: - Scoring Methods
    
    /// Get a score boost for foundational exercises based on user's experience level
    /// 
    /// ALL experience levels start with common exercises, but variety is introduced at different rates:
    /// - BEGINNER: Strong foundational preference for ~20 workouts
    /// - INTERMEDIATE: Moderate preference for ~10 workouts  
    /// - ADVANCED: Light preference for ~5 workouts, then full variety
    ///
    func getFoundationalBoostScore(
        exerciseName: String,
        userWorkoutCount: Int,
        userTotalCompletedExercises: Int = 0,
        experienceLevel: String = "beginner"
    ) -> Double {
        let level = experienceLevel.lowercased()
        
        guard let foundational = getFoundationalExercise(matching: exerciseName) else {
            // Not a foundational exercise - apply penalty based on experience level
            // Advanced users get variety faster, beginners stick to basics longer
            switch level {
            case "advanced":
                // Quick unlock: penalty only for first 3 workouts, then open
                if userWorkoutCount < 3 { return -40 }
                return 0
                
            case "intermediate":
                // Moderate unlock: penalty tapers by workout 10
                if userWorkoutCount < 5 { return -60 }
                else if userWorkoutCount < 10 { return -25 }
                return 0
                
            default: // beginner
                // Gradual unlock: strong preference for basics through workout 20
                if userWorkoutCount < 5 { return -80 }
                else if userWorkoutCount < 10 { return -50 }
                else if userWorkoutCount < 20 { return -20 }
                return 0
            }
        }
        
        // Calculate boost based on tier and user experience
        let tierBoost: Double
        switch foundational.tier {
        case .essential:
            tierBoost = 200  // Massive boost for essential exercises
        case .fundamental:
            tierBoost = 100  // Large boost
        case .standard:
            tierBoost = 50   // Moderate boost
        case .variety:
            tierBoost = 25   // Small boost
        }
        
        // Scale boost based on user experience
        // New users (0-5 workouts) get full boost
        // Experienced users (20+ workouts) get reduced boost
        let experienceMultiplier: Double
        if userWorkoutCount < 5 {
            experienceMultiplier = 1.0
        } else if userWorkoutCount < 10 {
            experienceMultiplier = 0.8
        } else if userWorkoutCount < 20 {
            experienceMultiplier = 0.5
        } else if userWorkoutCount < 50 {
            experienceMultiplier = 0.3
        } else {
            experienceMultiplier = 0.15  // Experienced users still get small boost for proven exercises
        }
        
        // Additional boost for compound movements (they're more important to learn)
        let compoundBoost = foundational.isCompound ? 20.0 : 0.0
        
        return (tierBoost * experienceMultiplier) + compoundBoost
    }
    
    /// Determine the max tier a user should see based on workout count
    func getMaxTierForUser(workoutCount: Int) -> FoundationTier {
        if workoutCount < 3 {
            return .essential
        } else if workoutCount < 6 {
            return .fundamental
        } else if workoutCount < 12 {
            return .standard
        } else {
            return .variety
        }
    }
    
    /// Check if user should be restricted to foundational exercises only
    func shouldRestrictToFoundational(workoutCount: Int, experienceLevel: String) -> Bool {
        // Beginners with few workouts should be restricted
        if experienceLevel.lowercased() == "beginner" && workoutCount < 10 {
            return true
        }
        // Very new users regardless of stated experience
        if workoutCount < 3 {
            return true
        }
        return false
    }
}
