import Foundation
import CoreData

// MARK: - Strength Profile Recommendation Engine
// A comprehensive system that generates personalized weight/rep recommendations
// based on user's strength assessment, demographics, goals, and exercise type

class StrengthProfileRecommendationEngine {
    static let shared = StrengthProfileRecommendationEngine()
    
    private init() {}
    
    // MARK: - Strength Levels (from household item assessment)
    
    enum StrengthLevel: String, CaseIterable, Codable {
        case veryLight = "Very Light"      // Phone/book (~1-2 lbs / ~1 kg)
        case light = "Light"               // Gallon of milk (~8 lbs / ~4 kg)
        case moderate = "Moderate"         // Bowling ball (~14 lbs / ~6 kg)
        case strong = "Strong"             // Large suitcase (~40 lbs / ~18 kg)
        case veryStrong = "Very Strong"    // Heavy barbell (~60+ lbs / ~27+ kg)
        
        var displayName: String {
            switch self {
            case .veryLight: return "Light Items"
            case .light: return "Milk Jug"
            case .moderate: return "Bowling Ball"
            case .strong: return "Heavy Suitcase"
            case .veryStrong: return "Heavy Weights"
            }
        }
        
        var description: String {
            // Use locale-appropriate units
            let useMetric = !UnitSettingsManager.localeUsesImperial
            
            switch self {
            case .veryLight: return useMetric ? "Books, phones (~1 kg)" : "Books, phones (~2 lbs)"
            case .light: return useMetric ? "Milk jug (~4 kg)" : "Milk jug (~8 lbs)"
            case .moderate: return useMetric ? "Bowling ball (~6 kg)" : "Bowling ball (~14 lbs)"
            case .strong: return useMetric ? "Heavy suitcase (~18 kg)" : "Heavy suitcase (~40 lbs)"
            case .veryStrong: return useMetric ? "Heavy barbell (~27+ kg)" : "Heavy barbell (~60+ lbs)"
            }
        }
        
        var emoji: String {
            switch self {
            case .veryLight: return "📱"
            case .light: return "🥛"
            case .moderate: return "🎳"
            case .strong: return "🧳"
            case .veryStrong: return "🏋️"
            }
        }
        
        // Base strength multiplier (1.0 = moderate baseline)
        var strengthMultiplier: Double {
            switch self {
            case .veryLight: return 0.4
            case .light: return 0.65
            case .moderate: return 1.0
            case .strong: return 1.4
            case .veryStrong: return 1.8
            }
        }
    }
    
    // MARK: - Exercise Categories for Weight Recommendations
    
    enum ExerciseCategory {
        case compoundUpper      // Bench, overhead press, rows
        case compoundLower      // Squats, deadlifts, lunges
        case isolationUpper     // Bicep curls, tricep extensions, laterals
        case isolationLower     // Leg curls, calf raises
        case coreAbdominal      // Planks, crunches (often bodyweight)
        case machineUpper       // Machine presses, cable work
        case machineLower       // Leg press, leg extension
        
        // Base weight (in lbs) for a "moderate" strength person
        // This is a starting point that gets adjusted
        var baseWeight: Double {
            switch self {
            case .compoundUpper: return 65    // Bench press
            case .compoundLower: return 95    // Squat
            case .isolationUpper: return 15   // Bicep curl
            case .isolationLower: return 30   // Leg curl
            case .coreAbdominal: return 0     // Bodyweight
            case .machineUpper: return 50     // Machine press
            case .machineLower: return 90     // Leg press
            }
        }
    }
    
    // MARK: - Smart Recommendation Data Model
    
    struct SmartRecommendation {
        let weight: Double           // Recommended starting weight
        let reps: Int                // Recommended reps
        let sets: Int                // Recommended number of sets
        let isPlaceholder: Bool      // Is this a placeholder (vs real history)
        var confidenceLevel: Double  // 0-1 how confident we are (mutable for enhancement)
        var adjustmentNote: String?  // Optional note about the recommendation (mutable for enhancement)
        
        var displayWeight: String {
            if weight == 0 {
                return "BW"  // Bodyweight
            }
            return "\(Int(weight))"
        }
        
        var displayString: String {
            if weight == 0 {
                return "BW × \(reps)"
            }
            return "\(Int(weight)) × \(reps)"
        }
    }
    
