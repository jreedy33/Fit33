import Foundation
import CoreData

// MARK: - Intelligent Workout Generator
// This system ensures variety, proper exercise classification, and smart rotation

class IntelligentWorkoutGenerator {
    static let shared = IntelligentWorkoutGenerator()
    
    private init() {}
    
    // MARK: - Exercise History Tracking
    
    private var userExerciseHistory: [String: [Date]] = [:] // exerciseName -> dates used
    private var lastGeneratedWorkouts: [[String]] = [] // Track last 5 workouts
    private let maxHistoryWorkouts = 5
    
    // MARK: - Exercise Classification & Metadata
    
    struct ExerciseMetadata {
        let exercise: ExerciseData
        let movementPattern: MovementPattern
        let emphasis: ExerciseEmphasis
        let complexity: ExerciseComplexity
        let equipment: EquipmentType
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let movementSignature: String // Unique identifier for similar movements
    }
    
    enum MovementPattern: String {
        case push = "Push"
        case pull = "Pull"
        case squat = "Squat"
        case hinge = "Hinge"
        case lunge = "Lunge"
        case carry = "Carry"
        case rotation = "Rotation"
        case isolation = "Isolation"
        case plank = "Plank"
        case groundBased = "Ground"
    }
    
    enum ExerciseEmphasis: String {
        case compound = "Compound"       // Multi-joint, heavy
        case accessory = "Accessory"     // Supporting movements
        case isolation = "Isolation"     // Single muscle focus
        case unilateral = "Unilateral"   // One side at a time
        case stability = "Stability"     // Core, balance
        case mobility = "Mobility"       // Stretching, ROM
        case plyometric = "Plyometric"   // Explosive
        case isometric = "Isometric"     // Static hold
    }
    
    enum ExerciseComplexity: String {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
    }
    
    enum EquipmentType: String {
        case barbell = "Barbell"
        case dumbbell = "Dumbbell"
        case cable = "Cable"
        case machine = "Machine"
        case bodyweight = "Bodyweight"
        case kettlebell = "Kettlebell"
        case band = "Band"
        case other = "Other"
    }
    
    // MARK: - Smart Workout Generation
    
    func generateIntelligentWorkout(
        targetBodyParts: Set<String>,
        availableEquipment: Set<String>,
        difficulty: ExerciseComplexity = .intermediate,
        exerciseCount: Int = 6,
        avoidRecentExercises: Bool = true,
        balanceMovementPatterns: Bool = true
    ) -> [ExerciseData] {
        
        print("🧠 Intelligent Workout Generation Started")
        print("   Target: \(targetBodyParts)")
        print("   Equipment: \(availableEquipment)")
        print("   Difficulty: \(difficulty.rawValue)")
        
        // Step 1: Get all exercises and classify them
        let allExercises = ExerciseDataProvider.shared.exercises
        let classifiedExercises = allExercises.map { classifyExercise($0) }
        
        // Step 2: Filter by body parts and equipment
        let filtered = filterExercises(
            classifiedExercises,
            targetBodyParts: targetBodyParts,
            availableEquipment: availableEquipment,
            difficulty: difficulty
        )
        
        print("   Filtered exercises: \(filtered.count)")
        
        // Step 3: Remove recently used exercises
        var candidates = filtered
        if avoidRecentExercises {
            candidates = removeRecentExercises(filtered)
            print("   After removing recent: \(candidates.count)")
        }
        
        // Step 4: Build balanced workout with smart selection
        let selectedExercises = buildBalancedWorkout(
            from: candidates,
            targetBodyParts: targetBodyParts,
            exerciseCount: exerciseCount,
            balancePatterns: balanceMovementPatterns
        )
        
        // Step 5: Track usage for future variety
        trackExerciseUsage(selectedExercises.map { $0.exercise.name })
        
        print("✅ Generated \(selectedExercises.count) exercises with variety")
        return selectedExercises.map { $0.exercise }
    }
    
    // MARK: - Enhanced Workout Generation (Uses ExerciseIntelligenceEngine)
    
