import Foundation
import CoreData

// MARK: - Smart Recommendation Engine 2.0
// A comprehensive personalization system that uses:
// - User profile data (age, gender, goals, experience, equipment, etc.)
// - Workout history and patterns
// - Muscle recovery and fatigue tracking
// - Community popularity and trending data
// - Progressive overload and adaptation

class SmartRecommendationEngine {
    static let shared = SmartRecommendationEngine()
    
    private init() {}
    
    // MARK: - Sub-Engines
    let userProfileAnalyzer = UserProfileAnalyzer()
    let muscleRecoveryTracker = MuscleRecoveryTracker()
    let communityInsights = CommunityInsightsEngine()
    let progressiveOverloadEngine = ProgressiveOverloadEngine()
    
    // MARK: - Main Recommendation Entry Point
    
    /// Generate a fully personalized workout based on all available user data
    func generatePersonalizedWorkout(
        for user: User,
        targetMuscles: Set<String>? = nil,
        duration: Int = 45,
        context: NSManagedObjectContext
    ) -> PersonalizedWorkoutPlan {
        
        print("🧠 Smart Recommendation Engine 2.0 Starting...")
        
        // Step 1: Analyze user profile
        let profile = userProfileAnalyzer.analyzeUser(user)
        print("   Profile Analysis: \(profile.summary)")
        
        // Step 2: Check muscle recovery status
        let recoveryStatus = muscleRecoveryTracker.getRecoveryStatus(for: user, context: context)
        print("   Recovery Status: \(recoveryStatus.summary)")
        
        // Step 3: Get community insights
        let communityData = communityInsights.getCachedInsights()
        print("   Community Data: \(communityData.topExercises.count) popular exercises loaded")
        
        // Step 4: Determine optimal muscles to train today
        let optimalMuscles = determineOptimalMuscles(
            requested: targetMuscles,
            recovery: recoveryStatus,
            profile: profile
        )
        print("   Optimal Muscles: \(optimalMuscles)")
        
        // Step 5: Get prioritized equipment
        let equipment = profile.prioritizedEquipment
        print("   Equipment Priority: \(equipment)")
        
        // Step 6: Calculate personalized parameters
        let parameters = calculatePersonalizedParameters(profile: profile, duration: duration)
        print("   Parameters: \(parameters.exerciseCount) exercises, \(parameters.setsPerExercise) sets avg")
        
        // Step 7: Generate exercises with all factors
        let exercises = generateSmartExercises(
            muscles: optimalMuscles,
            equipment: equipment,
            parameters: parameters,
            profile: profile,
            recovery: recoveryStatus,
            community: communityData
        )
        
        // Step 8: Apply progressive overload suggestions
        let exercisesWithProgression = progressiveOverloadEngine.applyProgressionSuggestions(
            to: exercises,
            for: user,
            context: context
        )
        
        print("✅ Generated \(exercisesWithProgression.count) personalized exercises")
        
        return PersonalizedWorkoutPlan(
            exercises: exercisesWithProgression,
            targetMuscles: optimalMuscles,
            estimatedDuration: duration,
            difficulty: parameters.difficulty,
            personalizedNotes: generatePersonalizedNotes(profile: profile, recovery: recoveryStatus)
        )
    }
    
    // MARK: - Smart Muscle Selection
    
    private func determineOptimalMuscles(
        requested: Set<String>?,
        recovery: MuscleRecoveryStatus,
        profile: UserProfileAnalysis
    ) -> Set<String> {
        
        // If user explicitly requested muscles, filter out any that aren't recovered
        if let requested = requested, !requested.isEmpty {
            let recovered = requested.filter { muscle in
                recovery.muscleReadiness[muscle.lowercased()] ?? 1.0 >= 0.6
            }
            
            // If most requested muscles are recovered, use them
            if recovered.count >= requested.count / 2 {
                return Set(recovered)
            }
            
            // Otherwise suggest alternatives
            print("   ⚠️ Some requested muscles need more recovery, adjusting...")
        }
        
        // Auto-select best muscles to train based on recovery
        let readyMuscles = recovery.muscleReadiness
            .filter { $0.value >= 0.7 } // At least 70% recovered
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map { $0.key.capitalized }
        
        if !readyMuscles.isEmpty {
            return Set(readyMuscles)
        }
        
        // Fallback: train least recently trained
        return Set(recovery.leastRecentlyTrained.prefix(3).map { $0.capitalized })
    }
    
    // MARK: - Personalized Parameters
    
