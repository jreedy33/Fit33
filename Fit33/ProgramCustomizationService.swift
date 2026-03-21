import Foundation
import SwiftUI

// MARK: - Customization Request Model

struct ProgramCustomizationRequest: Codable {
    let baseProgramId: String
    let baseProgramName: String
    
    // Quick customization options
    var availableEquipment: Set<String>
    var daysPerWeek: Int
    var maxWorkoutMinutes: Int
    var focusAdjustments: [String: Double] // e.g., ["chest": 1.5, "legs": 0.5] for more chest, less legs
    var avoidExercises: [String] // Exercises to skip (injuries, preferences)
    var specialInstructions: String? // Free text for AI/smart logic
    
    // Computed customization level
    var customizationLevel: CustomizationLevel {
        var changes = 0
        if !avoidExercises.isEmpty { changes += 1 }
        if !focusAdjustments.isEmpty { changes += 1 }
        if specialInstructions != nil { changes += 1 }
        
        switch changes {
        case 0: return .light
        case 1: return .moderate
        default: return .heavy
        }
    }
}

enum CustomizationLevel: String, Codable {
    case light = "light"      // Just equipment/days changes
    case moderate = "moderate" // Some exercise swaps
    case heavy = "heavy"       // Significant restructuring
}

// MARK: - Custom Program Models

struct UserCustomProgram: Codable, Identifiable {
    let id: String
    let userId: String
    let baseProgramId: String
    let customName: String
    let description: String
    let durationDays: Int
    let workoutsPerWeek: Int
    let avgWorkoutDurationMin: Int
    let equipment: [String]
    let icon: String
    let color: String
    let days: [CustomProgramDay]
    let createdAt: Date
    let customizationSummary: String // "Modified for home gym, 4 days/week"
    
    // For compatibility with existing views
    var duration: Int { durationDays }
}

struct CustomProgramDay: Codable, Identifiable {
    let id: String
    let dayNumber: Int
    let name: String
    let description: String
    let focusAreas: [String]
    let isRestDay: Bool
    let exercises: [CustomProgramExercise]
    let intensity: String
    let estimatedDurationMin: Int
}

struct CustomProgramExercise: Codable, Identifiable {
    let id: String
    let exerciseName: String
    let exerciseOrder: Int
    let sets: Int
    let repsMin: Int
    let repsMax: Int
    let repsType: String
    let restSeconds: Int
    let notes: String?
    let substitutes: [String] // Quick swap options
}

// MARK: - Equipment Categories

enum EquipmentCategory: String, CaseIterable {
    case bodyweight = "Bodyweight"
    case dumbbells = "Dumbbells"
    case barbell = "Barbell"
    case cables = "Cables"
    case machines = "Machines"
    case pullUpBar = "Pull-Up Bar"
    case bench = "Bench"
    case kettlebell = "Kettlebell"
    case bands = "Resistance Bands"
    
    var icon: String {
        switch self {
        case .bodyweight: return "figure.walk"
        case .dumbbells: return "dumbbell.fill"
        case .barbell: return "figure.strengthtraining.traditional"
        case .cables: return "cable.connector"
        case .machines: return "gearshape.2.fill"
        case .pullUpBar: return "figure.climbing"
        case .bench: return "rectangle.split.3x1"
        case .kettlebell: return "scalemass.fill"
        case .bands: return "circle.dotted"
        }
    }
}

// MARK: - Smart Exercise Mapping

struct ExerciseAlternative {
    let original: String
    let alternatives: [String: [String]] // equipment -> alternatives
}

// MARK: - Program Customization Service

@MainActor
class ProgramCustomizationService: ObservableObject {
    static let shared = ProgramCustomizationService()
    
    @Published var isGenerating = false
    @Published var generatedProgram: UserCustomProgram?
    @Published var error: String?
    
    private let supabase = SupabaseManager.shared
    private let programService = CloudProgramService.shared
    
    private init() {}
    
    // MARK: - Exercise Alternative Mappings
    
