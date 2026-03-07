import Foundation

// MARK: - Smart Exercise Pairing Engine
// Intelligent system for finding exercise substitutions based on movement patterns,
// muscle activation, equipment alternatives, and biomechanical similarity

final class SmartExercisePairingEngine {
    static let shared = SmartExercisePairingEngine()
    
    // MARK: - Pairing Data Structures
    
    struct ExercisePairing: Identifiable {
        let id = UUID()
        let exercise: Exercise
        let matchScore: Int          // 0-100, higher = better match
        let matchReasons: [MatchReason]
        let equipmentSwap: Bool      // True if this is an equipment alternative
        let difficultyDelta: Int     // -2 to +2 (easier to harder)
        
        enum MatchReason: String, CaseIterable {
            case sameMovementPattern = "Same Movement"
            case samePrimaryMuscle = "Same Target Muscle"
            case sameSecondaryMuscles = "Same Supporting Muscles"
            case equipmentAlternative = "Equipment Alternative"
            case sameGripType = "Same Grip"
            case samePlaneOfMotion = "Same Plane"
            case sameForceVector = "Same Force Direction"
            case similarDifficulty = "Similar Difficulty"
            case sameBodyPosition = "Same Position"
            case compoundToIsolation = "Isolation Alternative"
            case isolationToCompound = "Compound Alternative"
            
            var icon: String {
                switch self {
                case .sameMovementPattern: return "arrow.triangle.2.circlepath"
                case .samePrimaryMuscle: return "figure.strengthtraining.traditional"
                case .sameSecondaryMuscles: return "figure.arms.open"
                case .equipmentAlternative: return "dumbbell.fill"
                case .sameGripType: return "hand.raised.fill"
                case .samePlaneOfMotion: return "arrow.left.and.right"
                case .sameForceVector: return "arrow.up.forward"
                case .similarDifficulty: return "gauge.medium"
                case .sameBodyPosition: return "figure.stand"
                case .compoundToIsolation: return "scope"
                case .isolationToCompound: return "circle.grid.cross"
                }
            }
            
            var weight: Int {
                switch self {
                case .sameMovementPattern: return 25
                case .samePrimaryMuscle: return 30
                case .sameSecondaryMuscles: return 10
                case .equipmentAlternative: return 15
                case .sameGripType: return 5
                case .samePlaneOfMotion: return 8
                case .sameForceVector: return 8
                case .similarDifficulty: return 5
                case .sameBodyPosition: return 7
                case .compoundToIsolation: return 3
                case .isolationToCompound: return 3
                }
            }
        }
    }
    
    // MARK: - Movement Pattern Classification
    
    enum MovementPattern: String, CaseIterable {
        // Upper Body Push
        case horizontalPush = "Horizontal Push"      // Bench press, push-ups
        case verticalPush = "Vertical Push"          // Shoulder press, pike push-ups
        case tricepExtension = "Tricep Extension"    // Skull crushers, pushdowns
        
        // Upper Body Pull
        case horizontalPull = "Horizontal Pull"      // Rows
        case verticalPull = "Vertical Pull"          // Pull-ups, lat pulldowns
        case bicepCurl = "Bicep Curl"                // All curl variations
        
        // Lower Body
        case squat = "Squat"                         // Squats, leg press
        case hipHinge = "Hip Hinge"                  // Deadlifts, RDLs
        case lunge = "Lunge"                         // Lunges, split squats
        case legExtension = "Leg Extension"          // Quad isolation
        case legCurl = "Leg Curl"                    // Hamstring isolation
        case calfRaise = "Calf Raise"                // Calf work
        case hipAbduction = "Hip Abduction"          // Glute work
        case hipAdduction = "Hip Adduction"          // Inner thigh
        
        // Core
        case spinalFlexion = "Spinal Flexion"        // Crunches, sit-ups
        case spinalExtension = "Spinal Extension"    // Back extensions
        case rotation = "Rotation"                   // Russian twists
        case antiRotation = "Anti-Rotation"          // Pallof press
        case plank = "Plank/Isometric"               // Planks
        
        // Shoulders
        case lateralRaise = "Lateral Raise"          // Lateral raises, upright rows
        case shrug = "Shrug"                         // Shrugs, trap work
        
        // Full Body / Compound
        case olympicLift = "Olympic Lift"            // Cleans, snatches
        case carry = "Carry"                         // Farmer's walks
        case complexMovement = "Complex Movement"    // Burpees, etc.
        
        // Other
        case isolation = "Isolation"                 // Single joint movements
        case cardio = "Cardio"                       // Cardio movements
        case stretch = "Stretch"                     // Flexibility
        case unknown = "Unknown"
        