    private func calculatePersonalizedParameters(
        profile: UserProfileAnalysis,
        duration: Int
    ) -> WorkoutParameters {
        
        var exerciseCount: Int
        var setsPerExercise: Int
        var restBetweenSets: Int
        var repRange: ClosedRange<Int>
        var difficulty: WorkoutDifficulty
        
        // Base parameters on experience level
        switch profile.experienceLevel {
        case .beginner:
            exerciseCount = min(5, max(3, duration / 10))
            setsPerExercise = 3
            restBetweenSets = 90
            repRange = 10...15
            difficulty = .beginner
            
        case .intermediate:
            exerciseCount = min(7, max(4, duration / 8))
            setsPerExercise = 4
            restBetweenSets = 75
            repRange = 8...12
            difficulty = .intermediate
            
        case .advanced:
            exerciseCount = min(9, max(5, duration / 6))
            setsPerExercise = 4
            restBetweenSets = 60
            repRange = 6...10
            difficulty = .advanced
        }
        
        // Adjust for fitness goal
        switch profile.fitnessGoal {
        case .gainStrength, .powerlifting:
            repRange = profile.experienceLevel == .beginner ? 6...10 : 3...6
            restBetweenSets += 30
            setsPerExercise = min(setsPerExercise + 1, 5)
            
        case .buildMuscle, .bodybuilding:
            repRange = 8...12
            restBetweenSets = 60
            
        case .improveEndurance, .athletic:
            repRange = 15...20
            restBetweenSets = 45
            exerciseCount += 1
            
        case .loseWeight:
            repRange = 12...15
            restBetweenSets = 45
            exerciseCount += 2
            
        case .toneUp:
            repRange = 12...15
            restBetweenSets = 60
            
        case .generalFitness, .flexibility:
            break
        }
        
        // Adjust for age
        if profile.age > 50 {
            restBetweenSets += 15
            repRange = (repRange.lowerBound + 2)...(repRange.upperBound + 2) // Higher reps, lighter weight
        } else if profile.age < 25 {
            restBetweenSets = max(45, restBetweenSets - 10)
        }
        
        // Adjust for available time
        if duration < 30 {
            exerciseCount = max(3, exerciseCount - 2)
            restBetweenSets = max(45, restBetweenSets - 15)
        } else if duration > 60 {
            exerciseCount = min(10, exerciseCount + 1)
        }
        
        return WorkoutParameters(
            exerciseCount: exerciseCount,
            setsPerExercise: setsPerExercise,
            restBetweenSets: restBetweenSets,
            repRange: repRange,
            difficulty: difficulty
        )
    }
    
    // MARK: - Smart Exercise Generation
    
    private func generateSmartExercises(
        muscles: Set<String>,
        equipment: [String],
        parameters: WorkoutParameters,
        profile: UserProfileAnalysis,
        recovery: MuscleRecoveryStatus,
        community: CommunityInsightsData
    ) -> [RecommendedExercise] {
        
        let allExercises = ExerciseDataProvider.shared.exercises
        var selectedExercises: [RecommendedExercise] = []
        var usedMovementPatterns: Set<String> = []
        var usedExerciseNames: Set<String> = []
        
        // Score each exercise based on multiple factors
        let scoredExercises = allExercises.compactMap { exercise -> (ExerciseData, Double)? in
            let score = calculateExerciseScore(
                exercise: exercise,
                targetMuscles: muscles,
                equipment: equipment,
                profile: profile,
                recovery: recovery,
                community: community,
                usedPatterns: usedMovementPatterns,
                usedNames: usedExerciseNames
            )
            
            guard score > 0 else { return nil }
            return (exercise, score)
        }
        .sorted { $0.1 > $1.1 }
        
        // Select top exercises while maintaining variety
        for (exercise, score) in scoredExercises {
            guard selectedExercises.count < parameters.exerciseCount else { break }
            
            let pattern = getMovementPattern(for: exercise.name)
            
            // Skip if we already have 2 exercises with same pattern
            let patternCount = usedMovementPatterns.filter { $0 == pattern }.count
            if patternCount >= 2 { continue }
            
            // Skip duplicate exercise names
            if usedExerciseNames.contains(exercise.name.lowercased()) { continue }
            
            let recommended = RecommendedExercise(
                exercise: exercise,
                recommendedSets: parameters.setsPerExercise,
                recommendedReps: parameters.repRange,
                restSeconds: parameters.restBetweenSets,
                reasonForRecommendation: getRecommendationReason(score: score, profile: profile, community: community, exercise: exercise),
                personalScore: score
            )
            
            selectedExercises.append(recommended)
            usedMovementPatterns.insert(pattern)
            usedExerciseNames.insert(exercise.name.lowercased())
        }
        
        // Sort by movement pattern priority (compounds first)
        return selectedExercises.sorted { ex1, ex2 in
            let pattern1 = getMovementPattern(for: ex1.exercise.name)
            let pattern2 = getMovementPattern(for: ex2.exercise.name)
            return movementPatternPriority(pattern1) > movementPatternPriority(pattern2)
        }
    }
    