    // MARK: - Main Recommendation Entry Point
    
    /// Generate a smart weight/rep recommendation for an exercise
    func getRecommendation(
        for exerciseName: String,
        user: User,
        setNumber: Int = 1,
        context: NSManagedObjectContext
    ) -> SmartRecommendation {
        
        // First, check if user has history for this exercise
        if let historicalData = fetchLastPerformance(exerciseName: exerciseName, context: context) {
            return SmartRecommendation(
                weight: historicalData.weight,
                reps: historicalData.reps,
                sets: 3,
                isPlaceholder: false,
                confidenceLevel: 1.0,
                adjustmentNote: nil
            )
        }
        
        // No history - generate smart recommendation enhanced with user preferences
        let baseRecommendation = generateSmartRecommendation(
            exerciseName: exerciseName,
            user: user,
            setNumber: setNumber
        )
        
        // Enhance with favorites and workout history patterns
        return enhanceRecommendationWithUserData(
            baseRecommendation,
            exerciseName: exerciseName,
            context: context
        )
    }
    
    /// 🧠 ADVANCED: Get recommendation with full intelligence integration
    /// Incorporates: time-of-day, recovery, nutrition, progression velocity, optimal sets
    func getAdvancedRecommendation(
        for exerciseName: String,
        user: User,
        setNumber: Int = 1,
        context: NSManagedObjectContext
    ) async -> SmartRecommendation {
        guard let userId = user.id else {
            return getRecommendation(for: exerciseName, user: user, setNumber: setNumber, context: context)
        }
        
        // Get base recommendation
        var recommendation = getRecommendation(
            for: exerciseName,
            user: user,
            setNumber: setNumber,
            context: context
        )
        
        // 🧠 Apply Advanced Intelligence Adjustments
        var adjustments: [String] = []
        var weightMultiplier: Double = 1.0
        
        // 1. Time-of-day adjustment
        if let timeData = await AdvancedIntelligenceService.shared.getOptimalWorkoutTime(userId: userId) {
            let currentHour = Calendar.current.component(.hour, from: Date())
            let currentSlot = getTimeSlot(hour: currentHour)
            
            if currentSlot == timeData.timeSlot {
                // User is working out at their optimal time!
                adjustments.append("🌟 Optimal workout time")
            } else if timeData.multiplier > 1.05 {
                // User performs better at a different time
                weightMultiplier *= 0.95  // Slight reduction
                adjustments.append("⏰ Not your peak time (slightly adjusted)")
            }
        }
        
        // 2. Recovery status adjustment
        let recovery = await AdvancedIntelligenceService.shared.getIntelligenceRecoveryRecommendation(userId: userId)
        switch recovery.status {
        case .wellRested:
            weightMultiplier *= 1.05
            adjustments.append("💪 Well rested - push harder!")
        case .fatigued:
            weightMultiplier *= 0.9
            adjustments.append("🧘 Recovery mode - take it easier")
        case .moderate, .normal, .unknown:
            break
        }
        
        // 3. Get optimal set count for this exercise
        let optimalSets = await AdvancedIntelligenceService.shared.getOptimalSetCount(
            userId: userId,
            exerciseName: exerciseName
        )
        
        // 4. Check if this is an effective exercise for the user
        let effectiveExercises = await AdvancedIntelligenceService.shared.getMostEffectiveExercises(userId: userId)
        if effectiveExercises.contains(where: { $0.name.lowercased() == exerciseName.lowercased() }) {
            adjustments.append("⭐ Top exercise for you!")
        }
        
        // Apply multiplier to weight
        let adjustedWeight = recommendation.weight * weightMultiplier
        
        // Build adjustment note
        let adjustmentNote = adjustments.isEmpty ? nil : adjustments.joined(separator: " | ")
        
        // Round to nearest 2.5 or 5 lbs
        let roundedWeight = adjustedWeight < 20 
            ? round(adjustedWeight / 2.5) * 2.5 
            : round(adjustedWeight / 5) * 5
        
        return SmartRecommendation(
            weight: roundedWeight,
            reps: recommendation.reps,
            sets: optimalSets,
            isPlaceholder: recommendation.isPlaceholder,
            confidenceLevel: min(1.0, recommendation.confidenceLevel + 0.1),  // Boost confidence with intelligence
            adjustmentNote: adjustmentNote
        )
    }
    
