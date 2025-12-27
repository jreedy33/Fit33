import Foundation

// MARK: - Smart Warm-Up Generator
// Generates personalized warm-up routines based on today's workout

class SmartWarmUpGenerator {
    static let shared = SmartWarmUpGenerator()
    
    private init() {}
    
    // MARK: - Warm-Up Exercise Model
    
    struct WarmUpExercise: Identifiable {
        let id = UUID()
        let name: String
        let duration: Int // seconds
        let targetMuscles: [String]
        let type: WarmUpType
        let instructions: String
        let icon: String
        
        enum WarmUpType: String {
            case cardio = "Cardio"
            case dynamicStretch = "Dynamic Stretch"
            case activation = "Activation"
            case mobility = "Mobility"
            
            var color: String {
                switch self {
                case .cardio: return "red"
                case .dynamicStretch: return "orange"
                case .activation: return "green"
                case .mobility: return "blue"
                }
            }
        }
    }
    
    // MARK: - Warm-Up Routine
    
    struct WarmUpRoutine {
        let exercises: [WarmUpExercise]
        let totalDuration: Int // seconds
        let targetAreas: [String]
        let intensityLevel: String
        
        var formattedDuration: String {
            let minutes = totalDuration / 60
            return "\(minutes) min"
        }
    }
    
    // MARK: - Generate Warm-Up
    
    /// Generate a smart warm-up based on the planned workout
    func generateWarmUp(
        targetMuscles: [String],
        workoutIntensity: WorkoutIntensity = .moderate,
        userLevel: String = "Intermediate",
        duration: Int = 5 // minutes
    ) -> WarmUpRoutine {
        
        var warmUpExercises: [WarmUpExercise] = []
        let targetDuration = duration * 60 // convert to seconds
        var currentDuration = 0
        
        // 1. Always start with light cardio (30-60 seconds)
        let cardioExercise = selectCardioWarmUp(intensity: workoutIntensity)
        warmUpExercises.append(cardioExercise)
        currentDuration += cardioExercise.duration
        
        // 2. Add dynamic stretches for target muscles
        let dynamicStretches = selectDynamicStretches(for: targetMuscles)
        for stretch in dynamicStretches.prefix(3) {
            if currentDuration + stretch.duration <= targetDuration {
                warmUpExercises.append(stretch)
                currentDuration += stretch.duration
            }
        }
        
        // 3. Add activation exercises
        let activationExercises = selectActivationExercises(for: targetMuscles, level: userLevel)
        for activation in activationExercises.prefix(2) {
            if currentDuration + activation.duration <= targetDuration {
                warmUpExercises.append(activation)
                currentDuration += activation.duration
            }
        }
        
        // 4. Add mobility work if time allows
        if currentDuration < targetDuration - 30 {
            let mobility = selectMobilityExercises(for: targetMuscles)
            for mob in mobility.prefix(1) {
                if currentDuration + mob.duration <= targetDuration {
                    warmUpExercises.append(mob)
                    currentDuration += mob.duration
                }
            }
        }
        
        return WarmUpRoutine(
            exercises: warmUpExercises,
            totalDuration: currentDuration,
            targetAreas: targetMuscles,
            intensityLevel: workoutIntensity.rawValue
        )
    }
    
    // MARK: - Exercise Selection
    
    private func selectCardioWarmUp(intensity: WorkoutIntensity) -> WarmUpExercise {
        let cardioOptions: [WarmUpExercise] = [
            WarmUpExercise(
                name: "Jumping Jacks",
                duration: 45,
                targetMuscles: ["Full Body"],
                type: .cardio,
                instructions: "Perform jumping jacks at a moderate pace to elevate heart rate",
                icon: "figure.jumprope"
            ),
            WarmUpExercise(
                name: "High Knees",
                duration: 30,
                targetMuscles: ["Legs", "Core"],
                type: .cardio,
                instructions: "Run in place, bringing knees up to hip level",
                icon: "figure.run"
            ),
            WarmUpExercise(
                name: "Arm Circles",
                duration: 30,
                targetMuscles: ["Shoulders"],
                type: .cardio,
                instructions: "Make large circles with your arms, forward then backward",
                icon: "arrow.trianglehead.2.counterclockwise.rotate.90"
            ),
            WarmUpExercise(
                name: "March in Place",
                duration: 45,
                targetMuscles: ["Legs"],
                type: .cardio,
                instructions: "March in place with arm swings",
                icon: "figure.walk"
            )
        ]
        
        return intensity == .high 
            ? cardioOptions.first { $0.name == "High Knees" } ?? cardioOptions[0]
            : cardioOptions.randomElement() ?? cardioOptions[0]
    }
    