    // MARK: - Exercise Scoring System
    
    private func calculateExerciseScore(
        exercise: ExerciseData,
        targetMuscles: Set<String>,
        equipment: [String],
        profile: UserProfileAnalysis,
        recovery: MuscleRecoveryStatus,
        community: CommunityInsightsData,
        usedPatterns: Set<String>,
        usedNames: Set<String>
    ) -> Double {
        
        var score: Double = 0
        let exerciseName = exercise.name.lowercased()
        let exerciseEquipment = exercise.equipment.lowercased()
        let exerciseMuscles = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
        
        // ==========================================
        // MUSCLE TARGETING (0-100 points)
        // ==========================================
        let normalizedTargets = targetMuscles.map { $0.lowercased() }
        
        for target in normalizedTargets {
            if exerciseMuscles.first?.contains(target) == true || target.contains(exerciseMuscles.first ?? "") {
                score += 50 // Primary muscle match
            } else if exerciseMuscles.contains(where: { $0.contains(target) || target.contains($0) }) {
                score += 25 // Secondary muscle match
            }
        }
        
        // Bonus for exercises that hit multiple target muscles
        let matchedMuscles = exerciseMuscles.filter { muscle in
            normalizedTargets.contains(where: { $0.contains(muscle) || muscle.contains($0) })
        }
        if matchedMuscles.count > 1 {
            score += Double(matchedMuscles.count) * 10
        }
        
        // ==========================================
        // EQUIPMENT PRIORITY (0-80 points)
        // ==========================================
        let normalizedEquipment = equipment.map { $0.lowercased() }
        
        for (index, equip) in normalizedEquipment.enumerated() {
            if exerciseEquipment.contains(equip) || equip.contains(exerciseEquipment) {
                // Higher priority equipment = higher score
                let priorityBonus = Double(equipment.count - index) * 15
                score += min(80, priorityBonus)
                break
            }
        }
        
        // Penalize if equipment not in user's list at all
        let hasMatchingEquipment = normalizedEquipment.contains { equip in
            exerciseEquipment.contains(equip) || equip.contains(exerciseEquipment)
        }
        if !hasMatchingEquipment && !normalizedEquipment.contains("all") {
            score -= 100 // Strong penalty - don't show exercises user can't do
        }
        
        // ==========================================
        // EXPERIENCE LEVEL MATCH (0-40 points)
        // ==========================================
        let complexity = determineExerciseComplexity(exerciseName)
        
        switch (profile.experienceLevel, complexity) {
        case (.beginner, .beginner):
            score += 40
        case (.beginner, .intermediate):
            score += 20
        case (.beginner, .advanced):
            score -= 30 // Penalize advanced exercises for beginners
            
        case (.intermediate, .beginner):
            score += 25
        case (.intermediate, .intermediate):
            score += 40
        case (.intermediate, .advanced):
            score += 15
            
        case (.advanced, .beginner):
            score += 15
        case (.advanced, .intermediate):
            score += 30
        case (.advanced, .advanced):
            score += 40
        }
        
        // ==========================================
        // FITNESS GOAL ALIGNMENT (0-50 points)
        // ==========================================
        score += goalAlignmentScore(exercise: exercise, goal: profile.fitnessGoal)
        
        // ==========================================
        // MUSCLE RECOVERY STATUS (0-30 points)
        // ==========================================
        for muscle in exerciseMuscles {
            if let readiness = recovery.muscleReadiness[muscle] {
                if readiness >= 0.9 {
                    score += 30 // Fully recovered, great to train
                } else if readiness >= 0.7 {
                    score += 15 // Mostly recovered
                } else if readiness < 0.5 {
                    score -= 40 // Not recovered, avoid
                }
            }
        }
        
        // ==========================================
        // COMMUNITY POPULARITY BOOST (0-30 points)
        // ==========================================
        if community.isPopularExercise(exerciseName) {
            score += 15
        }
        if community.isTrendingExercise(exerciseName) {
            score += 10
        }
        if community.isFavoritedExercise(exerciseName) {
            score += 20 // High boost for community favorites
        }
        
        // ==========================================
        // SMART FAVORITE-BASED DISCOVERY (0-180 points)
        // Uses favorites as seeds for variety, not just exact matches
        // ==========================================
        let favoriteScore = FavoriteBasedDiscoveryEngine.shared.getFavoriteBasedScore(
            for: exerciseName,
            targetMuscles: targetMuscles.map { $0.rawValue }
        )
        if favoriteScore > 0 {
            score += favoriteScore
        } else if isUserFavorite(exerciseName) {
            // Fallback for direct favorites
            score += 50
        }
        
        // ==========================================
        // VARIETY BONUS (0-20 points)
        // ==========================================
        let pattern = getMovementPattern(for: exercise.name)
        if !usedPatterns.contains(pattern) {
            score += 20 // Bonus for new movement pattern
        }
        
        // ==========================================
        // AGE-APPROPRIATE ADJUSTMENTS
        // ==========================================
        if profile.age > 55 {
            // Prefer lower-impact, machine-based exercises for older users
            if exerciseEquipment.contains("machine") || exerciseEquipment.contains("cable") {
                score += 15
            }
            // Penalize high-impact exercises
            if exerciseName.contains("jump") || exerciseName.contains("plyometric") || exerciseName.contains("explosive") {
                score -= 25
            }
        }
        
        // ==========================================
        // GENDER CONSIDERATIONS (subtle adjustments)
        // ==========================================
        // Note: These are statistical preferences, not restrictions
        if profile.gender == .female {
            // Women often prefer glute, leg, and core focus
            if exerciseMuscles.contains("glutes") || exerciseMuscles.contains("core") {
                score += 5
            }
        }
        
        return max(0, score)
    }
    