    /// Comprehensive mapping of exercises to alternatives based on equipment
    /// Format: [OriginalExercise: [equipment_type: alternative_exercise]]
    private let exerciseAlternatives: [String: [String: String]] = [
        
        // ============================================================================
        // CHEST EXERCISES (20+ mappings)
        // ============================================================================
        
        "Barbell Bench Press": [
            "dumbbells": "Dumbbell Bench Press",
            "bodyweight": "Push Up",
            "cables": "Cable Chest Press",
            "machines": "Machine Chest Press",
            "bands": "Band Chest Press",
            "kettlebell": "Kettlebell Floor Press"
        ],
        "Dumbbell Bench Press": [
            "bodyweight": "Push Up",
            "cables": "Cable Chest Press",
            "barbell": "Barbell Bench Press",
            "bands": "Band Chest Press",
            "kettlebell": "Kettlebell Floor Press"
        ],
        "Incline Barbell Press": [
            "dumbbells": "Dumbbell Incline Press",
            "bodyweight": "Decline Push Up",
            "cables": "Incline Cable Press",
            "machines": "Incline Machine Press"
        ],
        "Dumbbell Incline Press": [
            "bodyweight": "Decline Push Up",
            "barbell": "Incline Barbell Press",
            "cables": "Incline Cable Fly",
            "bands": "Incline Band Press"
        ],
        "Decline Bench Press": [
            "dumbbells": "Decline Dumbbell Press",
            "bodyweight": "Decline Push Up",
            "cables": "High Cable Fly"
        ],
        "Cable Fly": [
            "dumbbells": "Dumbbell Fly",
            "bodyweight": "Wide Push Up",
            "machines": "Pec Deck",
            "bands": "Band Fly"
        ],
        "Dumbbell Fly": [
            "cables": "Cable Fly",
            "bodyweight": "Wide Push Up",
            "machines": "Pec Deck",
            "bands": "Band Fly"
        ],
        "Incline Dumbbell Fly": [
            "cables": "Low Cable Fly",
            "bodyweight": "Decline Push Up",
            "bands": "Incline Band Fly"
        ],
        "Cable Crossover": [
            "dumbbells": "Dumbbell Fly",
            "bodyweight": "Wide Push Up",
            "bands": "Band Crossover"
        ],
        "Pec Deck": [
            "dumbbells": "Dumbbell Fly",
            "cables": "Cable Fly",
            "bodyweight": "Wide Push Up"
        ],
        "Machine Chest Press": [
            "dumbbells": "Dumbbell Bench Press",
            "barbell": "Barbell Bench Press",
            "bodyweight": "Push Up"
        ],
        "Push Up": [
            "dumbbells": "Dumbbell Bench Press",
            "barbell": "Barbell Bench Press",
            "cables": "Cable Chest Press"
        ],
        "Wide Push Up": [
            "dumbbells": "Dumbbell Fly",
            "cables": "Cable Fly"
        ],
        "Diamond Push Up": [
            "dumbbells": "Close Grip Dumbbell Press",
            "barbell": "Close Grip Bench Press",
            "cables": "Cable Triceps Pushdown"
        ],
        "Decline Push Up": [
            "dumbbells": "Dumbbell Incline Press",
            "barbell": "Incline Barbell Press"
        ],
        "Dumbbell Pullover": [
            "cables": "Straight Arm Pulldown",
            "barbell": "Barbell Pullover",
            "bodyweight": "Pull Up"
        ],
        "Close Grip Bench Press": [
            "dumbbells": "Close Grip Dumbbell Press",
            "bodyweight": "Diamond Push Up",
            "cables": "Cable Triceps Pushdown"
        ],
        
        // ============================================================================
        // BACK EXERCISES (25+ mappings)
        // ============================================================================
        
        "Barbell Row": [
            "dumbbells": "Dumbbell Row",
            "cables": "Cable Seated Row",
            "bodyweight": "Inverted Row",
            "bands": "Band Row",
            "kettlebell": "Kettlebell Row"
        ],
        "Dumbbell Row": [
            "barbell": "Barbell Row",
            "cables": "Cable Row",
            "bodyweight": "Inverted Row",
            "bands": "Band Row",
            "kettlebell": "Kettlebell Row"
        ],
        "T-Bar Row": [
            "dumbbells": "Dumbbell Row",
            "barbell": "Barbell Row",
            "cables": "Cable Seated Row"
        ],
        "Pendlay Row": [
            "dumbbells": "Dumbbell Row",
            "cables": "Cable Seated Row",
            "bodyweight": "Inverted Row"
        ],
        "Pull Up": [
            "cables": "Lat Pulldown",
            "bands": "Band Assisted Pull Up",
            "dumbbells": "Dumbbell Pullover",
            "machines": "Assisted Pull Up Machine"
        ],
        "Chin Up": [
            "cables": "Underhand Lat Pulldown",
            "dumbbells": "Dumbbell Curl",
            "bands": "Band Chin Up"
        ],
        "Wide Grip Pull Up": [
            "cables": "Wide Grip Lat Pulldown",
            "bodyweight": "Inverted Row"
        ],
        "Lat Pulldown": [
            "bodyweight": "Pull Up",
            "bands": "Band Pulldown",
            "dumbbells": "Dumbbell Pullover"
        ],
        "Wide Grip Lat Pulldown": [
            "bodyweight": "Wide Grip Pull Up",
            "dumbbells": "Dumbbell Pullover"
        ],
        "Close Grip Lat Pulldown": [
            "bodyweight": "Chin Up",
            "cables": "Straight Arm Pulldown"
        ],
        "Cable Seated Row": [
            "dumbbells": "Dumbbell Row",
            "barbell": "Barbell Row",
            "bands": "Band Row",
            "bodyweight": "Inverted Row"
        ],
        "Cable Row": [
            "dumbbells": "Dumbbell Row",
            "barbell": "Barbell Row",
            "bands": "Band Row"
        ],
        "Seated Row Machine": [
            "dumbbells": "Dumbbell Row",
            "cables": "Cable Seated Row",
            "barbell": "Barbell Row"
        ],
        "Straight Arm Pulldown": [
            "dumbbells": "Dumbbell Pullover",
            "bands": "Band Straight Arm Pulldown",
            "bodyweight": "Straight Arm Pull Up"
        ],
        "Cable Face Pull": [
            "dumbbells": "Reverse Fly",
            "bands": "Band Face Pull",
            "bodyweight": "Prone Y Raise"
        ],
        "Inverted Row": [
            "dumbbells": "Dumbbell Row",
            "cables": "Cable Row",
            "barbell": "Barbell Row"
        ],
        "Barbell Deadlift": [
            "dumbbells": "Dumbbell Deadlift",
            "kettlebell": "Kettlebell Deadlift",
            "bodyweight": "Single Leg Deadlift"
        ],
        "Dumbbell Deadlift": [
            "barbell": "Barbell Deadlift",
            "kettlebell": "Kettlebell Deadlift",
            "bodyweight": "Single Leg Deadlift"
        ],
        "Rack Pull": [
            "dumbbells": "Dumbbell Romanian Deadlift",
            "barbell": "Barbell Romanian Deadlift"
        ],
        "Good Morning": [
            "dumbbells": "Dumbbell Romanian Deadlift",
            "bands": "Band Good Morning",
            "bodyweight": "Superman"
        ],
        "Back Extension": [
            "bodyweight": "Superman",
            "dumbbells": "Dumbbell Romanian Deadlift"
        ],
        "Hyperextension": [
            "bodyweight": "Superman",
            "dumbbells": "Dumbbell Romanian Deadlift"
        ],
        "Superman": [
            "dumbbells": "Dumbbell Romanian Deadlift",
            "machines": "Back Extension Machine"
        ],
        "Dumbbell Shrug": [
            "barbell": "Barbell Shrug",
            "cables": "Cable Shrug",
            "bands": "Band Shrug"
        ],
        "Barbell Shrug": [
            "dumbbells": "Dumbbell Shrug",
            "cables": "Cable Shrug"
        ],
        
        // ============================================================================
        // LEG EXERCISES (30+ mappings)
        // ============================================================================
        
        "Barbell Squat": [
            "dumbbells": "Goblet Squat",
            "bodyweight": "Bodyweight Squat",
            "machines": "Leg Press",
            "kettlebell": "Kettlebell Goblet Squat",
            "bands": "Band Squat"
        ],
        "Front Squat": [
            "dumbbells": "Goblet Squat",
            "bodyweight": "Bodyweight Squat",
            "kettlebell": "Kettlebell Front Squat"
        ],
        "Goblet Squat": [
            "barbell": "Barbell Squat",
            "bodyweight": "Bodyweight Squat",
            "kettlebell": "Kettlebell Goblet Squat"
        ],
        "Bodyweight Squat": [
            "dumbbells": "Goblet Squat",
            "barbell": "Barbell Squat",
            "bands": "Band Squat"
        ],
        "Hack Squat": [
            "barbell": "Barbell Squat",
            "dumbbells": "Goblet Squat",
            "bodyweight": "Sissy Squat"
        ],
        "Leg Press": [
            "dumbbells": "Goblet Squat",
            "barbell": "Barbell Squat",
            "bodyweight": "Bulgarian Split Squat"
        ],
        "Bulgarian Split Squat": [
            "barbell": "Barbell Lunge",
            "bodyweight": "Reverse Lunge",
            "machines": "Leg Press"
        ],
        "Barbell Lunge": [
            "dumbbells": "Dumbbell Lunge",
            "bodyweight": "Reverse Lunge",
            "kettlebell": "Kettlebell Lunge"
        ],
        "Dumbbell Lunge": [
            "barbell": "Barbell Lunge",
            "bodyweight": "Reverse Lunge",
            "kettlebell": "Kettlebell Lunge"
        ],
        "Walking Lunge": [
            "dumbbells": "Dumbbell Lunge",
            "bodyweight": "Reverse Lunge",
            "barbell": "Barbell Lunge"
        ],
        "Reverse Lunge": [
            "dumbbells": "Dumbbell Lunge",
            "barbell": "Barbell Lunge",
            "kettlebell": "Kettlebell Lunge"
        ],
        "Step Up": [
            "bodyweight": "Box Step Up",
            "dumbbells": "Dumbbell Step Up",
            "barbell": "Barbell Step Up"
        ],
        "Barbell Romanian Deadlift": [
            "dumbbells": "Dumbbell Romanian Deadlift",
            "bodyweight": "Single Leg Deadlift",
            "kettlebell": "Kettlebell Romanian Deadlift",
            "bands": "Band Romanian Deadlift"
        ],
        "Dumbbell Romanian Deadlift": [
            "barbell": "Barbell Romanian Deadlift",
            "bodyweight": "Single Leg Deadlift",
            "kettlebell": "Kettlebell Romanian Deadlift"
        ],
        "Single Leg Deadlift": [
            "dumbbells": "Dumbbell Romanian Deadlift",
            "kettlebell": "Kettlebell Single Leg Deadlift"
        ],
        "Stiff Leg Deadlift": [
            "dumbbells": "Dumbbell Romanian Deadlift",
            "bodyweight": "Single Leg Deadlift"
        ],
        "Leg Extension": [
            "bodyweight": "Sissy Squat",
            "dumbbells": "Dumbbell Lunge",
            "bands": "Band Leg Extension"
        ],
        "Leg Curl": [
            "bodyweight": "Nordic Curl",
            "dumbbells": "Dumbbell Leg Curl",
            "bands": "Band Leg Curl"
        ],
        "Lying Leg Curl": [
            "bodyweight": "Nordic Curl",
            "dumbbells": "Dumbbell Leg Curl",
            "bands": "Band Leg Curl"
        ],
        "Seated Leg Curl": [
            "bodyweight": "Nordic Curl",
            "bands": "Band Leg Curl"
        ],
        "Nordic Curl": [
            "machines": "Leg Curl",
            "bands": "Band Leg Curl"
        ],
        "Glute Bridge": [
            "barbell": "Barbell Hip Thrust",
            "dumbbells": "Dumbbell Hip Thrust",
            "bands": "Band Glute Bridge"
        ],
        "Hip Thrust": [
            "bodyweight": "Glute Bridge",
            "bands": "Band Hip Thrust"
        ],
        "Barbell Hip Thrust": [
            "dumbbells": "Dumbbell Hip Thrust",
            "bodyweight": "Glute Bridge",
            "bands": "Band Hip Thrust"
        ],
        "Cable Kickback": [
            "bands": "Band Kickback",
            "bodyweight": "Donkey Kick"
        ],
        "Donkey Kick": [
            "cables": "Cable Kickback",
            "bands": "Band Kickback"
        ],
        "Calf Raise": [
            "dumbbells": "Dumbbell Calf Raise",
            "barbell": "Barbell Calf Raise",
            "bodyweight": "Bodyweight Calf Raise"
        ],
        "Standing Calf Raise": [
            "dumbbells": "Dumbbell Calf Raise",
            "bodyweight": "Single Leg Calf Raise"
        ],
        "Seated Calf Raise": [
            "dumbbells": "Dumbbell Seated Calf Raise",
            "bodyweight": "Bodyweight Calf Raise"
        ],
        "Leg Raise": [
            "bodyweight": "Lying Leg Raise",
            "cables": "Cable Leg Raise"
        ],
        "Wall Sit": [
            "dumbbells": "Goblet Squat Hold",
            "bands": "Band Squat Hold"
        ],
        
        // ============================================================================
        // SHOULDER EXERCISES (20+ mappings)
        // ============================================================================
        
        "Barbell Overhead Press": [
            "dumbbells": "Dumbbell Shoulder Press",
            "bodyweight": "Pike Push Up",
            "machines": "Machine Shoulder Press",
            "kettlebell": "Kettlebell Press",
            "bands": "Band Shoulder Press"
        ],
        "Dumbbell Shoulder Press": [
            "barbell": "Barbell Overhead Press",
            "bodyweight": "Pike Push Up",
            "bands": "Band Shoulder Press",
            "kettlebell": "Kettlebell Press"
        ],
        "Arnold Press": [
            "barbell": "Barbell Overhead Press",
            "bodyweight": "Pike Push Up",
            "cables": "Cable Shoulder Press"
        ],
        "Machine Shoulder Press": [
            "dumbbells": "Dumbbell Shoulder Press",
            "barbell": "Barbell Overhead Press",
            "bodyweight": "Pike Push Up"
        ],
        "Push Press": [
            "dumbbells": "Dumbbell Push Press",
            "bodyweight": "Pike Push Up"
        ],
        "Pike Push Up": [
            "dumbbells": "Dumbbell Shoulder Press",
            "barbell": "Barbell Overhead Press"
        ],
        "Handstand Push Up": [
            "dumbbells": "Dumbbell Shoulder Press",
            "bodyweight": "Pike Push Up"
        ],
        "Dumbbell Lateral Raise": [
            "cables": "Cable Lateral Raise",
            "bands": "Band Lateral Raise",
            "bodyweight": "Arm Circles"
        ],
        "Cable Lateral Raise": [
            "dumbbells": "Dumbbell Lateral Raise",
            "bands": "Band Lateral Raise"
        ],
        "Machine Lateral Raise": [
            "dumbbells": "Dumbbell Lateral Raise",
            "cables": "Cable Lateral Raise"
        ],
        "Dumbbell Front Raise": [
            "cables": "Cable Front Raise",
            "bands": "Band Front Raise",
            "barbell": "Barbell Front Raise"
        ],
        "Cable Front Raise": [
            "dumbbells": "Dumbbell Front Raise",
            "bands": "Band Front Raise"
        ],
        "Barbell Front Raise": [
            "dumbbells": "Dumbbell Front Raise",
            "cables": "Cable Front Raise"
        ],
        "Reverse Fly": [
            "cables": "Cable Face Pull",
            "bands": "Band Reverse Fly",
            "bodyweight": "Prone Y Raise"
        ],
        "Rear Delt Fly": [
            "cables": "Cable Face Pull",
            "bands": "Band Reverse Fly",
            "dumbbells": "Reverse Fly"
        ],
        "Face Pull": [
            "dumbbells": "Reverse Fly",
            "bands": "Band Face Pull"
        ],
        "Upright Row": [
            "dumbbells": "Dumbbell Upright Row",
            "cables": "Cable Upright Row",
            "bands": "Band Upright Row"
        ],
        "Dumbbell Upright Row": [
            "barbell": "Barbell Upright Row",
            "cables": "Cable Upright Row"
        ],
        
        // ============================================================================
        // BICEPS EXERCISES (15+ mappings)
        // ============================================================================
        
        "Barbell Curl": [
            "dumbbells": "Dumbbell Biceps Curl",
            "cables": "Cable Curl",
            "bands": "Band Curl",
            "bodyweight": "Chin Up"
        ],
        "EZ Bar Curl": [
            "dumbbells": "Dumbbell Biceps Curl",
            "cables": "Cable Curl",
            "barbell": "Barbell Curl"
        ],
        "Dumbbell Biceps Curl": [
            "barbell": "Barbell Curl",
            "cables": "Cable Curl",
            "bands": "Band Curl"
        ],
        "Dumbbell Curl": [
            "barbell": "Barbell Curl",
            "cables": "Cable Curl",
            "bands": "Band Curl"
        ],
        "Hammer Curl": [
            "cables": "Cable Hammer Curl",
            "bands": "Band Hammer Curl",
            "barbell": "Reverse Curl"
        ],
        "Dumbbell Hammer Curl": [
            "cables": "Cable Hammer Curl",
            "bands": "Band Hammer Curl"
        ],
        "Preacher Curl": [
            "dumbbells": "Concentration Curl",
            "cables": "Cable Preacher Curl"
        ],
        "Concentration Curl": [
            "cables": "Cable Curl",
            "bands": "Band Curl"
        ],
        "Incline Curl": [
            "cables": "Cable Curl",
            "bodyweight": "Chin Up"
        ],
        "Dumbbell Incline Curl": [
            "cables": "Cable Curl",
            "barbell": "Barbell Curl"
        ],
        "Spider Curl": [
            "cables": "Cable Curl",
            "dumbbells": "Concentration Curl"
        ],
        "Cable Curl": [
            "dumbbells": "Dumbbell Biceps Curl",
            "barbell": "Barbell Curl",
            "bands": "Band Curl"
        ],
        "Reverse Curl": [
            "dumbbells": "Dumbbell Reverse Curl",
            "cables": "Cable Reverse Curl"
        ],
        "Zottman Curl": [
            "cables": "Cable Curl",
            "barbell": "Reverse Curl"
        ],
        
        // ============================================================================
        // TRICEPS EXERCISES (15+ mappings)
        // ============================================================================
        
        "Cable Triceps Pushdown": [
            "dumbbells": "Dumbbell Overhead Triceps Extension",
            "bodyweight": "Diamond Push Up",
            "bands": "Band Triceps Pushdown"
        ],
        "Triceps Pushdown": [
            "dumbbells": "Dumbbell Kickback",
            "bodyweight": "Diamond Push Up",
            "bands": "Band Triceps Pushdown"
        ],
        "Rope Pushdown": [
            "dumbbells": "Dumbbell Kickback",
            "bodyweight": "Diamond Push Up"
        ],
        "Skull Crusher": [
            "dumbbells": "Dumbbell Skull Crusher",
            "cables": "Cable Overhead Triceps Extension",
            "bodyweight": "Close Grip Push Up"
        ],
        "Dumbbell Skull Crusher": [
            "barbell": "Skull Crusher",
            "cables": "Cable Overhead Triceps Extension",
            "bodyweight": "Close Grip Push Up"
        ],
        "Dumbbell Overhead Triceps Extension": [
            "cables": "Cable Overhead Triceps Extension",
            "bodyweight": "Diamond Push Up",
            "bands": "Band Triceps Extension"
        ],
        "Cable Overhead Triceps Extension": [
            "dumbbells": "Dumbbell Overhead Triceps Extension",
            "bodyweight": "Diamond Push Up"
        ],
        "Triceps Dip": [
            "bodyweight": "Bench Dip",
            "cables": "Cable Triceps Pushdown",
            "machines": "Dip Machine"
        ],
        "Bench Dip": [
            "cables": "Cable Triceps Pushdown",
            "dumbbells": "Dumbbell Kickback"
        ],
        "Dumbbell Kickback": [
            "cables": "Cable Kickback",
            "bands": "Band Kickback"
        ],
        "Cable Kickback": [
            "dumbbells": "Dumbbell Kickback",
            "bands": "Band Kickback"
        ],
        "Close Grip Push Up": [
            "dumbbells": "Close Grip Dumbbell Press",
            "barbell": "Close Grip Bench Press",
            "cables": "Cable Triceps Pushdown"
        ],
        "JM Press": [
            "dumbbells": "Dumbbell Skull Crusher",
            "cables": "Cable Triceps Pushdown"
        ],
        
        // ============================================================================
        // CORE EXERCISES (20+ mappings)
        // ============================================================================
        
        "Plank": [
            "bodyweight": "Dead Bug",
            "dumbbells": "Weighted Plank"
        ],
        "Side Plank": [
            "bodyweight": "Side Crunch",
            "cables": "Cable Side Bend"
        ],
        "Crunch": [
            "cables": "Cable Crunch",
            "dumbbells": "Weighted Crunch"
        ],
        "Cable Crunch": [
            "bodyweight": "Crunch",
            "dumbbells": "Weighted Crunch",
            "bands": "Band Crunch"
        ],
        "Weighted Crunch": [
            "cables": "Cable Crunch",
            "bodyweight": "Crunch"
        ],
        "Bicycle Crunch": [
            "bodyweight": "Russian Twist",
            "cables": "Cable Woodchop"
        ],
        "Russian Twist": [
            "dumbbells": "Dumbbell Russian Twist",
            "cables": "Cable Woodchop",
            "bodyweight": "Bicycle Crunch"
        ],
        "Leg Raise": [
            "bodyweight": "Lying Leg Raise",
            "cables": "Cable Leg Raise"
        ],
        "Hanging Leg Raise": [
            "bodyweight": "Lying Leg Raise",
            "cables": "Cable Leg Raise"
        ],
        "Lying Leg Raise": [
            "cables": "Cable Leg Raise",
            "bodyweight": "Reverse Crunch"
        ],
        "Reverse Crunch": [
            "cables": "Cable Crunch",
            "bodyweight": "Lying Leg Raise"
        ],
        "Mountain Climber": [
            "bodyweight": "High Knees",
            "cables": "Cable Crunch"
        ],
        "Dead Bug": [
            "bodyweight": "Bird Dog",
            "dumbbells": "Weighted Dead Bug"
        ],
        "Bird Dog": [
            "bodyweight": "Dead Bug",
            "bands": "Band Bird Dog"
        ],
        "Ab Rollout": [
            "bodyweight": "Plank",
            "cables": "Cable Crunch"
        ],
        "Woodchop": [
            "dumbbells": "Dumbbell Woodchop",
            "bands": "Band Woodchop"
        ],
        "Cable Woodchop": [
            "dumbbells": "Dumbbell Woodchop",
            "bands": "Band Woodchop"
        ],
        "Pallof Press": [
            "bands": "Band Pallof Press",
            "bodyweight": "Plank"
        ],
        "Cable Pallof Press": [
            "bands": "Band Pallof Press",
            "bodyweight": "Side Plank"
        ],
        
        // ============================================================================
        // COMPOUND / FULL BODY EXERCISES (10+ mappings)
        // ============================================================================
        
        "Burpee": [
            "bodyweight": "Squat Thrust",
            "dumbbells": "Dumbbell Thruster"
        ],
        "Thruster": [
            "dumbbells": "Dumbbell Thruster",
            "kettlebell": "Kettlebell Thruster",
            "bodyweight": "Jump Squat"
        ],
        "Dumbbell Thruster": [
            "barbell": "Barbell Thruster",
            "kettlebell": "Kettlebell Thruster"
        ],
        "Clean and Press": [
            "dumbbells": "Dumbbell Clean and Press",
            "kettlebell": "Kettlebell Clean and Press"
        ],
        "Kettlebell Swing": [
            "dumbbells": "Dumbbell Swing",
            "bands": "Band Pull Through",
            "cables": "Cable Pull Through"
        ],
        "Turkish Get Up": [
            "dumbbells": "Dumbbell Turkish Get Up",
            "bodyweight": "Bodyweight Get Up"
        ],
        "Farmer Walk": [
            "dumbbells": "Dumbbell Farmer Walk",
            "kettlebell": "Kettlebell Farmer Walk",
            "barbell": "Trap Bar Farmer Walk"
        ],
        "Sled Push": [
            "bodyweight": "Bear Crawl",
            "dumbbells": "Walking Lunge"
        ],
        "Battle Ropes": [
            "bodyweight": "Mountain Climber",
            "kettlebell": "Kettlebell Swing"
        ],
        "Box Jump": [
            "bodyweight": "Jump Squat",
            "dumbbells": "Dumbbell Jump Squat"
        ],
        "Jump Squat": [
            "bodyweight": "Bodyweight Squat",
            "dumbbells": "Goblet Squat"
        ],
        
        // ============================================================================
        // FOREARM EXERCISES (5+ mappings)
        // ============================================================================
        
        "Wrist Curl": [
            "dumbbells": "Dumbbell Wrist Curl",
            "cables": "Cable Wrist Curl"
        ],
        "Reverse Wrist Curl": [
            "dumbbells": "Dumbbell Reverse Wrist Curl",
            "cables": "Cable Reverse Wrist Curl"
        ],
        "Farmer Walk": [
            "dumbbells": "Dumbbell Farmer Walk",
            "kettlebell": "Kettlebell Carry"
        ],
        "Dead Hang": [
            "bodyweight": "Grip Squeeze",
            "dumbbells": "Farmer Walk"
        ]
    ]
    
