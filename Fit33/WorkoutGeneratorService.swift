import Foundation
import Supabase

struct GeneratedExercise: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let primaryBodyRegion: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let equipment: String
    let difficulty: String
    let videoUrl: String?
    let instructions: String?
    var score: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, equipment, difficulty, instructions, score
        case primaryBodyRegion = "primary_body_region"
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
        case videoUrl = "video_url"
    }
    
    static func == (lhs: GeneratedExercise, rhs: GeneratedExercise) -> Bool {
        lhs.id == rhs.id
    }
    
    // Convert from local ExerciseData
    init(from exerciseData: ExerciseData) {
        self.id = UUID().uuidString
        self.name = exerciseData.name
        self.category = exerciseData.category
        self.primaryBodyRegion = exerciseData.primaryBodyRegion
        self.primaryMuscle = exerciseData.primaryMuscle
        self.secondaryMuscles = exerciseData.secondaryMuscles
        self.equipment = exerciseData.equipment
        self.difficulty = "Intermediate"
        self.videoUrl = nil
        self.instructions = exerciseData.instructions
        self.score = nil
    }
    
    // Direct initializer for Core Data exercises
    init(
        id: String,
        name: String,
        category: String,
        primaryBodyRegion: String,
        primaryMuscle: String,
        secondaryMuscles: [String],
        equipment: String,
        difficulty: String,
        videoUrl: String?,
        instructions: String?
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.primaryBodyRegion = primaryBodyRegion
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.difficulty = difficulty
        self.videoUrl = videoUrl
        self.instructions = instructions
        self.score = nil
    }
}

struct WorkoutGenerationRequest: Codable {
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]
    let count: Int
    let excludeExerciseIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case primaryMuscles, secondaryMuscles, equipment, count
        case excludeExerciseIds = "excludeExerciseIds"
    }
}

struct WorkoutGenerationResponse: Codable {
    let exercises: [GeneratedExercise]
    let totalAvailable: Int
    
    enum CodingKeys: String, CodingKey {
        case exercises
        case totalAvailable = "total_available"
    }
}

@MainActor
class WorkoutGeneratorService: ObservableObject {
    static let shared = WorkoutGeneratorService()
    
    /// Get recommended exercise count based on workout duration
    /// Rules:
    /// - 15-20 min: 4 exercises
    /// - 25-35 min: 5 exercises
    /// - 40 min: 6 exercises (cap for "quick" workouts)
    /// - 45-50 min: 7 exercises
    /// - 60+ min: 8 exercises (hard cap)
    static func exerciseCountForDuration(_ durationMinutes: Int) -> Int {
        if durationMinutes <= 20 {
            return 4
        } else if durationMinutes <= 35 {
            return 5
        } else if durationMinutes <= 40 {
            return 6  // Cap for "quick" workouts
        } else if durationMinutes <= 50 {
            return 7
        } else {
            return 8  // Hard cap
        }
    }
    