    // MARK: - Helper Functions
    
    private func goalAlignmentScore(exercise: ExerciseData, goal: ProgramGoal) -> Double {
        let name = exercise.name.lowercased()
        let isCompound = name.contains("squat") || name.contains("deadlift") || name.contains("press") ||
                        name.contains("row") || name.contains("pull up") || name.contains("chin up")
        let isIsolation = name.contains("curl") || name.contains("extension") || name.contains("fly") ||
                         name.contains("raise") || name.contains("kickback")
        let isCardio = name.contains("jump") || name.contains("burpee") || name.contains("mountain climber")
        
        switch goal {
        case .gainStrength, .powerlifting:
            return isCompound ? 50 : (isIsolation ? 10 : 20)
        case .buildMuscle, .bodybuilding:
            return isCompound ? 40 : (isIsolation ? 35 : 25)
        case .improveEndurance, .athletic:
            return isCardio ? 50 : (isIsolation ? 20 : 30)
        case .loseWeight:
            return isCompound ? 45 : (isCardio ? 40 : 20)
        case .toneUp:
            return isIsolation ? 40 : (isCompound ? 30 : 25)
        case .generalFitness, .flexibility:
            return isCompound ? 35 : 25
        }
    }
    
    private func determineExerciseComplexity(_ name: String) -> ExperienceLevel {
        let lowercased = name.lowercased()
        
        // Advanced exercises
        if lowercased.contains("olympic") || lowercased.contains("clean") || lowercased.contains("snatch") ||
           lowercased.contains("muscle up") || lowercased.contains("pistol") || lowercased.contains("one arm") {
            return .advanced
        }
        
        // Beginner exercises
        if lowercased.contains("machine") || lowercased.contains("assisted") || lowercased.contains("seated") ||
           lowercased.contains("bodyweight") && !lowercased.contains("pull up") {
            return .beginner
        }
        
        return .intermediate
    }
    
    private func getMovementPattern(for exerciseName: String) -> String {
        let name = exerciseName.lowercased()
        
        if name.contains("press") || name.contains("push") || name.contains("fly") { return "push" }
        if name.contains("pull") || name.contains("row") || name.contains("curl") { return "pull" }
        if name.contains("squat") { return "squat" }
        if name.contains("deadlift") || name.contains("hinge") { return "hinge" }
        if name.contains("lunge") || name.contains("step") { return "lunge" }
        if name.contains("plank") || name.contains("crunch") || name.contains("core") { return "core" }
        
        return "isolation"
    }
    
    private func movementPatternPriority(_ pattern: String) -> Int {
        // Compounds first, isolation last
        switch pattern {
        case "squat", "hinge": return 5
        case "push", "pull": return 4
        case "lunge": return 3
        case "core": return 2
        default: return 1
        }
    }
    
    private func isUserFavorite(_ exerciseName: String) -> Bool {
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        return allExercises.first { $0.name?.lowercased() == exerciseName.lowercased() }?.isFavorite ?? false
    }
    