        var relatedPatterns: [MovementPattern] {
            switch self {
            case .horizontalPush: return [.verticalPush, .tricepExtension]
            case .verticalPush: return [.horizontalPush, .tricepExtension]
            case .tricepExtension: return [.horizontalPush, .verticalPush]
            case .horizontalPull: return [.verticalPull, .bicepCurl]
            case .verticalPull: return [.horizontalPull, .bicepCurl]
            case .bicepCurl: return [.horizontalPull, .verticalPull]
            case .squat: return [.lunge, .legExtension]
            case .hipHinge: return [.squat, .legCurl]
            case .lunge: return [.squat, .hipHinge]
            case .legExtension: return [.squat, .lunge]
            case .legCurl: return [.hipHinge]
            case .calfRaise: return []
            case .hipAbduction: return [.hipAdduction, .squat]
            case .hipAdduction: return [.hipAbduction, .squat]
            case .spinalFlexion: return [.plank, .rotation]
            case .spinalExtension: return [.hipHinge]
            case .rotation: return [.antiRotation, .spinalFlexion]
            case .antiRotation: return [.rotation, .plank]
            case .plank: return [.spinalFlexion, .antiRotation]
            case .olympicLift: return [.hipHinge, .squat]
            case .carry: return [.plank]
            case .complexMovement: return [.squat, .horizontalPush]
            case .lateralRaise: return [.verticalPush, .shrug]
            case .shrug: return [.lateralRaise, .verticalPull]
            case .isolation: return []
            case .cardio: return []
            case .stretch: return []
            case .unknown: return []
            }
        }
    }
    
    // MARK: - Equipment Equivalency Groups
    
    struct EquipmentGroup {
        let primary: String
        let alternatives: [String]
        let qualityRating: [String: Int] // How good each alternative is (0-100)
        
        static let groups: [EquipmentGroup] = [
            // Free Weights
            EquipmentGroup(
                primary: "Dumbbells",
                alternatives: ["Barbell", "Kettlebell", "Cables", "Resistance Bands", "Machines"],
                qualityRating: ["Barbell": 95, "Kettlebell": 85, "Cables": 80, "Resistance Bands": 70, "Machines": 75]
            ),
            EquipmentGroup(
                primary: "Barbell",
                alternatives: ["Dumbbells", "Smith Machine", "Cables", "Machines", "EZ Bar"],
                qualityRating: ["Dumbbells": 90, "Smith Machine": 85, "Cables": 75, "Machines": 80, "EZ Bar": 95]
            ),
            EquipmentGroup(
                primary: "Cables",
                alternatives: ["Resistance Bands", "Dumbbells", "Machines"],
                qualityRating: ["Resistance Bands": 85, "Dumbbells": 80, "Machines": 90]
            ),
            EquipmentGroup(
                primary: "Machines",
                alternatives: ["Cables", "Dumbbells", "Barbell", "Bodyweight"],
                qualityRating: ["Cables": 90, "Dumbbells": 85, "Barbell": 80, "Bodyweight": 70]
            ),
            EquipmentGroup(
                primary: "Kettlebell",
                alternatives: ["Dumbbells", "Barbell", "Cables"],
                qualityRating: ["Dumbbells": 90, "Barbell": 80, "Cables": 70]
            ),
            EquipmentGroup(
                primary: "Resistance Bands",
                alternatives: ["Cables", "Dumbbells", "Bodyweight"],
                qualityRating: ["Cables": 95, "Dumbbells": 85, "Bodyweight": 80]
            ),
            EquipmentGroup(
                primary: "Bodyweight",
                alternatives: ["Resistance Bands", "Cables", "Machines"],
                qualityRating: ["Resistance Bands": 85, "Cables": 80, "Machines": 75]
            ),
            EquipmentGroup(
                primary: "Smith Machine",
                alternatives: ["Barbell", "Dumbbells", "Machines"],
                qualityRating: ["Barbell": 95, "Dumbbells": 85, "Machines": 90]
            ),
            EquipmentGroup(
                primary: "EZ Bar",
                alternatives: ["Barbell", "Dumbbells", "Cables"],
                qualityRating: ["Barbell": 95, "Dumbbells": 90, "Cables": 85]
            )
        ]
        
        static func getAlternatives(for equipment: String) -> [(equipment: String, quality: Int)] {
            let normalizedEquipment = equipment.lowercased()
            
            for group in groups {
                if group.primary.lowercased() == normalizedEquipment {
                    return group.alternatives.compactMap { alt in
                        guard let quality = group.qualityRating[alt] else { return nil }
                        return (equipment: alt, quality: quality)
                    }.sorted { $0.quality > $1.quality }
                }
            }
            
            // Check if it's in alternatives of any group
            for group in groups {
                if group.alternatives.map({ $0.lowercased() }).contains(normalizedEquipment) {
                    var results: [(equipment: String, quality: Int)] = [(group.primary, 90)]
                    for alt in group.alternatives where alt.lowercased() != normalizedEquipment {
                        if let quality = group.qualityRating[alt] {
                            results.append((alt, quality))
                        }
                    }
                    return results.sorted { $0.quality > $1.quality }
                }
            }
            
            return []
        }
    }
    