    // MARK: - Generate Custom Program
    
    /// Generate a customized program based on user preferences
    func generateCustomProgram(from request: ProgramCustomizationRequest) async -> UserCustomProgram? {
        isGenerating = true
        error = nil
        
        // Get base program - first try active, then fetch from server
        let baseProgram: FullCloudProgram
        if let active = programService.activeProgramDetails {
            baseProgram = active
        } else if let fetched = await fetchBaseProgram(id: request.baseProgramId) {
            baseProgram = fetched
        } else {
            error = "Could not load base program"
            isGenerating = false
            return nil
        }
        
        AppLogger.debug("🎨 Generating custom program from: \(baseProgram.program.name)", category: .workout)
        AppLogger.debug("   Equipment: \(request.availableEquipment)", category: .workout)
        AppLogger.debug("   Days/week: \(request.daysPerWeek)", category: .workout)
        AppLogger.debug("   Max duration: \(request.maxWorkoutMinutes) min", category: .workout)
        
        // Step 1: Adjust schedule based on days per week
        let adjustedDays = adjustSchedule(
            baseDays: baseProgram.days,
            targetDaysPerWeek: request.daysPerWeek,
            totalDuration: baseProgram.program.durationDays
        )
        
        // Step 2: Swap exercises based on equipment
        let equipmentAdjustedDays = adjustedDays.map { day in
            adjustExercisesForEquipment(
                day: day,
                availableEquipment: request.availableEquipment,
                avoidExercises: Set(request.avoidExercises)
            )
        }
        
        // Step 3: Apply focus adjustments if any
        let focusAdjustedDays = applyFocusAdjustments(
            days: equipmentAdjustedDays,
            adjustments: request.focusAdjustments
        )
        
        // Step 4: Trim exercises if needed for time constraints
        let timeAdjustedDays = adjustForTime(
            days: focusAdjustedDays,
            maxMinutes: request.maxWorkoutMinutes
        )
        
        // Step 5: Generate custom program object
        let customProgram = UserCustomProgram(
            id: UUID().uuidString,
            userId: supabase.currentUser?.id.uuidString ?? "local",
            baseProgramId: request.baseProgramId,
            customName: generateCustomName(baseName: request.baseProgramName, request: request),
            description: generateCustomDescription(baseProgram: baseProgram.program, request: request),
            durationDays: baseProgram.program.durationDays,
            workoutsPerWeek: request.daysPerWeek,
            avgWorkoutDurationMin: request.maxWorkoutMinutes,
            equipment: Array(request.availableEquipment),
            icon: baseProgram.program.icon,
            color: baseProgram.program.color,
            days: timeAdjustedDays,
            createdAt: Date(),
            customizationSummary: generateSummary(request: request)
        )
        
        generatedProgram = customProgram
        isGenerating = false
        
        AppLogger.info("✅ Generated custom program: \(customProgram.customName)", category: .workout)
        AppLogger.debug("   \(customProgram.days.count) days, \(customProgram.days.filter { !$0.isRestDay }.count) workout days", category: .workout)
        
        return customProgram
    }
    