    private func getRecommendationReason(
        score: Double,
        profile: UserProfileAnalysis,
        community: CommunityInsightsData,
        exercise: ExerciseData
    ) -> String {
        let name = exercise.name
        
        if isUserFavorite(name.lowercased()) {
            return "One of your favorites! ⭐"
        }
        
        if community.isTrendingExercise(name.lowercased()) {
            return "Trending in the community 🔥"
        }
        
        if community.isFavoritedExercise(name.lowercased()) {
            return "Community favorite 💪"
        }
        
        let equipment = profile.prioritizedEquipment.first ?? "equipment"
        if exercise.equipment.lowercased().contains(equipment.lowercased()) {
            return "Uses your preferred \(equipment)"
        }
        
        switch profile.fitnessGoal {
        case .gainStrength, .powerlifting:
            return "Great for building strength"
        case .buildMuscle, .bodybuilding:
            return "Optimal for muscle growth"
        case .loseWeight:
            return "High calorie burn"
        case .improveEndurance, .athletic:
            return "Builds endurance"
        case .toneUp:
            return "Perfect for toning"
        case .generalFitness, .flexibility:
            return "Well-rounded exercise"
        }
    }
    
    private func generatePersonalizedNotes(
        profile: UserProfileAnalysis,
        recovery: MuscleRecoveryStatus
    ) -> [String] {
        var notes: [String] = []
        
        // Recovery-based notes
        let lowRecovery = recovery.muscleReadiness.filter { $0.value < 0.6 }
        if !lowRecovery.isEmpty {
            let muscles = lowRecovery.keys.prefix(2).joined(separator: ", ")
            notes.append("💡 Your \(muscles) may need more recovery. We've adjusted today's workout.")
        }
        
        // Goal-based tips
        switch profile.fitnessGoal {
        case .gainStrength, .powerlifting:
            notes.append("🎯 Focus on heavy weight with longer rest periods (2-3 min)")
        case .buildMuscle, .bodybuilding:
            notes.append("🎯 Aim for time under tension - 3 second negatives work great!")
        case .loseWeight:
            notes.append("🎯 Keep rest periods short (30-45s) for maximum calorie burn")
        case .improveEndurance, .athletic:
            notes.append("🎯 Higher reps with shorter rest builds endurance")
        case .toneUp:
            notes.append("🎯 Moderate weight with controlled movements for definition")
        case .generalFitness, .flexibility:
            notes.append("🎯 Mix up your tempo and rest periods for balanced results")
        }
        
        // Experience-based tips
        if profile.experienceLevel == .beginner {
            notes.append("📚 Form is everything! Start lighter and perfect your technique")
        }
        
        return notes
    }
}

// MARK: - User Profile Analyzer

class UserProfileAnalyzer {
    
    func analyzeUser(_ user: User) -> UserProfileAnalysis {
        // Parse equipment with priority order
        let equipment = (user.equipment as? [String]) ?? []
        let prioritizedEquipment = prioritizeEquipment(equipment, forGoal: user.fitnessGoal ?? "General")
        
        // Determine experience level
        let experience = parseExperienceLevel(user.experienceLevel ?? "Beginner")
        
        // Determine fitness goal
        let goal = parseFitnessGoal(user.fitnessGoal ?? "General Fitness")
        
        // Parse gender
        let gender = parseGender(user.gender)
        
        // Calculate training age (approximate based on total workouts)
        let trainingAge = estimateTrainingAge(totalWorkouts: Int(user.totalWorkouts))
        
        return UserProfileAnalysis(
            age: Int(user.age),
            gender: gender,
            height: Int(user.height),
            weight: Int(user.weight),
            fitnessGoal: goal,
            experienceLevel: experience,
            prioritizedEquipment: prioritizedEquipment,
            availableDays: Int(user.availableDays),
            totalWorkouts: Int(user.totalWorkouts),
            currentStreak: Int(user.currentStreak),
            trainingAge: trainingAge
        )
    }
    