    /// Generate workout using the advanced intelligence engine with 7000+ exercise library
    func generateSmartWorkout(
        targetMuscles: [String],
        availableEquipment: [String],
        skillLevel: String,
        duration: Int,
        goal: ExerciseIntelligenceEngine.FitnessGoal
    ) -> GeneratedWorkout {
        print("🧠 Smart Workout Generation (Intelligence Engine)")
        print("   Muscles: \(targetMuscles)")
        print("   Equipment: \(availableEquipment)")
        print("   Skill: \(skillLevel), Duration: \(duration)min, Goal: \(goal.rawValue)")
        
        let workout = ExerciseIntelligenceEngine.shared.generateWorkout(
            targetMuscles: targetMuscles,
            availableEquipment: availableEquipment,
            skillLevel: skillLevel,
            duration: duration,
            goal: goal
        )
        
        print("✅ Generated \(workout.exercises.count) exercises, est. \(workout.estimatedDuration)min")
        return workout
    }
    
    /// Find substitutes for an exercise when equipment isn't available
    func findSubstitutes(for exerciseName: String, availableEquipment: [String]) -> [ExerciseIntelligenceEngine.ExerciseMetadata] {
        return ExerciseIntelligenceEngine.shared.findEquipmentSubstitutions(
            for: exerciseName,
            availableEquipment: availableEquipment
        )
    }
    
    /// Find exercises that pair well for supersets
    func findSupersetPartners(for exerciseName: String) -> [ExerciseIntelligenceEngine.ExerciseMetadata] {
        return ExerciseIntelligenceEngine.shared.findComplementaryExercises(for: exerciseName)
    }
    
    // MARK: - Exercise Classification Engine
    
    private func classifyExercise(_ exercise: ExerciseData) -> ExerciseMetadata {
        let name = exercise.name.lowercased()
        let category = exercise.category.lowercased()
        let muscles = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
        let equipment = exercise.equipment.lowercased()
        
        // Determine movement pattern
        let pattern = determineMovementPattern(name: name, category: category, muscles: muscles)
        
        // Determine emphasis
        let emphasis = determineEmphasis(name: name, category: category, muscles: muscles, pattern: pattern)
        
        // Determine complexity
        let complexity = determineComplexity(name: name, emphasis: emphasis)
        
        // Classify equipment
        let equipmentType = classifyEquipment(equipment)
        
        // Split primary and secondary muscles
        let (primary, secondary) = splitMuscles(muscles, category: category)
        
        // Create movement signature for avoiding duplicates
        let signature = createMovementSignature(name: name, pattern: pattern)
        
        return ExerciseMetadata(
            exercise: exercise,
            movementPattern: pattern,
            emphasis: emphasis,
            complexity: complexity,
            equipment: equipmentType,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            movementSignature: signature
        )
    }
    
    private func determineMovementPattern(name: String, category: String, muscles: [String]) -> MovementPattern {
        // Push patterns
        if name.contains("press") || name.contains("push") || name.contains("dip") ||
           name.contains("fly") || name.contains("raise") && (muscles.contains("chest") || muscles.contains("shoulders") || muscles.contains("triceps")) {
            return .push
        }
        
        // Pull patterns
        if name.contains("pull") || name.contains("row") || name.contains("curl") && !name.contains("leg curl") ||
           name.contains("pulldown") || name.contains("chin") {
            return .pull
        }
        
        // Squat patterns
        if name.contains("squat") {
            return .squat
        }
        
        // Hinge patterns
        if name.contains("deadlift") || name.contains("good morning") ||
           (name.contains("swing") && muscles.contains("glutes")) {
            return .hinge
        }
        
        // Lunge patterns
        if name.contains("lunge") || name.contains("step up") || name.contains("split squat") {
            return .lunge
        }
        
        // Plank/Core
        if name.contains("plank") || name.contains("hollow") || name.contains("bird dog") {
            return .plank
        }
        
        // Ground-based
        if name.contains("sit up") || name.contains("crunch") || name.contains("leg raise") && category.contains("abs") {
            return .groundBased
        }
        
        // Rotation
        if name.contains("twist") || name.contains("rotation") || name.contains("chop") {
            return .rotation
        }
        
        // Default to isolation
        return .isolation
    }
    