    // MARK: - Muscle Mapping
    
    struct MuscleMapping {
        static let primaryToSecondary: [String: [String]] = [
            "chest": ["triceps", "front delts", "shoulders"],
            "back": ["biceps", "rear delts", "forearms"],
            "lats": ["biceps", "rear delts", "rhomboids"],
            "shoulders": ["triceps", "traps", "upper chest"],
            "biceps": ["forearms", "brachialis"],
            "triceps": ["shoulders", "chest"],
            "quads": ["glutes", "hamstrings", "calves"],
            "hamstrings": ["glutes", "lower back", "calves"],
            "glutes": ["hamstrings", "quads", "lower back"],
            "calves": ["tibialis"],
            "core": ["obliques", "hip flexors", "lower back"],
            "abs": ["obliques", "hip flexors"],
            "traps": ["rhomboids", "rear delts", "neck"],
            "forearms": ["biceps", "grip"]
        ]
        
        static let muscleGroups: [String: [String]] = [
            "chest": ["pectoralis major", "pectoralis minor", "upper chest", "lower chest", "inner chest"],
            "back": ["lats", "rhomboids", "traps", "lower back", "teres major", "teres minor"],
            "shoulders": ["front delts", "side delts", "rear delts", "rotator cuff"],
            "arms": ["biceps", "triceps", "forearms", "brachialis"],
            "legs": ["quads", "hamstrings", "glutes", "calves", "hip flexors", "adductors", "abductors"],
            "core": ["abs", "obliques", "transverse abdominis", "lower back", "hip flexors"]
        ]
        
        static func getRelatedMuscles(_ muscle: String) -> [String] {
            let normalized = muscle.lowercased()
            
            // Check primary to secondary
            if let secondary = primaryToSecondary[normalized] {
                return secondary
            }
            
            // Check muscle groups
            for (group, muscles) in muscleGroups {
                if muscles.map({ $0.lowercased() }).contains(normalized) {
                    return muscles.filter { $0.lowercased() != normalized }
                }
                if group.lowercased() == normalized {
                    return muscles
                }
            }
            
            return []
        }
        
        static func musclesMatch(_ muscles1: [String], _ muscles2: [String]) -> (exact: Int, related: Int) {
            let set1 = Set(muscles1.map { $0.lowercased() })
            let set2 = Set(muscles2.map { $0.lowercased() })
            
            let exactMatches = set1.intersection(set2).count
            
            // Check for related muscle matches
            var relatedMatches = 0
            for m1 in set1 {
                let related = Set(getRelatedMuscles(m1).map { $0.lowercased() })
                relatedMatches += related.intersection(set2).count
            }
            
            return (exact: exactMatches, related: relatedMatches)
        }
    }
    
    // MARK: - Cached Pairing Data
    
    private var pairingCache: [String: [ExercisePairing]] = [:]
    private var movementPatternCache: [String: MovementPattern] = [:]
    private var exerciseAnalysisCache: [String: ExerciseAnalysis] = [:]
    private var isInitialized = false
    
    struct ExerciseAnalysis {
        let name: String
        let movementPattern: MovementPattern
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let equipment: String
        let isCompound: Bool
        let difficulty: Int // 1-10
        let gripType: String?
        let bodyPosition: String?
        let planeOfMotion: String?
        let forceVector: String?
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    func initialize() {
        guard !isInitialized else { return }
        
        print("🧠 [PAIRING ENGINE] Initializing smart pairing system...")
        
        Task(priority: .background) {
            await buildPairingDatabase()
        }
    }
    
    private func buildPairingDatabase() async {
        // Fetch exercise data on main thread to avoid Core Data threading issues
        let exerciseData: [(name: String, muscles: [String], equipment: String)] = await MainActor.run {
            let exercises = ExerciseLibraryService.shared.getAllExercises()
            return exercises.map { exercise in
                (
                    name: (exercise.name ?? "").lowercased(),
                    muscles: (exercise.muscleGroups as? [String]) ?? [],
                    equipment: exercise.equipment ?? "Bodyweight"
                )
            }
        }
        
        print("🧠 [PAIRING ENGINE] Analyzing \(exerciseData.count) exercises...")
        
        // First pass: Analyze all exercises (now safe to do on background thread)
        for data in exerciseData {
            let analysis = analyzeExerciseData(name: data.name, muscles: data.muscles, equipment: data.equipment)
            exerciseAnalysisCache[data.name] = analysis
            movementPatternCache[data.name] = analysis.movementPattern
        }
        
        print("🧠 [PAIRING ENGINE] Exercise analysis complete")
        
        // Second pass: Build pairings (do this lazily on demand)
        isInitialized = true
        print("✅ [PAIRING ENGINE] Ready for pairing queries")
    }
    
