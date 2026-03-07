import Foundation

// MARK: - Exercise Intelligence Engine
/// Advanced AI-like engine for smart exercise selection, substitution, and pairing
/// Considers: equipment, skill level, time, goals, muscle synergy, movement patterns
/// Powers: Auto-workout generator, Program builder, Exercise recommendations

final class ExerciseIntelligenceEngine {
    static let shared = ExerciseIntelligenceEngine()
    
    // MARK: - Muscle Synergy Map
    /// Which muscle groups work well together in the same workout
    /// Based on push/pull splits, antagonist pairings, and energy system optimization
    
    static let muscleSynergyPairs: [String: [String]] = [
        // Push muscles (work together)
        "Chest": ["Triceps", "Front Delts", "Side Delts"],
        "Triceps": ["Chest", "Shoulders"],
        "Front Delts": ["Chest", "Triceps", "Side Delts"],
        "Side Delts": ["Front Delts", "Rear Delts", "Traps"],
        "Shoulders": ["Chest", "Triceps", "Traps", "Core"],
        
        // Pull muscles (work together)
        "Back": ["Biceps", "Rear Delts", "Forearms"],
        "Lats": ["Biceps", "Rear Delts", "Upper Back"],
        "Upper Back": ["Biceps", "Rear Delts", "Traps"],
        "Biceps": ["Back", "Lats", "Forearms"],
        "Rear Delts": ["Back", "Upper Back", "Traps"],
        "Traps": ["Shoulders", "Back", "Rear Delts", "Upper Back"],
        "Forearms": ["Biceps", "Back"],
        
        // Leg muscles (work together)
        "Quads": ["Glutes", "Calves", "Core"],
        "Quadriceps": ["Glutes", "Calves", "Core"],
        "Hamstrings": ["Glutes", "Lower Back", "Calves"],
        "Glutes": ["Quads", "Hamstrings", "Core"],
        "Calves": ["Quads", "Hamstrings"],
        "Hip Flexors": ["Core", "Quads", "Abs"],
        
        // Core muscles
        "Abs": ["Obliques", "Lower Back", "Hip Flexors"],
        "Obliques": ["Abs", "Core"],
        "Core": ["Abs", "Obliques", "Glutes"],
        "Lower Back": ["Hamstrings", "Glutes", "Abs"]
    ]
    
    // MARK: - Movement Pattern Categories
    /// Group exercises by fundamental movement patterns
    
    enum MovementPattern: String, CaseIterable {
        case push = "Push"           // Bench press, shoulder press, pushups
        case pull = "Pull"           // Rows, pulldowns, curls
        case squat = "Squat"         // Squats, lunges, leg press
        case hinge = "Hinge"         // Deadlifts, RDL, hip thrusts
        case carry = "Carry"         // Farmers walk, loaded carries
        case rotation = "Rotation"   // Russian twists, woodchops
        case plank = "Plank"         // Planks, dead bugs, stability
        case isolation = "Isolation" // Curls, extensions, raises
        
        var complementaryPatterns: [MovementPattern] {
            switch self {
            case .push: return [.pull, .squat]
            case .pull: return [.push, .hinge]
            case .squat: return [.hinge, .push]
            case .hinge: return [.squat, .pull]
            case .carry: return [.squat, .hinge]
            case .rotation: return [.plank, .push]
            case .plank: return [.rotation, .carry]
            case .isolation: return [.push, .pull]
            }
        }
    }
    
    // MARK: - Equipment Hierarchy
    /// Equipment substitution priority (most versatile → most specific)
    