    private func determineEmphasis(name: String, category: String, muscles: [String], pattern: MovementPattern) -> ExerciseEmphasis {
        // Compound movements (multi-joint, heavy)
        if pattern == .squat || pattern == .hinge || pattern == .lunge ||
           name.contains("deadlift") || name.contains("squat") || name.contains("press") && name.contains("bench") ||
           name.contains("pull up") || name.contains("chin up") {
            return .compound
        }
        
        // Unilateral
        if name.contains("single") || name.contains("one arm") || name.contains("one leg") ||
           name.contains("unilateral") || name.contains("alternate") && !name.contains("alternating grip") {
            return .unilateral
        }
        
        // Stability/Core
        if pattern == .plank || name.contains("stabilization") || name.contains("balance") ||
           category.contains("core") || name.contains("bird dog") {
            return .stability
        }
        
        // Isometric holds
        if name.contains("hold") || name.contains("plank") || name.contains("static") {
            return .isometric
        }
        
        // Isolation (single muscle, single joint)
        if name.contains("curl") || name.contains("extension") && !name.contains("back extension") ||
           name.contains("fly") || name.contains("raise") && !name.contains("leg raise") ||
           name.contains("kickback") || muscles.count == 1 {
            return .isolation
        }
        
        // Default to accessory
        return .accessory
    }
    
    private func determineComplexity(name: String, emphasis: ExerciseEmphasis) -> ExerciseComplexity {
        // Advanced movements
        if name.contains("olympic") || name.contains("clean") || name.contains("snatch") ||
           name.contains("muscle up") || name.contains("pistol") {
            return .advanced
        }
        
        // Beginner movements
        if name.contains("machine") || name.contains("assisted") ||
           emphasis == .isolation || name.contains("bodyweight") && !name.contains("pull up") {
            return .beginner
        }
        
        // Default to intermediate
        return .intermediate
    }
    
    private func classifyEquipment(_ equipment: String) -> EquipmentType {
        if equipment.contains("barbell") { return .barbell }
        if equipment.contains("dumbbell") { return .dumbbell }
        if equipment.contains("cable") { return .cable }
        if equipment.contains("machine") || equipment.contains("lever") || equipment.contains("smith") { return .machine }
        if equipment.contains("bodyweight") || equipment.contains("body weight") { return .bodyweight }
        if equipment.contains("kettlebell") { return .kettlebell }
        if equipment.contains("band") || equipment.contains("resistance") { return .band }
        return .other
    }
    
    private func splitMuscles(_ muscles: [String], category: String) -> ([String], [String]) {
        // First muscle is usually primary, rest are secondary
        if muscles.isEmpty {
            return ([category.lowercased()], [])
        }
        
        let primary = [muscles[0]]
        let secondary = muscles.count > 1 ? Array(muscles[1...]) : []
        return (primary, secondary)
    }
    
    private func createMovementSignature(name: String, pattern: MovementPattern) -> String {
        // Create a signature to identify similar movements
        // e.g., "Barbell Front Raise" and "Dumbbell Front Raise" = "front raise"
        
        let stopWords = ["barbell", "dumbbell", "cable", "machine", "smith", "ez",
                        "lever", "band", "kettlebell", "seated", "standing", "lying",
                        "incline", "decline", "flat", "high", "low", "wide", "close",
                        "grip", "neutral", "underhand", "overhand", "single", "double",
                        "alternate", "alternating", "with", "on", "to", "the", "-", "(", ")"]
        
        var words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .filter { !stopWords.contains($0) }
        
        // Keep only the core movement words
        let signature = words.joined(separator: " ")
        return signature.isEmpty ? name : signature
    }
    
    // MARK: - Filtering Logic
    