    // MARK: - Schedule Adjustment
    
    private func adjustSchedule(baseDays: [FullProgramDay], targetDaysPerWeek: Int, totalDuration: Int) -> [FullProgramDay] {
        let workoutDays = baseDays.filter { !$0.day.isRestDay }
        let restDays = baseDays.filter { $0.day.isRestDay }
        
        // If same days per week, return as-is
        let currentWorkoutsPerWeek = workoutDays.count / (totalDuration / 7)
        if currentWorkoutsPerWeek == targetDaysPerWeek {
            return baseDays
        }
        
        // For now, return as-is (advanced scheduling would redistribute days)
        // In a full implementation, this would intelligently merge or split days
        return baseDays
    }
    
    // MARK: - Equipment-Based Exercise Swapping
    
    private func adjustExercisesForEquipment(
        day: FullProgramDay,
        availableEquipment: Set<String>,
        avoidExercises: Set<String>
    ) -> CustomProgramDay {
        
        // If rest day, return simple rest day
        if day.day.isRestDay {
            return CustomProgramDay(
                id: day.day.id,
                dayNumber: day.day.dayNumber,
                name: day.day.name,
                description: day.day.description ?? "Rest and recovery",
                focusAreas: day.day.focusAreas,
                isRestDay: true,
                exercises: [],
                intensity: day.day.intensity,
                estimatedDurationMin: 0
            )
        }
        
        let lowercaseEquipment = Set(availableEquipment.map { $0.lowercased() })
        
        // Get exercises for this day (from pre-defined or generate)
        let baseExercises = getExercisesForDay(day)
        
        // Swap exercises based on equipment
        let adjustedExercises: [CustomProgramExercise] = baseExercises.enumerated().map { index, exercise in
            let exerciseName = exercise.exerciseName
            
            // Check if exercise should be avoided
            if avoidExercises.contains(exerciseName) {
                if let alternative = findAlternative(for: exerciseName, with: lowercaseEquipment) {
                    return createCustomExercise(from: exercise, newName: alternative, order: index + 1)
                }
            }
            
            // Check if we have the equipment for this exercise
            let exerciseEquipment = getRequiredEquipment(for: exerciseName).lowercased()
            
            if !lowercaseEquipment.contains(exerciseEquipment) && exerciseEquipment != "bodyweight" {
                // Need to swap this exercise
                if let alternative = findAlternative(for: exerciseName, with: lowercaseEquipment) {
                    return createCustomExercise(from: exercise, newName: alternative, order: index + 1)
                }
            }
            
            // Keep original exercise
            return createCustomExercise(from: exercise, newName: exerciseName, order: index + 1)
        }
        
        return CustomProgramDay(
            id: day.day.id,
            dayNumber: day.day.dayNumber,
            name: day.day.name,
            description: day.day.description ?? "",
            focusAreas: day.day.focusAreas,
            isRestDay: false,
            exercises: adjustedExercises,
            intensity: day.day.intensity,
            estimatedDurationMin: day.day.estimatedDurationMin
        )
    }
    