    private func prioritizeEquipment(_ equipment: [String], forGoal goal: String) -> [String] {
        // Prioritize equipment based on fitness goal
        let priority: [String: Int]
        
        switch goal.lowercased() {
        case "strength":
            priority = ["Barbell": 10, "Dumbbells": 8, "Machines": 6, "Cables": 5, "Kettlebell": 4,
                         "Bodyweight": 3, "Smith Machine": 3, "Resistance Bands": 2]
        case "bulk", "build muscle":
            priority = ["Barbell": 10, "Dumbbells": 9, "Cables": 7, "Machines": 6, "Kettlebell": 5,
                         "Smith Machine": 5, "Bodyweight": 4, "Resistance Bands": 3]
        case "cut", "fat loss":
            priority = ["Bodyweight": 9, "Dumbbells": 8, "Cables": 7, "Kettlebell": 7, "Machines": 6,
                         "Resistance Bands": 5, "TRX/Rings": 5, "Barbell": 4]
        case "tone":
            priority = ["Dumbbells": 9, "Cables": 8, "Resistance Bands": 7, "Kettlebell": 7,
                         "Machines": 6, "Bodyweight": 5, "TRX/Rings": 5, "Barbell": 4]
        case "cardio", "endurance":
            priority = ["Bodyweight": 10, "Resistance Bands": 7, "Kettlebell": 6, "TRX/Rings": 6,
                         "Dumbbells": 5, "Cables": 4, "Machines": 3, "Barbell": 2]
        default:
            priority = ["Dumbbells": 8, "Barbell": 8, "Bodyweight": 7, "Cables": 6, "Kettlebell": 6,
                         "Machines": 5, "Smith Machine": 5, "Resistance Bands": 4, "TRX/Rings": 4]
        }
        
        return equipment.sorted { equip1, equip2 in
            (priority[equip1] ?? 0) > (priority[equip2] ?? 0)
        }
    }
    
    private func parseExperienceLevel(_ level: String) -> ExperienceLevel {
        switch level.lowercased() {
        case "beginner", "newbie", "new":
            return .beginner
        case "intermediate", "some experience":
            return .intermediate
        case "advanced", "experienced", "expert":
            return .advanced
        default:
            return .beginner
        }
    }
    
    private func parseFitnessGoal(_ goal: String) -> ProgramGoal {
        ProgramGoal.fromUserGoalString(goal)
    }
    
    private func parseGender(_ gender: String?) -> Gender {
        switch gender?.lowercased() {
        case "male", "m":
            return .male
        case "female", "f":
            return .female
        default:
            return .other
        }
    }
    
    private func estimateTrainingAge(totalWorkouts: Int) -> TrainingAge {
        if totalWorkouts < 20 {
            return .novice
        } else if totalWorkouts < 100 {
            return .beginner
        } else if totalWorkouts < 300 {
            return .intermediate
        } else if totalWorkouts < 500 {
            return .advanced
        } else {
            return .elite
        }
    }
}

// MARK: - Muscle Recovery Tracker

/// Delegates to ProgramMuscleRecoveryTracker (the authoritative singleton) and
/// adapts its data into the MuscleRecoveryStatus format used by SmartRecommendationEngine.
class MuscleRecoveryTracker {
    
    private let trackedMuscles = ["chest", "upper chest", "lower chest", "back", "lats",
                                  "upper back", "quads", "hamstrings", "glutes", "calves",
                                  "shoulders", "front delts", "side delts", "rear delts",
                                  "biceps", "triceps", "forearms", "traps",
                                  "core", "abs", "obliques", "lower back",
                                  "hip flexors", "rotator cuff", "inner thighs", "neck"]
    
    func getRecoveryStatus(for user: User, context: NSManagedObjectContext) -> MuscleRecoveryStatus {
        let tracker = ProgramMuscleRecoveryTracker.shared
        
        var readiness: [String: Double] = [:]
        for muscle in trackedMuscles {
            readiness[muscle] = min(1.0, tracker.getRecoveryPercentage(for: muscle) / 100.0)
        }
        
        let sorted = readiness.sorted { $0.value < $1.value }
        let leastRecent = sorted.map { $0.key }
        
        return MuscleRecoveryStatus(
            muscleReadiness: readiness,
            leastRecentlyTrained: leastRecent,
            weeklyVolume: [:]
        )
    }
}

// MARK: - Community Insights Engine

class CommunityInsightsEngine {
    
    private var cachedData: CommunityInsightsData?
    private var lastFetch: Date?
    private let cacheTimeout: TimeInterval = 3600 // 1 hour
    
    /// Check if insights need refresh (stale or never fetched)
    var needsRefresh: Bool {
        guard let lastFetch = lastFetch else { return true }
        return Date().timeIntervalSince(lastFetch) >= cacheTimeout
    }
    
    func getCachedInsights() -> CommunityInsightsData {
        // Return cached data if fresh enough
        if let cached = cachedData,
           let lastFetch = lastFetch,
           Date().timeIntervalSince(lastFetch) < cacheTimeout {
            return cached
        }
        
        // Return empty data if no cache (will be populated async)
        return cachedData ?? CommunityInsightsData.empty()
    }
    