    // MARK: - Exercise Analysis
    
    /// Thread-safe analysis using pre-extracted data
    private func analyzeExerciseData(name: String, muscles: [String], equipment: String) -> ExerciseAnalysis {
        return ExerciseAnalysis(
            name: name,
            movementPattern: detectMovementPattern(name: name, muscles: muscles, equipment: equipment),
            primaryMuscles: muscles.isEmpty ? detectMusclesFromName(name) : muscles,
            secondaryMuscles: detectSecondaryMuscles(name: name, primary: muscles),
            equipment: normalizeEquipment(equipment),
            isCompound: isCompoundMovement(name: name, muscles: muscles),
            difficulty: estimateDifficulty(name: name, equipment: equipment),
            gripType: detectGripType(name),
            bodyPosition: detectBodyPosition(name),
            planeOfMotion: detectPlaneOfMotion(name),
            forceVector: detectForceVector(name)
        )
    }
    
    /// Analyze exercise from Core Data object (must be called on main thread)
    private func analyzeExercise(_ exercise: Exercise) -> ExerciseAnalysis {
        let name = (exercise.name ?? "").lowercased()
        let muscles = (exercise.muscleGroups as? [String]) ?? []
        let equipment = exercise.equipment ?? "Bodyweight"
        
        return ExerciseAnalysis(
            name: name,
            movementPattern: detectMovementPattern(name: name, muscles: muscles, equipment: equipment),
            primaryMuscles: muscles.isEmpty ? detectMusclesFromName(name) : muscles,
            secondaryMuscles: detectSecondaryMuscles(name: name, primary: muscles),
            equipment: normalizeEquipment(equipment),
            isCompound: isCompoundMovement(name: name, muscles: muscles),
            difficulty: estimateDifficulty(name: name, equipment: equipment),
            gripType: detectGripType(name),
            bodyPosition: detectBodyPosition(name),
            planeOfMotion: detectPlaneOfMotion(name),
            forceVector: detectForceVector(name)
        )
    }
    
    // MARK: - Movement Pattern Detection
    