    private func getTimeSlot(hour: Int) -> String {
        if hour >= 5 && hour < 9 { return "early_morning" }
        if hour >= 9 && hour < 12 { return "morning" }
        if hour >= 12 && hour < 17 { return "afternoon" }
        if hour >= 17 && hour < 21 { return "evening" }
        return "night"
    }
    
    /// Generate recommendations for multiple sets with PROGRESSIVE OVERLOAD
    func getRecommendationsForSets(
        exerciseName: String,
        user: User,
        numberOfSets: Int,
        context: NSManagedObjectContext,
        programWeek: Int? = nil
    ) -> [SmartRecommendation] {
        
        // FIRST: Try to get progressive recommendations based on workout history
        let progressiveSets = ProgressiveWorkoutIntelligence.shared.generateProgressiveSets(
            for: exerciseName,
            targetSetCount: numberOfSets,
            context: context,
            programWeek: programWeek
        )
        
        // If we have progressive recommendations, use them!
        if !progressiveSets.isEmpty {
            return progressiveSets.map { progSet in
                SmartRecommendation(
                    weight: progSet.weight,
                    reps: progSet.reps,
                    sets: numberOfSets,
                    isPlaceholder: false,  // Based on real history
                    confidenceLevel: 0.95,  // High confidence from history
                    adjustmentNote: progSet.note
                )
            }
        }
        
        // FALLBACK: No history - generate smart recommendations
        var recommendations: [SmartRecommendation] = []
        
        for setNumber in 1...numberOfSets {
            let rec = getRecommendation(
                for: exerciseName,
                user: user,
                setNumber: setNumber,
                context: context
            )
            recommendations.append(rec)
        }
        
        return recommendations
    }
    
    // MARK: - Smart Recommendation Generation
    
    private func generateSmartRecommendation(
        exerciseName: String,
        user: User,
        setNumber: Int
    ) -> SmartRecommendation {
        
        // Parse user profile
        let strengthLevel = parseStrengthLevel(user.strengthLevel)
        let age = Int(user.age)
        let gender = user.gender?.lowercased() ?? "other"
        let experience = parseExperienceLevel(user.experienceLevel)
        let goal = user.fitnessGoal?.lowercased() ?? "general"
        
        // Determine exercise category
        let category = categorizeExercise(exerciseName)
        
        // Start with base weight for this exercise category
        var weight = category.baseWeight
        
        // Apply strength level multiplier
        weight *= strengthLevel.strengthMultiplier
        
        // Apply gender adjustment
        weight *= genderMultiplier(gender: gender, category: category)
        
        // Apply age adjustment
        weight *= ageMultiplier(age: age)
        
        // Apply experience adjustment
        weight *= experienceMultiplier(experience: experience)
        
        // Apply goal adjustment (including age-based rep capping)
        let (goalWeightMult, reps) = goalAdjustment(goal: goal, experience: experience, age: age)
        weight *= goalWeightMult
        
        // Round to nearest 5 lbs for most exercises, 2.5 for light isolation
        if weight < 20 {
            weight = round(weight / 2.5) * 2.5
        } else {
            weight = round(weight / 5) * 5
        }
        
        // Ensure minimum weights
        weight = max(weight, minimumWeight(for: category))
        
        // Adjust for set number (later sets might be slightly lighter)
        if setNumber > 2 {
            // Slight reduction for later sets (fatigue)
            weight *= 0.95
            weight = round(weight / 2.5) * 2.5
        }
        
        // Generate confidence based on data quality
        let confidence = calculateConfidence(
            strengthLevel: strengthLevel,
            experience: experience,
            age: age
        )
        
        // Generate note
        let note = generateRecommendationNote(
            weight: weight,
            strengthLevel: strengthLevel,
            experience: experience,
            category: category
        )
        
        return SmartRecommendation(
            weight: weight,
            reps: reps,
            sets: 3,
            isPlaceholder: true,
            confidenceLevel: confidence,
            adjustmentNote: note
        )
    }
    
    // MARK: - Exercise Categorization
    