    private func selectDynamicStretches(for muscles: [String]) -> [WarmUpExercise] {
        var stretches: [WarmUpExercise] = []
        
        let musclesLower = muscles.map { $0.lowercased() }
        
        // Leg stretches
        if musclesLower.contains(where: { ["legs", "quads", "hamstrings", "glutes", "calves"].contains($0) }) {
            stretches.append(WarmUpExercise(
                name: "Leg Swings",
                duration: 30,
                targetMuscles: ["Hip Flexors", "Hamstrings"],
                type: .dynamicStretch,
                instructions: "Swing leg forward and back, 10 each side",
                icon: "figure.walk"
            ))
            stretches.append(WarmUpExercise(
                name: "Walking Lunges",
                duration: 45,
                targetMuscles: ["Quads", "Glutes", "Hip Flexors"],
                type: .dynamicStretch,
                instructions: "Take 10 walking lunges, alternating legs",
                icon: "figure.walk"
            ))
            stretches.append(WarmUpExercise(
                name: "Bodyweight Squats",
                duration: 30,
                targetMuscles: ["Quads", "Glutes"],
                type: .dynamicStretch,
                instructions: "Perform 10 slow, controlled bodyweight squats",
                icon: "figure.strengthtraining.traditional"
            ))
        }
        
        // Upper body stretches
        if musclesLower.contains(where: { ["chest", "back", "shoulders", "arms", "biceps", "triceps"].contains($0) }) {
            stretches.append(WarmUpExercise(
                name: "Arm Crossovers",
                duration: 30,
                targetMuscles: ["Chest", "Shoulders"],
                type: .dynamicStretch,
                instructions: "Cross arms in front alternating which arm is on top",
                icon: "figure.arms.open"
            ))
            stretches.append(WarmUpExercise(
                name: "Cat-Cow Stretch",
                duration: 30,
                targetMuscles: ["Back", "Core"],
                type: .dynamicStretch,
                instructions: "Alternate between arching and rounding your back",
                icon: "figure.flexibility"
            ))
            stretches.append(WarmUpExercise(
                name: "Shoulder Rolls",
                duration: 20,
                targetMuscles: ["Shoulders", "Traps"],
                type: .dynamicStretch,
                instructions: "Roll shoulders forward 10x, then backward 10x",
                icon: "arrow.trianglehead.2.counterclockwise.rotate.90"
            ))
        }
        
        // Core stretches
        if musclesLower.contains(where: { ["core", "abs", "obliques"].contains($0) }) {
            stretches.append(WarmUpExercise(
                name: "Torso Twists",
                duration: 30,
                targetMuscles: ["Obliques", "Core"],
                type: .dynamicStretch,
                instructions: "Stand with arms out, twist torso side to side",
                icon: "arrow.left.arrow.right"
            ))
            stretches.append(WarmUpExercise(
                name: "Hip Circles",
                duration: 30,
                targetMuscles: ["Hips", "Core"],
                type: .dynamicStretch,
                instructions: "Make large circles with your hips, both directions",
                icon: "arrow.triangle.2.circlepath"
            ))
        }
        
        return stretches
    }
    