    private func detectMovementPattern(name: String, muscles: [String], equipment: String) -> MovementPattern {
        let nameLower = name.lowercased()
        let musclesLower = muscles.map { $0.lowercased() }
        
        // Curls
        if nameLower.contains("curl") {
            if nameLower.contains("leg") || nameLower.contains("hamstring") {
                return .legCurl
            }
            return .bicepCurl
        }
        
        // Extensions
        if nameLower.contains("extension") || nameLower.contains("pushdown") || nameLower.contains("kickback") {
            if nameLower.contains("leg") || nameLower.contains("quad") {
                return .legExtension
            }
            if nameLower.contains("back") || nameLower.contains("hyper") {
                return .spinalExtension
            }
            return .tricepExtension
        }
        
        // Presses
        if nameLower.contains("press") || nameLower.contains("push") {
            if nameLower.contains("leg") || nameLower.contains("squat") {
                return .squat
            }
            if nameLower.contains("shoulder") || nameLower.contains("overhead") || nameLower.contains("military") {
                return .verticalPush
            }
            if nameLower.contains("bench") || nameLower.contains("chest") || nameLower.contains("floor") {
                return .horizontalPush
            }
            if nameLower.contains("pallof") {
                return .antiRotation
            }
            // Default press
            if musclesLower.contains(where: { $0.contains("chest") }) {
                return .horizontalPush
            }
            if musclesLower.contains(where: { $0.contains("shoulder") || $0.contains("delt") }) {
                return .verticalPush
            }
        }
        
        // Push-ups
        if nameLower.contains("push up") || nameLower.contains("pushup") || nameLower.contains("push-up") {
            if nameLower.contains("pike") || nameLower.contains("handstand") {
                return .verticalPush
            }
            return .horizontalPush
        }
        
        // Rows
        if nameLower.contains("row") {
            if nameLower.contains("upright") {
                return .lateralRaise
            }
            return .horizontalPull
        }
        
        // Pulls
        if nameLower.contains("pull") {
            if nameLower.contains("up") || nameLower.contains("down") || nameLower.contains("lat") {
                return .verticalPull
            }
            if nameLower.contains("face") {
                return .horizontalPull
            }
            return .verticalPull
        }
        
        // Squats
        if nameLower.contains("squat") || nameLower.contains("leg press") {
            return .squat
        }
        
        // Lunges
        if nameLower.contains("lunge") || nameLower.contains("split squat") || nameLower.contains("step up") {
            return .lunge
        }
        
        // Hip Hinge / Deadlifts
        if nameLower.contains("deadlift") || nameLower.contains("rdl") || nameLower.contains("romanian") ||
           nameLower.contains("good morning") || nameLower.contains("hip hinge") {
            return .hipHinge
        }
        
        // Hip movements
        if nameLower.contains("hip thrust") || nameLower.contains("bridge") {
            return .hipHinge
        }
        if nameLower.contains("abduction") || nameLower.contains("clam") {
            return .hipAbduction
        }
        if nameLower.contains("adduction") {
            return .hipAdduction
        }
        
        // Calves
        if nameLower.contains("calf") || nameLower.contains("raise") && musclesLower.contains(where: { $0.contains("calf") }) {
            return .calfRaise
        }
        
        // Core
        if nameLower.contains("crunch") || nameLower.contains("sit up") || nameLower.contains("situp") {
            return .spinalFlexion
        }
        if nameLower.contains("plank") || nameLower.contains("hollow") {
            return .plank
        }
        if nameLower.contains("twist") || nameLower.contains("rotation") || nameLower.contains("woodchop") {
            return .rotation
        }
        if nameLower.contains("pallof") || nameLower.contains("anti-rotation") {
            return .antiRotation
        }
        
        // Olympic lifts
        if nameLower.contains("clean") || nameLower.contains("snatch") || nameLower.contains("jerk") {
            return .olympicLift
        }
        
        // Carries
        if nameLower.contains("carry") || nameLower.contains("walk") && nameLower.contains("farmer") {
            return .carry
        }
        
        // Complex
        if nameLower.contains("burpee") || nameLower.contains("thruster") {
            return .complexMovement
        }
        
        // Cardio
        if nameLower.contains("run") || nameLower.contains("bike") || nameLower.contains("jump") ||
           nameLower.contains("jumping jack") || nameLower.contains("mountain climber") {
            return .cardio
        }
        
        // Stretch
        if nameLower.contains("stretch") || nameLower.contains("mobility") || nameLower.contains("flexibility") {
            return .stretch
        }
        
        // Fallback based on muscles
        if musclesLower.contains(where: { $0.contains("bicep") }) {
            return .bicepCurl
        }
        if musclesLower.contains(where: { $0.contains("tricep") }) {
            return .tricepExtension
        }
        if musclesLower.contains(where: { $0.contains("chest") || $0.contains("pec") }) {
            return .horizontalPush
        }
        if musclesLower.contains(where: { $0.contains("back") || $0.contains("lat") }) {
            return .horizontalPull
        }
        if musclesLower.contains(where: { $0.contains("quad") }) {
            return .squat
        }
        if musclesLower.contains(where: { $0.contains("hamstring") || $0.contains("glute") }) {
            return .hipHinge
        }
        if musclesLower.contains(where: { $0.contains("ab") || $0.contains("core") }) {
            return .spinalFlexion
        }
        
        return .unknown
    }
    
    // MARK: - Helper Detection Functions
    
    /// Normalize equipment to user-selectable category
    /// Uses centralized ExerciseFilterService for consistency
    private func normalizeEquipment(_ equipment: String) -> String {
        return ExerciseFilterService.normalizeEquipment(equipment)
    }
    
    private func detectMusclesFromName(_ name: String) -> [String] {
        var muscles: [String] = []
        let lower = name.lowercased()
        
        if lower.contains("bicep") { muscles.append("Biceps") }
        if lower.contains("tricep") { muscles.append("Triceps") }
        if lower.contains("chest") || lower.contains("pec") { muscles.append("Chest") }
        if lower.contains("back") || lower.contains("lat") { muscles.append("Back") }
        if lower.contains("shoulder") || lower.contains("delt") { muscles.append("Shoulders") }
        if lower.contains("quad") || lower.contains("leg extension") { muscles.append("Quads") }
        if lower.contains("hamstring") || lower.contains("leg curl") { muscles.append("Hamstrings") }
        if lower.contains("glute") || lower.contains("hip thrust") { muscles.append("Glutes") }
        if lower.contains("calf") || lower.contains("calves") { muscles.append("Calves") }
        if lower.contains("ab") || lower.contains("core") || lower.contains("crunch") { muscles.append("Core") }
        if lower.contains("trap") { muscles.append("Traps") }
        if lower.contains("forearm") { muscles.append("Forearms") }
        
        return muscles.isEmpty ? ["General"] : muscles
    }
    