    private func categorizeExercise(_ name: String) -> ExerciseCategory {
        let lowercased = name.lowercased()
        
        // Compound Lower
        if lowercased.contains("squat") || lowercased.contains("deadlift") ||
           lowercased.contains("lunge") || lowercased.contains("leg press") ||
           lowercased.contains("hip thrust") {
            if lowercased.contains("machine") || lowercased.contains("lever") {
                return .machineLower
            }
            return .compoundLower
        }
        
        // Compound Upper
        if lowercased.contains("bench") || lowercased.contains("press") ||
           lowercased.contains("row") || lowercased.contains("pull") ||
           lowercased.contains("push up") || lowercased.contains("dip") {
            if lowercased.contains("machine") || lowercased.contains("lever") {
                return .machineUpper
            }
            return .compoundUpper
        }
        
        // Isolation Lower
        if lowercased.contains("leg curl") || lowercased.contains("leg extension") ||
           lowercased.contains("calf") || lowercased.contains("glute") {
            if lowercased.contains("machine") || lowercased.contains("lever") {
                return .machineLower
            }
            return .isolationLower
        }
        
        // Core
        if lowercased.contains("crunch") || lowercased.contains("plank") ||
           lowercased.contains("abs") || lowercased.contains("core") ||
           lowercased.contains("sit up") || lowercased.contains("russian twist") {
            return .coreAbdominal
        }
        
        // Machine exercises
        if lowercased.contains("machine") || lowercased.contains("cable") || lowercased.contains("lever") {
            if lowercased.contains("leg") || lowercased.contains("calf") {
                return .machineLower
            }
            return .machineUpper
        }
        
        // Default to isolation upper for curls, raises, etc.
        if lowercased.contains("curl") || lowercased.contains("extension") ||
           lowercased.contains("raise") || lowercased.contains("fly") ||
           lowercased.contains("kickback") || lowercased.contains("shrug") {
            return .isolationUpper
        }
        
        return .isolationUpper // Default
    }
    
    // MARK: - Adjustment Multipliers
    
    private func genderMultiplier(gender: String, category: ExerciseCategory) -> Double {
        // Based on average strength differences
        // These are statistical averages, not limitations
        switch gender {
        case "male", "m":
            return 1.0
        case "female", "f":
            switch category {
            case .compoundUpper, .isolationUpper, .machineUpper:
                return 0.55  // Upper body shows larger difference
            case .compoundLower, .isolationLower, .machineLower:
                return 0.70  // Lower body closer
            case .coreAbdominal:
                return 0.9   // Core similar
            }
        default:
            return 0.8 // Neutral/unknown - use conservative estimate
        }
    }
    
    private func ageMultiplier(age: Int) -> Double {
        // Adjust for age-related strength changes
        switch age {
        case 0..<18:
            return 0.7  // Youth - lighter for safety
        case 18..<25:
            return 1.0  // Peak years
        case 25..<35:
            return 0.98
        case 35..<45:
            return 0.93
        case 45..<55:
            return 0.85
        case 55..<65:
            return 0.75
        case 65..<75:
            return 0.65
        default:
            return 0.55 // 75+
        }
    }
    
    private func experienceMultiplier(experience: String) -> Double {
        switch experience.lowercased() {
        case "beginner", "newbie", "new":
            return 0.7  // Start conservative
        case "intermediate", "some experience":
            return 0.9
        case "advanced", "experienced", "expert":
            return 1.1
        default:
            return 0.7  // Default conservative
        }
    }
    
    private func goalAdjustment(goal: String, experience: String, age: Int = 30) -> (weightMultiplier: Double, reps: Int) {
        // Different goals require different weight/rep schemes
        let isBeginner = experience.lowercased().contains("beginner")
        
        var reps: Int
        var weightMult: Double
        
        switch goal.lowercased() {
        case "strength", "get stronger":
            // Heavy weight, low reps
            weightMult = 1.15
            reps = isBeginner ? 6 : 5
        case "bulk", "build muscle", "muscle":
            // Moderate weight, moderate reps
            weightMult = 1.0
            reps = isBeginner ? 10 : 8
        case "cut", "lose weight", "fat loss":
            // Lighter weight, higher reps
            weightMult = 0.85
            reps = 12
        case "tone", "toning", "define":
            // Moderate-light weight, higher reps
            weightMult = 0.9
            reps = 12
        case "cardio", "endurance":
            // Light weight, high reps
            weightMult = 0.7
            reps = 15
        default:
            // General fitness - balanced
            weightMult = 0.9
            reps = isBeginner ? 10 : 8
        }
        
        // Senior adjustment: cap reps at 12 for safety and joint health
        if age >= 65 {
            reps = min(reps, 12)
            // Slightly reduce weight for seniors on high-rep schemes
            if reps > 10 {
                weightMult *= 0.9
            }
        } else if age >= 55 {
            reps = min(reps, 15)
        }
        
        return (weightMult, reps)
    }
    