    private let supabase = SupabaseClient(
        supabaseURL: URL(string: "https://ehooeghabzefgoqzugrc.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"
    )
    
    @Published var isGenerating = false
    @Published var generatedExercises: [GeneratedExercise] = []
    @Published var error: String?
    
    func generateWorkout(
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: [String],
        count: Int = 5,
        excludeExerciseIds: [String] = []
    ) async throws -> [GeneratedExercise] {
        let startTime = Date()
        isGenerating = true
        error = nil
        
        // Log workout generation start
        SessionLogManager.shared.logWorkoutGeneration(
            type: "AutoGen",
            muscleGroups: primaryMuscles + secondaryMuscles,
            equipment: equipment,
            duration: count * 8 // Estimate ~8 min per exercise
        )
        
        defer {
            isGenerating = false
        }
        
        // ALL user-selected muscles are targets - combine them
        let allTargetMuscles = primaryMuscles + secondaryMuscles
        
        // Get current user for logging
        let user = UserManager.shared.currentUser
        
        #if DEBUG
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║            🎯 AUTO-GEN WORKOUT GENERATION                    ║")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ USER PROFILE (from database):")
        print("║   • Name: \(user?.name ?? "Unknown")")
        print("║   • Goal: \(user?.fitnessGoal ?? "Not set")")
        print("║   • Experience: \(user?.experienceLevel ?? "Not set")")
        print("║   • Workout Environment: \(user?.workoutEnvironment ?? "Not set")")
        print("║   • Stored Equipment: \(user?.getEquipment()?.joined(separator: ", ") ?? "None")")
        print("║   • Available Days: \(user?.availableDays ?? 0)")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ WORKOUT REQUEST:")
        print("║   • Primary Muscles: \(primaryMuscles.joined(separator: ", "))")
        print("║   • Secondary Muscles: \(secondaryMuscles.joined(separator: ", "))")
        print("║   • Equipment Filter: \(equipment.joined(separator: ", "))")
        print("║   • Exercise Count: \(count)")
        print("╠══════════════════════════════════════════════════════════════╣")
        #endif
        
        // 🚀 SIMPLE & CLEAN: Generate exercises that hit user's selected muscles
        // Exercises hitting MULTIPLE targets get bonus (compound value)
        
        // Convert excludeExerciseIds to exercise names for filtering
        var excludeNames: Set<String> = []
        if !excludeExerciseIds.isEmpty {
            let allExercises = ExerciseLibraryService.shared.getAllExercises()
            for exerciseId in excludeExerciseIds {
                if let exercise = allExercises.first(where: { $0.id?.uuidString == exerciseId }),
                   let name = exercise.name {
                    excludeNames.insert(name)
                }
            }
            #if DEBUG
            print("║ 🚫 Excluding \(excludeNames.count) previously used exercises")
            #endif
        }
        
        let coreDataExercises = await generateFromCoreData(
            targetMuscles: allTargetMuscles,
            equipment: equipment,
            count: count,
            isPrimary: true,
            excludeNames: excludeNames
        )
        
        if !coreDataExercises.isEmpty {
            let duration = Date().timeIntervalSince(startTime)
            #if DEBUG
            print("║ GENERATION COMPLETE:")
            print("║   ✅ Generated \(coreDataExercises.count) exercises")
            for (index, ex) in coreDataExercises.enumerated() {
                print("║   \(index + 1). \(ex.name) [\(ex.equipment ?? "Bodyweight")]")
            }
            print("╚══════════════════════════════════════════════════════════════╝")
            #endif
            
            // Log generation complete
            SessionLogManager.shared.logWorkoutGenerationComplete(
                exerciseCount: coreDataExercises.count,
                duration: duration
            )
            
            generatedExercises = coreDataExercises
            return coreDataExercises
        }
        
        // Fallback to old local generation
        let exercises = generateLocalWorkout(
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            equipment: equipment,
            count: count,
            excludeExerciseIds: excludeExerciseIds
        )
        
        if !exercises.isEmpty {
            #if DEBUG
            print("✅ Generated \(exercises.count) exercises from fallback")
            #endif
            generatedExercises = exercises
            return exercises
        }
        
        // Final fallback to edge function
        do {
            let request = WorkoutGenerationRequest(
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles,
                equipment: equipment,
                count: count,
                excludeExerciseIds: excludeExerciseIds
            )
            
            let response: WorkoutGenerationResponse = try await supabase.functions
                .invoke(
                    "workout-generator",
                    options: FunctionInvokeOptions(
                        body: request
                    )
                )
            
            print("✅ Generated \(response.exercises.count) exercises from cloud")
            generatedExercises = response.exercises
            
            return response.exercises
            
        } catch {
            print("❌ Cloud generation failed: \(error)")
            self.error = "Failed to generate workout: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Local Workout Generation
    
    private func generateLocalWorkout(
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: [String],
        count: Int,
        excludeExerciseIds: [String]
    ) -> [GeneratedExercise] {
        let allExercises = ComprehensiveExerciseDatabase.exercises
        
        // Normalize inputs for matching
        let normalizedPrimaries = Set(primaryMuscles.map { $0.lowercased() })
        let normalizedSecondaries = Set(secondaryMuscles.map { $0.lowercased() })
        let normalizedEquipment = Set(equipment.map { $0.lowercased() })
        
        // Map user-friendly names to database category values
        let categoryMapping: [String: String] = [
            "chest": "chest",
            "back": "back",
            "shoulders": "shoulders",
            "arms": "arms",
            "biceps": "arms",
            "triceps": "arms",
            "legs": "legs",
            "quadriceps": "legs",
            "hamstrings": "legs",
            "glutes": "legs",
            "calves": "legs",
            "core": "core",
            "abs": "core",
            "obliques": "core"
        ]
        
        // Map to specific muscle targets within a category
        let specificMuscleMapping: [String: [String]] = [
            "chest": ["chest", "upper chest", "mid chest", "lower chest", "pectorals"],
            "back": ["back", "lats", "upper back", "middle back", "lower back", "traps", "rhomboids"],
            "shoulders": ["shoulders", "front delts", "side delts", "rear delts", "deltoids", "anterior deltoid", "lateral deltoid", "posterior deltoid"],
            "arms": ["biceps", "triceps", "forearms", "brachialis"],
            "biceps": ["biceps", "brachialis"],
            "triceps": ["triceps"],
            "legs": ["quadriceps", "hamstrings", "glutes", "calves", "hip flexors", "adductors", "abductors"],
            "core": ["abs", "obliques", "abdominals", "lower abs", "upper abs", "transverse abdominis"]
        ]
        
        // Get target categories from user's primary muscle selection
        var targetCategories: Set<String> = []
        var targetMuscles: Set<String> = []
        
        for muscle in normalizedPrimaries {
            if let category = categoryMapping[muscle] {
                targetCategories.insert(category)
            }
            if let specificMuscles = specificMuscleMapping[muscle] {
                targetMuscles.formUnion(specificMuscles)
            }
            targetMuscles.insert(muscle)
        }
        
        #if DEBUG
        print("🔍 Searching for exercises matching:")
        print("   User selected primaries: \(normalizedPrimaries)")
        print("   Target categories: \(targetCategories)")
        print("   Target muscles: \(targetMuscles)")
        print("   Equipment: \(normalizedEquipment)")
        #endif
        
        // STRICT Filter - Only include exercises that match the user's selected muscles
        var matchingExercises = allExercises.filter { exercise in
            let exerciseCategory = exercise.category.lowercased()
            let exercisePrimaryMuscle = exercise.primaryMuscle.lowercased()
            let exerciseName = exercise.name.lowercased()
            
            // STRICT: Exercise category must match one of the target categories
            let matchesCategory = targetCategories.isEmpty || targetCategories.contains(exerciseCategory)
            
            // Additional check: make sure the exercise name doesn't indicate a different muscle group
            // e.g., "Triceps Dip" should not be included in a chest-only workout
            let conflictingMuscles = ["triceps", "biceps", "shoulder", "leg", "squat", "curl", "deadlift", "row"]
            var hasConflict = false
            
            if !normalizedPrimaries.contains("arms") && !normalizedPrimaries.contains("triceps") {
                if exerciseName.contains("tricep") {
                    hasConflict = true
                }
            }
            if !normalizedPrimaries.contains("arms") && !normalizedPrimaries.contains("biceps") {
                if exerciseName.contains("bicep") || exerciseName.contains("curl") {
                    hasConflict = true
                }
            }
            if !normalizedPrimaries.contains("legs") {
                if exerciseName.contains("squat") || exerciseName.contains("leg ") || exerciseName.contains("lunge") {
                    hasConflict = true
                }
            }
            if !normalizedPrimaries.contains("back") {
                if exerciseName.contains(" row") || exerciseName.contains("deadlift") || exerciseName.contains("lat ") {
                    hasConflict = true
                }
            }
            
            // Check equipment
            let exerciseEquipment = exercise.equipment.lowercased()
            let matchesEquipment = normalizedEquipment.isEmpty ||
                normalizedEquipment.contains(exerciseEquipment) ||
                normalizedEquipment.contains { exerciseEquipment.contains($0) } ||
                (normalizedEquipment.contains("bodyweight") && exerciseEquipment == "bodyweight")
            
            return matchesCategory && matchesEquipment && !hasConflict
        }
        
        #if DEBUG
        print("   Found \(matchingExercises.count) strictly matching exercises")
        #endif
        
        // If very few matches, slightly broaden but still respect category
        if matchingExercises.count < count {
            #if DEBUG
            print("⚠️ Few strict matches, including more exercises from same categories...")
            #endif
            let additionalExercises = allExercises.filter { exercise in
                let exerciseCategory = exercise.category.lowercased()
                let exerciseEquipment = exercise.equipment.lowercased()
                
                let matchesCategory = targetCategories.contains(exerciseCategory)
                let matchesEquipment = normalizedEquipment.isEmpty ||
                    normalizedEquipment.contains(exerciseEquipment) ||
                    exerciseEquipment == "bodyweight"
                
                // Don't include if already in matching
                let notAlreadyIncluded = !matchingExercises.contains { $0.name == exercise.name }
                
                return matchesCategory && matchesEquipment && notAlreadyIncluded
            }
            matchingExercises.append(contentsOf: additionalExercises)
            #if DEBUG
            print("   Now have \(matchingExercises.count) exercises")
            #endif
        }
        
        // Shuffle for variety
        var selectedExercises = matchingExercises.shuffled()
        
        // Try to get variety - distribute across different specific muscles within the category
        var result: [ExerciseData] = []
        var usedMuscles: Set<String> = []
        var usedNames: Set<String> = []
        
        // First pass: get variety across different specific muscles
        for exercise in selectedExercises {
            guard result.count < count else { break }
            let muscle = exercise.primaryMuscle.lowercased()
            if !usedMuscles.contains(muscle) && !usedNames.contains(exercise.name) {
                result.append(exercise)
                usedMuscles.insert(muscle)
                usedNames.insert(exercise.name)
            }
        }
        
        // Second pass: fill remaining slots with different exercises
        for exercise in selectedExercises {
            guard result.count < count else { break }
            if !usedNames.contains(exercise.name) {
                result.append(exercise)
                usedNames.insert(exercise.name)
            }
        }
        
        #if DEBUG
        print("✅ Selected \(result.count) exercises for workout")
        for (index, exercise) in result.enumerated() {
            print("   \(index + 1). \(exercise.name) - \(exercise.category) - \(exercise.primaryMuscle)")
        }
        #endif
        
        // 🎯 Apply smart exercise ordering
        let generated = result.map { GeneratedExercise(from: $0) }
        return sortExercisesStrategically(generated)
    }
    
    func generateSurpriseWorkout(equipment: [String] = [], count: Int = 5) async throws -> [GeneratedExercise] {
        // Get user profile for personalization
        let userGoal = UserManager.shared.currentUser?.fitnessGoal?.lowercased() ?? "build muscle"
        let userLevel = UserManager.shared.currentUser?.experienceLevel ?? "Intermediate"
        let userEquipment = equipment.isEmpty 
            ? ((UserManager.shared.currentUser?.equipment as? [String]) ?? ["Barbell", "Dumbbells", "Bodyweight", "Cables"])
            : equipment
        
        // Smart workout splits based on user goal
        let workoutSplits: [(name: String, muscles: [String], forGoals: [String])] = [
            // Muscle building splits
            ("Push Day", ["Chest", "Shoulders", "Triceps"], ["build muscle", "get stronger"]),
            ("Pull Day", ["Back", "Biceps"], ["build muscle", "get stronger"]),
            ("Leg Day", ["Quads", "Hamstrings", "Glutes", "Calves"], ["build muscle", "get stronger"]),
            ("Chest & Triceps", ["Chest", "Triceps"], ["build muscle"]),
            ("Back & Biceps", ["Back", "Biceps"], ["build muscle"]),
            ("Shoulders & Arms", ["Shoulders", "Biceps", "Triceps"], ["build muscle"]),
            
            // Strength splits
            ("Upper Body Strength", ["Chest", "Back", "Shoulders"], ["get stronger"]),
            ("Lower Body Strength", ["Quads", "Hamstrings", "Glutes"], ["get stronger"]),
            
            // Fat loss / cardio splits
            ("HIIT Full Body", ["Full Body", "Cardio"], ["lose fat", "lose weight", "improve endurance"]),
            ("Cardio Blast", ["Cardio", "Plyometrics"], ["lose fat", "lose weight"]),
            ("Metabolic Circuit", ["Full Body", "Core"], ["lose fat", "lose weight"]),
            
            // General fitness
            ("Full Body", ["Chest", "Back", "Legs", "Shoulders"], ["general fitness", "stay active"]),
            ("Core & Functional", ["Core", "Abs", "Obliques"], ["general fitness", "improve flexibility"]),
            
            // Flexibility
            ("Flexibility & Mobility", ["Stretching"], ["improve flexibility", "general fitness"]),
            
            // Universal (good for anyone)
            ("Upper Body", ["Chest", "Back", "Shoulders"], ["build muscle", "get stronger", "general fitness"]),
            ("Chest & Back Superset", ["Chest", "Back"], ["build muscle", "lose fat"])
        ]
        
        // Filter splits based on user goal
        var relevantSplits = workoutSplits.filter { split in
            split.forGoals.contains { userGoal.contains($0) }
        }
        
        // If no matches, use all splits
        if relevantSplits.isEmpty {
            relevantSplits = workoutSplits
        }
        
        // Randomly select one of the relevant splits
        let selectedSplit = relevantSplits.randomElement() ?? workoutSplits[0]
        
        #if DEBUG
        print("🎲 Surprise workout (Goal-Optimized):")
        print("   User goal: \(userGoal)")
        print("   User level: \(userLevel)")
        print("   Selected split: \(selectedSplit.name)")
        print("   Muscles: \(selectedSplit.muscles)")
        print("   Equipment: \(userEquipment)")
        #endif
        
        // Use the smart generation with user context
        let coreDataExercises = await generateFromCoreData(
            targetMuscles: selectedSplit.muscles,
            equipment: userEquipment,
            count: count
        )
        
        if !coreDataExercises.isEmpty {
            generatedExercises = coreDataExercises
            return coreDataExercises
        }
        
        // Fallback to standard generation
        return try await generateWorkout(
            primaryMuscles: selectedSplit.muscles,
            secondaryMuscles: [],
            equipment: userEquipment,
            count: count
        )
    }
    
    // MARK: - Smart Exercise Generation from 7000+ Library
    
    private func generateFromCoreData(
        targetMuscles: [String],
        equipment: [String],
        count: Int,
        isPrimary: Bool = true,
        excludeNames: Set<String> = [],
        workoutLocation: ExerciseFilterService.WorkoutLocation = .gym
    ) async -> [GeneratedExercise] {
        // Get exercises from the new 7000+ library
        var allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        // Filter out already selected exercises
        if !excludeNames.isEmpty {
            allExercises = allExercises.filter { exercise in
                guard let name = exercise.name else { return true }
                return !excludeNames.contains(name)
            }
        }
        
        // 🛡️ CRITICAL: Filter exercises based on user's injuries/limitations
        let preFilterCount = allExercises.count
        allExercises = LimitationsService.shared.filterSafeExercises(allExercises)
        let filteredForSafety = preFilterCount - allExercises.count
        
        #if DEBUG
        if filteredForSafety > 0 {
            print("🛡️ [SAFETY] Filtered out \(filteredForSafety) exercises due to user limitations")
        }
        #endif
        
        // 🚫 PRE-FILTER: Remove risky exercises for foundational users
        // This mirrors the Python script's risky exercise filtering
        let foundationalDB = FoundationalExerciseDatabase.shared
        let hasLowerBackIssue = LimitationsService.shared.hasLowerBackLimitation
        
        if restrictToFoundational || userWorkoutCount < 10 {
            let beforeRiskyFilter = allExercises.count
            allExercises = allExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                
                // Pre-filter risky exercises for foundational users
                if foundationalDB.isRiskyExercise(name) {
                    #if DEBUG
                    print("   🚫 [RISKY] Pre-filtering '\(exercise.name ?? "")' - risky for foundational user")
                    #endif
                    return false
                }
                return true
            }
            let filteredRisky = beforeRiskyFilter - allExercises.count
            #if DEBUG
            if filteredRisky > 0 {
                print("🚫 [RISKY] Pre-filtered \(filteredRisky) risky exercises for foundational user")
            }
            #endif
        }
        
        // 🚫 PRE-FILTER: Remove lower back stress exercises if user has back issues
        if hasLowerBackIssue {
            let beforeBackFilter = allExercises.count
            allExercises = allExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                
                if foundationalDB.isLowerBackStressExercise(name) {
                    #if DEBUG
                    print("   🚫 [BACK SAFETY] Pre-filtering '\(exercise.name ?? "")' - stresses lower back")
                    #endif
                    return false
                }
                return true
            }
            let filteredBack = beforeBackFilter - allExercises.count
            #if DEBUG
            if filteredBack > 0 {
                print("🚫 [BACK SAFETY] Pre-filtered \(filteredBack) lower back stress exercises")
            }
            #endif
        }
        
        guard !allExercises.isEmpty else {
            print("⚠️ No exercises in Core Data library (or all filtered for safety)")
            return []
        }
        
        // Get user's favorites for prioritization
        let favorites = Set(allExercises.filter { $0.isFavorite }.compactMap { $0.name?.lowercased() })
        
        // 🧠 Get learned user preferences
        let learningEngine = await UserBehaviorLearningEngine.shared
        let hasLearnedPreferences = await learningEngine.userPreferences != nil
        
        // 🌟 Get progressive unlock status for foundational exercise prioritization
        let progressiveUnlock = await ProgressiveExerciseUnlockService.shared
        let userWorkoutCount = progressiveUnlock.workoutCount
        let currentTier = progressiveUnlock.currentTier
        let restrictToFoundational = progressiveUnlock.shouldRestrictToFoundational
        let varietyPercentage = progressiveUnlock.varietyPercentage
        
        #if DEBUG
        if hasLearnedPreferences {
            print("🧠 [SMART GEN] Using learned user preferences for personalized selection")
        }
        print("🌟 [PROGRESSIVE UNLOCK] User workout count: \(userWorkoutCount), Tier: \(currentTier.displayName)")
        print("🌟 [PROGRESSIVE UNLOCK] Restrict to foundational: \(restrictToFoundational), Variety: \(Int(varietyPercentage * 100))%")
        #endif
        
        // Get FULL user profile for smart filtering
        let userLevel = UserManager.shared.currentUser?.experienceLevel ?? "Intermediate"
        let userGoal = UserManager.shared.currentUser?.fitnessGoal ?? "Build Muscle"
        let userGender = UserManager.shared.currentUser?.gender?.lowercased() ?? "male"
        let preferredGender = userGender.contains("female") ? "female" : "male"
        let userEnvironment = UserManager.shared.currentUser?.workoutEnvironment ?? "Hybrid"
        let userWeight = Double(UserManager.shared.currentUser?.weight ?? 170)  // in lbs or kg
        let userAge = Int(UserManager.shared.currentUser?.age ?? 30)
        
        // Convert weight to lbs if needed (assuming kg if < 100)
        let userWeightLbs: Double = userWeight < 100.0 ? userWeight * 2.2 : userWeight
        
        // Muscle group expansion - PRECISE mappings, no overlaps
        // General terms expand to specific ones; specific terms stay specific
        let muscleGroupExpansion: [String: [String]] = [
            // General -> Specific
            "arms": ["arms", "biceps", "triceps", "forearms"],
            "shoulders": ["shoulders", "front delts", "rear delts", "side delts", "delts"],
            "legs": ["legs", "quads", "hamstrings", "glutes", "calves", "adductors", "abductors"],
            "back": ["back", "lats", "upper back", "lower back", "traps", "rhomboids"],
            "chest": ["chest", "upper chest", "lower chest", "pecs"],
            "core": ["core", "abs", "obliques", "lower abs"],
            // Specific muscles - no cross-expansion
            "glutes": ["glutes"],
            "quads": ["quads", "quadriceps"],
            "hamstrings": ["hamstrings"],
            "lats": ["lats"],
            "biceps": ["biceps"],
            "triceps": ["triceps"],
            "abs": ["abs", "lower abs"],
            "upper chest": ["upper chest"],
            "lower chest": ["lower chest"],
            "upper back": ["upper back"],
            "lower back": ["lower back"],
            "front delts": ["front delts"],
            "rear delts": ["rear delts"],
            "calves": ["calves"],
        ]
        
        // Expand target muscles to include sub-muscles
        var expandedMuscles = Set(targetMuscles.map { $0.lowercased() })
        for target in targetMuscles.map({ $0.lowercased() }) {
            if let subMuscles = muscleGroupExpansion[target] {
                expandedMuscles.formUnion(subMuscles)
            }
        }
        
        let normalizedMuscles = expandedMuscles
        let normalizedEquipment = Set(equipment.map { ExerciseFilterService.normalizeEquipment($0) })
        
        #if DEBUG
        print("🧠 [SMART GEN] Starting intelligent workout generation:")
        print("   Target muscles: \(targetMuscles)")
        print("   Expanded to: \(normalizedMuscles)")
        print("   User equipment: \(normalizedEquipment)")
        print("   User level: \(userLevel)")
        print("   User goal: \(userGoal)")
        print("   👤 User gender: \(preferredGender.uppercased())")
        print("   ⚖️ User weight: \(Int(userWeightLbs))lbs, Age: \(userAge)")
        print("   Favorite exercises: \(favorites.count)")
        print("   Total library: \(allExercises.count)")
        #endif
        
        // 🧠 SMART PROFILE-BASED EXCLUSION KEYWORDS
        // Heavy users (>250lbs) cannot do bodyweight lifting exercises
        let bodyweightLiftingKeywords = ["pull up", "pullup", "chin up", "chinup", "muscle up", 
                                          "dip", "pistol squat", "handstand", "l-sit", "planche",
                                          "front lever", "back lever", "human flag", "one arm push up"]
        
        // Advanced exercises not for beginners
        let advancedKeywords = ["clean", "snatch", "jerk", "olympic", "muscle up", 
                                "pistol squat", "dragon flag", "front lever", "back lever",
                                "planche", "handstand push up", "deficit deadlift"]
        
        // High impact exercises (not for seniors 60+ or heavy users)
        let highImpactKeywords = ["jump", "box jump", "broad jump", "depth jump", "burpee",
                                   "plyometric", "plyo", "tuck jump", "star jump", "jump squat",
                                   "jump lunge", "sprint"]
        
        // Enhanced category mapping with body region matching
        let categoryMapping: [String: [String]] = [
            "chest": ["chest"],
            "back": ["back"],
            "shoulders": ["shoulders", "shoulder"],
            "arms": ["arms", "upper arms", "forearms"],
            "biceps": ["arms", "upper arms"],
            "triceps": ["arms", "upper arms"],
            "legs": ["legs", "thighs", "hips", "calves"],
            "quads": ["legs", "thighs"],
            "hamstrings": ["legs", "thighs", "hips"],
            "glutes": ["legs", "hips"],
            "calves": ["legs", "calves"],
            "core": ["core", "waist"],
            "abs": ["core", "waist"],
            "obliques": ["core", "waist"],
            "lower back": ["back"],
            "full body": ["full body", "plyometrics", "cardio"],
            "stretching": ["stretching"],
            "cardio": ["cardio", "plyometrics", "full body"]
        ]
        
        // Build target categories
        var targetCategories: Set<String> = []
        for muscle in normalizedMuscles {
            if let cats = categoryMapping[muscle] {
                targetCategories.formUnion(cats)
            }
            // Also add the muscle itself as a potential match
            targetCategories.insert(muscle)
        }
        
        // Get the gender video cache for gender-based filtering
        let genderVideoCache = VideoStreamingService.shared.genderVideoCache
        let preferredVideoGender: VideoStreamingService.VideoGender = preferredGender == "female" ? .female : .male
        
        // STRICT filtering - use ACTUAL database fields, not name matching
        #if DEBUG
        var matchCount = 0
        var equipmentFailCount = 0
        var muscleFailCount = 0
        var profileFailCount = 0  // Exercises filtered due to user profile (weight, age, experience)
        #endif
        
        var matchingExercises = allExercises.filter { exercise in
            let exerciseCategory = exercise.category?.lowercased() ?? ""
            let exerciseEquipmentRaw = exercise.equipment?.lowercased() ?? ""
            let muscleGroups = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
            
            // STRICT Equipment check using centralized ExerciseFilterService
            // Handles new equipment format (e.g., "Dumbbells, Incline Bench", "Cable Machine", "Lever Machine")
            let isBodyweightExercise = exerciseEquipmentRaw.isEmpty || exerciseEquipmentRaw == "bodyweight"
            
            // Use centralized equipment matching that handles the new database format
            let matchesEquipment: Bool
            if normalizedEquipment.isEmpty {
                // No equipment filter = include everything
                matchesEquipment = true
            } else if isBodyweightExercise {
                // Bodyweight exercise - ONLY include if user explicitly selected "Bodyweight"
                matchesEquipment = normalizedEquipment.contains(where: { 
                    $0.lowercased().contains("bodyweight") || $0.lowercased().contains("body")
                })
            } else {
                // Use centralized equipment matching for new database format
                matchesEquipment = ExerciseFilterService.userHasRequiredEquipment(
                    exerciseEquipment: exercise.equipment,
                    exerciseName: exercise.name,
                    userEquipment: Array(normalizedEquipment)
                )
            }
            
            guard matchesEquipment else {
                #if DEBUG
                equipmentFailCount += 1
                // Log when unusual equipment is missing (for debugging)
                if exerciseEquipmentRaw.contains("wall") || exerciseEquipmentRaw.contains("rings") || 
                   exerciseEquipmentRaw.contains("partner") || exerciseEquipmentRaw.contains("tire") {
                    print("   🚫 [EQUIPMENT] Excluded '\(exercise.name ?? "")': requires \(exerciseEquipmentRaw)")
                }
                #endif
                return false
            }
            
            // 🚫 LOCATION APPROPRIATENESS CHECK - Filter out improvised/home equipment for gym users
            // e.g., No "Chair" exercises at the gym when user has machines, cables, etc.
            let workoutLocation: ExerciseFilterService.WorkoutLocation = {
                switch userEnvironment.lowercased() {
                case "gym": return .gym
                case "home": return .home
                case "outdoor", "outdoors": return .outdoor
                default: return .hybrid
                }
            }()
            
            let isAppropriateForLocation = ExerciseFilterService.isExerciseAppropriateForLocation(
                exerciseName: exercise.name ?? "",
                equipment: exerciseEquipmentRaw,
                location: workoutLocation
            )
            
            guard isAppropriateForLocation else {
                #if DEBUG
                print("   🚫 [LOCATION] Excluded '\(exercise.name ?? "")': not appropriate for \(userEnvironment)")
                #endif
                return false
            }
            
            // STRICT Muscle match - use actual muscleGroups AND secondaryMuscles fields from database
            let secondaryMuscles = (exercise.secondaryMuscles as? [String])?.map { $0.lowercased() } ?? []
            let allMuscles = muscleGroups + secondaryMuscles
            let exerciseName = (exercise.name ?? "").lowercased()
            
            // 🎯 PRIMARY MUSCLE MATCHING - Exercise must PRIMARILY target one of user's selected muscles
            // Secondary muscle overlap is fine (e.g., bench press primarily hits chest, works triceps as secondary)
            // This ensures user gets exercises that actually focus on what they selected
            
            let exercisePrimaryMuscle = muscleGroups.first?.lowercased() ?? ""
            let normalizedExercisePrimary = normalizeMuscleName(exercisePrimaryMuscle)
            
            // Check if exercise's PRIMARY muscle matches ANY of user's target muscles
            let primaryMuscleMatchesTarget = normalizedMuscles.contains { target in
                let normalizedTarget = normalizeMuscleName(target)
                return normalizedExercisePrimary == normalizedTarget ||
                       exercisePrimaryMuscle.contains(target) || 
                       target.contains(exercisePrimaryMuscle)
            }
            
            // Also check category as fallback (for exercises where muscle data might be incomplete)
            let categoryMatchesTarget = targetCategories.contains { target in
                exerciseCategory.contains(target) || target.contains(exerciseCategory)
            }
            
            // STRICT: Exercise must primarily target one of user's selected muscles
            // OR match the category (fallback for incomplete data)
            let matchesMuscle = primaryMuscleMatchesTarget || (categoryMatchesTarget && exercisePrimaryMuscle.isEmpty)
            
            // Must match muscle groups as PRIMARY target
            guard matchesMuscle else {
                #if DEBUG
                muscleFailCount += 1
                #endif
                return false
            }
            
            // 🎯 BODY REGION CONSISTENCY - Exclude exercises that don't match workout context
            // Prevents squats from appearing in arm workouts, curls from appearing in leg workouts, etc.
            // (exerciseName already defined above)
            
            // Define body region keywords
            let lowerBodyKeywords = ["squat", "lunge", "deadlift", "leg press", "leg curl", "leg extension",
                                      "hip thrust", "glute bridge", "calf raise", "step up", "box jump",
                                      "romanian deadlift", "sumo", "goblet squat", "split squat",
                                      "hip abduct", "hip adduct", "hamstring curl"]
            let upperBodyKeywords = ["press", "curl", "fly", "pulldown", "row", "push up", "pushup",
                                      "tricep", "bicep", "shoulder", "chest", "lat", "delt"]
            
            // Determine if user is targeting upper or lower body
            let upperBodyTargets = ["chest", "arms", "biceps", "triceps", "shoulders", "back", 
                                    "lats", "pecs", "delts", "forearms", "upper chest", "lower chest"]
            let lowerBodyTargets = ["legs", "quads", "hamstrings", "glutes", "calves", "thighs", "hips"]
            
            let targetingUpperBody = normalizedMuscles.contains { target in
                upperBodyTargets.contains { upper in target.contains(upper) || upper.contains(target) }
            }
            let targetingLowerBody = normalizedMuscles.contains { target in
                lowerBodyTargets.contains { lower in target.contains(lower) || lower.contains(target) }
            }
            
            // If targeting ONLY upper body, exclude clear lower body exercises
            if targetingUpperBody && !targetingLowerBody {
                let isLowerBodyExercise = lowerBodyKeywords.contains { keyword in
                    exerciseName.contains(keyword)
                }
                if isLowerBodyExercise {
                    #if DEBUG
                    print("   🚫 [BODY REGION] Excluding '\(exercise.name ?? "")': lower body exercise in upper body workout")
                    #endif
                    return false
                }
            }
            
            // If targeting ONLY lower body, exclude clear upper body exercises
            if targetingLowerBody && !targetingUpperBody {
                let isUpperBodyExercise = upperBodyKeywords.contains { keyword in
                    exerciseName.contains(keyword)
                }
                if isUpperBodyExercise {
                    #if DEBUG
                    print("   🚫 [BODY REGION] Excluding '\(exercise.name ?? "")': upper body exercise in lower body workout")
                    #endif
                    return false
                }
            }
            
            // 🎯 PRACTICALITY FILTER - Use database score to filter unrealistic exercises
            let dbPracticalityScore = Int(exercise.practicalityScore)
            if dbPracticalityScore > 0 && dbPracticalityScore < 30 {
                // Exclude exercises with very low practicality scores (handstands, weird variations, etc.)
                #if DEBUG
                print("   🚫 [PRACTICALITY] Excluding '\(exercise.name ?? "")': score=\(dbPracticalityScore)")
                #endif
                return false
            }
            
            // 🧠 SMART PROFILE-BASED FILTERING
            // Check if exercise is appropriate for user's weight, age, and experience
            // Note: exerciseName already defined above in body region filter
            
            // Rule 1: Heavy users (>250lbs) cannot do bodyweight lifting exercises
            if userWeightLbs > 250.0 && isBodyweightExercise {
                let isBodyweightLift = bodyweightLiftingKeywords.contains { keyword in
                    exerciseName.contains(keyword)
                }
                if isBodyweightLift {
                    #if DEBUG
                    profileFailCount += 1
                    #endif
                    return false
                }
            }
            
            // Rule 2: Beginners should avoid advanced exercises
            if userLevel.lowercased() == "beginner" {
                let isAdvanced = advancedKeywords.contains { keyword in
                    exerciseName.contains(keyword)
                }
                if isAdvanced {
                    #if DEBUG
                    profileFailCount += 1
                    #endif
                    return false
                }
            }
            
            // Rule 3: Seniors (60+) and heavy users (>280lbs) should avoid high-impact
            if userAge >= 60 || userWeightLbs > 280.0 {
                let isHighImpact = highImpactKeywords.contains { keyword in
                    exerciseName.contains(keyword)
                }
                if isHighImpact {
                    #if DEBUG
                    profileFailCount += 1
                    #endif
                    return false
                }
                
                // Also check workout type
                let workoutType = exercise.workoutType?.lowercased() ?? ""
                if workoutType == "plyometrics" {
                    #if DEBUG
                    profileFailCount += 1
                    #endif
                    return false
                }
            }
            
            // Rule 4: Very heavy users (>300lbs) need primarily seated/machine exercises
            if userWeightLbs > 300.0 && isBodyweightExercise {
                let isSafe = exerciseName.contains("seated") || 
                             exerciseName.contains("lying") || 
                             exerciseName.contains("bench")
                if !isSafe {
                    #if DEBUG
                    profileFailCount += 1
                    #endif
                    return false
                }
            }
            
            #if DEBUG
            matchCount += 1
            #endif
            
            return true
        }
        
        #if DEBUG
        print("   🔍 Filtering stats:")
        print("      ✅ Passed filters: \(matchCount)")
        print("      ❌ Failed equipment: \(equipmentFailCount)")
        print("      ❌ Failed muscle: \(muscleFailCount)")
        print("      🧠 Filtered by profile (weight/age/exp): \(profileFailCount)")
        
        // Show first 5 ACTUAL barbell exercises if user selected Barbell
        if normalizedEquipment.contains(where: { $0.lowercased().contains("barbell") }) {
            let barbellOnly = matchingExercises.filter { ($0.equipment ?? "").lowercased().contains("barbell") }
            print("   🏋️ Barbell exercises found: \(barbellOnly.count)")
            for (idx, ex) in barbellOnly.prefix(5).enumerated() {
                print("      \(idx+1). \(ex.name ?? "?") - \(ex.equipment ?? "?")")
            }
        }
        #endif
        
        #if DEBUG
        print("   🔍 STRICT filtering results:")
        print("      Equipment filter: User has \(normalizedEquipment)")
        print("      Muscle filter: Looking for \(normalizedMuscles)")
        print("      Exercises after STRICT filter: \(matchingExercises.count)")
        
        // Show first 10 matching exercises with their equipment and muscles
        print("   📋 Sample matches:")
        for (idx, ex) in matchingExercises.prefix(10).enumerated() {
            let muscles = (ex.muscleGroups as? [String]) ?? []
            let equipment = ex.equipment ?? "?"
            let workoutType = ex.workoutType ?? "?"
            print("      \(idx+1). \(ex.name ?? "?") - Equipment: \(equipment) - Muscles: \(muscles) - Type: \(workoutType)")
        }
        #endif
        
        // 👤 GENDER PRIORITIZATION - Count exercises by gender availability
        var genderMatchCount = 0
        var genderFallbackCount = 0
        
        for exercise in matchingExercises {
            let exerciseKey = exercise.name?.lowercased() ?? ""
            if let genderInfo = genderVideoCache[exerciseKey] {
                if genderInfo.filename(for: preferredVideoGender) != nil {
                    genderMatchCount += 1
                } else {
                    genderFallbackCount += 1
                }
            }
        }
        
        #if DEBUG
        print("   Exercises after strict filter: \(matchingExercises.count)")
        print("   👤 Gender-matching videos: \(genderMatchCount)")
        print("   👤 Opposite gender fallback: \(genderFallbackCount)")
        #endif
        
        // Score each exercise for intelligent selection
        struct ScoredExercise {
            let exercise: Exercise
            var score: Double
        }
        
        // Pre-compute user equipment set for use in scoring closure
        let userEquipmentLower = Set(normalizedEquipment.map { $0.lowercased() })
        
        var scoredExercises = matchingExercises.map { exercise -> ScoredExercise in
            var score: Double = 100.0
            let name = exercise.name?.lowercased() ?? ""
            let category = exercise.category?.lowercased() ?? ""
            let muscleGroups = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
            let primaryMuscle = muscleGroups.first ?? ""
            let equipmentType = ExerciseFilterService.normalizeEquipment(exercise.equipment)
            
            // 🌟 FOUNDATIONAL EXERCISE BOOST - CRITICAL FOR NEW USERS
            // Prioritizes well-known, beginner-friendly exercises
            // Prevents obscure exercises like "Behind Back Cable Tricep Extension"
            let foundationalBoost = FoundationalExerciseDatabase.shared.getFoundationalBoostScore(
                exerciseName: name,
                userWorkoutCount: userWorkoutCount,
                userTotalCompletedExercises: 0
            )
            score += foundationalBoost
            
            // If user is restricted to foundational and this isn't foundational, heavy penalty
            if restrictToFoundational && foundationalBoost < 0 {
                score -= 500  // Massive penalty to ensure non-foundational rarely appears
                #if DEBUG
                print("   🚫 [BEGINNER] Heavy penalty for '\(exercise.name ?? "")': non-foundational for new user")
                #endif
            }
            
            // 🚫 RISKY EXERCISE PENALTY - Block complex/dangerous exercises for foundational users
            // Mirrors the Python script's RISKY_EXERCISES filtering
            let foundationalDB = FoundationalExerciseDatabase.shared
            let hasLowerBackIssue = LimitationsService.shared.hasLowerBackLimitation
            
            let riskyPenalty = foundationalDB.getRiskyExercisePenalty(
                exerciseName: name,
                userWorkoutCount: userWorkoutCount,
                restrictToFoundational: restrictToFoundational,
                hasLowerBackIssue: hasLowerBackIssue
            )
            if riskyPenalty != 0 {
                score += riskyPenalty
                #if DEBUG
                if riskyPenalty < -100 {
                    print("   ⚠️ [SAFETY] '\(exercise.name ?? "")' penalty: \(Int(riskyPenalty))")
                }
                #endif
            }
            
            // ✅ LOWER BACK SAFE ALTERNATIVE BOOST - Promote chest-supported/machine rows
            if hasLowerBackIssue && foundationalDB.isLowerBackSafeAlternative(name) {
                score += 100
                #if DEBUG
                print("   ✅ [BACK SAFE] '\(exercise.name ?? "")' boosted +100 (safe for lower back)")
                #endif
            }
            
            // 🛡️ METADATA-DRIVEN SAFETY PENALTY - Uses the comprehensive rule system
            // This applies penalties/boosts for ALL limitation areas, not just lower back
            let safetyPenalty = LimitationsService.shared.getSafetyPenalty(for: exercise)
            if safetyPenalty != 0 {
                score -= safetyPenalty  // Subtract penalty (positive penalty = decrease score)
                #if DEBUG
                if abs(safetyPenalty) > 50 {
                    let direction = safetyPenalty > 0 ? "🚫" : "✅"
                    print("   \(direction) [SAFETY] '\(exercise.name ?? "")': \(safetyPenalty > 0 ? "-" : "+")\(Int(abs(safetyPenalty)))")
                }
                #endif
            }
            
            // 🏋️ BEGINNER EQUIPMENT PREFERENCE - Machines > Cables > Dumbbells > Barbells
            // New gym users are often intimidated by free weights
            // Prioritize machines and cables for their first few workouts
            let beginnerEquipBoost = FoundationalExerciseDatabase.shared.getBeginnerEquipmentBoost(
                equipment: exercise.equipment ?? "",
                userWorkoutCount: userWorkoutCount,
                experienceLevel: userLevel,
                userEquipment: Array(userEquipmentLower)
            )
            score += beginnerEquipBoost
            
            #if DEBUG
            if beginnerEquipBoost != 0 && userWorkoutCount < 5 {
                let equipType = exercise.equipment ?? "unknown"
                print("   🏋️ [BEGINNER EQUIP] '\(exercise.name ?? "")' (\(equipType)): \(beginnerEquipBoost > 0 ? "+" : "")\(Int(beginnerEquipBoost))")
            }
            #endif
            
            // 🧠 LEARNED USER PREFERENCES - GENTLE INFLUENCE (not dominant)
            // Favorites/history should be a HINT, not a guarantee
            // Cap at +30 points (was +150) to ensure variety
            var learnedBoost = learningEngine.calculateLearnedBoostScore(
                exerciseName: name,
                equipment: exercise.equipment ?? "",
                muscleGroups: muscleGroups,
                category: category
            )
            
            // 🆕 AGGRESSIVE DAMPENING: Favorites are hints, not mandates
            // Max +30 from learned preferences (was 150)
            let maxLearnedBoost: Double = 30.0
            let finalLearnedBoost = min(learnedBoost * 0.2, maxLearnedBoost)  // Scale down by 80%
            
            score += finalLearnedBoost
            
            // 👤 GENDER MATCH - HIGH PRIORITY (+200 for matching gender)
            // This ensures user almost always sees their gender's exercises
            // Check VideoStreamingService's gender cache
            let exerciseKey = name
            var genderMatches = true // Default to true if no video info
            if let genderInfo = genderVideoCache[exerciseKey] {
                genderMatches = genderInfo.filename(for: preferredVideoGender) != nil
            }
            
            if genderMatches {
                score += 200  // Massive boost for gender match
            } else {
                score -= 150  // Heavy penalty for opposite gender (only used as fallback)
            }
            
            // ⭐ FAVORITES AS GENTLE HINTS (not guarantees)
            // Favorites get a small boost (+20), not a dominant one
            // This ensures variety while still considering user preferences
            if favorites.contains(name) {
                score += 20  // Was +100, now just a gentle nudge
            }
            
            // 🔄 SMART VARIANT ROTATION - Learn from user behavior
            // Note: Variant scoring uses cached data for synchronous access
            // The actual rotation logic runs on MainActor when workouts complete
            
            // 🎯 DIRECT MUSCLE MATCH - Count how many target muscles this exercise hits
            // Exercises hitting MULTIPLE user-selected muscles get BIG bonus (compound value!)
            let secondaryMusclesLower = (exercise.secondaryMuscles as? [String])?.map { $0.lowercased() } ?? []
            let allExerciseMuscles = muscleGroups + secondaryMusclesLower
            
            var matchedTargetCount = 0
            var matchedTargets: [String] = []
            
            for target in normalizedMuscles {
                let hits = allExerciseMuscles.contains { muscle in
                    muscle == target || muscle.contains(target) || target.contains(muscle)
                }
                if hits {
                    matchedTargetCount += 1
                    matchedTargets.append(target)
                }
            }
            
            if matchedTargetCount > 0 {
                // Base bonus for hitting any target
                score += 150
                
                // 🔥 MULTI-TARGET BONUS - Exercises hitting multiple user selections are GOLD
                // e.g., Close-Grip Bench hits both Chest AND Triceps = +100 extra
                if matchedTargetCount >= 2 {
                    let multiTargetBonus = Double((matchedTargetCount - 1) * 100)
                    score += multiTargetBonus
                }
            } else {
                // Matched via category only - lower priority
                score -= 50
            }
            
            // 📊 CATEGORY MATCH - Smaller bonus (secondary to muscle match)
            if targetCategories.contains(category) {
                score += 25
            }
            
            // 🏋️ COMPOUND MOVEMENT BONUS - Use actual movement_type from database
            let isCompound: Bool
            if let movementType = exercise.movementType?.lowercased() {
                isCompound = movementType.contains("compound")
            } else {
                isCompound = isCompoundExercise(name: name)  // Fallback to keyword detection
            }
            if isCompound {
                score += 40
            }
            
            // 🏠 HOME GYM FRIENDLY - Boost if user is training at home
            if userEnvironment.lowercased() == "home" && exercise.homeGymFriendly {
                score += 25
            }
            
            // 🎯 GOAL-SPECIFIC RATINGS - Use actual ratings from database
            // These ratings are from exercise_goal_classifications.csv with scientific backing
            let goalLower = userGoal.lowercased()
            
            // BUILD MUSCLE - Uses hypertrophy_rating (compound movements, 8-12 rep exercises)
            if goalLower.contains("build muscle") || goalLower.contains("hypertrophy") || goalLower.contains("bulk") {
                if exercise.hypertrophyRating > 0 {
                    score += Double(exercise.hypertrophyRating) * 4  // 0-40 points (higher weight for primary goal)
                }
                // Bonus for compound movements in muscle building
                if exercise.isCompound {
                    score += 15
                }
            }
            
            // GET LEAN - Uses fat_loss_rating (metabolic exercises, supersetable, higher rep)
            if goalLower.contains("get lean") || goalLower.contains("fat loss") || goalLower.contains("lose weight") || goalLower.contains("cut") {
                if exercise.fatLossRating > 0 {
                    score += Double(exercise.fatLossRating) * 4  // 0-40 points
                }
                // Bonus for supersetable exercises (keep heart rate elevated)
                if exercise.supersetable {
                    score += 10
                }
                // Bonus for exercises with lower fatigability (can do more volume)
                if exercise.fatigability < 6 {
                    score += 8
                }
            }
            
            // ENDURANCE - Uses endurance_rating (cardio, high-rep, low fatigue)
            if goalLower.contains("endurance") || goalLower.contains("stamina") || goalLower.contains("conditioning") {
                if exercise.enduranceRating > 0 {
                    score += Double(exercise.enduranceRating) * 4  // 0-40 points
                }
                // Prefer cardio/stretching exercises for endurance
                let workoutTypeLower = (exercise.workoutType ?? "").lowercased()
                if workoutTypeLower == "cardio" || workoutTypeLower == "stretching" {
                    score += 15
                }
            }
            
            // GENERAL FITNESS - Uses general_fitness_rating (balanced, functional)
            if goalLower.contains("general") || goalLower.contains("stay healthy") || goalLower.contains("maintain") {
                if exercise.generalFitnessRating > 0 {
                    score += Double(exercise.generalFitnessRating) * 4  // 0-40 points
                }
            }
            
            // STRENGTH - Uses strength_rating (heavy compounds, low rep)
            if goalLower.contains("strength") || goalLower.contains("stronger") || goalLower.contains("power") {
                if exercise.strengthRating > 0 {
                    score += Double(exercise.strengthRating) * 4  // 0-40 points
                }
                // Bonus for compound movements in strength training
                if exercise.isCompound {
                    score += 20
                }
            }
            
            // 📈 SKILL LEVEL MATCHING - Use actual difficulty from database (or estimate)
            let exerciseDifficulty = exercise.difficultyLevel > 0 ? Int(exercise.difficultyLevel) : estimateExerciseDifficulty(name: name)
            
            // Technical exercise keywords (advanced-only)
            let technicalKeywords = ["snatch", "clean", "jerk", "muscle up", "pistol", 
                                     "handstand", "planche", "dragon flag", "l-sit", 
                                     "front lever", "back lever", "human flag"]
            let isTechnicalExercise = technicalKeywords.contains(where: { name.contains($0) })
            
            // Beginner-friendly exercise indicators
            let beginnerKeywords = ["machine", "assisted", "supported", "seated", 
                                    "lying", "leg press", "smith", "guided"]
            let isBeginnerFriendly = beginnerKeywords.contains(where: { name.contains($0) }) ||
                                     equipmentType.lowercased().contains("machine")
            
            switch userLevel.lowercased() {
            case "beginner":
                // Beginners: HEAVILY prefer machine/assisted/simple exercises
                if isTechnicalExercise {
                    score -= 300  // Block technical exercises for beginners
                }
                if isBeginnerFriendly {
                    score += 100  // Big boost for beginner-friendly
                }
                if exerciseDifficulty <= 3 { 
                    score += 50  // Easy exercises
                } else if exerciseDifficulty >= 6 { 
                    score -= 100  // Penalty for harder exercises
                }
                // Prefer isolation (easier to learn form)
                if !isCompound { score += 25 }
                
            case "advanced":
                // Advanced: Prefer technical and compound, slight penalty for too-easy
                if isTechnicalExercise {
                    score += 150  // Big boost for technical exercises
                }
                if isBeginnerFriendly {
                    score -= 40  // Slight penalty for beginner exercises
                }
                if exerciseDifficulty >= 7 { 
                    score += 60  // Boost hard exercises
                } else if exerciseDifficulty <= 2 { 
                    score -= 30  // Slight penalty for very easy
                }
                // Strongly prefer compound movements
                if isCompound { score += 50 }
                // Prefer barbell/dumbbell over machines
                if equipmentType == "Barbell" || equipmentType == "Dumbbells" {
                    score += 30
                }
                
            default: // Intermediate
                if isTechnicalExercise {
                    score -= 50  // Slight penalty for technical (not ideal yet)
                }
                if exerciseDifficulty >= 3 && exerciseDifficulty <= 7 { 
                    score += 30  // Sweet spot
                }
            }
            
            // 🎯 GOAL OPTIMIZATION
            switch userGoal.lowercased() {
            case "build muscle":
                if isCompound { score += 25 }
                if equipmentType == "Barbell" || equipmentType == "Dumbbells" { score += 15 }
            case "lose fat", "lose weight":
                if category == "cardio" || category == "plyometrics" { score += 35 }
                if name.contains("burpee") || name.contains("jump") { score += 20 }
            case "get stronger":
                if isCompound { score += 35 }
                if equipmentType == "Barbell" { score += 25 }
            default:
                break
            }
            
            // 🪑 SMART BENCH HANDLING WITH CONTEXT CLUES
            // Uses target muscle selection to infer what bench types user likely has
            // Example: "Lower Chest" + "Bench" → user probably has/wants decline bench
            let exerciseEquipment = exercise.equipment ?? ""
            let userHasBench = userEquipmentLower.contains { $0.contains("bench") }
            
            if userHasBench && exerciseEquipment.lowercased().contains("bench") {
                // Pass target muscles for context-aware bench scoring
                let benchScore = ExerciseFilterService.getBenchCompatibilityScore(
                    exerciseEquipment, 
                    targetMuscles: Array(normalizedMuscles)
                )
                
                // Context-matched (score 95) gets +35, specialized without context (score 20) gets -25
                let benchAdjustment = Double(benchScore - 60) * 0.7
                score += benchAdjustment
                
                #if DEBUG
                if benchScore >= 90 {
                    print("   🪑 [CONTEXT BENCH] '\(exercise.name ?? "")' bench type matches muscle context (+\(Int(benchAdjustment)))")
                } else if benchScore < 50 {
                    print("   🪑 [SMART BENCH] '\(exercise.name ?? "")' requires specialized bench without context (\(exerciseEquipment)) - score: \(Int(benchAdjustment))")
                }
                #endif
            }
            
            // Small bonus for exercises that DON'T require a bench
            // These are guaranteed to work regardless of bench type
            if userHasBench && !exerciseEquipment.lowercased().contains("bench") {
                score += 5
            }
            
            // 🏢 LOCATION CONTEXT PENALTIES
            // Deprioritize exercises that don't fit the user's workout context:
            // - Chair/wall exercises should NOT appear in gym workouts
            // - Floor-lying exercises deprioritized for strength training
            // - Improvised equipment excluded for serious training
            let locationPenalty = ExerciseFilterService.getLocationContextPenalty(
                exerciseName: name,
                equipment: exerciseEquipment,
                location: workoutLocation,
                userGoal: userGoal
            )
            score += locationPenalty
            
            #if DEBUG
            if locationPenalty < -30 {
                print("   🏢 [LOCATION] '\(exercise.name ?? "")' penalized (\(Int(locationPenalty))) - not suitable for \(workoutLocation.displayName)")
            }
            #endif
            
            // 🔄 Add randomness for variety
            score += Double.random(in: 0...30)
            
            return ScoredExercise(exercise: exercise, score: score)
        }
        
        // Sort by score (highest first)
        scoredExercises.sort { $0.score > $1.score }
        
        // 🎯 EQUIPMENT DIVERSITY: Identify unique equipment types user selected
        // Updated to handle new equipment format (Cable Machine, Lever Machine, etc.)
        let selectedEquipmentTypes = Set(userEquipmentLower.compactMap { equip -> String? in
            // Normalize user equipment to categories
            if equip.contains("dumbbell") { return "dumbbell" }
            if equip.contains("cable") { return "cable" }  // Matches "Cables" user selection
            if equip.contains("barbell") { return "barbell" }
            if equip.contains("machine") && !equip.contains("smith") { return "machine" }  // Matches "Machines"
            if equip.contains("smith") { return "smith" }
            if equip.contains("kettlebell") { return "kettlebell" }
            if equip.contains("band") || equip.contains("resistance") { return "band" }
            if equip.contains("bench") { return "bench" }
            return nil
        })
        
        // 🎯 MUSCLE DIVERSITY: Normalize target muscles for smart distribution
        let normalizedTargetMuscles: Set<String> = Set(normalizedMuscles.compactMap { muscle -> String? in
            let m = muscle.lowercased()
            // Group similar muscles together for diversity tracking
            if m.contains("bicep") { return "biceps" }
            if m.contains("tricep") { return "triceps" }
            if m.contains("chest") || m.contains("pec") { return "chest" }
            if m.contains("back") || m.contains("lat") { return "back" }
            if m.contains("shoulder") || m.contains("delt") { return "shoulders" }
            if m.contains("quad") || m.contains("thigh") { return "quads" }
            if m.contains("hamstring") { return "hamstrings" }
            if m.contains("glute") { return "glutes" }
            if m.contains("calf") || m.contains("calves") { return "calves" }
            if m.contains("core") || m.contains("ab") { return "core" }
            if m.contains("forearm") { return "forearms" }
            if m.contains("trap") { return "traps" }
            return m  // Keep as-is if no match
        })
        
        // Calculate target exercises per muscle group
        let exercisesPerMuscle = max(1, count / max(1, normalizedTargetMuscles.count))
        
        #if DEBUG
        print("   🔧 Selected equipment types for diversity: \(selectedEquipmentTypes)")
        print("   💪 Target muscle groups (\(normalizedTargetMuscles.count)): \(normalizedTargetMuscles)")
        print("   📊 Target ~\(exercisesPerMuscle) exercises per muscle group")
        #endif
        
        // Select exercises with MAXIMUM VARIETY (avoid duplicates and repetitive patterns)
        var result: [GeneratedExercise] = []
        var usedNames: Set<String> = []
        var usedMuscles: [String: Int] = [:]
        var usedBodyPositions: [String: Int] = [:]  // Track lying, standing, seated, etc.
        var usedMovementKeywords: [String: Int] = [:] // Track press, fly, row, etc.
        var usedMovementPatterns: [String: Int] = [:] // Track from database field
        var usedEquipmentTypes: [String: Int] = [:]  // Track equipment diversity
        var usedNormalizedMuscles: [String: Int] = [:]  // Track muscle group diversity
        var usedExerciseFamilies: [String: Int] = [:]  // 🆕 Track exercise families (bench press, curl, fly, etc.)
        var usedBaseMovements: Set<String> = []  // 🆕 Track base movements (prevents Barbell + Smith Machine of same exercise)
        var equipmentTypesRepresented: Set<String> = []  // Which equipment types have at least 1 exercise
        
        // 🆕 Helper to extract exercise family from name
        // Helper to get base movement name (strips equipment prefix)
        func getBaseMovement(_ name: String) -> String {
            var baseName = name.lowercased()
            // Strip equipment prefixes to get base movement
            let equipmentPrefixes = ["barbell ", "dumbbell ", "smith machine ", "cable ", "machine ", 
                                    "lever ", "band ", "kettlebell ", "ez bar ", "trap bar "]
            for prefix in equipmentPrefixes {
                if baseName.hasPrefix(prefix) {
                    baseName = String(baseName.dropFirst(prefix.count))
                    break
                }
            }
            return baseName
        }
        
        func getExerciseFamily(_ name: String) -> String {
            let n = name.lowercased()
            // Specific exercise families - order matters (check specific first)
            
            // 🎯 ALL CHEST PRESSES grouped together (bench, incline, decline, chest press = same family!)
            // This prevents workouts with 5 different press variations
            if n.contains("close grip") && n.contains("press") { return "chest_press" }
            if n.contains("bench press") { return "chest_press" }
            if n.contains("incline press") && !n.contains("shoulder") { return "chest_press" }
            if n.contains("decline press") { return "chest_press" }
            if n.contains("chest press") { return "chest_press" }
            if n.contains("lever") && n.contains("press") && (n.contains("chest") || n.contains("pec")) { return "chest_press" }
            // Shoulder presses are separate (includes "shoulders press" for plural variation)
            if n.contains("overhead press") || n.contains("shoulder press") || n.contains("shoulders press") || n.contains("military press") || n.contains("arnold press") { return "shoulder_press" }
            // JM Press and Skull Crushers are tricep-focused bench variants
            if n.contains("jm press") || n.contains("jm bench") { return "skull_crusher" }
            if n.contains("lying") && n.contains("extension") && n.contains("tricep") { return "skull_crusher" }
            if n.contains("bicep curl") || n.contains("biceps curl") { return "bicep_curl" }
            if n.contains("hammer curl") { return "hammer_curl" }
            if n.contains("preacher curl") { return "preacher_curl" }
            if n.contains("tricep extension") || n.contains("triceps extension") { return "tricep_extension" }
            if n.contains("tricep pushdown") || n.contains("triceps pushdown") { return "tricep_pushdown" }
            if n.contains("skull crusher") { return "skull_crusher" }
            if n.contains("cable fly") || n.contains("cable flye") { return "cable_fly" }
            if n.contains("dumbbell fly") || n.contains("dumbbell flye") { return "dumbbell_fly" }
            if n.contains("pec deck") || n.contains("pec fly") { return "pec_fly" }
            if n.contains("lat pulldown") { return "lat_pulldown" }
            if n.contains("pull up") || n.contains("pullup") || n.contains("chin up") || n.contains("chinup") { return "pullup" }
            if n.contains("seated row") { return "seated_row" }
            if n.contains("bent over row") { return "bent_row" }
            if n.contains("cable row") { return "cable_row" }
            if n.contains("lateral raise") { return "lateral_raise" }
            if n.contains("front raise") { return "front_raise" }
            if n.contains("rear delt") { return "rear_delt" }
            if n.contains("squat") { return "squat" }
            if n.contains("leg press") { return "leg_press" }
            if n.contains("leg curl") { return "leg_curl" }
            if n.contains("leg extension") { return "leg_extension" }
            if n.contains("deadlift") { return "deadlift" }
            if n.contains("lunge") { return "lunge" }
            // Dips and push-ups (compound chest/tricep movements)
            if n.contains("dip") { return "dip" }
            if n.contains("push up") || n.contains("pushup") || n.contains("push-up") { return "pushup" }
            // Generic fallbacks - include ALL row variations (narrow grip, wide grip, etc.)
            if n.contains("press") { return "press_other" }
            if n.contains("curl") { return "curl_other" }
            if n.contains("fly") || n.contains("flye") { return "fly_other" }
            // CRITICAL: Check for " row" to avoid matching "narrow" in leg press names
            if (n.contains(" row") || n.hasPrefix("row")) && !n.contains("upright") { return "row_other" }
            if n.contains("raise") { return "raise_other" }
            if n.contains("extension") { return "extension_other" }
            return "other"
        }
        
        // 🎯 PHASE 1: ROUND-ROBIN equipment diversity allocation
        // Ensures FAIR distribution across ALL selected equipment types
        // Rather than filling one type completely before moving to next
        if selectedEquipmentTypes.count > 1 {
            // Calculate fair distribution: ensure each equipment type gets at least 1 exercise
            // Then distribute remaining slots evenly
            let equipmentTypesList = Array(selectedEquipmentTypes).sorted()  // Sort for consistency
            let slotsPerType = max(1, count / equipmentTypesList.count)
            let maxSlotsForPhase1 = min(count, equipmentTypesList.count * slotsPerType)
            
            #if DEBUG
            print("   🔄 [EQUIP DIVERSITY] Round-robin allocation: \(equipmentTypesList.count) types, \(slotsPerType) per type, \(maxSlotsForPhase1) total Phase 1 slots")
            #endif
            
            // Pre-index exercises by equipment type for efficient lookup
            var exercisesByEquipType: [String: [ScoredExercise]] = [:]
            for equipType in equipmentTypesList {
                exercisesByEquipType[equipType] = scoredExercises.filter { scored in
                    let equipLower = (scored.exercise.equipment ?? "").lowercased()
                    return equipLower.contains(equipType)
                }
            }
            
            #if DEBUG
            for (equipType, exercises) in exercisesByEquipType {
                print("   📦 Available for \(equipType): \(exercises.count) exercises")
            }
            #endif
            
            // Track how many we've taken from each type
            var takenPerType: [String: Int] = [:]
            for equipType in equipmentTypesList {
                takenPerType[equipType] = 0
            }
            
            // Round-robin: take 1 from each type, then repeat until slots filled
            var round = 0
            while result.count < maxSlotsForPhase1 {
                var addedThisRound = false
                
                for equipType in equipmentTypesList {
                    guard result.count < maxSlotsForPhase1 else { break }
                    
                    // Skip if this type already has enough (fair share)
                    let currentCount = takenPerType[equipType] ?? 0
                    if currentCount >= slotsPerType { continue }
                    
                    // Find next available exercise of this type
                    let availableExercises = exercisesByEquipType[equipType] ?? []
                    for scored in availableExercises {
                        let exercise = scored.exercise
                        let name = exercise.name ?? ""
                        let nameLower = name.lowercased()
                        
                        // Skip if already used
                        guard !usedNames.contains(nameLower) else { continue }
                        
                        // 🆕 BASE MOVEMENT CHECK: Prevent Barbell Bench Press + Smith Machine Bench Press
                        let baseMovement = getBaseMovement(nameLower)
                        if usedBaseMovements.contains(baseMovement) {
                            #if DEBUG
                            print("   🚫 Skipping '\(name)' - base movement '\(baseMovement)' already used")
                            #endif
                            continue
                        }
                        
                        let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                        let primaryMuscle = muscleGroups.first?.lowercased() ?? "unknown"
                        let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
                        let normalizedMuscle = normalizeMuscleName(primaryMuscle)
                        
                        // 🆕 Muscle balance check: Don't over-represent one muscle group
                        let currentMuscleCount = usedNormalizedMuscles[normalizedMuscle] ?? 0
                        let maxPerMuscle = max(2, Int(ceil(Double(count) / Double(max(1, normalizedTargetMuscles.count)))) + 1)
                        if currentMuscleCount >= maxPerMuscle && normalizedTargetMuscles.count > 1 {
                            continue
                        }
                        
                        // 🆕 EXERCISE FAMILY CHECK: Only 1 exercise per family (no 3 bench press variations!)
                        let exerciseFamily = getExerciseFamily(nameLower)
                        let familyCount = usedExerciseFamilies[exerciseFamily] ?? 0
                        if exerciseFamily != "other" && familyCount >= 1 {
                            continue  // Already have one from this family
                        }
                        
                        // 🆕 MOVEMENT KEYWORD CHECK in Phase 1: Limit presses, curls, etc.
                        // Include ALL row variations (narrow grip, wide grip, etc.)
                        let movementKeyword: String = {
                            if nameLower.contains("press") { return "press" }
                            if nameLower.contains("fly") || nameLower.contains("flye") { return "fly" }
                            // CRITICAL: Check for " row" to avoid matching "narrow"
                            if (nameLower.contains(" row") || nameLower.hasPrefix("row")) && !nameLower.contains("upright") { return "row" }
                            if nameLower.contains("curl") { return "curl" }
                            if nameLower.contains("extension") { return "extension" }
                            if nameLower.contains("raise") { return "raise" }
                            if nameLower.contains("pulldown") || nameLower.contains("pull down") { return "pulldown" }
                            return "other"
                        }()
                        let movementKeywordCount = usedMovementKeywords[movementKeyword] ?? 0
                        let maxPerMovement = count <= 6 ? 2 : 3  // Allow 2 presses for variety (e.g., bench + shoulder)
                        if movementKeyword != "other" && movementKeywordCount >= maxPerMovement {
                            continue  // Too many of this movement type
                        }
                        
                        let generated = GeneratedExercise(
                            id: exercise.id?.uuidString ?? UUID().uuidString,
                            name: name,
                            category: exercise.category ?? "Unknown",
                            primaryBodyRegion: exercise.category ?? "Unknown",
                            primaryMuscle: muscleGroups.first ?? "Unknown",
                            secondaryMuscles: secondaryMuscles,
                            equipment: exercise.equipment ?? "Bodyweight",
                            difficulty: "Intermediate",
                            videoUrl: nil,
                            instructions: exercise.instructions
                        )
                        
                        result.append(generated)
                        usedNames.insert(nameLower)
                        usedBaseMovements.insert(baseMovement)  // Track base movement
                        usedMuscles[primaryMuscle] = (usedMuscles[primaryMuscle] ?? 0) + 1
                        usedNormalizedMuscles[normalizedMuscle] = (usedNormalizedMuscles[normalizedMuscle] ?? 0) + 1
                        usedEquipmentTypes[equipType] = (usedEquipmentTypes[equipType] ?? 0) + 1
                        usedExerciseFamilies[exerciseFamily] = (usedExerciseFamilies[exerciseFamily] ?? 0) + 1
                        usedMovementKeywords[movementKeyword] = (usedMovementKeywords[movementKeyword] ?? 0) + 1
                        equipmentTypesRepresented.insert(equipType)
                        takenPerType[equipType] = currentCount + 1
                        addedThisRound = true
                        
                        #if DEBUG
                        print("   🎯 [ROUND \(round)] \(equipType): \(name) (\(normalizedMuscle), family: \(exerciseFamily), move: \(movementKeyword)) - slot \(currentCount + 1)/\(slotsPerType)")
                        #endif
                        
                        break  // Move to next equipment type
                    }
                }
                
                round += 1
                // Safety: prevent infinite loop if no exercises available
                if !addedThisRound || round > count * 2 { break }
            }
            
            #if DEBUG
            print("   ✅ [PHASE 1 COMPLETE] Reserved \(result.count) exercises across \(equipmentTypesRepresented.count) equipment types")
            for (equipType, cnt) in takenPerType.sorted(by: { $0.key < $1.key }) {
                print("      • \(equipType): \(cnt)")
            }
            #endif
        }
        
        // 🎯 PHASE 1b: Ensure each target muscle group has at least 1 exercise
        if normalizedTargetMuscles.count > 1 {
            for targetMuscle in normalizedTargetMuscles {
                guard result.count < count else { break }
                
                // Skip if this muscle group already has an exercise
                let currentCount = usedNormalizedMuscles[targetMuscle] ?? 0
                if currentCount >= 1 { continue }
                
                // Find the best exercise for this muscle group that hasn't been used
                for scored in scoredExercises {
                    guard result.count < count else { break }
                    
                    let exercise = scored.exercise
                    let name = exercise.name ?? ""
                    let nameLower = name.lowercased()
                    
                    // Skip if already used
                    guard !usedNames.contains(nameLower) else { continue }
                    
                    // 🆕 BASE MOVEMENT CHECK: Prevent Barbell + Smith Machine of same exercise
                    let baseMovement = getBaseMovement(nameLower)
                    if usedBaseMovements.contains(baseMovement) { continue }
                    
                    let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                    let primaryMuscle = muscleGroups.first?.lowercased() ?? "unknown"
                    let normalizedMuscle = normalizeMuscleName(primaryMuscle)
                    
                    // Check if this exercise targets the muscle we need
                    guard normalizedMuscle == targetMuscle else { continue }
                    
                    // 🆕 EXERCISE FAMILY CHECK
                    let exerciseFamily = getExerciseFamily(nameLower)
                    let familyCount = usedExerciseFamilies[exerciseFamily] ?? 0
                    if exerciseFamily != "other" && familyCount >= 1 { continue }
                    
                    let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
                    let equipmentLower = (exercise.equipment ?? "").lowercased()
                    let exerciseEquipType = getEquipmentType(equipmentLower)
                    
                    let generated = GeneratedExercise(
                        id: exercise.id?.uuidString ?? UUID().uuidString,
                        name: name,
                        category: exercise.category ?? "Unknown",
                        primaryBodyRegion: exercise.category ?? "Unknown",
                        primaryMuscle: muscleGroups.first ?? "Unknown",
                        secondaryMuscles: secondaryMuscles,
                        equipment: exercise.equipment ?? "Bodyweight",
                        difficulty: "Intermediate",
                        videoUrl: nil,
                        instructions: exercise.instructions
                    )
                    
                    result.append(generated)
                    usedNames.insert(nameLower)
                    usedBaseMovements.insert(baseMovement)  // Track base movement
                    usedMuscles[primaryMuscle] = (usedMuscles[primaryMuscle] ?? 0) + 1
                    usedNormalizedMuscles[normalizedMuscle] = (usedNormalizedMuscles[normalizedMuscle] ?? 0) + 1
                    usedEquipmentTypes[exerciseEquipType] = (usedEquipmentTypes[exerciseEquipType] ?? 0) + 1
                    usedExerciseFamilies[exerciseFamily] = (usedExerciseFamilies[exerciseFamily] ?? 0) + 1
                    
                    #if DEBUG
                    print("   💪 [MUSCLE DIVERSITY] Reserved slot for \(targetMuscle): \(name) (\(exerciseEquipType), family: \(exerciseFamily), base: \(baseMovement))")
                    #endif
                    break
                }
            }
        }
        
        // 🎯 PHASE 2: Fill remaining slots with normal diversity rules
        for scored in scoredExercises {
            guard result.count < count else { break }
            
            let exercise = scored.exercise
            let name = exercise.name ?? ""
            let nameLower = name.lowercased()
            let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
            let primaryMuscle = muscleGroups.first?.lowercased() ?? "unknown"
            let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
            
            // Skip if already used
            if usedNames.contains(nameLower) { continue }
            
            // 🆕 BASE MOVEMENT CHECK: Prevent Barbell + Smith Machine of same exercise
            let baseMovement = getBaseMovement(nameLower)
            if usedBaseMovements.contains(baseMovement) { continue }
            
            // Limit exercises per muscle group for variety (max 2 per muscle for smaller workouts)
            let muscleCount = usedMuscles[primaryMuscle] ?? 0
            if muscleCount >= 2 { continue }
            
            // 🆕 MUSCLE BALANCE: Check normalized muscle group
            let normalizedMuscle = normalizeMuscleName(primaryMuscle)
            let normalizedMuscleCount = usedNormalizedMuscles[normalizedMuscle] ?? 0
            let maxPerMuscleGroup = max(2, Int(ceil(Double(count) / Double(max(1, normalizedTargetMuscles.count)))) + 1)
            
            // Soft skip: If this muscle group dominates AND we have underrepresented muscles
            if normalizedMuscleCount >= maxPerMuscleGroup && normalizedTargetMuscles.count > 1 {
                let underrepresentedMuscles = normalizedTargetMuscles.filter { (usedNormalizedMuscles[$0] ?? 0) < maxPerMuscleGroup }
                if !underrepresentedMuscles.isEmpty {
                    #if DEBUG
                    print("   💪 [MUSCLE BALANCE] Soft-skipping \(normalizedMuscle) (has \(normalizedMuscleCount)/\(maxPerMuscleGroup)), prefer: \(underrepresentedMuscles)")
                    #endif
                    continue
                }
            }
            
            // 🆕 EXERCISE FAMILY CHECK: Only 1 exercise per family (no 3 bench press variations!)
            let exerciseFamily = getExerciseFamily(nameLower)
            let familyCount = usedExerciseFamilies[exerciseFamily] ?? 0
            if exerciseFamily != "other" && familyCount >= 1 {
                #if DEBUG
                print("   🚫 [FAMILY] Skipping '\(name)': already have 1 from \(exerciseFamily) family")
                #endif
                continue
            }
            
            // 🆕 DIVERSITY CHECK: Body Position (no more than 2 exercises in same position)
            let bodyPosition = exercise.bodyPosition?.lowercased() ?? {
                // Fallback: extract from name
                if nameLower.contains("lying") || nameLower.contains("floor") { return "lying" }
                if nameLower.contains("seated") || nameLower.contains("sitting") { return "seated" }
                if nameLower.contains("standing") { return "standing" }
                if nameLower.contains("kneeling") { return "kneeling" }
                return "other"
            }()
            
            let positionCount = usedBodyPositions[bodyPosition] ?? 0
            if positionCount >= 2 { continue }  // Max 2 exercises per position
            
            // 🆕 DIVERSITY CHECK: Movement keywords (no more than 2 of same movement type)
            // Include ALL row variations (narrow grip, wide grip, etc.)
            let movementKeyword: String = {
                if nameLower.contains("press") { return "press" }
                if nameLower.contains("fly") || nameLower.contains("flye") { return "fly" }
                // CRITICAL: Check for " row" to avoid matching "narrow"
                if (nameLower.contains(" row") || nameLower.hasPrefix("row")) && !nameLower.contains("upright") { return "row" }
                if nameLower.contains("curl") { return "curl" }
                if nameLower.contains("extension") { return "extension" }
                if nameLower.contains("raise") { return "raise" }
                if nameLower.contains("pulldown") || nameLower.contains("pull down") { return "pulldown" }
                return "other"
            }()
            
            let movementKeywordCount = usedMovementKeywords[movementKeyword] ?? 0
            // 🎨 VARIETY: Max 1 per movement type for small workouts, 2 for larger
            let maxPerMovement = count <= 6 ? 1 : 2
            if movementKeyword != "other" && movementKeywordCount >= maxPerMovement {
                #if DEBUG
                print("   🎨 [VARIETY] Skipping '\(name)': already have \(movementKeywordCount) \(movementKeyword) exercises")
                #endif
                continue
            }
            
            // 🆕 DIVERSITY CHECK: Movement pattern from database
            if let pattern = exercise.movementPattern?.lowercased() {
                let patternCount = usedMovementPatterns[pattern] ?? 0
                if patternCount >= maxPerMovement { continue }
            }
            
            // 🎨 BODY POSITION VARIETY: Max 2 per position (avoid 4 lying exercises)
            if bodyPosition != "other" && positionCount >= 2 {
                #if DEBUG
                print("   🎨 [VARIETY] Skipping '\(name)': already have \(positionCount) \(bodyPosition) exercises")
                #endif
                continue
            }
            
            // 🆕 SOFT EQUIPMENT BALANCE: If one equipment type dominates (>60%), slightly skip
            let exerciseEquipmentLower = (exercise.equipment ?? "").lowercased()
            let exerciseEquipType: String = {
                if exerciseEquipmentLower.contains("dumbbell") { return "dumbbell" }
                if exerciseEquipmentLower.contains("cable") { return "cable" }
                if exerciseEquipmentLower.contains("barbell") { return "barbell" }
                if exerciseEquipmentLower.contains("machine") { return "machine" }
                if exerciseEquipmentLower.contains("kettlebell") { return "kettlebell" }
                if exerciseEquipmentLower.contains("band") { return "band" }
                return "other"
            }()
            
            let equipTypeCount = usedEquipmentTypes[exerciseEquipType] ?? 0
            let maxPerEquipType = max(2, Int(ceil(Double(count) * 0.6)))  // Max 60% from one type
            
            // Soft skip: If this equipment type already dominates AND we have other types available
            if equipTypeCount >= maxPerEquipType && selectedEquipmentTypes.count > 1 {
                // Check if there are still exercises from other equipment types available
                let underrepresentedTypes = selectedEquipmentTypes.filter { (usedEquipmentTypes[$0] ?? 0) < maxPerEquipType }
                if !underrepresentedTypes.isEmpty {
                    #if DEBUG
                    print("   ⚖️ [BALANCE] Soft-skipping \(exerciseEquipType) (has \(equipTypeCount)/\(maxPerEquipType)), prefer: \(underrepresentedTypes)")
                    #endif
                    continue
                }
            }
            
            let generated = GeneratedExercise(
                id: exercise.id?.uuidString ?? UUID().uuidString,
                name: name,
                category: exercise.category ?? "Unknown",
                primaryBodyRegion: exercise.category ?? "Unknown",
                primaryMuscle: muscleGroups.first ?? "Unknown",
                secondaryMuscles: secondaryMuscles,
                equipment: exercise.equipment ?? "Bodyweight",
                difficulty: "Intermediate",
                videoUrl: nil,
                instructions: exercise.instructions
            )
            
            result.append(generated)
            usedNames.insert(nameLower)
            usedBaseMovements.insert(baseMovement)  // Track base movement
            usedMuscles[primaryMuscle] = muscleCount + 1
            usedNormalizedMuscles[normalizedMuscle] = normalizedMuscleCount + 1
            usedBodyPositions[bodyPosition] = positionCount + 1
            usedMovementKeywords[movementKeyword] = movementKeywordCount + 1
            usedEquipmentTypes[exerciseEquipType] = equipTypeCount + 1
            usedExerciseFamilies[exerciseFamily] = familyCount + 1  // 🆕 Track exercise family
            if let pattern = exercise.movementPattern?.lowercased() {
                usedMovementPatterns[pattern] = (usedMovementPatterns[pattern] ?? 0) + 1
            }
        }
        
        // Order: Compound exercises first, then isolation
        result.sort { ex1, ex2 in
            let isCompound1 = isCompoundExercise(name: ex1.name.lowercased())
            let isCompound2 = isCompoundExercise(name: ex2.name.lowercased())
            if isCompound1 && !isCompound2 { return true }
            if !isCompound1 && isCompound2 { return false }
            return false
        }
        
        #if DEBUG
        // Count gender distribution in final results
        var finalGenderMatchCount = 0
        var finalGenderFallbackCount = 0
        
        for ex in result {
            let exKey = ex.name.lowercased()
            if let genderInfo = genderVideoCache[exKey] {
                if genderInfo.filename(for: preferredVideoGender) != nil {
                    finalGenderMatchCount += 1
                } else {
                    finalGenderFallbackCount += 1
                }
            } else {
                finalGenderMatchCount += 1 // No video info = assume match
            }
        }
        
        print("✅ [SMART GEN] Final workout (\(result.count) exercises):")
        print("   👤 Gender: \(finalGenderMatchCount) matching, \(finalGenderFallbackCount) fallback")
        print("   🎯 Diversity: Positions \(usedBodyPositions.count), Movements \(usedMovementKeywords.count), Families \(usedExerciseFamilies.count), Base movements: \(usedBaseMovements.count)")
        print("   🔧 Equipment mix: \(usedEquipmentTypes.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
        print("   💪 Muscle mix: \(usedNormalizedMuscles.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
        print("   🏋️ Exercise families: \(usedExerciseFamilies.filter { $0.key != "other" }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
        for (idx, ex) in result.enumerated() {
            let isFav = favorites.contains(ex.name.lowercased()) ? "⭐" : ""
            print("   \(idx + 1). \(isFav) \(ex.name) - \(ex.category) - \(ex.equipment)")
        }
        #endif
        
        // 🎯 SMART EXERCISE ORDERING
        // Strategy: Compound first → Isolation last, grouped by equipment for efficiency
        let sortedResult = sortExercisesStrategically(result)
        
        #if DEBUG
        print("\n   📋 FINAL ORDER (after smart sorting):")
        for (idx, ex) in sortedResult.enumerated() {
            print("   \(idx + 1). \(ex.name) - \(ex.equipment)")
        }
        #endif
        
        return sortedResult
    }
    
    // MARK: - Smart Exercise Ordering
    
    /// Strategically orders exercises for optimal workout flow
    /// Priority: 1) Compound movements first (need most energy)
    ///           2) Isolation movements after
    ///           3) Spread similar exercises apart (no two dips back-to-back)
    ///           4) Core/abs at the very end
    private func sortExercisesStrategically(_ exercises: [GeneratedExercise]) -> [GeneratedExercise] {
        guard exercises.count > 1 else { return exercises }
        
        // Helper to determine if exercise is compound (multi-joint) or isolation
        func isCompound(_ exercise: GeneratedExercise) -> Bool {
            let name = exercise.name.lowercased()
            let compoundKeywords = [
                "press", "row", "pull up", "pullup", "chin up", "chinup",
                "squat", "deadlift", "lunge", "dip", "push up", "pushup",
                "clean", "snatch", "thruster", "burpee"
            ]
            let isolationKeywords = [
                "curl", "extension", "fly", "flye", "raise", "kickback",
                "pullover", "shrug", "calf", "crunch", "plank", "twist"
            ]
            
            // Check isolation first (more specific)
            for keyword in isolationKeywords {
                if name.contains(keyword) { return false }
            }
            // Then check compound
            for keyword in compoundKeywords {
                if name.contains(keyword) { return true }
            }
            return exercise.equipment.lowercased().contains("barbell")
        }
        
        // Helper to check if exercise is core/abs (should go last)
        func isCore(_ exercise: GeneratedExercise) -> Bool {
            let name = exercise.name.lowercased()
            let muscle = exercise.primaryMuscle.lowercased()
            let coreKeywords = ["ab", "core", "crunch", "plank", "twist", "oblique", "sit up", "situp"]
            return coreKeywords.contains { name.contains($0) || muscle.contains($0) }
        }
        
        // Helper to get movement category for spacing similar exercises
        func getMovementCategory(_ exercise: GeneratedExercise) -> String {
            let name = exercise.name.lowercased()
            if name.contains("dip") { return "dip" }
            if name.contains("push up") || name.contains("pushup") { return "pushup" }
            if name.contains("bench press") || name.contains("chest press") { return "bench_press" }
            if name.contains("incline press") { return "incline_press" }
            if name.contains("decline press") { return "decline_press" }
            if name.contains("fly") || name.contains("flye") { return "fly" }
            // CRITICAL: Check for " row" to avoid matching "narrow"
            if (name.contains(" row") || name.hasPrefix("row")) && !name.contains("upright") { return "row" }
            if name.contains("pulldown") || name.contains("pull down") { return "pulldown" }
            if name.contains("pull up") || name.contains("pullup") || name.contains("chin up") { return "pullup" }
            if name.contains("curl") { return "curl" }
            if name.contains("extension") { return "extension" }
            if name.contains("raise") { return "raise" }
            if name.contains("squat") { return "squat" }
            if name.contains("lunge") { return "lunge" }
            if name.contains("deadlift") { return "deadlift" }
            return "other"
        }
        
        // Step 1: Separate into categories
        var compounds: [GeneratedExercise] = []
        var isolations: [GeneratedExercise] = []
        var coreExercises: [GeneratedExercise] = []
        
        for exercise in exercises {
            if isCore(exercise) {
                coreExercises.append(exercise)
            } else if isCompound(exercise) {
                compounds.append(exercise)
            } else {
                isolations.append(exercise)
            }
        }
        
        // Step 2: Space out similar exercises within each category
        func spaceOutSimilar(_ exerciseList: [GeneratedExercise]) -> [GeneratedExercise] {
            guard exerciseList.count > 1 else { return exerciseList }
            
            var result: [GeneratedExercise] = []
            var remaining = exerciseList
            
            while !remaining.isEmpty {
                if result.isEmpty {
                    // First exercise: just take the first one
                    result.append(remaining.removeFirst())
                } else {
                    // Find an exercise with a different movement category than the last added
                    let lastCategory = getMovementCategory(result.last!)
                    
                    // Try to find one with different category
                    if let differentIndex = remaining.firstIndex(where: { getMovementCategory($0) != lastCategory }) {
                        result.append(remaining.remove(at: differentIndex))
                    } else {
                        // No different category available, just take the next one
                        result.append(remaining.removeFirst())
                    }
                }
            }
            
            return result
        }
        
        // Apply spacing to each category
        let spacedCompounds = spaceOutSimilar(compounds)
        let spacedIsolations = spaceOutSimilar(isolations)
        
        // Step 3: Combine in order: compounds → isolations → core
        var finalOrder = spacedCompounds + spacedIsolations + coreExercises
        
        #if DEBUG
        print("   🔀 [SMART ORDER] Compounds: \(spacedCompounds.count), Isolations: \(spacedIsolations.count), Core: \(coreExercises.count)")
        #endif
        
        return finalOrder
    }
    
    // MARK: - Helper Functions
    
    /// Normalize muscle name to a standard group for diversity tracking
    private func normalizeMuscleName(_ muscle: String) -> String {
        let m = muscle.lowercased()
        if m.contains("bicep") { return "biceps" }
        if m.contains("tricep") { return "triceps" }
        if m.contains("chest") || m.contains("pec") { return "chest" }
        if m.contains("back") || m.contains("lat") && !m.contains("delt") { return "back" }
        if m.contains("shoulder") || m.contains("delt") { return "shoulders" }
        if m.contains("quad") || m.contains("thigh") { return "quads" }
        if m.contains("hamstring") { return "hamstrings" }
        if m.contains("glute") { return "glutes" }
        if m.contains("calf") || m.contains("calves") { return "calves" }
        if m.contains("core") || m.contains("ab") { return "core" }
        if m.contains("forearm") { return "forearms" }
        if m.contains("trap") { return "traps" }
        return m
    }
    
    /// Get normalized equipment type from equipment string
    /// Get equipment type category from exercise equipment string
    /// Updated to handle new database format (Cable Machine, Lever Machine, etc.)
    private func getEquipmentType(_ equipment: String) -> String {
        let e = equipment.lowercased()
        
        // Check specific types first (order matters)
        if e.contains("dumbbell") { return "dumbbell" }
        if e.contains("barbell") || e.contains("ez bar") || e.contains("trap bar") { return "barbell" }
        if e.contains("cable") { return "cable" }  // Catches "Cable Machine"
        if e.contains("smith") { return "smith" }
        if e.contains("lever") || (e.contains("machine") && !e.contains("smith") && !e.contains("cable")) { return "machine" }
        if e.contains("kettlebell") { return "kettlebell" }
        if e.contains("band") || e.contains("resistance") { return "band" }
        if e.contains("bench") && !e.contains("dumbbell") && !e.contains("barbell") { return "bench" }
        if e.contains("bodyweight") || e.isEmpty { return "bodyweight" }
        if e.contains("pull-up") || e.contains("pullup") || e.contains("chin-up") { return "bodyweight" }
        
        return "other"
    }
    
    private func isCompoundExercise(name: String) -> Bool {
        let compoundKeywords = ["squat", "deadlift", "press", "bench", "row", "pull-up", "pullup", 
                                "chin-up", "chinup", "lunge", "dip", "clean", "snatch", "thruster"]
        return compoundKeywords.contains { name.contains($0) }
    }
    
    private func estimateExerciseDifficulty(name: String) -> Int {
        let name = name.lowercased()
        if name.contains("olympic") || name.contains("snatch") || name.contains("clean") { return 9 }
        if name.contains("pistol") || name.contains("muscle-up") || name.contains("muscle up") { return 8 }
        if name.contains("deadlift") || name.contains("squat") && name.contains("barbell") { return 7 }
        if name.contains("bench press") || name.contains("military press") { return 6 }
        if name.contains("pull-up") || name.contains("pullup") { return 6 }
        if name.contains("row") || name.contains("press") { return 5 }
        if name.contains("dumbbell") { return 4 }
        if name.contains("curl") || name.contains("extension") || name.contains("raise") { return 3 }
        if name.contains("machine") { return 2 }
        if name.contains("stretch") || name.contains("foam") { return 1 }
        return 5 // Default medium
    }
    
    func addMoreExercises(
        to existing: [GeneratedExercise],
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: [String]
    ) async throws -> GeneratedExercise {
        // Generate one more exercise, excluding already selected ones
        let excludeIds = existing.map { $0.id }
        
        let newExercises = try await generateWorkout(
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            equipment: equipment,
            count: 1,
            excludeExerciseIds: excludeIds
        )
        
        guard let newExercise = newExercises.first else {
            throw NSError(domain: "WorkoutGenerator", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No more exercises available"
            ])
        }
        
        return newExercise
    }
    
    func swapExercise(
        _ exerciseToSwap: GeneratedExercise,
        in workout: [GeneratedExercise],
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: [String]
    ) async throws -> GeneratedExercise {
        // Generate a replacement exercise with similar characteristics
        let excludeIds = workout.map { $0.id }
        
        // Try to match the same primary muscle
        let specificPrimaries = [exerciseToSwap.primaryBodyRegion]
        
        let replacements = try await generateWorkout(
            primaryMuscles: specificPrimaries.isEmpty ? primaryMuscles : specificPrimaries,
            secondaryMuscles: secondaryMuscles,
            equipment: equipment,
            count: 3, // Get a few options and pick the best
            excludeExerciseIds: excludeIds
        )
        
        // Return the best scoring replacement
        guard let replacement = replacements.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) else {
            throw NSError(domain: "WorkoutGenerator", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No replacement exercise available"
            ])
        }
        
        return replacement
    }
}