    private func detectSecondaryMuscles(name: String, primary: [String]) -> [String] {
        var secondary: [String] = []
        
        for muscle in primary {
            if let related = MuscleMapping.primaryToSecondary[muscle.lowercased()] {
                secondary.append(contentsOf: related)
            }
        }
        
        return Array(Set(secondary))
    }
    
    private func isCompoundMovement(name: String, muscles: [String]) -> Bool {
        let lower = name.lowercased()
        
        let compoundKeywords = ["squat", "deadlift", "press", "row", "pull up", "pullup", "chin up", "chinup",
                                "clean", "snatch", "lunge", "thrust", "push up", "pushup"]
        
        // "dip" only counts as compound in specific contexts (not "bench dip")
        if lower.contains("dip") && !lower.contains("bench dip") && !lower.contains("assisted dip") {
            return true
        }
        
        let isolationKeywords = ["curl", "extension", "raise", "fly", "flye", "kickback", "pullover",
                                 "crunch", "shrug", "rotation"]
        
        if compoundKeywords.contains(where: { lower.contains($0) }) {
            return true
        }
        
        if isolationKeywords.contains(where: { lower.contains($0) }) {
            return false
        }
        
        return muscles.count > 1
    }
    
    private func estimateDifficulty(name: String, equipment: String) -> Int {
        let lower = name.lowercased()
        let equipLower = equipment.lowercased()
        
        // Base difficulty by equipment type
        var difficulty: Int
        if equipLower.contains("machine") || equipLower.contains("smith") {
            difficulty = 3
        } else if equipLower.contains("cable") {
            difficulty = 4
        } else if equipLower.contains("dumbbell") {
            difficulty = 5
        } else if equipLower.contains("barbell") || equipLower.contains("ez bar") {
            difficulty = 6
        } else if equipLower.contains("bodyweight") || equipLower.isEmpty {
            difficulty = 5
        } else {
            difficulty = 5
        }
        
        // Harder indicators
        if lower.contains("single leg") || lower.contains("one leg") { difficulty += 2 }
        if lower.contains("single arm") || lower.contains("one arm") { difficulty += 1 }
        if lower.contains("deficit") { difficulty += 1 }
        if lower.contains("pause") { difficulty += 1 }
        if lower.contains("explosive") || lower.contains("jump") { difficulty += 2 }
        if lower.contains("weighted") { difficulty += 1 }
        if lower.contains("advanced") { difficulty += 2 }
        
        // Easier indicators
        if lower.contains("assisted") { difficulty -= 2 }
        if lower.contains("beginner") { difficulty -= 2 }
        if lower.contains("modified") { difficulty -= 1 }
        
        return max(1, min(10, difficulty))
    }
    
    private func detectGripType(_ name: String) -> String? {
        let lower = name.lowercased()
        
        if lower.contains("underhand") || lower.contains("supinated") { return "Underhand" }
        if lower.contains("overhand") || lower.contains("pronated") { return "Overhand" }
        if lower.contains("neutral") || lower.contains("hammer") { return "Neutral" }
        if lower.contains("reverse") { return "Reverse" }
        if lower.contains("wide grip") { return "Wide" }
        if lower.contains("close grip") || lower.contains("narrow") { return "Close" }
        
        return nil
    }
    
    private func detectBodyPosition(_ name: String) -> String? {
        let lower = name.lowercased()
        
        if lower.contains("seated") || lower.contains("sitting") { return "Seated" }
        if lower.contains("standing") { return "Standing" }
        if lower.contains("lying") || lower.contains("supine") { return "Lying" }
        if lower.contains("incline") { return "Incline" }
        if lower.contains("decline") { return "Decline" }
        if lower.contains("bent over") || lower.contains("bent-over") { return "Bent Over" }
        if lower.contains("kneeling") { return "Kneeling" }
        if lower.contains("hanging") { return "Hanging" }
        
        return nil
    }
    
    private func detectPlaneOfMotion(_ name: String) -> String? {
        let lower = name.lowercased()
        
        // Sagittal (forward/backward)
        if lower.contains("curl") || lower.contains("extension") || lower.contains("press") ||
           lower.contains("row") || lower.contains("squat") || lower.contains("lunge") {
            return "Sagittal"
        }
        
        // Frontal (side to side)
        if lower.contains("lateral") || lower.contains("abduction") || lower.contains("adduction") ||
           lower.contains("side") {
            return "Frontal"
        }
        
        // Transverse (rotation)
        if lower.contains("rotation") || lower.contains("twist") || lower.contains("woodchop") {
            return "Transverse"
        }
        
        return nil
    }
    