    static let equipmentSubstitutions: [String: [String]] = [
        // Dumbbell exercises can often be done with...
        "Dumbbells": ["Barbell", "Cables", "Kettlebell", "Resistance Bands", "Machines", "Bodyweight"],
        "Dumbbell": ["Barbell", "Cables", "Kettlebell", "Resistance Bands", "Machines", "Bodyweight"],
        
        // Barbell exercises can be substituted with...
        "Barbell": ["Dumbbells", "Smith Machine", "Cables", "Machines"],
        
        // Cable exercises alternatives...
        "Cables": ["Resistance Bands", "Dumbbells", "Machines"],
        "Cable": ["Resistance Bands", "Dumbbells", "Machines"],
        
        // Machine alternatives...
        "Machines": ["Cables", "Dumbbells", "Barbell", "Resistance Bands"],
        "Machine": ["Cables", "Dumbbells", "Barbell", "Resistance Bands"],
        
        // Bodyweight can be loaded with...
        "Bodyweight": ["Dumbbells", "Resistance Bands", "Kettlebell"],
        
        // Kettlebell alternatives...
        "Kettlebell": ["Dumbbells", "Resistance Bands"],
        
        // Resistance bands alternatives...
        "Resistance Bands": ["Cables", "Dumbbells", "Bodyweight"],
        
        // Smith Machine alternatives...
        "Smith Machine": ["Barbell", "Machines", "Dumbbells"],
        
        // TRX/Rings alternatives...
        "TRX/Rings": ["Bodyweight", "Cables", "Resistance Bands"],
        
        // Stability Ball alternatives...
        "Stability Ball": ["Bench", "Bodyweight"],
        
        // Bench alternatives...
        "Bench": ["Stability Ball", "Bodyweight"]
    ]
    
    // MARK: - Exercise Category Mapping
    /// Map exercise names to movement patterns based on keywords
    
    private let pushKeywords = ["press", "push", "dip", "fly", "flye", "raise front", "chest"]
    private let pullKeywords = ["row", "pull", "curl", "lat", "pulldown", "chin", "face pull"]
    private let squatKeywords = ["squat", "lunge", "leg press", "leg extension", "step"]
    private let hingeKeywords = ["deadlift", "rdl", "hip thrust", "glute bridge", "hyperextension", "good morning", "leg curl"]
    private let coreKeywords = ["crunch", "plank", "twist", "ab", "core", "sit-up", "situp"]
    private let isolationKeywords = ["curl", "extension", "raise", "fly", "kickback", "shrug"]
    
    // MARK: - Difficulty Multipliers
    
    struct DifficultyConfig {
        static let beginner = DifficultyLevel(
            maxExercisesPerMuscle: 2,
            preferCompound: true,
            maxTotalExercises: 6,
            restMultiplier: 1.5,
            preferredEquipment: ["Bodyweight", "Machines", "Dumbbells"],
            avoidComplexMovements: true
        )
        
        static let intermediate = DifficultyLevel(
            maxExercisesPerMuscle: 3,
            preferCompound: true,
            maxTotalExercises: 8,
            restMultiplier: 1.0,
            preferredEquipment: ["Dumbbells", "Barbell", "Cables", "Machines"],
            avoidComplexMovements: false
        )
        
        static let advanced = DifficultyLevel(
            maxExercisesPerMuscle: 4,
            preferCompound: false,
            maxTotalExercises: 12,
            restMultiplier: 0.8,
            preferredEquipment: ["Barbell", "Dumbbells", "Cables", "Kettlebell", "TRX/Rings"],
            avoidComplexMovements: false
        )
    }
    
    struct DifficultyLevel {
        let maxExercisesPerMuscle: Int
        let preferCompound: Bool
        let maxTotalExercises: Int
        let restMultiplier: Double
        let preferredEquipment: [String]
        let avoidComplexMovements: Bool
    }
    
    // MARK: - Goal-Based Configuration
    
    enum FitnessGoal: String, CaseIterable {
        case buildMuscle = "Build Muscle"
        case loseFat = "Lose Fat"
        case getStronger = "Get Stronger"
        case improveEndurance = "Improve Endurance"
        case generalFitness = "General Fitness"
        