    func refreshInsights() async {
        do {
            let popular = try await SupabaseManager.shared.fetchPopularExercises(limit: 100)
            let trending = try await SupabaseManager.shared.fetchTrendingExercises(limit: 50)
            let favorited = try await SupabaseManager.shared.fetchMostFavoritedExercises(limit: 50)
            
            let data = CommunityInsightsData(
                topExercises: popular.map { $0.exerciseName.lowercased() },
                trendingExercises: trending.map { $0.exerciseName.lowercased() },
                favoritedExercises: favorited.map { $0.exerciseName.lowercased() },
                popularityScores: Dictionary(uniqueKeysWithValues: popular.map { ($0.exerciseName.lowercased(), $0.popularityScore) }),
                trendingScores: Dictionary(uniqueKeysWithValues: trending.map { ($0.exerciseName.lowercased(), $0.trendingScore) })
            )
            
            await MainActor.run {
                self.cachedData = data
                self.lastFetch = Date()
            }
            
            print("✅ Community insights refreshed: \(popular.count) popular, \(trending.count) trending, \(favorited.count) favorited")
            
        } catch {
            print("⚠️ Error fetching community insights: \(error)")
        }
    }
}

// MARK: - Progressive Overload Engine

class ProgressiveOverloadEngine {
    
    func applyProgressionSuggestions(
        to exercises: [RecommendedExercise],
        for user: User,
        context: NSManagedObjectContext
    ) -> [RecommendedExercise] {
        
        return exercises.map { recommended in
            var updated = recommended
            
            // Look up previous performance for this exercise
            if let previousBest = fetchPreviousBest(for: recommended.exercise.name, context: context) {
                updated.previousWeight = previousBest.weight
                updated.previousReps = previousBest.reps
                
                // Suggest progression based on goal
                let progression = calculateProgression(
                    previousWeight: previousBest.weight,
                    previousReps: previousBest.reps,
                    targetReps: recommended.recommendedReps,
                    experience: parseExperience(user.experienceLevel ?? "Beginner")
                )
                
                updated.suggestedWeight = progression.weight
                updated.progressionNote = progression.note
            }
            
            return updated
        }
    }
    
    private func fetchPreviousBest(for exerciseName: String, context: NSManagedObjectContext) -> (weight: Double, reps: Int)? {
        let request: NSFetchRequest<WorkoutSet> = WorkoutSet.fetchRequest()
        request.predicate = NSPredicate(format: "workoutExercise.exercise.name == %@ AND isCompleted == YES", exerciseName)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutSet.weight, ascending: false)]
        request.fetchLimit = 1
        
        do {
            if let best = try context.fetch(request).first {
                return (best.weight, Int(best.reps))
            }
        } catch {
            print("⚠️ Error fetching previous best: \(error)")
        }
        
        return nil
    }
    
    private func calculateProgression(
        previousWeight: Double,
        previousReps: Int,
        targetReps: ClosedRange<Int>,
        experience: ExperienceLevel
    ) -> (weight: Double, note: String) {
        
        // If previous reps exceeded target range, increase weight
        if previousReps > targetReps.upperBound {
            let increment: Double
            switch experience {
            case .beginner:
                increment = previousWeight < 50 ? 2.5 : 5
            case .intermediate:
                increment = previousWeight < 100 ? 2.5 : 5
            case .advanced:
                increment = 2.5 // Smaller increments for advanced
            }
            
            return (previousWeight + increment, "🔥 You crushed it last time! Add \(Int(increment))lbs")
        }
        
        // If within range, maintain
        if targetReps.contains(previousReps) {
            return (previousWeight, "💪 Match your last weight - try for 1 more rep!")
        }
        
        // If below range, might need to reduce
        if previousReps < targetReps.lowerBound {
            return (max(0, previousWeight - 5), "🎯 Try slightly lighter to hit your rep target")
        }
        
        return (previousWeight, "")
    }
    
    /// Enhanced progression with community insights
    private func calculateProgressionWithCommunityInsights(
        exerciseName: String,
        previousWeight: Double,
        previousReps: Int,
        targetReps: ClosedRange<Int>,
        user: User,
        experience: ExperienceLevel
    ) async -> (weight: Double, note: String) {
        
        // Get base progression
        let baseProgression = calculateProgression(
            previousWeight: previousWeight,
            previousReps: previousReps,
            targetReps: targetReps,
            experience: experience
        )
        
        // Try to get community insights for validation
        if let communityInsight = await ProgressiveWorkoutIntelligence.shared.getCommunityProgressionInsights(
            for: exerciseName,
            userWeight: previousWeight,
            userAge: Int(user.age),
            userGender: user.gender ?? "Other"
        ) {
            
            // If community suggests smaller progression, be conservative
            if communityInsight.confidence > 0.5 {
                let suggestedProgression = previousWeight + communityInsight.averageProgression
                
                // Use community suggestion if more conservative
                if suggestedProgression < baseProgression.weight {
                    return (
                        suggestedProgression,
                        "📊 Community avg: +\(Int(communityInsight.averageProgression))lbs (\(communityInsight.sampleSize) users)"
                    )
                }
            }
        }
        
        // Use base progression if no community data or it agrees
        return baseProgression
    }
    
    private func parseExperience(_ level: String) -> ExperienceLevel {
        switch level.lowercased() {
        case "advanced": return .advanced
        case "intermediate": return .intermediate
        default: return .beginner
        }
    }
}