    private func detectForceVector(_ name: String) -> String? {
        let lower = name.lowercased()
        
        if lower.contains("press") || lower.contains("push") || lower.contains("extension") {
            return "Push"
        }
        if lower.contains("pull") || lower.contains("row") || lower.contains("curl") {
            return "Pull"
        }
        if lower.contains("squat") || lower.contains("deadlift") || lower.contains("lunge") {
            return "Vertical"
        }
        
        return nil
    }
    
    // MARK: - Main Pairing Function
    
    func findSubstitutes(for exercise: Exercise, limit: Int = 15, userEquipment: [String]? = nil) -> [ExercisePairing] {
        let exerciseName = (exercise.name ?? "").lowercased()
        
        // Check cache first
        if let cached = pairingCache[exerciseName] {
            if let equipment = userEquipment {
                return cached.filter { pairing in
                    let pairingEquip = (pairing.exercise.equipment ?? "Bodyweight").lowercased()
                    return equipment.map { $0.lowercased() }.contains(pairingEquip) ||
                           pairingEquip == "bodyweight"
                }.prefix(limit).map { $0 }
            }
            return Array(cached.prefix(limit))
        }
        
        // Get or create analysis for source exercise
        let sourceAnalysis: ExerciseAnalysis
        if let cached = exerciseAnalysisCache[exerciseName] {
            sourceAnalysis = cached
        } else {
            sourceAnalysis = analyzeExercise(exercise)
            exerciseAnalysisCache[exerciseName] = sourceAnalysis
        }
        
        // Find all matching exercises
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        var pairings: [ExercisePairing] = []
        
        for candidate in allExercises {
            guard candidate.id != exercise.id else { continue }
            
            let candidateName = (candidate.name ?? "").lowercased()
            
            // Get or create analysis for candidate
            let candidateAnalysis: ExerciseAnalysis
            if let cached = exerciseAnalysisCache[candidateName] {
                candidateAnalysis = cached
            } else {
                candidateAnalysis = analyzeExercise(candidate)
                exerciseAnalysisCache[candidateName] = candidateAnalysis
            }
            
            // Calculate match score and reasons
            let (score, reasons) = calculateMatchScore(source: sourceAnalysis, candidate: candidateAnalysis)
            
            // Only include if there's meaningful match
            if score >= 30 {
                let pairing = ExercisePairing(
                    exercise: candidate,
                    matchScore: score,
                    matchReasons: reasons,
                    equipmentSwap: sourceAnalysis.equipment != candidateAnalysis.equipment,
                    difficultyDelta: candidateAnalysis.difficulty - sourceAnalysis.difficulty
                )
                pairings.append(pairing)
            }
        }
        
        // Sort by match score
        pairings.sort { $0.matchScore > $1.matchScore }
        
        // Cache results
        pairingCache[exerciseName] = pairings
        
        // Filter by user equipment if provided
        if let equipment = userEquipment {
            let filtered = pairings.filter { pairing in
                let pairingEquip = (pairing.exercise.equipment ?? "Bodyweight").lowercased()
                return equipment.map { $0.lowercased() }.contains(pairingEquip) ||
                       pairingEquip == "bodyweight"
            }
            return Array(filtered.prefix(limit))
        }
        
        return Array(pairings.prefix(limit))
    }
    