    private func findAlternative(for exercise: String, with availableEquipment: Set<String>) -> String? {
        // Try direct lookup first
        if let alternatives = exerciseAlternatives[exercise] {
            if let alt = findBestMatch(from: alternatives, with: availableEquipment) {
                return alt
            }
        }
        
        // Try case-insensitive matching
        let lowercaseExercise = exercise.lowercased()
        for (key, alternatives) in exerciseAlternatives {
            if key.lowercased() == lowercaseExercise {
                if let alt = findBestMatch(from: alternatives, with: availableEquipment) {
                    return alt
                }
            }
        }
        
        // Try partial matching (for exercises with slight name variations)
        let exerciseWords = Set(exercise.lowercased().split(separator: " ").map { String($0) })
        for (key, alternatives) in exerciseAlternatives {
            let keyWords = Set(key.lowercased().split(separator: " ").map { String($0) })
            // If 70% of words match, consider it a match
            let intersection = exerciseWords.intersection(keyWords)
            if intersection.count >= Int(Double(min(exerciseWords.count, keyWords.count)) * 0.7) {
                if let alt = findBestMatch(from: alternatives, with: availableEquipment) {
                    return alt
                }
            }
        }
        
        // Try smart equipment-based fallback
        return findSmartFallback(for: exercise, with: availableEquipment)
    }
    
