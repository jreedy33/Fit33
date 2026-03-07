import Foundation

// MARK: - Models

struct RecoveryExercise: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: RecoveryCategory
    let targetMuscles: [String]
    let durationSeconds: Int
    let difficulty: RecoveryDifficulty
    let instructions: [String]
    let sfSymbol: String
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RecoveryExercise, rhs: RecoveryExercise) -> Bool { lhs.id == rhs.id }
}

enum RecoveryCategory: String, CaseIterable {
    case stretch = "Stretch"
    case foamRolling = "Foam Rolling"
    case mobility = "Mobility"
    case yoga = "Yoga"
    case breathing = "Breathing"
    
    var icon: String {
        switch self {
        case .stretch: return "figure.flexibility"
        case .foamRolling: return "circle.dotted"
        case .mobility: return "figure.walk"
        case .yoga: return "figure.mind.and.body"
        case .breathing: return "wind"
        }
    }
}

enum RecoveryDifficulty: String {
    case beginner, intermediate, advanced
}

struct RecoveryRoutine: Identifiable {
    let id = UUID()
    let title: String
    let targetMuscles: [String]
    let exercises: [RecoveryExercise]
    let totalDurationMinutes: Int
    let difficulty: RecoveryDifficulty
    let generatedAt: Date
}

// MARK: - Database

struct RecoveryExerciseDatabase {
    
    // MARK: - Chest
    