    private func calculateMatchScore(source: ExerciseAnalysis, candidate: ExerciseAnalysis) -> (score: Int, reasons: [ExercisePairing.MatchReason]) {
        var score = 0
        var reasons: [ExercisePairing.MatchReason] = []
        
        // 1. Movement Pattern Match (highest weight)
        if source.movementPattern == candidate.movementPattern {
            score += ExercisePairing.MatchReason.sameMovementPattern.weight
            reasons.append(.sameMovementPattern)
        } else if source.movementPattern.relatedPatterns.contains(candidate.movementPattern) {
            score += ExercisePairing.MatchReason.sameMovementPattern.weight / 2
            reasons.append(.sameMovementPattern)
        }
        
        // 2. Primary Muscle Match
        let (exactMuscles, relatedMuscles) = MuscleMapping.musclesMatch(
            source.primaryMuscles,
            candidate.primaryMuscles
        )
        if exactMuscles > 0 {
            score += ExercisePairing.MatchReason.samePrimaryMuscle.weight
            reasons.append(.samePrimaryMuscle)
        } else if relatedMuscles > 0 {
            score += ExercisePairing.MatchReason.samePrimaryMuscle.weight / 2
        }
        
        // 3. Secondary Muscle Match
        let (exactSecondary, _) = MuscleMapping.musclesMatch(
            source.secondaryMuscles,
            candidate.secondaryMuscles
        )
        if exactSecondary > 0 {
            score += ExercisePairing.MatchReason.sameSecondaryMuscles.weight
            reasons.append(.sameSecondaryMuscles)
        }
        
        // 4. Equipment Alternative
        if source.equipment != candidate.equipment {
            let alternatives = EquipmentGroup.getAlternatives(for: source.equipment)
            if let match = alternatives.first(where: { $0.equipment.lowercased() == candidate.equipment.lowercased() }) {
                let equipmentScore = (ExercisePairing.MatchReason.equipmentAlternative.weight * match.quality) / 100
                score += equipmentScore
                reasons.append(.equipmentAlternative)
            }
        } else {
            // Same equipment is good
            score += ExercisePairing.MatchReason.equipmentAlternative.weight
        }
        
        // 5. Grip Type Match
        if let sourceGrip = source.gripType, let candidateGrip = candidate.gripType {
            if sourceGrip == candidateGrip {
                score += ExercisePairing.MatchReason.sameGripType.weight
                reasons.append(.sameGripType)
            }
        }
        
        // 6. Body Position Match
        if let sourcePos = source.bodyPosition, let candidatePos = candidate.bodyPosition {
            if sourcePos == candidatePos {
                score += ExercisePairing.MatchReason.sameBodyPosition.weight
                reasons.append(.sameBodyPosition)
            }
        }
        
        // 7. Plane of Motion Match
        if let sourcePlane = source.planeOfMotion, let candidatePlane = candidate.planeOfMotion {
            if sourcePlane == candidatePlane {
                score += ExercisePairing.MatchReason.samePlaneOfMotion.weight
                reasons.append(.samePlaneOfMotion)
            }
        }
        
        // 8. Force Vector Match
        if let sourceForce = source.forceVector, let candidateForce = candidate.forceVector {
            if sourceForce == candidateForce {
                score += ExercisePairing.MatchReason.sameForceVector.weight
                reasons.append(.sameForceVector)
            }
        }
        
        // 9. Difficulty Match (prefer similar difficulty)
        let diffDelta = abs(source.difficulty - candidate.difficulty)
        if diffDelta <= 1 {
            score += ExercisePairing.MatchReason.similarDifficulty.weight
            reasons.append(.similarDifficulty)
        } else if diffDelta <= 2 {
            score += ExercisePairing.MatchReason.similarDifficulty.weight / 2
        }
        
        // 10. Compound/Isolation consideration
        if source.isCompound != candidate.isCompound {
            if source.isCompound {
                reasons.append(.compoundToIsolation)
            } else {
                reasons.append(.isolationToCompound)
            }
            score += 3 // Small bonus for having an alternative type
        }
        
        // Cap at 100
        return (min(score, 100), reasons)
    }
    
    // MARK: - Quick Lookup Methods
    
    /// Get equipment alternatives for a specific exercise
    func getEquipmentAlternatives(for exercise: Exercise) -> [ExercisePairing] {
        let all = findSubstitutes(for: exercise, limit: 30)
        return all.filter { $0.equipmentSwap }
    }
    
    /// Get easier variations
    func getEasierVariations(for exercise: Exercise) -> [ExercisePairing] {
        let all = findSubstitutes(for: exercise, limit: 30)
        return all.filter { $0.difficultyDelta < 0 }.sorted { $0.difficultyDelta > $1.difficultyDelta }
    }
    
    /// Get harder progressions
    func getHarderProgressions(for exercise: Exercise) -> [ExercisePairing] {
        let all = findSubstitutes(for: exercise, limit: 30)
        return all.filter { $0.difficultyDelta > 0 }.sorted { $0.difficultyDelta < $1.difficultyDelta }
    }
    
    /// Get bodyweight alternatives
    func getBodyweightAlternatives(for exercise: Exercise) -> [ExercisePairing] {
        let all = findSubstitutes(for: exercise, limit: 30)
        return all.filter { ($0.exercise.equipment ?? "").lowercased() == "bodyweight" }
    }
    
    // MARK: - Debug / Testing
    
    func debugPrintAnalysis(for exercise: Exercise) {
        let analysis = analyzeExercise(exercise)
        print("""
        📊 Exercise Analysis: \(analysis.name)
        ├── Movement Pattern: \(analysis.movementPattern.rawValue)
        ├── Primary Muscles: \(analysis.primaryMuscles.joined(separator: ", "))
        ├── Secondary Muscles: \(analysis.secondaryMuscles.joined(separator: ", "))
        ├── Equipment: \(analysis.equipment)
        ├── Is Compound: \(analysis.isCompound)
        ├── Difficulty: \(analysis.difficulty)/10
        ├── Grip Type: \(analysis.gripType ?? "N/A")
        ├── Body Position: \(analysis.bodyPosition ?? "N/A")
        ├── Plane of Motion: \(analysis.planeOfMotion ?? "N/A")
        └── Force Vector: \(analysis.forceVector ?? "N/A")
        """)
    }
}