    private func findBestMatch(from alternatives: [String: String], with availableEquipment: Set<String>) -> String? {
        // Priority order for equipment (most versatile first)
        let priorityOrder = ["dumbbells", "bodyweight", "cables", "bands", "kettlebell", "machines", "barbell"]
        
        for equipment in priorityOrder {
            if availableEquipment.contains(equipment), let alt = alternatives[equipment] {
                return alt
            }
        }
        
        // Return first available alternative
        for (equipment, alternative) in alternatives {
            if availableEquipment.contains(equipment) {
                return alternative
            }
        }
        
        return nil
    }
    
    /// Smart fallback when no direct mapping exists
    private func findSmartFallback(for exercise: String, with availableEquipment: Set<String>) -> String? {
        let lowercased = exercise.lowercased()
        
        // Determine the muscle group from exercise name
        let muscleGroup = detectMuscleGroup(from: lowercased)
        
        // Find alternative exercises for same muscle group with available equipment
        for (mappedExercise, alternatives) in exerciseAlternatives {
            let mappedMuscle = detectMuscleGroup(from: mappedExercise.lowercased())
            
            if mappedMuscle == muscleGroup {
                // This exercise targets the same muscle - check if we can use any alternatives
                for (equipment, alternative) in alternatives {
                    if availableEquipment.contains(equipment) {
                        return alternative
                    }
                }
            }
        }
        
        return nil
    }
    