    static let chestExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Doorway Chest Stretch", category: .stretch, targetMuscles: ["Chest", "Front Delts"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Stand in a doorway with arms at 90 degrees", "Step forward until you feel a stretch in your chest", "Hold and breathe deeply"], sfSymbol: "figure.flexibility"),
        RecoveryExercise(name: "Chest Opener Stretch", category: .stretch, targetMuscles: ["Chest"], durationSeconds: 40,
                         difficulty: .beginner, instructions: ["Clasp hands behind your back", "Lift arms while squeezing shoulder blades", "Hold when you feel the chest stretch"], sfSymbol: "figure.flexibility"),
        RecoveryExercise(name: "Foam Roll Pecs", category: .foamRolling, targetMuscles: ["Chest"], durationSeconds: 45,
                         difficulty: .intermediate, instructions: ["Lie face down with foam roller under one pec", "Roll slowly from shoulder to sternum", "Pause on tender spots for 10 seconds"], sfSymbol: "circle.dotted"),
        RecoveryExercise(name: "Thread the Needle", category: .mobility, targetMuscles: ["Chest", "Thoracic Spine"], durationSeconds: 40,
                         difficulty: .beginner, instructions: ["Start on all fours", "Reach one arm under your body, rotating torso", "Follow with your gaze and hold the stretch"], sfSymbol: "figure.walk"),
    ]
    
    // MARK: - Back
    
    static let backExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Cat-Cow Stretch", category: .mobility, targetMuscles: ["Back", "Core"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Start on all fours, hands under shoulders", "Inhale: arch back, look up (cow)", "Exhale: round back, tuck chin (cat)", "Flow between positions slowly"], sfSymbol: "figure.walk"),
        RecoveryExercise(name: "Child's Pose", category: .yoga, targetMuscles: ["Back", "Lats"], durationSeconds: 60,
                         difficulty: .beginner, instructions: ["Kneel and sit back on heels", "Extend arms forward on the floor", "Relax into the stretch and breathe deeply"], sfSymbol: "figure.mind.and.body"),
        RecoveryExercise(name: "Foam Roll Lats", category: .foamRolling, targetMuscles: ["Lats", "Back"], durationSeconds: 45,
                         difficulty: .intermediate, instructions: ["Lie on your side with roller under armpit", "Roll from armpit to mid-back", "Keep arm extended overhead"], sfSymbol: "circle.dotted"),
        RecoveryExercise(name: "Thoracic Rotation", category: .mobility, targetMuscles: ["Thoracic Spine", "Back"], durationSeconds: 40,
                         difficulty: .beginner, instructions: ["Lie on side with knees stacked at 90 degrees", "Rotate top arm open toward the ceiling", "Follow with your gaze, keep knees together"], sfSymbol: "figure.walk"),
        RecoveryExercise(name: "Seated Spinal Twist", category: .yoga, targetMuscles: ["Back", "Core"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Sit with legs extended, cross one leg over", "Twist toward the bent knee", "Use opposite elbow for leverage, hold"], sfSymbol: "figure.mind.and.body"),
    ]
    
    // MARK: - Shoulders
    
    static let shoulderExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Cross-Body Shoulder Stretch", category: .stretch, targetMuscles: ["Shoulders", "Rear Delts"], durationSeconds: 40,
                         difficulty: .beginner, instructions: ["Pull one arm across your chest", "Use the opposite hand to press gently", "Hold and switch sides"], sfSymbol: "figure.flexibility"),
        RecoveryExercise(name: "Wall Slides", category: .mobility, targetMuscles: ["Shoulders", "Scapula"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Stand with back against a wall", "Arms in W position against the wall", "Slowly slide arms up to Y position and back down"], sfSymbol: "figure.walk"),
        RecoveryExercise(name: "Shoulder Dislocates", category: .mobility, targetMuscles: ["Shoulders", "Chest"], durationSeconds: 40,
                         difficulty: .intermediate, instructions: ["Hold a band or towel with wide grip", "Slowly rotate arms overhead and behind you", "Keep arms straight throughout the motion"], sfSymbol: "figure.walk"),
        RecoveryExercise(name: "Foam Roll Upper Back", category: .foamRolling, targetMuscles: ["Upper Back", "Shoulders"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Lie on roller at mid-back", "Cross arms over chest", "Roll from mid-back to upper back slowly"], sfSymbol: "circle.dotted"),
    ]
    
    // MARK: - Legs (Quads/Hamstrings/Glutes)
    
    static let legExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Standing Quad Stretch", category: .stretch, targetMuscles: ["Quads"], durationSeconds: 40,
                         difficulty: .beginner, instructions: ["Stand on one leg, grab opposite ankle", "Pull heel toward glute", "Keep knees together, hold for balance"], sfSymbol: "figure.flexibility"),
        RecoveryExercise(name: "Seated Hamstring Stretch", category: .stretch, targetMuscles: ["Hamstrings"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Sit with one leg extended, other bent", "Hinge forward from hips toward extended foot", "Keep back straight, reach for toes"], sfSymbol: "figure.flexibility"),
        RecoveryExercise(name: "Pigeon Pose", category: .yoga, targetMuscles: ["Glutes", "Hip Flexors"], durationSeconds: 60,
                         difficulty: .intermediate, instructions: ["From all fours, bring one knee forward", "Extend the back leg straight behind you", "Sink hips toward the floor and hold"], sfSymbol: "figure.mind.and.body"),
        RecoveryExercise(name: "Foam Roll Quads", category: .foamRolling, targetMuscles: ["Quads"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Lie face down with roller under thighs", "Roll from hip to just above knee", "Pause on tender spots"], sfSymbol: "circle.dotted"),
        RecoveryExercise(name: "Foam Roll IT Band", category: .foamRolling, targetMuscles: ["IT Band", "Legs"], durationSeconds: 45,
                         difficulty: .intermediate, instructions: ["Lie on your side with roller under outer thigh", "Roll from hip to just above knee", "Support yourself with hands, control pressure"], sfSymbol: "circle.dotted"),
        RecoveryExercise(name: "90/90 Hip Stretch", category: .mobility, targetMuscles: ["Hips", "Glutes"], durationSeconds: 50,
                         difficulty: .intermediate, instructions: ["Sit with front leg at 90 degrees, back leg at 90 degrees", "Lean forward over front shin", "Switch sides after hold"], sfSymbol: "figure.walk"),
        RecoveryExercise(name: "Couch Stretch", category: .stretch, targetMuscles: ["Hip Flexors", "Quads"], durationSeconds: 50,
                         difficulty: .intermediate, instructions: ["Kneel with back foot against a wall or couch", "Front foot planted, knee at 90 degrees", "Push hips forward gently"], sfSymbol: "figure.flexibility"),
    ]
    
    // MARK: - Core
    
    static let coreExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Dead Bug", category: .mobility, targetMuscles: ["Core", "Hip Flexors"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Lie on back, arms toward ceiling, knees at 90", "Slowly extend opposite arm and leg", "Return and alternate sides, keep lower back flat"], sfSymbol: "figure.walk"),
        RecoveryExercise(name: "Bird Dog", category: .mobility, targetMuscles: ["Core", "Back"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Start on all fours", "Extend opposite arm and leg simultaneously", "Hold briefly, return, and switch sides"], sfSymbol: "figure.walk"),
        RecoveryExercise(name: "Gentle Spinal Twist", category: .stretch, targetMuscles: ["Core", "Back"], durationSeconds: 45,
                         difficulty: .beginner, instructions: ["Lie on back, knees bent", "Drop both knees to one side", "Keep shoulders flat, look opposite direction"], sfSymbol: "figure.flexibility"),
    ]
    
    // MARK: - Arms (Biceps/Triceps)
    
    static let armExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Tricep Overhead Stretch", category: .stretch, targetMuscles: ["Triceps"], durationSeconds: 35,
                         difficulty: .beginner, instructions: ["Raise one arm overhead", "Bend elbow, reach hand down your back", "Use other hand to gently press elbow back"], sfSymbol: "figure.flexibility"),
        RecoveryExercise(name: "Bicep Wall Stretch", category: .stretch, targetMuscles: ["Biceps", "Forearms"], durationSeconds: 35,
                         difficulty: .beginner, instructions: ["Place palm flat on a wall, fingers pointing back", "Slowly rotate body away from the wall", "Hold when you feel the bicep stretch"], sfSymbol: "figure.flexibility"),
        RecoveryExercise(name: "Wrist Circles", category: .mobility, targetMuscles: ["Forearms", "Wrists"], durationSeconds: 30,
                         difficulty: .beginner, instructions: ["Extend arms in front", "Make slow circles with wrists", "10 circles each direction per wrist"], sfSymbol: "figure.walk"),
    ]
    
    // MARK: - Full Body / General
    
    static let fullBodyExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Sun Salutation Flow", category: .yoga, targetMuscles: ["Full Body"], durationSeconds: 90,
                         difficulty: .intermediate, instructions: ["Mountain pose → Forward fold", "Half lift → Plank → Chaturanga", "Upward dog → Downward dog", "Step forward → Rise to mountain pose"], sfSymbol: "figure.mind.and.body"),
        RecoveryExercise(name: "World's Greatest Stretch", category: .mobility, targetMuscles: ["Full Body"], durationSeconds: 60,
                         difficulty: .intermediate, instructions: ["Lunge forward, place both hands inside front foot", "Rotate and reach one arm to ceiling", "Return, switch sides, repeat 5 each side"], sfSymbol: "figure.walk"),
    ]
    
    // MARK: - Breathing
    
    static let breathingExercises: [RecoveryExercise] = [
        RecoveryExercise(name: "Box Breathing", category: .breathing, targetMuscles: ["Full Body"], durationSeconds: 120,
                         difficulty: .beginner, instructions: ["Inhale for 4 seconds", "Hold for 4 seconds", "Exhale for 4 seconds", "Hold for 4 seconds", "Repeat 6-8 cycles"], sfSymbol: "wind"),
        RecoveryExercise(name: "Diaphragmatic Breathing", category: .breathing, targetMuscles: ["Core"], durationSeconds: 90,
                         difficulty: .beginner, instructions: ["Lie on back, one hand on chest, one on belly", "Breathe in through nose, belly rises", "Exhale slowly through mouth, belly falls", "Chest stays still throughout"], sfSymbol: "wind"),
    ]
    
    // MARK: - Lookup
    
    static func exercises(for muscle: String) -> [RecoveryExercise] {
        let normalized = muscle.lowercased()
        switch normalized {
        case "chest", "pecs":
            return chestExercises
        case "back", "lats", "traps", "upper back", "lower back":
            return backExercises
        case "shoulders", "delts", "front delts", "rear delts", "side delts":
            return shoulderExercises
        case "quads", "hamstrings", "glutes", "legs", "calves", "hip flexors":
            return legExercises
        case "core", "abs", "obliques":
            return coreExercises
        case "biceps", "triceps", "arms", "forearms":
            return armExercises
        default:
            return fullBodyExercises
        }
    }
    
    static var allExercises: [RecoveryExercise] {
        chestExercises + backExercises + shoulderExercises + legExercises + coreExercises + armExercises + fullBodyExercises + breathingExercises
    }
}