    private func filterExercises(
        _ exercises: [ExerciseMetadata],
        targetBodyParts: Set<String>,
        availableEquipment: Set<String>,
        difficulty: ExerciseComplexity
    ) -> [ExerciseMetadata] {
        
        let normalizedTargets = targetBodyParts.map { $0.lowercased() }
        let normalizedEquipment = availableEquipment.map { $0.lowercased() }
        
        return exercises.filter { meta in
            // Filter by body parts (primary or secondary muscles)
            let muscleMatch = normalizedTargets.isEmpty || normalizedTargets.contains(where: { target in
                meta.primaryMuscles.contains(where: { $0.contains(target) || target.contains($0) }) ||
                meta.secondaryMuscles.contains(where: { $0.contains(target) || target.contains($0) }) ||
                meta.exercise.category.lowercased().contains(target) ||
                target.contains(meta.exercise.category.lowercased())
            })
            
            // Filter by equipment
            let equipmentMatch = normalizedEquipment.isEmpty ||
                normalizedEquipment.contains("all") ||
                normalizedEquipment.contains(where: { equip in
                    meta.exercise.equipment.lowercased().contains(equip) ||
                    equip.contains(meta.exercise.equipment.lowercased())
                })
            
            // Filter by difficulty (allow beginner and intermediate for intermediate difficulty)
            let difficultyMatch = meta.complexity == difficulty ||
                (difficulty == .intermediate && meta.complexity == .beginner) ||
                (difficulty == .advanced && meta.complexity == .intermediate)
            
            return muscleMatch && equipmentMatch && difficultyMatch
        }
    }
    
    private func removeRecentExercises(_ exercises: [ExerciseMetadata]) -> [ExerciseMetadata] {
        // Get recently used exercise names from last few workouts
        let recentNames = Set(lastGeneratedWorkouts.flatMap { $0 })
        
        // Remove exercises used in last workouts, but keep some if we run out
        let fresh = exercises.filter { !recentNames.contains($0.exercise.name) }
        
        // If we filtered out too many, add some back
        if fresh.count < 10 && !exercises.isEmpty {
            return exercises
        }
        
        return fresh.isEmpty ? exercises : fresh
    }
    
    // MARK: - Balanced Workout Building
    