    private func minimumWeight(for category: ExerciseCategory) -> Double {
        switch category {
        case .compoundUpper: return 20   // At least the bar (or light dumbbells)
        case .compoundLower: return 45   // At least the bar
        case .isolationUpper: return 5   // Very light dumbbells
        case .isolationLower: return 10
        case .coreAbdominal: return 0    // Bodyweight is fine
        case .machineUpper: return 15
        case .machineLower: return 20
        }
    }
    
    // MARK: - Helper Functions
    
    private func parseStrengthLevel(_ level: String?) -> StrengthLevel {
        guard let level = level else { return .moderate }
        return StrengthLevel(rawValue: level) ?? .moderate
    }
    
    private func parseExperienceLevel(_ level: String?) -> String {
        return level ?? "Beginner"
    }
    
    private func calculateConfidence(
        strengthLevel: StrengthLevel,
        experience: String,
        age: Int
    ) -> Double {
        // Higher confidence when we have more data points
        var confidence = 0.6 // Base confidence for new users
        
        // Moderate strength level = more typical, higher confidence
        if strengthLevel == .moderate {
            confidence += 0.1
        }
        
        // Known experience level helps
        if !experience.isEmpty {
            confidence += 0.1
        }
        
        // Age in typical range
        if age >= 18 && age <= 55 {
            confidence += 0.1
        }
        
        return min(0.9, confidence) // Cap at 90% - never 100% for first time
    }
    
    private func generateRecommendationNote(
        weight: Double,
        strengthLevel: StrengthLevel,
        experience: String,
        category: ExerciseCategory
    ) -> String? {
        
        let isBeginner = experience.lowercased().contains("beginner")
        
        if isBeginner {
            return "Start light - focus on form first"
        }
        
        if strengthLevel == .veryLight || strengthLevel == .light {
            return "Build up gradually - form over weight"
        }
        
        if strengthLevel == .veryStrong && category == .compoundLower {
            return "Strong foundation - push yourself!"
        }
        
        return nil
    }
    
    // MARK: - Historical Data & User Preferences
    
    private func fetchLastPerformance(
        exerciseName: String,
        context: NSManagedObjectContext
    ) -> (weight: Double, reps: Int)? {
        
        let request: NSFetchRequest<WorkoutSet> = WorkoutSet.fetchRequest()
        request.predicate = NSPredicate(
            format: "workoutExercise.exercise.name ==[c] %@ AND isCompleted == YES AND weight > 0",
            exerciseName
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \WorkoutSet.workoutExercise?.workout?.date, ascending: false)
        ]
        request.fetchLimit = 1
        
        do {
            if let lastSet = try context.fetch(request).first {
                return (lastSet.weight, Int(lastSet.reps))
            }
        } catch {
            AppLogger.warning("⚠️ Error fetching last performance: \(error)", category: .workout)
        }
        