        var config: GoalConfig {
            switch self {
            case .buildMuscle:
                return GoalConfig(
                    repRange: 8...12,
                    sets: 3...4,
                    restSeconds: 60...90,
                    volumePriority: .high,
                    intensityPriority: .medium,
                    preferCompound: true,
                    supersetFriendly: true
                )
            case .loseFat:
                return GoalConfig(
                    repRange: 8...15,
                    sets: 3...4,
                    restSeconds: 30...60,
                    volumePriority: .medium,
                    intensityPriority: .medium,
                    preferCompound: true,
                    supersetFriendly: true
                )
            case .getStronger:
                return GoalConfig(
                    repRange: 3...6,
                    sets: 4...5,
                    restSeconds: 120...180,
                    volumePriority: .low,
                    intensityPriority: .high,
                    preferCompound: true,
                    supersetFriendly: false
                )
            case .improveEndurance:
                return GoalConfig(
                    repRange: 15...25,
                    sets: 2...3,
                    restSeconds: 20...30,
                    volumePriority: .high,
                    intensityPriority: .low,
                    preferCompound: false,
                    supersetFriendly: true
                )
            case .generalFitness:
                return GoalConfig(
                    repRange: 10...15,
                    sets: 3...3,
                    restSeconds: 45...60,
                    volumePriority: .medium,
                    intensityPriority: .medium,
                    preferCompound: true,
                    supersetFriendly: true
                )
            }
        }
    }
    
    struct GoalConfig {
        let repRange: ClosedRange<Int>
        let sets: ClosedRange<Int>
        let restSeconds: ClosedRange<Int>
        let volumePriority: Priority
        let intensityPriority: Priority
        let preferCompound: Bool
        let supersetFriendly: Bool
        
        enum Priority { case low, medium, high }
    }
    
    // MARK: - Cached Exercise Data
    
    private var exerciseCache: [String: ExerciseMetadata] = [:]
    private var equipmentToExercises: [String: Set<String>] = [:]
    private var muscleToExercises: [String: Set<String>] = [:]
    private var categoryToExercises: [String: Set<String>] = [:]
    private var isInitialized = false
    
    struct ExerciseMetadata {
        let name: String
        let category: String
        let equipment: String
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let movementPattern: MovementPattern
        let isCompound: Bool
        let difficulty: Int // 1-10
        let videoFilename: String?
    }
    
    // MARK: - Initialization
    
    /// Track whether a load is already in flight to prevent duplicate network requests
    private var isLoading = false
    
    private init() {
        loadExerciseData()
    }
    
    func loadExerciseData() {
        // BUG FIX: Guard against double-loading. init() calls this, and then
        // Fit33App.runIntelligenceInit() calls it again explicitly.
        // Without this guard, exercises are fetched from Supabase twice (~6500 each time),
        // wasting network bandwidth and holding ~2x memory during the overlap.
        guard !isInitialized && !isLoading else { return }
        isLoading = true
        
        // Load in background with low priority to not block UI
        Task(priority: .background) {
            await loadFromDatabase()
            await MainActor.run { self.isLoading = false }
        }
    }
    
    private func loadFromDatabase() async {
        do {
            let exercises = try await SupabaseManager.shared.fetchAllExercises()
            
            await MainActor.run {
                for exercise in exercises {
                    let pattern = determineMovementPattern(
                        name: exercise.name,
                        category: exercise.category,
                        primaryMuscles: exercise.primaryMusclesArray
                    )
                    
                    let isCompound = determineIfCompound(
                        primaryMuscles: exercise.primaryMusclesArray,
                        secondaryMuscles: exercise.secondaryMusclesArray
                    )
                    
                    let normalizedEquipment = ExerciseFilterService.normalizeEquipment(exercise.equipment)
                    
                    let metadata = ExerciseMetadata(
                        name: exercise.name,
                        category: exercise.category,
                        equipment: normalizedEquipment,
                        primaryMuscles: exercise.primaryMusclesArray,
                        secondaryMuscles: exercise.secondaryMusclesArray,
                        movementPattern: pattern,
                        isCompound: isCompound,
                        difficulty: calculateDifficulty(exercise),
                        videoFilename: exercise.videoFilename
                    )
                    
                    let normalizedName = exercise.name.lowercased()
                    exerciseCache[normalizedName] = metadata
                    
                    // Index by equipment
                    if equipmentToExercises[normalizedEquipment] == nil {
                        equipmentToExercises[normalizedEquipment] = []
                    }
                    equipmentToExercises[normalizedEquipment]?.insert(normalizedName)
                    
                    // Index by primary muscles
                    for muscle in exercise.primaryMusclesArray {
                        let normalizedMuscle = muscle.lowercased()
                        if muscleToExercises[normalizedMuscle] == nil {
                            muscleToExercises[normalizedMuscle] = []
                        }
                        muscleToExercises[normalizedMuscle]?.insert(normalizedName)
                    }
                    
                    // Index by category
                    let normalizedCategory = exercise.category.lowercased()
                    if categoryToExercises[normalizedCategory] == nil {
                        categoryToExercises[normalizedCategory] = []
                    }
                    categoryToExercises[normalizedCategory]?.insert(normalizedName)
                }
                
                isInitialized = true
                #if DEBUG
                print("🧠 ExerciseIntelligenceEngine: Loaded \(exerciseCache.count) exercises")
                print("   Equipment groups: \(equipmentToExercises.keys.count)")
                print("   Muscle groups: \(muscleToExercises.keys.count)")
                #endif
            }
        } catch {
            print("❌ ExerciseIntelligenceEngine: Failed to load data: \(error)")
        }
    }
    