    private func buildBalancedWorkout(
        from candidates: [ExerciseMetadata],
        targetBodyParts: Set<String>,
        exerciseCount: Int,
        balancePatterns: Bool
    ) -> [ExerciseMetadata] {
        
        var selected: [ExerciseMetadata] = []
        var usedSignatures = Set<String>()
        var patternCounts: [MovementPattern: Int] = [:]
        var emphasisCounts: [ExerciseEmphasis: Int] = [:]
        
        // Get user's preferred gender for video matching
        let userGender = UserManager.shared.currentUser?.gender?.lowercased() ?? "male"
        let preferredGender: VideoStreamingService.VideoGender = userGender.contains("female") ? .female : .male
        
        // Get user's skill level for difficulty-based scoring
        let userLevel = UserManager.shared.currentUser?.experienceLevel?.lowercased() ?? "intermediate"
        let isAdvanced = userLevel == "advanced"
        let isBeginner = userLevel == "beginner"
        
        // Scoring system for exercise selection
        func scoreExercise(_ meta: ExerciseMetadata) -> Double {
            var score = 100.0
            let exerciseKey = meta.exercise.name.lowercased()
            let exerciseEquipment = meta.exercise.equipment.lowercased()
            
            // 🎯 SKILL LEVEL MATCHING - Most important factor
            // This ensures exercises match user's ability level
            
            // Technical/complex exercises (Olympic lifts, advanced movements)
            let technicalKeywords = ["snatch", "clean", "jerk", "muscle up", "pistol", 
                                     "handstand", "planche", "dragon flag", "l-sit", 
                                     "front lever", "back lever", "human flag", "strict press"]
            let isTechnicalExercise = technicalKeywords.contains(where: { exerciseKey.contains($0) })
            
            // Beginner-friendly exercises
            let beginnerKeywords = ["machine", "assisted", "supported", "seated", 
                                    "lying", "cable", "leg press", "smith"]
            let isBeginnerFriendly = beginnerKeywords.contains(where: { 
                exerciseKey.contains($0) || exerciseEquipment.contains($0) 
            })
            
            // Score based on skill level
            if isBeginner {
                // Beginners: Prefer machine/assisted exercises, avoid technical movements
                if isTechnicalExercise {
                    score -= 300  // Heavily penalize technical exercises
                }
                if isBeginnerFriendly {
                    score += 100  // Boost beginner-friendly exercises
                }
                // Prefer isolation over compound for beginners (easier to learn)
                if meta.emphasis == .isolation {
                    score += 30
                }
            } else if isAdvanced {
                // Advanced: Prefer technical/compound exercises, slight penalty for too-easy exercises
                if isTechnicalExercise {
                    score += 150  // Big boost for technical exercises
                }
                if isBeginnerFriendly && !exerciseKey.contains("cable") {
                    score -= 50  // Slight penalty for "easy" exercises (except cables which are great)
                }
                // Prefer compound movements
                if meta.emphasis == .compound {
                    score += 80
                }
                // Advanced users should see more barbell/dumbbell work
                if exerciseEquipment.contains("barbell") || exerciseEquipment.contains("dumbbell") {
                    score += 40
                }
            } else {
                // Intermediate: Balanced approach
                if isTechnicalExercise {
                    score -= 50  // Slight penalty for very technical
                }
                if meta.emphasis == .compound {
                    score += 40
                }
            }
            
            // 📍 ENVIRONMENT FIT - Prioritize exercises appropriate for user's workout location
            // Gym users get gym exercises, home users get home exercises
            let environmentAdjustment = WorkoutEnvironmentService.shared.getEnvironmentScoreAdjustment(
                exerciseName: meta.exercise.name,
                equipment: meta.exercise.equipment
            )
            score += Double(environmentAdjustment)
            
            // 🚫 OBSCURE EXERCISE PENALTY - Deprioritize weird/uncommon exercises
            // "Under table pull ups", "couch dips", etc. should rarely appear
            let obscurePatterns = ["under table", "couch", "doorway", "towel", "broomstick", 
                                   "suitcase", "grocery", "water bottle", "backpack", "gallon"]
            for pattern in obscurePatterns {
                if exerciseKey.contains(pattern) || exerciseEquipment.contains(pattern) {
                    score -= 250 // Heavy penalty (increased)
                }
            }
            
            // 📊 POPULARITY BOOST - Prioritize well-known, proven exercises
            // This helps users discover effective exercises and ensures quality
            let popularityBoost = ExercisePopularityService.shared.getPopularityBoost(for: meta.exercise.name)
            score += Double(popularityBoost)
            
            // 🔥 TRENDING BOOST - Exercises gaining recent usage across all users
            if ExercisePopularityService.shared.isTrendingExercise(meta.exercise.name) {
                score += 40
            }
            
            // ⭐ COMMUNITY FAVORITES - Exercises many users have favorited
            if ExercisePopularityService.shared.isCommunityFavorite(meta.exercise.name) {
                score += 60
            }
            
            // 👤 GENDER MATCH - Check if exercise has matching gender video
            // Use VideoStreamingService's gender cache
            let genderCache = VideoStreamingService.shared.genderVideoCache
            if let genderInfo = genderCache[exerciseKey] {
                // Check if we have a video for the user's preferred gender
                if genderInfo.filename(for: preferredGender) != nil {
                    score += 150  // Big boost for gender match
                } else if genderInfo.filenameWithFallback(preferred: preferredGender) != nil {
                    score -= 100  // Penalty for opposite gender (fallback only)
                }
            }
            
            // 💝 SMART FAVORITE-BASED SCORING
            // Uses favorites as seeds for variety - not just the exact exercise
            let favoriteScore = FavoriteBasedDiscoveryEngine.shared.getFavoriteBasedScore(
                for: meta.exercise.name,
                targetMuscles: Array(targetBodyParts)
            )
            score += favoriteScore
            
            // Legacy: Direct favorite check (reduced from 200 to allow discovery engine to work)
            if isFavoriteExercise(meta.exercise.name) && favoriteScore == 0 {
                score += 80  // Backup boost if discovery engine didn't catch it
            }
            
            // Prioritize compound movements early in workout (first 2 exercises)
            if selected.count < 2 && meta.emphasis == .compound {
                score += 50
            }
            
            // Avoid duplicate movement signatures
            if usedSignatures.contains(meta.movementSignature) {
                score -= 100
            }
            
            // Balance movement patterns
            if balancePatterns {
                let patternCount = patternCounts[meta.movementPattern] ?? 0
                score -= Double(patternCount * 20)
            }
            
            // Balance emphasis types
            let emphasisCount = emphasisCounts[meta.emphasis] ?? 0
            score -= Double(emphasisCount * 15)
            
            // Prefer primary muscle match
            let normalizedTargets = targetBodyParts.map { $0.lowercased() }
            let primaryMatch = normalizedTargets.contains(where: { target in
                meta.primaryMuscles.contains(where: { $0.contains(target) || target.contains($0) })
            })
            if primaryMatch {
                score += 30
            }
            
            // Add some randomness for variety (reduced to keep popular exercises more consistent)
            score += Double.random(in: 0...15)
            
            return score
        }
        
        // Create a pool of candidates with scores
        var scoredCandidates = candidates.map { ($0, scoreExercise($0)) }
        
        // Select exercises
        while selected.count < exerciseCount && !scoredCandidates.isEmpty {
            // Sort by score and pick the top one
            scoredCandidates.sort { $0.1 > $1.1 }
            let (best, _) = scoredCandidates.removeFirst()
            
            selected.append(best)
            usedSignatures.insert(best.movementSignature)
            patternCounts[best.movementPattern, default: 0] += 1
            emphasisCounts[best.emphasis, default: 0] += 1
            
            // Rescore remaining candidates
            scoredCandidates = scoredCandidates.map { ($0.0, scoreExercise($0.0)) }
        }
        
        // Log the selection with favorite-based discovery info
        print("📊 Workout Balance:")
        print("   Patterns: \(patternCounts)")
        print("   Emphasis: \(emphasisCounts)")
        
        // Log favorite-based recommendations
        for meta in selected {
            let favoriteScore = FavoriteBasedDiscoveryEngine.shared.getFavoriteBasedScore(
                for: meta.exercise.name,
                targetMuscles: Array(targetBodyParts)
            )
            if favoriteScore > 0 {
                if isFavoriteExercise(meta.exercise.name) {
                    print("   ⭐ \(meta.exercise.name) - Your favorite!")
                } else {
                    print("   🔄 \(meta.exercise.name) - Based on your favorites (score: +\(Int(favoriteScore)))")
                }
            }
        }
        
        return selected
    }
    