// MARK: - Data Types

struct UserProfileAnalysis {
    let age: Int
    let gender: Gender
    let height: Int
    let weight: Int
    let fitnessGoal: FitnessGoal
    let experienceLevel: ExperienceLevel
    let prioritizedEquipment: [String]
    let availableDays: Int
    let totalWorkouts: Int
    let currentStreak: Int
    let trainingAge: TrainingAge
    
    var summary: String {
        "\(age)yo \(gender.rawValue), \(experienceLevel.rawValue) level, goal: \(fitnessGoal.rawValue)"
    }
}

struct MuscleRecoveryStatus {
    let muscleReadiness: [String: Double] // 0.0 = not recovered, 1.0 = fully recovered
    let leastRecentlyTrained: [String]
    let weeklyVolume: [String: Int]
    
    var summary: String {
        let ready = muscleReadiness.filter { $0.value >= 0.8 }.count
        let total = muscleReadiness.count
        return "\(ready)/\(total) muscles ready"
    }
    
    static func fullyRecovered() -> MuscleRecoveryStatus {
        MuscleRecoveryStatus(
            muscleReadiness: ["chest": 1, "back": 1, "quads": 1, "hamstrings": 1, "glutes": 1,
                              "shoulders": 1, "biceps": 1, "triceps": 1, "core": 1, "calves": 1],
            leastRecentlyTrained: ["chest", "back", "quads", "hamstrings", "shoulders", "core"],
            weeklyVolume: [:]
        )
    }
}

struct CommunityInsightsData {
    let topExercises: [String]
    let trendingExercises: [String]
    let favoritedExercises: [String]
    let popularityScores: [String: Double]
    let trendingScores: [String: Double]
    
    static func empty() -> CommunityInsightsData {
        CommunityInsightsData(
            topExercises: [],
            trendingExercises: [],
            favoritedExercises: [],
            popularityScores: [:],
            trendingScores: [:]
        )
    }
    
    func isPopularExercise(_ name: String) -> Bool {
        topExercises.contains(name.lowercased())
    }
    
    func isTrendingExercise(_ name: String) -> Bool {
        trendingExercises.contains(name.lowercased())
    }
    
    func isFavoritedExercise(_ name: String) -> Bool {
        favoritedExercises.contains(name.lowercased())
    }
}

struct WorkoutParameters {
    let exerciseCount: Int
    let setsPerExercise: Int
    let restBetweenSets: Int
    let repRange: ClosedRange<Int>
    let difficulty: WorkoutDifficulty
}

struct PersonalizedWorkoutPlan {
    let exercises: [RecommendedExercise]
    let targetMuscles: Set<String>
    let estimatedDuration: Int
    let difficulty: WorkoutDifficulty
    let personalizedNotes: [String]
}

struct RecommendedExercise {
    let exercise: ExerciseData
    let recommendedSets: Int
    let recommendedReps: ClosedRange<Int>
    let restSeconds: Int
    let reasonForRecommendation: String
    let personalScore: Double
    
    // Progressive overload tracking
    var previousWeight: Double?
    var previousReps: Int?
    var suggestedWeight: Double?
    var progressionNote: String?
}

enum ExperienceLevel: String {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

typealias FitnessGoal = ProgramGoal

enum Gender: String {
    case male = "Male"
    case female = "Female"
    case other = "Other"
}

enum TrainingAge {
    case novice      // < 20 workouts
    case beginner    // 20-100 workouts
    case intermediate // 100-300 workouts
    case advanced    // 300-500 workouts
    case elite       // 500+ workouts
}

enum WorkoutDifficulty {
    case beginner
    case intermediate
    case advanced
}