    // MARK: - Public API
    
    /// Find equipment substitutions for an exercise
    func findEquipmentSubstitutions(for exerciseName: String, availableEquipment: [String]) -> [ExerciseMetadata] {
        guard let original = exerciseCache[exerciseName.lowercased()] else { return [] }
        
        var substitutes: [ExerciseMetadata] = []
        let normalizedAvailable = Set(availableEquipment.map { ExerciseFilterService.normalizeEquipment($0) })
        
        // Find exercises targeting same muscles with available equipment
        for muscle in original.primaryMuscles {
            guard let exercisesForMuscle = muscleToExercises[muscle.lowercased()] else { continue }
            
            for exerciseName in exercisesForMuscle {
                guard let exercise = exerciseCache[exerciseName],
                      exercise.name.lowercased() != original.name.lowercased(),
                      normalizedAvailable.contains(exercise.equipment) else { continue }
                
                // Check movement pattern similarity
                if exercise.movementPattern == original.movementPattern ||
                   original.movementPattern.complementaryPatterns.contains(exercise.movementPattern) {
                    substitutes.append(exercise)
                }
            }
        }
        
        // Sort by similarity (same pattern first, then difficulty)
        return substitutes.sorted { a, b in
            if a.movementPattern == original.movementPattern && b.movementPattern != original.movementPattern {
                return true
            }
            return abs(a.difficulty - original.difficulty) < abs(b.difficulty - original.difficulty)
        }
    }
    
    /// Find complementary exercises that pair well together
    func findComplementaryExercises(for exerciseName: String, limit: Int = 5) -> [ExerciseMetadata] {
        guard let original = exerciseCache[exerciseName.lowercased()] else { return [] }
        
        var complementary: [ExerciseMetadata] = []
        
        // Find exercises for synergistic muscles
        for muscle in original.primaryMuscles {
            guard let synergyMuscles = ExerciseIntelligenceEngine.muscleSynergyPairs[muscle] else { continue }
            
            for synergyMuscle in synergyMuscles {
                guard let exercises = muscleToExercises[synergyMuscle.lowercased()] else { continue }
                
                for name in exercises {
                    guard let exercise = exerciseCache[name],
                          exercise.name.lowercased() != original.name.lowercased() else { continue }
                    
                    complementary.append(exercise)
                }
            }
        }
        
        // Also add exercises with complementary movement patterns
        for pattern in original.movementPattern.complementaryPatterns {
            for (name, exercise) in exerciseCache {
                if exercise.movementPattern == pattern && name != exerciseName.lowercased() {
                    complementary.append(exercise)
                }
            }
        }
        
        // Remove duplicates and limit
        let unique = Array(Set(complementary.map { $0.name }))
            .prefix(limit)
            .compactMap { exerciseCache[$0.lowercased()] }
        
        return unique
    }
    