    // MARK: - Favorite Exercise Checking
    
    private func isFavoriteExercise(_ exerciseName: String) -> Bool {
        // Query Core Data to see if this exercise is marked as favorite
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        if let exercise = allExercises.first(where: { $0.name == exerciseName }) {
            return exercise.isFavorite
        }
        return false
    }
    
    // MARK: - Usage Tracking
    
    private func trackExerciseUsage(_ exerciseNames: [String]) {
        // Add to history
        let now = Date()
        for name in exerciseNames {
            if userExerciseHistory[name] == nil {
                userExerciseHistory[name] = []
            }
            userExerciseHistory[name]?.append(now)
        }
        
        // Add to recent workouts
        lastGeneratedWorkouts.append(exerciseNames)
        if lastGeneratedWorkouts.count > maxHistoryWorkouts {
            lastGeneratedWorkouts.removeFirst()
        }
    }
    
    // MARK: - Statistics & Analytics
    
    func getExerciseUsageStats() -> [String: Int] {
        return userExerciseHistory.mapValues { $0.count }
    }
    
    func clearHistory() {
        userExerciseHistory.removeAll()
        lastGeneratedWorkouts.removeAll()
        print("🧹 Exercise history cleared")
    }
    
    func getUnusedExercises(forBodyParts bodyParts: Set<String>, equipment: Set<String>) -> [ExerciseData] {
        let allExercises = ExerciseDataProvider.shared.exercises
        let classified = allExercises.map { classifyExercise($0) }
        let filtered = filterExercises(classified, targetBodyParts: bodyParts, availableEquipment: equipment, difficulty: .intermediate)
        
        let usedNames = Set(userExerciseHistory.keys)
        return filtered
            .filter { !usedNames.contains($0.exercise.name) }
            .map { $0.exercise }
    }
}