    private func detectMuscleGroup(from exerciseName: String) -> String {
        // Chest detection
        if exerciseName.contains("bench") || exerciseName.contains("chest") || 
           exerciseName.contains("fly") || exerciseName.contains("pec") ||
           exerciseName.contains("push up") || exerciseName.contains("pushup") {
            return "chest"
        }
        
        // Back detection
        if exerciseName.contains("row") || exerciseName.contains("pull") || 
           exerciseName.contains("lat") || exerciseName.contains("back") ||
           exerciseName.contains("deadlift") {
            return "back"
        }
        
        // Shoulders detection
        if exerciseName.contains("shoulder") || exerciseName.contains("delt") || 
           exerciseName.contains("overhead") || exerciseName.contains("lateral") ||
           exerciseName.contains("front raise") || exerciseName.contains("press") && exerciseName.contains("military") {
            return "shoulders"
        }
        
        // Biceps detection
        if exerciseName.contains("curl") && !exerciseName.contains("leg") && !exerciseName.contains("ham") {
            return "biceps"
        }
        
        // Triceps detection
        if exerciseName.contains("tricep") || exerciseName.contains("pushdown") || 
           exerciseName.contains("skull") || exerciseName.contains("kickback") ||
           exerciseName.contains("dip") || exerciseName.contains("close grip") {
            return "triceps"
        }
        
        // Quads detection
        if exerciseName.contains("squat") || exerciseName.contains("leg press") || 
           exerciseName.contains("leg extension") || exerciseName.contains("lunge") {
            return "quads"
        }
        
        // Hamstrings detection
        if exerciseName.contains("ham") || exerciseName.contains("leg curl") || 
           exerciseName.contains("romanian") || exerciseName.contains("stiff leg") {
            return "hamstrings"
        }
        
        // Glutes detection
        if exerciseName.contains("glute") || exerciseName.contains("hip thrust") || 
           exerciseName.contains("bridge") || exerciseName.contains("kickback") {
            return "glutes"
        }
        
        // Core detection
        if exerciseName.contains("crunch") || exerciseName.contains("plank") || 
           exerciseName.contains("ab") || exerciseName.contains("core") ||
           exerciseName.contains("twist") || exerciseName.contains("leg raise") {
            return "core"
        }
        
        return "compound"
    }
    
    private func getRequiredEquipment(for exercise: String) -> String {
        // First try the database
        if let exerciseData = ExerciseDataProvider.shared.exercises.first(where: { $0.name == exercise }) {
            return exerciseData.equipment
        }
        
        // Smart detection from exercise name
        let lowercased = exercise.lowercased()
        
        // Barbell exercises
        if lowercased.contains("barbell") || lowercased.contains("ez bar") || lowercased.contains("ez-bar") {
            return "Barbell"
        }
        
        // Dumbbell exercises
        if lowercased.contains("dumbbell") || lowercased.contains("db ") {
            return "Dumbbells"
        }
        
        // Kettlebell exercises
        if lowercased.contains("kettlebell") || lowercased.contains("kb ") {
            return "Kettlebell"
        }
        
        // Cable exercises
        if lowercased.contains("cable") || lowercased.contains("pulley") {
            return "Cables"
        }
        
        // Machine exercises
        if lowercased.contains("machine") || lowercased.contains("smith") || 
           lowercased.contains("leg press") || lowercased.contains("leg curl") ||
           lowercased.contains("leg extension") || lowercased.contains("pec deck") ||
           lowercased.contains("hack squat") {
            return "Machines"
        }
        
        // Band exercises
        if lowercased.contains("band") || lowercased.contains("resistance") {
            return "Bands"
        }
        
        // Bodyweight indicators
        if lowercased.contains("push up") || lowercased.contains("pushup") ||
           lowercased.contains("pull up") || lowercased.contains("pullup") ||
           lowercased.contains("chin up") || lowercased.contains("chinup") ||
           lowercased.contains("dip") || lowercased.contains("plank") ||
           lowercased.contains("crunch") || lowercased.contains("sit up") ||
           lowercased.contains("burpee") || lowercased.contains("lunge") ||
           lowercased.contains("squat") && !lowercased.contains("goblet") ||
           lowercased.contains("bodyweight") {
            return "Bodyweight"
        }
        
        return "Bodyweight"
    }
    
    private func getExercisesForDay(_ day: FullProgramDay) -> [CloudProgramExercise] {
        // If day has pre-defined exercises, use them
        if !day.exercises.isEmpty {
            return day.exercises.map { $0.exercise }
        }
        
        // Otherwise generate based on focus areas
        return generateExercisesForFocus(day.day.focusAreas, count: day.day.exerciseCount)
    }
    