    /// Generate a smart workout based on user preferences
    func generateWorkout(
        targetMuscles: [String],
        availableEquipment: [String],
        skillLevel: String,
        duration: Int, // minutes
        goal: FitnessGoal
    ) -> GeneratedWorkout {
        
        let difficultyConfig = getDifficultyConfig(skillLevel)
        let goalConfig = goal.config
        let normalizedEquipment = Set(availableEquipment.map { ExerciseFilterService.normalizeEquipment($0) })
        
        var selectedExercises: [SelectedExercise] = []
        var musclesCovered: Set<String> = []
        
        // Calculate time per exercise (including rest)
        let avgTimePerExercise = 5 // minutes per exercise on average
        let maxExercises = min(duration / avgTimePerExercise, difficultyConfig.maxTotalExercises)
        
        // Prioritize compound movements first
        if goalConfig.preferCompound || difficultyConfig.preferCompound {
            let compounds = findCompoundExercises(
                for: targetMuscles,
                equipment: normalizedEquipment,
                difficulty: difficultyConfig
            )
            
            for exercise in compounds.prefix(maxExercises / 2) {
                if selectedExercises.count >= maxExercises { break }
                
                let selected = SelectedExercise(
                    exercise: exercise,
                    sets: goalConfig.sets.lowerBound,
                    reps: goalConfig.repRange.lowerBound,
                    restSeconds: Int(Double(goalConfig.restSeconds.lowerBound) * difficultyConfig.restMultiplier)
                )
                selectedExercises.append(selected)
                musclesCovered.formUnion(exercise.primaryMuscles.map { $0.lowercased() })
            }
        }
        
        // Fill remaining slots with isolation/targeted exercises
        let remainingMuscles = Set(targetMuscles.map { $0.lowercased() }).subtracting(musclesCovered)
        
        for muscle in remainingMuscles {
            if selectedExercises.count >= maxExercises { break }
            
            if let exercises = findExercisesForMuscle(
                muscle,
                equipment: normalizedEquipment,
                difficulty: difficultyConfig,
                excluding: Set(selectedExercises.map { $0.exercise.name })
            ).first {
                let selected = SelectedExercise(
                    exercise: exercises,
                    sets: goalConfig.sets.lowerBound,
                    reps: goalConfig.repRange.lowerBound,
                    restSeconds: Int(Double(goalConfig.restSeconds.lowerBound) * difficultyConfig.restMultiplier)
                )
                selectedExercises.append(selected)
            }
        }
        
        // Arrange exercises optimally (compound first, then by muscle group)
        let arranged = arrangeExerciseOrder(selectedExercises, goal: goal)
        
        // Generate supersets if goal supports it
        let finalExercises: [SelectedExercise]
        if goalConfig.supersetFriendly && arranged.count >= 4 {
            finalExercises = createSupersets(from: arranged)
        } else {
            finalExercises = arranged
        }
        
        return GeneratedWorkout(
            exercises: finalExercises,
            estimatedDuration: calculateDuration(finalExercises),
            targetMuscles: targetMuscles,
            difficulty: skillLevel,
            goal: goal
        )
    }
    
    /// Get exercises for a specific split day
    func getExercisesForSplitDay(
        split: WorkoutSplit,
        day: Int,
        equipment: [String],
        skillLevel: String,
        goal: FitnessGoal
    ) -> [ExerciseMetadata] {
        
        let targetMuscles = split.musclesForDay(day)
        let normalizedEquipment = Set(equipment.map { ExerciseFilterService.normalizeEquipment($0) })
        let difficultyConfig = getDifficultyConfig(skillLevel)
        
        var exercises: [ExerciseMetadata] = []
        
        for muscle in targetMuscles {
            let muscleExercises = findExercisesForMuscle(
                muscle,
                equipment: normalizedEquipment,
                difficulty: difficultyConfig,
                excluding: Set(exercises.map { $0.name })
            )
            
            let count = min(difficultyConfig.maxExercisesPerMuscle, muscleExercises.count)
            exercises.append(contentsOf: muscleExercises.prefix(count))
        }
        
        return exercises
    }
    
    // MARK: - Workout Split Definitions
    