        return nil
    }
    
    /// Check if user has favorited this exercise
    private func isExerciseFavorited(_ exerciseName: String, context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@ AND isFavorite == YES", exerciseName)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return !results.isEmpty
        } catch {
            return false
        }
    }
    
    /// Get frequency of how often user does this exercise
    private func getExerciseFrequency(_ exerciseName: String, context: NSManagedObjectContext) -> Int {
        let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
        request.predicate = NSPredicate(
            format: "exercise.name ==[c] %@ AND workout.isCompleted == YES",
            exerciseName
        )
        
        do {
            return try context.count(for: request)
        } catch {
            return 0
        }
    }
    
    /// Enhance recommendation based on user preferences and history
    private func enhanceRecommendationWithUserData(
        _ recommendation: SmartRecommendation,
        exerciseName: String,
        context: NSManagedObjectContext
    ) -> SmartRecommendation {
        
        var enhanced = recommendation
        var notes: [String] = []
        
        // Check if favorited
        if isExerciseFavorited(exerciseName, context: context) {
            notes.append("⭐ One of your favorites!")
            enhanced.confidenceLevel = min(1.0, enhanced.confidenceLevel + 0.1)
        }
        
        // Check frequency
        let frequency = getExerciseFrequency(exerciseName, context: context)
        if frequency > 0 {
            notes.append("You've done this \(frequency) time\(frequency == 1 ? "" : "s") before")
            // Slightly increase confidence based on frequency
            enhanced.confidenceLevel = min(1.0, enhanced.confidenceLevel + Double(min(frequency, 5)) * 0.02)
        }
        
        // Combine notes
        if !notes.isEmpty {
            let existingNote = enhanced.adjustmentNote ?? ""
            let combinedNote = [existingNote] + notes
            enhanced.adjustmentNote = combinedNote.filter { !$0.isEmpty }.joined(separator: " • ")
        }
        
        return enhanced
    }
    
    // MARK: - Batch Recommendations for Workout
    
    /// Generate recommendations for all exercises in a workout
    func generateWorkoutRecommendations(
        exercises: [Exercise],
        user: User,
        context: NSManagedObjectContext
    ) -> [String: [SmartRecommendation]] {
        
        var recommendations: [String: [SmartRecommendation]] = [:]
        
        for exercise in exercises {
            guard let exerciseName = exercise.name,
                  let exerciseId = exercise.id?.uuidString else { continue }
            
            let recs = getRecommendationsForSets(
                exerciseName: exerciseName,
                user: user,
                numberOfSets: WorkoutManager.userDefaultSetCount,
                context: context
            )
            
            recommendations[exerciseId] = recs
        }
        
        return recommendations
    }
    
    // MARK: - Exercise-Specific Overrides
    
    // Database of exercise-specific weight adjustments (relative to category base)
    private let exerciseSpecificMultipliers: [String: Double] = [
        // Upper body - relative to compound upper base (65)
        "bench press": 1.0,
        "incline bench press": 0.85,
        "decline bench press": 1.05,
        "dumbbell bench press": 0.75,
        "dumbbell fly": 0.35,
        "overhead press": 0.7,
        "shoulder press": 0.7,
        "lateral raise": 0.2,
        "front raise": 0.2,
        "bicep curl": 0.35,
        "hammer curl": 0.38,
        "tricep extension": 0.3,
        "tricep pushdown": 0.45,
        "skull crusher": 0.35,
        
        // Back
        "barbell row": 0.85,
        "dumbbell row": 0.5,
        "lat pulldown": 0.9,
        "pull up": 0.0,  // Bodyweight
        "chin up": 0.0,
        
        // Lower body - relative to compound lower base (95)
        "squat": 1.0,
        "front squat": 0.8,
        "goblet squat": 0.35,
        "leg press": 2.5,  // Much heavier on leg press
        "deadlift": 1.2,
        "romanian deadlift": 0.7,
        "lunge": 0.5,
        "leg curl": 0.4,
        "leg extension": 0.5,
        "calf raise": 0.8,
        "hip thrust": 1.1
    ]
    
    /// Get exercise-specific weight recommendation
    func getExerciseSpecificWeight(
        exerciseName: String,
        baseWeight: Double
    ) -> Double {
        let lowercased = exerciseName.lowercased()
        
        // Find matching exercise override
        for (exercise, multiplier) in exerciseSpecificMultipliers {
            if lowercased.contains(exercise) {
                return baseWeight * multiplier
            }
        }
        
        // No specific override - use category base
        return baseWeight
    }
}

// MARK: - User Extension for Strength Level

extension User {
    /// Get the user's strength level assessment
    func getStrengthLevel() -> StrengthProfileRecommendationEngine.StrengthLevel {
        guard let level = strengthLevel else { return .moderate }
        return StrengthProfileRecommendationEngine.StrengthLevel(rawValue: level) ?? .moderate
    }
    
    /// Set the user's strength level assessment
    func setStrengthLevel(_ level: StrengthProfileRecommendationEngine.StrengthLevel) {
        strengthLevel = level.rawValue
    }
}