    private func selectActivationExercises(for muscles: [String], level: String) -> [WarmUpExercise] {
        var activations: [WarmUpExercise] = []
        let musclesLower = muscles.map { $0.lowercased() }
        
        // Glute activation
        if musclesLower.contains(where: { ["legs", "glutes", "hamstrings"].contains($0) }) {
            activations.append(WarmUpExercise(
                name: "Glute Bridges",
                duration: 45,
                targetMuscles: ["Glutes"],
                type: .activation,
                instructions: "Perform 15 glute bridges, squeezing at the top",
                icon: "figure.core.training"
            ))
            activations.append(WarmUpExercise(
                name: "Clamshells",
                duration: 30,
                targetMuscles: ["Glutes", "Hip Abductors"],
                type: .activation,
                instructions: "10 each side, lying on your side",
                icon: "figure.strengthtraining.functional"
            ))
        }
        
        // Shoulder activation
        if musclesLower.contains(where: { ["shoulders", "chest", "back"].contains($0) }) {
            activations.append(WarmUpExercise(
                name: "Band Pull-Aparts",
                duration: 30,
                targetMuscles: ["Rear Delts", "Upper Back"],
                type: .activation,
                instructions: "15 reps with light resistance band or mimicking motion",
                icon: "figure.arms.open"
            ))
            activations.append(WarmUpExercise(
                name: "Scapular Push-Ups",
                duration: 30,
                targetMuscles: ["Serratus", "Shoulders"],
                type: .activation,
                instructions: "10 push-ups focusing only on shoulder blade movement",
                icon: "figure.core.training"
            ))
        }
        
        // Core activation
        if musclesLower.contains(where: { ["core", "abs", "full body"].contains($0) }) {
            activations.append(WarmUpExercise(
                name: "Dead Bug",
                duration: 45,
                targetMuscles: ["Core", "Hip Flexors"],
                type: .activation,
                instructions: "10 reps each side, keeping lower back pressed down",
                icon: "figure.core.training"
            ))
        }
        
        return activations
    }
    
    private func selectMobilityExercises(for muscles: [String]) -> [WarmUpExercise] {
        var mobility: [WarmUpExercise] = []
        let musclesLower = muscles.map { $0.lowercased() }
        
        if musclesLower.contains(where: { ["legs", "quads", "hamstrings", "glutes"].contains($0) }) {
            mobility.append(WarmUpExercise(
                name: "Hip 90/90 Stretch",
                duration: 45,
                targetMuscles: ["Hips", "Glutes"],
                type: .mobility,
                instructions: "Sit in 90/90 position, hold 20 seconds each side",
                icon: "figure.flexibility"
            ))
        }
        
        if musclesLower.contains(where: { ["shoulders", "chest", "back"].contains($0) }) {
            mobility.append(WarmUpExercise(
                name: "Thoracic Spine Rotation",
                duration: 45,
                targetMuscles: ["Upper Back", "Spine"],
                type: .mobility,
                instructions: "On all fours, rotate upper back, 10 each side",
                icon: "figure.flexibility"
            ))
        }
        
        return mobility
    }
    
    // MARK: - Intensity Levels
    
    enum WorkoutIntensity: String {
        case light = "Light"
        case moderate = "Moderate"
        case high = "High"
        case max = "Maximum"
    }
}

// MARK: - Quick Warm-Up Presets

extension SmartWarmUpGenerator {
    
    /// Get a quick 3-minute full body warm-up
    func quickFullBodyWarmUp() -> WarmUpRoutine {
        return generateWarmUp(
            targetMuscles: ["Full Body"],
            workoutIntensity: .moderate,
            duration: 3
        )
    }
    
    /// Get a leg day warm-up
    func legDayWarmUp() -> WarmUpRoutine {
        return generateWarmUp(
            targetMuscles: ["Legs", "Glutes", "Hamstrings", "Quads"],
            workoutIntensity: .moderate,
            duration: 5
        )
    }
    
    /// Get an upper body warm-up
    func upperBodyWarmUp() -> WarmUpRoutine {
        return generateWarmUp(
            targetMuscles: ["Chest", "Back", "Shoulders", "Arms"],
            workoutIntensity: .moderate,
            duration: 5
        )
    }
    
    /// Get a push day warm-up
    func pushDayWarmUp() -> WarmUpRoutine {
        return generateWarmUp(
            targetMuscles: ["Chest", "Shoulders", "Triceps"],
            workoutIntensity: .moderate,
            duration: 5
        )
    }
    
    /// Get a pull day warm-up
    func pullDayWarmUp() -> WarmUpRoutine {
        return generateWarmUp(
            targetMuscles: ["Back", "Biceps", "Rear Delts"],
            workoutIntensity: .moderate,
            duration: 5
        )
    }
}