    enum WorkoutSplit {
        case pushPullLegs       // 6 day
        case upperLower         // 4 day
        case fullBody           // 3 day
        case broSplit           // 5 day (chest, back, shoulders, arms, legs)
        case pushPull           // 4 day
        
        var daysPerWeek: Int {
            switch self {
            case .pushPullLegs: return 6
            case .upperLower: return 4
            case .fullBody: return 3
            case .broSplit: return 5
            case .pushPull: return 4
            }
        }
        
        func musclesForDay(_ day: Int) -> [String] {
            switch self {
            case .pushPullLegs:
                switch day % 3 {
                case 0: return ["Chest", "Triceps", "Front Delts", "Side Delts"] // Push
                case 1: return ["Back", "Biceps", "Rear Delts"] // Pull
                case 2: return ["Quads", "Hamstrings", "Glutes", "Calves"] // Legs
                default: return []
                }
                
            case .upperLower:
                switch day % 2 {
                case 0: return ["Chest", "Back", "Shoulders", "Biceps", "Triceps"] // Upper
                case 1: return ["Quads", "Hamstrings", "Glutes", "Calves", "Abs"] // Lower
                default: return []
                }
                
            case .fullBody:
                return ["Chest", "Back", "Legs", "Shoulders", "Abs"]
                
            case .broSplit:
                switch day % 5 {
                case 0: return ["Chest"]
                case 1: return ["Back"]
                case 2: return ["Shoulders"]
                case 3: return ["Biceps", "Triceps"]
                case 4: return ["Quads", "Hamstrings", "Glutes", "Calves"]
                default: return []
                }
                
            case .pushPull:
                switch day % 2 {
                case 0: return ["Chest", "Shoulders", "Triceps"] // Push
                case 1: return ["Back", "Biceps", "Rear Delts"] // Pull
                default: return []
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func getDifficultyConfig(_ level: String) -> DifficultyLevel {
        switch level.lowercased() {
        case "beginner": return DifficultyConfig.beginner
        case "advanced": return DifficultyConfig.advanced
        default: return DifficultyConfig.intermediate
        }
    }
    
    private func determineMovementPattern(name: String, category: String, primaryMuscles: [String]) -> MovementPattern {
        let lowercaseName = name.lowercased()
        let lowercaseCategory = category.lowercased()
        
        if pushKeywords.contains(where: { lowercaseName.contains($0) }) { return .push }
        if pullKeywords.contains(where: { lowercaseName.contains($0) }) { return .pull }
        if squatKeywords.contains(where: { lowercaseName.contains($0) }) { return .squat }
        if hingeKeywords.contains(where: { lowercaseName.contains($0) }) { return .hinge }
        if coreKeywords.contains(where: { lowercaseName.contains($0) }) { return .plank }
        
        // Infer from category
        if lowercaseCategory.contains("chest") { return .push }
        if lowercaseCategory.contains("back") { return .pull }
        if lowercaseCategory.contains("leg") { return .squat }
        if lowercaseCategory.contains("core") || lowercaseCategory.contains("abs") { return .plank }
        if lowercaseCategory.contains("shoulder") { return .push }
        if lowercaseCategory.contains("arm") { return .isolation }
        
        return .isolation
    }
    
    private func determineIfCompound(primaryMuscles: [String], secondaryMuscles: [String]) -> Bool {
        // Compound exercises typically work multiple muscle groups
        return primaryMuscles.count + secondaryMuscles.count >= 3
    }
    
    private func calculateDifficulty(_ exercise: ExerciseDTO) -> Int {
        let name = exercise.name.lowercased()
        
        // Complex movements are harder
        if name.contains("olympic") || name.contains("snatch") || name.contains("clean") { return 9 }
        if name.contains("pistol") || name.contains("muscle-up") { return 8 }
        if name.contains("deadlift") || name.contains("squat") { return 7 }
        if name.contains("press") || name.contains("row") { return 5 }
        if name.contains("curl") || name.contains("extension") { return 3 }
        if name.contains("stretch") { return 2 }
        
        return 5 // Default medium difficulty
    }
    
    private func findCompoundExercises(
        for muscles: [String],
        equipment: Set<String>,
        difficulty: DifficultyLevel
    ) -> [ExerciseMetadata] {
        
        var results: [ExerciseMetadata] = []
        
        for (_, exercise) in exerciseCache {
            guard exercise.isCompound,
                  equipment.contains(exercise.equipment) || equipment.contains("Bodyweight") else { continue }
            
            // Check if exercise targets any of our target muscles
            let exerciseMuscles = Set(exercise.primaryMuscles.map { $0.lowercased() })
            let targetMuscles = Set(muscles.map { $0.lowercased() })
            
            if !exerciseMuscles.isDisjoint(with: targetMuscles) {
                results.append(exercise)
            }
        }
        
        // Sort by difficulty appropriateness
        return results.sorted { a, b in
            abs(a.difficulty - 5) < abs(b.difficulty - 5) // Prefer medium difficulty
        }
    }
    
    private func findExercisesForMuscle(
        _ muscle: String,
        equipment: Set<String>,
        difficulty: DifficultyLevel,
        excluding: Set<String>
    ) -> [ExerciseMetadata] {
        
        guard let exerciseNames = muscleToExercises[muscle.lowercased()] else { return [] }
        
        var results: [ExerciseMetadata] = []
        
        for name in exerciseNames {
            guard let exercise = exerciseCache[name],
                  !excluding.contains(exercise.name),
                  equipment.contains(exercise.equipment) || equipment.contains("Bodyweight") else { continue }
            
            results.append(exercise)
        }
        
        // Sort by equipment preference and difficulty
        return results.sorted { a, b in
            let aEquipIndex = difficulty.preferredEquipment.firstIndex(of: a.equipment) ?? 999
            let bEquipIndex = difficulty.preferredEquipment.firstIndex(of: b.equipment) ?? 999
            
            if aEquipIndex != bEquipIndex {
                return aEquipIndex < bEquipIndex
            }
            
            return abs(a.difficulty - 5) < abs(b.difficulty - 5)
        }
    }
    
    private func arrangeExerciseOrder(_ exercises: [SelectedExercise], goal: FitnessGoal) -> [SelectedExercise] {
        // Compound movements first, then isolations
        // Larger muscle groups before smaller
        return exercises.sorted { a, b in
            if a.exercise.isCompound && !b.exercise.isCompound { return true }
            if !a.exercise.isCompound && b.exercise.isCompound { return false }
            return a.exercise.difficulty > b.exercise.difficulty
        }
    }
    
    private func createSupersets(from exercises: [SelectedExercise]) -> [SelectedExercise] {
        // Pair antagonist muscles together for supersets
        var paired = exercises
        
        for i in stride(from: 0, to: exercises.count - 1, by: 2) {
            var first = paired[i]
            first.supersetWith = paired[i + 1].exercise.name
            paired[i] = first
        }
        
        return paired
    }
    
    private func calculateDuration(_ exercises: [SelectedExercise]) -> Int {
        var total = 0
        for exercise in exercises {
            let setTime = 45 // seconds per set
            let exerciseTime = (exercise.sets * setTime) + (exercise.sets * exercise.restSeconds)
            total += exerciseTime / 60
        }
        return total
    }
}

// MARK: - Supporting Types

struct SelectedExercise {
    let exercise: ExerciseIntelligenceEngine.ExerciseMetadata
    var sets: Int
    var reps: Int
    var restSeconds: Int
    var supersetWith: String? = nil
}

struct GeneratedWorkout {
    let exercises: [SelectedExercise]
    let estimatedDuration: Int
    let targetMuscles: [String]
    let difficulty: String
    let goal: ExerciseIntelligenceEngine.FitnessGoal
}

// MARK: - Hashable Conformance

extension ExerciseIntelligenceEngine.ExerciseMetadata: Hashable {
    static func == (lhs: ExerciseIntelligenceEngine.ExerciseMetadata, rhs: ExerciseIntelligenceEngine.ExerciseMetadata) -> Bool {
        lhs.name == rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