    private func generateExercisesForFocus(_ focusAreas: [String], count: Int) -> [CloudProgramExercise] {
        // Simple generation based on focus areas
        let allExercises = ExerciseDataProvider.shared.exercises
        var selected: [CloudProgramExercise] = []
        var usedNames: Set<String> = []
        
        for (index, focus) in focusAreas.enumerated() {
            let matching = allExercises.filter { ex in
                !usedNames.contains(ex.name) &&
                (ex.category.lowercased().contains(focus.lowercased()) ||
                 ex.primaryMuscle.lowercased().contains(focus.lowercased()))
            }
            
            if let exercise = matching.randomElement() {
                usedNames.insert(exercise.name)
                selected.append(CloudProgramExercise(
                    id: UUID().uuidString,
                    programDayId: "",
                    exerciseName: exercise.name,
                    exerciseId: nil,
                    exerciseOrder: index + 1,
                    supersetGroup: nil,
                    sets: 3,
                    repsMin: 8,
                    repsMax: 12,
                    repsType: "reps",
                    restSeconds: 60,
                    tempo: nil,
                    notes: nil,
                    isWarmup: false,
                    isOptional: false,
                    targetRpe: nil
                ))
            }
        }
        
        // Fill remaining slots
        while selected.count < count {
            let matching = allExercises.filter { !usedNames.contains($0.name) }
            if let exercise = matching.randomElement() {
                usedNames.insert(exercise.name)
                selected.append(CloudProgramExercise(
                    id: UUID().uuidString,
                    programDayId: "",
                    exerciseName: exercise.name,
                    exerciseId: nil,
                    exerciseOrder: selected.count + 1,
                    supersetGroup: nil,
                    sets: 3,
                    repsMin: 10,
                    repsMax: 12,
                    repsType: "reps",
                    restSeconds: 60,
                    tempo: nil,
                    notes: nil,
                    isWarmup: false,
                    isOptional: false,
                    targetRpe: nil
                ))
            } else {
                break
            }
        }
        
        return selected
    }
    
    private func createCustomExercise(from base: CloudProgramExercise, newName: String, order: Int) -> CustomProgramExercise {
        // Find substitute options for the new exercise
        let substitutes = exerciseAlternatives[newName]?.values.map { $0 } ?? []
        
        return CustomProgramExercise(
            id: UUID().uuidString,
            exerciseName: newName,
            exerciseOrder: order,
            sets: base.sets,
            repsMin: base.repsMin,
            repsMax: base.repsMax,
            repsType: base.repsType,
            restSeconds: base.restSeconds,
            notes: base.notes,
            substitutes: Array(substitutes.prefix(3))
        )
    }
    
    // MARK: - Focus Adjustments
    
    private func applyFocusAdjustments(days: [CustomProgramDay], adjustments: [String: Double]) -> [CustomProgramDay] {
        // For now, return as-is
        // Advanced implementation would add/remove exercises based on focus multipliers
        return days
    }
    
    // MARK: - Time Adjustments
    
    private func adjustForTime(days: [CustomProgramDay], maxMinutes: Int) -> [CustomProgramDay] {
        return days.map { day in
            if day.isRestDay { return day }
            
            // Estimate ~4 minutes per exercise (including rest)
            let maxExercises = maxMinutes / 4
            
            if day.exercises.count <= maxExercises {
                return day
            }
            
            // Trim exercises to fit time
            let trimmedExercises = Array(day.exercises.prefix(maxExercises))
            
            return CustomProgramDay(
                id: day.id,
                dayNumber: day.dayNumber,
                name: day.name,
                description: day.description,
                focusAreas: day.focusAreas,
                isRestDay: day.isRestDay,
                exercises: trimmedExercises,
                intensity: day.intensity,
                estimatedDurationMin: maxMinutes
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func generateCustomName(baseName: String, request: ProgramCustomizationRequest) -> String {
        var suffix = ""
        
        if !request.availableEquipment.contains("Barbell") && !request.availableEquipment.contains("barbell") {
            suffix = " (Home)"
        } else if request.daysPerWeek <= 3 {
            suffix = " (Quick)"
        }
        
        return "My \(baseName)\(suffix)"
    }
    
    private func generateCustomDescription(baseProgram: CloudProgram, request: ProgramCustomizationRequest) -> String {
        return "Customized version of \(baseProgram.name). \(request.daysPerWeek) days per week, \(request.maxWorkoutMinutes) minute workouts."
    }
    
    private func generateSummary(request: ProgramCustomizationRequest) -> String {
        var parts: [String] = []
        
        if !request.availableEquipment.contains("Barbell") {
            parts.append("No barbell")
        }
        if request.daysPerWeek <= 3 {
            parts.append("\(request.daysPerWeek) days/week")
        }
        if request.maxWorkoutMinutes <= 45 {
            parts.append("\(request.maxWorkoutMinutes) min workouts")
        }
        
        return parts.isEmpty ? "Lightly customized" : parts.joined(separator: ", ")
    }
    
    private func fetchBaseProgram(id: String) async -> FullCloudProgram? {
        // Try to get from cached programs first
        if let program = programService.allPrograms.first(where: { $0.id == id }) {
            // Would need to fetch full details here
            return nil
        }
        return nil
    }
    
    // MARK: - Save Custom Program
    
    /// Save the custom program to Supabase for persistence
    func saveCustomProgram(_ program: UserCustomProgram) async -> Bool {
        guard let userId = supabase.currentUser?.id else {
            error = "Not logged in"
            return false
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            struct CustomProgramInsert: Encodable {
                let id: String
                let user_id: String
                let base_program_id: String
                let custom_name: String
                let description: String
                let duration_days: Int
                let workouts_per_week: Int
                let avg_workout_duration_min: Int
                let equipment: [String]
                let icon: String
                let color: String
                let days_json: String // Store days as JSON string
                let customization_summary: String
            }
            
            let daysJson = try String(data: encoder.encode(program.days), encoding: .utf8) ?? "[]"
            
            let insert = CustomProgramInsert(
                id: program.id,
                user_id: userId.uuidString,
                base_program_id: program.baseProgramId,
                custom_name: program.customName,
                description: program.description,
                duration_days: program.durationDays,
                workouts_per_week: program.workoutsPerWeek,
                avg_workout_duration_min: program.avgWorkoutDurationMin,
                equipment: program.equipment,
                icon: program.icon,
                color: program.color,
                days_json: daysJson,
                customization_summary: program.customizationSummary
            )
            
            try await supabase.supabaseClient
                .from("user_custom_programs")
                .insert(insert)
                .execute()
            
            AppLogger.info("✅ Custom program saved to cloud", category: .workout)
            return true
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
            AppLogger.error("❌ Error saving custom program: \(error)", category: .workout)
            return false
        }
    }
}

