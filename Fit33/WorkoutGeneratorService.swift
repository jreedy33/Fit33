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

// ⚡️ PERF: Pre-snapshotted @MainActor data for background generation (Agent Rule 9)
struct WorkoutGenerationContext: @unchecked Sendable {
    let safeExercises: [Exercise]
    let userWorkoutCount: Int
    let restrictToFoundational: Bool
    let currentTier: String
    let varietyPercentage: Double
    let hasLowerBackIssue: Bool
    let hasLearnedPreferences: Bool
    let userLevel: String
    let userGoal: String
    let userGender: String
    let userEnvironment: String
    let userWeight: Double
    let userAge: Int
    let favorites: Set<String>
    let genderVideoCache: [String: VideoStreamingService.GenderVideoInfo]
    /// Wearable Personalization — Phase 1. Snapshotted from
    /// `ReadinessService.shared.todayReadiness` on main before
    /// `Task.detached` so background generation sees a stable value
    /// (Fitness Expert threading rules). `nil` when the feature flag
    /// is off so existing code paths behave identically.
    let readiness: DailyReadinessSnapshot?
}

@MainActor
class WorkoutGeneratorService: ObservableObject {
    static let shared = WorkoutGeneratorService()
    
    /// Suppresses per-exercise filter/scoring logs during generation to prevent main thread flooding.
    /// nonisolated(unsafe) because it's a simple flag toggled at generation boundaries, safe for concurrent read.
    nonisolated(unsafe) static var suppressPerExerciseLogs = false
    
    /// Get recommended exercise count based on workout duration.
    /// Delegates to the canonical implementation in WorkoutComboRules.
    /// Audit 2026-05-08: forwards optional `experienceLevel` + `goal` so callers can
    /// trigger the Advanced + Build Muscle + ≥50min bump when context is available.
    static func exerciseCountForDuration(
        _ durationMinutes: Int,
        equipmentIsMostlyMachines: Bool = false,
        experienceLevel: String = "",
        goal: String = ""
    ) -> Int {
        return getExerciseCountForDuration(
            durationMinutes,
            equipmentIsMostlyMachines: equipmentIsMostlyMachines,
            experienceLevel: experienceLevel,
            goal: goal
        )
    }
    
    // ⚡️ Use the shared Supabase client instead of duplicating credentials
    private var supabase: SupabaseClient { SupabaseManager.shared.supabaseClient }
    
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

        // 🧠 Wearable Personalization — Phase 1 recovery override.
        // When the feature flag is on AND the user has a real wearable
        // signal AND today's band is `.red`, bypass normal selection and
        // return a mobility / stretch / yoga session (FITNESS_EXPERT_AGENT
        // invariant #23). Yellow caps `count`; green leaves it alone
        // (the per-exercise +10% ceiling is handled inside selection).
        let readinessAdjustment: ReadinessAdjustment? = {
            guard AppConfig.FeatureFlags.readinessAdaptiveAutoGen else { return nil }
            return ReadinessWorkoutAdjuster.adjustment(
                for: ReadinessService.shared.todayReadiness,
                requestedCount: count
            )
        }()

        if let adjustment = readinessAdjustment, adjustment.replaceWithRecoveryDay {
            let recoveryExercises = ReadinessWorkoutAdjuster.buildRecoveryDayExercises(
                count: adjustment.adjustedCount
            )
            // If the library is cold / no stretches exist, fall
            // through to normal generation so we never ship a blank
            // workout. Rare in prod (pre-warm is reliable).
            if !recoveryExercises.isEmpty {
                let generated = recoveryExercises.compactMap { exercise -> GeneratedExercise? in
                    guard let name = exercise.name else { return nil }
                    // Core Data Exercise stores muscles as
                    // transformable `muscleGroups` array — first
                    // entry is the primary, fall back to category.
                    let muscles = (exercise.muscleGroups as? [String]) ?? []
                    let primary = muscles.first ?? exercise.category ?? "General"
                    return GeneratedExercise(
                        id: exercise.id?.uuidString ?? UUID().uuidString,
                        name: name,
                        category: exercise.category ?? "Stretch",
                        primaryBodyRegion: primary,
                        primaryMuscle: primary,
                        secondaryMuscles: Array(muscles.dropFirst()),
                        equipment: exercise.equipment ?? "Bodyweight",
                        difficulty: "Beginner",
                        videoUrl: nil,
                        instructions: exercise.instructions
                    )
                }
                AppLogger.info(
                    "[Readiness] Replaced requested \(count) with \(generated.count) recovery exercises (band=red)",
                    category: .workout
                )
                SessionLogManager.shared.logWorkoutGenerationComplete(
                    exerciseCount: generated.count,
                    duration: Date().timeIntervalSince(startTime)
                )
                generatedExercises = generated
                return generated
            }
            AppLogger.warning(
                "[Readiness] Recovery override requested but no stretches available; falling back to normal generation",
                category: .workout
            )
        }

        let effectiveCount: Int = readinessAdjustment?.adjustedCount ?? count

        // ALL user-selected muscles are targets - combine them
        let allTargetMuscles = primaryMuscles + secondaryMuscles
        
        // Get current user for logging
        let user = UserManager.shared.currentUser
        
        #if DEBUG
        AppLogger.debug("AUTO-GEN WORKOUT GENERATION | User: \(user?.name ?? "Unknown"), Goal: \(user?.fitnessGoal ?? "Not set"), Experience: \(user?.experienceLevel ?? "Not set"), Environment: \(user?.workoutEnvironment ?? "Not set"), Equipment: \(user?.getEquipment()?.joined(separator: ", ") ?? "None"), Available Days: \(user?.availableDays ?? 0)", category: .workout)
        AppLogger.debug("WORKOUT REQUEST | Primary: \(primaryMuscles.joined(separator: ", ")), Secondary: \(secondaryMuscles.joined(separator: ", ")), Equipment: \(equipment.joined(separator: ", ")), Count: \(count)", category: .workout)
        #endif
        
        // 🚀 SIMPLE & CLEAN: Generate exercises that hit user's selected muscles
        // Exercises hitting MULTIPLE targets get bonus (compound value)
        
        let allExercisesSnapshot = ExerciseLibraryService.shared.getAllExercises()
        
        var excludeNames: Set<String> = []
        if !excludeExerciseIds.isEmpty {
            for exerciseId in excludeExerciseIds {
                if let exercise = allExercisesSnapshot.first(where: { $0.id?.uuidString == exerciseId }),
                   let name = exercise.name {
                    excludeNames.insert(name)
                }
            }
        }
        
        Self.suppressPerExerciseLogs = true
        
        // ⚡️ PERF: Snapshot @MainActor state on main thread, then generate on background
        // generateFromCoreData iterates 5500+ exercises — MUST NOT block main (Agent Rule 9)
        let context = buildGenerationContext(exercises: allExercisesSnapshot)
        let targetMusclesCopy = allTargetMuscles
        let equipmentCopy = equipment
        // Phase 1: `effectiveCount` honors the yellow-band 0.9× cap
        // (falls through to the raw `count` when the feature flag is
        // off or snapshot has no wearable signal).
        let countCopy = effectiveCount
        let excludeNamesCopy = excludeNames
        
        let coreDataExercises: [GeneratedExercise] = await Task.detached(priority: .userInitiated) { [self] in
            await self.generateFromCoreData(
                context: context,
                targetMuscles: targetMusclesCopy,
                equipment: equipmentCopy,
                count: countCopy,
                isPrimary: true,
                excludeNames: excludeNamesCopy
            )
        }.value
        
        Self.suppressPerExerciseLogs = false
        
        if !coreDataExercises.isEmpty {
            let duration = Date().timeIntervalSince(startTime)
            #if DEBUG
            AppLogger.info("Generation complete: \(coreDataExercises.count) exercises", category: .workout)
            for (index, ex) in coreDataExercises.enumerated() {
                AppLogger.debug("  \(index + 1). \(ex.name) [\(ex.equipment ?? "Bodyweight")]", category: .workout)
            }
            #endif
            
            // Log generation complete
            SessionLogManager.shared.logWorkoutGenerationComplete(
                exerciseCount: coreDataExercises.count,
                duration: duration
            )
            
            generatedExercises = coreDataExercises
            return coreDataExercises
        }
        
        // Fallback to old local generation — honour Phase 1 effective count.
        let exercises = generateLocalWorkout(
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            equipment: equipment,
            count: effectiveCount,
            excludeExerciseIds: excludeExerciseIds
        )
        
        if !exercises.isEmpty {
            #if DEBUG
            AppLogger.info("Generated \(exercises.count) exercises from fallback", category: .workout)
            #endif
            generatedExercises = exercises
            return exercises
        }
        
        // Final fallback to edge function — cloud generation also respects effectiveCount.
        do {
            let request = WorkoutGenerationRequest(
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles,
                equipment: equipment,
                count: effectiveCount,
                excludeExerciseIds: excludeExerciseIds
            )
            
            let response: WorkoutGenerationResponse = try await supabase.functions
                .invoke(
                    "workout-generator",
                    options: FunctionInvokeOptions(
                        body: request
                    )
                )
            
            AppLogger.info("Generated \(response.exercises.count) exercises from cloud", category: .workout)
            generatedExercises = response.exercises
            
            return response.exercises
            
        } catch {
            AppLogger.error("Cloud generation failed: \(error.localizedDescription)", category: .workout)
            self.error = "Failed to generate workout: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Generation Context Builder
    
    /// Snapshots all @MainActor service state needed for generation.
    /// Called on main thread before dispatching heavy generation to background.
    private func buildGenerationContext(exercises: [Exercise]) -> WorkoutGenerationContext {
        let safeExercises = LimitationsService.shared.filterSafeExercises(exercises)
        let progressiveUnlock = ProgressiveExerciseUnlockService.shared
        let learningEngine = UserBehaviorLearningEngine.shared
        let user = UserManager.shared.currentUser
        let favorites = Set(safeExercises.filter { $0.isFavorite }.compactMap { $0.name?.lowercased() })
        
        // Snapshot readiness on the @MainActor BEFORE the generation
        // Task.detached so the background pipeline sees a stable
        // value even if a wearable sync writes mid-generation. Only
        // attached when the feature flag is on — behaviour identical
        // to pre-Phase-1 when off.
        let readinessSnapshot: DailyReadinessSnapshot? = {
            guard AppConfig.FeatureFlags.readinessAdaptiveAutoGen else { return nil }
            return ReadinessService.shared.todayReadiness
        }()

        return WorkoutGenerationContext(
            safeExercises: safeExercises,
            userWorkoutCount: progressiveUnlock.workoutCount,
            restrictToFoundational: progressiveUnlock.shouldRestrictToFoundational,
            currentTier: progressiveUnlock.currentTier.displayName,
            varietyPercentage: progressiveUnlock.varietyPercentage,
            hasLowerBackIssue: LimitationsService.shared.hasLowerBackLimitation,
            hasLearnedPreferences: learningEngine.userPreferences != nil,
            userLevel: user?.experienceLevel ?? "Intermediate",
            userGoal: user?.fitnessGoal ?? "Build Muscle",
            userGender: (user?.gender ?? "male").lowercased(),
            userEnvironment: user?.workoutEnvironment ?? "Hybrid",
            userWeight: Double(user?.weight ?? 170),
            userAge: Int(user?.age ?? 30),
            favorites: favorites,
            genderVideoCache: VideoStreamingService.shared.genderVideoCache,
            readiness: readinessSnapshot
        )
    }
    
    // MARK: - Local Workout Generation
    
    private func generateLocalWorkout(
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: [String],
        count: Int,
        excludeExerciseIds: [String]
    ) -> [GeneratedExercise] {
        let allExercises = ExerciseDataProvider.shared.exercises
        
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
        AppLogger.debug("Searching for exercises matching: primaries=\(normalizedPrimaries), categories=\(targetCategories), muscles=\(targetMuscles), equipment=\(normalizedEquipment)", category: .workout)
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
        AppLogger.debug("Found \(matchingExercises.count) strictly matching exercises", category: .workout)
        #endif
        
        // If very few matches, slightly broaden but still respect category
        if matchingExercises.count < count {
            #if DEBUG
            AppLogger.warning("Few strict matches, including more exercises from same categories...", category: .workout)
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
            AppLogger.debug("Now have \(matchingExercises.count) exercises", category: .workout)
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
        AppLogger.info("Selected \(result.count) exercises for workout", category: .workout)
        for (index, exercise) in result.enumerated() {
            AppLogger.debug("  \(index + 1). \(exercise.name) - \(exercise.category) - \(exercise.primaryMuscle)", category: .workout)
        }
        #endif
        
        // 🎯 Apply smart exercise ordering
        let generated = result.map { GeneratedExercise(from: $0) }
        let sorted = sortExercisesStrategically(generated)
        
        // Log to advanced session logger for AI analysis
        if AdvancedSessionLogger.isActive {
            let currentUser = UserManager.shared.currentUser
            let userLimitations = LimitationsService.shared.userLimitations
            let limitationsSummary = userLimitations.map { "\($0.limitationType.rawValue): \($0.affectedArea.rawValue) (\($0.severity.rawValue))" }.joined(separator: ", ")
            let userProfile: [String: Any] = [
                "name": currentUser?.name ?? "unknown",
                "goal": currentUser?.fitnessGoal ?? "unknown",
                "experience": currentUser?.experienceLevel ?? "unknown",
                "environment": currentUser?.workoutEnvironment ?? "unknown",
                "available_days": currentUser?.availableDays ?? 0,
                "weight_lbs": currentUser?.weightLbs ?? 0,
                "height_inches": currentUser?.height ?? 0,
                "age": currentUser?.age ?? 0,
                "gender": currentUser?.gender ?? "unknown",
                "total_workouts": currentUser?.totalWorkouts ?? 0,
                "current_streak": currentUser?.currentStreak ?? 0,
                "injuries_limitations": limitationsSummary.isEmpty ? "none" : limitationsSummary,
                "exercises_to_avoid": userLimitations.flatMap { $0.exercisesToAvoid }.joined(separator: ", "),
                "movements_to_avoid": userLimitations.flatMap { $0.movementPatternsToAvoid }.joined(separator: ", "),
                "equipment_to_avoid": userLimitations.flatMap { $0.equipmentToAvoid }.joined(separator: ", "),
            ]
            let allTargets = primaryMuscles + secondaryMuscles
            let exerciseDetails = sorted.map { ex -> [String: Any] in
                ["name": ex.name, "equipment": ex.equipment, "primary_muscle": ex.primaryMuscle, "category": ex.category, "difficulty": ex.difficulty]
            }
            Task { @MainActor in
                AdvancedSessionLogger.shared.logAutogenWorkout(
                    userProfile: userProfile,
                    equipment: equipment,
                    targetMuscles: allTargets,
                    generatedExercises: exerciseDetails,
                    generationTimeMs: 0
                )
            }
        }
        
        return sorted
    }
    
    func generateSurpriseWorkout(equipment: [String] = [], count: Int = 5) async throws -> [GeneratedExercise] {
        let userGoal = UserManager.shared.currentUser?.fitnessGoal?.lowercased() ?? "build muscle"
        let userLevel = UserManager.shared.currentUser?.experienceLevel ?? "Intermediate"
        let userEquipment = equipment.isEmpty 
            ? ((UserManager.shared.currentUser?.equipment as? [String]) ?? ["Barbell", "Dumbbells", "Bodyweight", "Cables"])
            : equipment
        
        let workoutSplits: [(name: String, muscles: [String], forGoals: [String], family: WorkoutSuggestionEngine.SplitFamily)] = [
            ("Push Day", ["Chest", "Shoulders", "Triceps"], ["build muscle", "get stronger"], .push),
            ("Pull Day", ["Back", "Biceps"], ["build muscle", "get stronger"], .pull),
            ("Leg Day", ["Quads", "Hamstrings", "Glutes", "Calves"], ["build muscle", "get stronger"], .legs),
            ("Chest & Triceps", ["Chest", "Triceps"], ["build muscle"], .push),
            ("Back & Biceps", ["Back", "Biceps"], ["build muscle"], .pull),
            ("Shoulders & Arms", ["Shoulders", "Biceps", "Triceps"], ["build muscle"], .upperBody),
            ("Upper Body Strength", ["Chest", "Back", "Shoulders"], ["get stronger"], .upperBody),
            ("Lower Body Strength", ["Quads", "Hamstrings", "Glutes"], ["get stronger"], .legs),
            ("HIIT Full Body", ["Full Body", "Cardio"], ["lose fat", "lose weight", "improve endurance"], .fullBody),
            ("Cardio Blast", ["Cardio", "Plyometrics"], ["lose fat", "lose weight"], .coreCardio),
            ("Metabolic Circuit", ["Full Body", "Core"], ["lose fat", "lose weight"], .fullBody),
            ("Full Body", ["Chest", "Back", "Legs", "Shoulders"], ["general fitness", "stay active"], .fullBody),
            ("Core & Functional", ["Core", "Abs", "Obliques"], ["general fitness", "improve flexibility"], .coreCardio),
            ("Flexibility & Mobility", ["Stretch"], ["improve flexibility", "general fitness"], .coreCardio),
            ("Upper Body", ["Chest", "Back", "Shoulders"], ["build muscle", "get stronger", "general fitness"], .upperBody),
            ("Chest & Back Superset", ["Chest", "Back"], ["build muscle", "lose fat"], .upperBody)
        ]
        
        // Filter by user goal
        var relevantSplits = workoutSplits.filter { split in
            split.forGoals.contains { userGoal.contains($0) }
        }
        if relevantSplits.isEmpty { relevantSplits = workoutSplits }
        
        // Recovery + anti-repetition: exclude the last Surprise Me family and fatigued muscles
        let engine = WorkoutSuggestionEngine.shared
        let excludedFamily = engine.surpriseMeExclusion()
        let recoveredMuscles = Set(engine.recoveredMuscles().map { $0.rawValue.capitalized })
        
        let smartSplits = relevantSplits.filter { split in
            if let excluded = excludedFamily, split.family == excluded { return false }
            let splitMuscles = split.muscles.map { $0.lowercased() }
            let hasFatigued = splitMuscles.contains { muscle in
                let canonical = muscle.lowercased()
                if ["full body", "cardio", "plyometrics", "stretch"].contains(canonical) { return false }
                return !recoveredMuscles.contains { $0.lowercased() == canonical }
            }
            return !hasFatigued
        }
        
        let candidateSplits = smartSplits.isEmpty ? relevantSplits : smartSplits
        
        let weightedSplits = candidateSplits.map { split -> (split: (name: String, muscles: [String], forGoals: [String], family: WorkoutSuggestionEngine.SplitFamily), weight: Int) in
            var weight = 1
            let goalMatchCount = split.forGoals.filter { userGoal.contains($0) }.count
            weight += goalMatchCount * 2
            if split.muscles.count >= 3 { weight += 1 }
            
            let splitMuscleSet = Set(split.muscles.map { $0.lowercased() })
            let recoveredOverlap = splitMuscleSet.intersection(recoveredMuscles.map { $0.lowercased() }).count
            weight += recoveredOverlap
            
            return (split, weight)
        }
        let totalWeight = weightedSplits.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0..<max(1, totalWeight))
        var selectedSplit = weightedSplits[0].split
        for ws in weightedSplits {
            roll -= ws.weight
            if roll < 0 {
                selectedSplit = ws.split
                break
            }
        }
        
        engine.recordSurpriseSplit(selectedSplit.family)
        
        #if DEBUG
        AppLogger.debug("Surprise workout (Smart): goal=\(userGoal), level=\(userLevel), split=\(selectedSplit.name), muscles=\(selectedSplit.muscles), excluded=\(excludedFamily?.rawValue ?? "none"), equipment=\(userEquipment)", category: .workout)
        #endif
        
        // ⚡️ PERF: Snapshot then generate on background (Agent Rule 9)
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let surpriseContext = buildGenerationContext(exercises: allExercises)
        let muscles = selectedSplit.muscles
        let equip = userEquipment
        let cnt = count
        
        let coreDataExercises: [GeneratedExercise] = await Task.detached(priority: .userInitiated) { [self] in
            await self.generateFromCoreData(
                context: surpriseContext,
                targetMuscles: muscles,
                equipment: equip,
                count: cnt
            )
        }.value
        
        if !coreDataExercises.isEmpty {
            generatedExercises = coreDataExercises
            return coreDataExercises
        }
        
        return try await generateWorkout(
            primaryMuscles: selectedSplit.muscles,
            secondaryMuscles: [],
            equipment: userEquipment,
            count: count
        )
    }
    
    // MARK: - Smart Exercise Generation from 7000+ Library
    
    // ⚡️ PERF: nonisolated — runs on background thread via Task.detached (Agent Rule 9)
    // All @MainActor state is pre-snapshotted in WorkoutGenerationContext
    nonisolated private func generateFromCoreData(
        context: WorkoutGenerationContext,
        targetMuscles: [String],
        equipment: [String],
        count: Int,
        isPrimary: Bool = true,
        excludeNames: Set<String> = [],
        workoutLocation: ExerciseFilterService.WorkoutLocation = .gym
    ) async -> [GeneratedExercise] {
        var allExercises = context.safeExercises
        
        // Filter out already selected exercises
        if !excludeNames.isEmpty {
            allExercises = allExercises.filter { exercise in
                guard let name = exercise.name else { return true }
                return !excludeNames.contains(name)
            }
        }
        
        // Safety filtering already applied via context.safeExercises
        AppLogger.debug("🛡️ [LIMITATIONS] \(context.hasLowerBackIssue ? "Lower back limitation active" : "No active limitations") - all exercises safe", category: .workout)
        
        // Use pre-snapshotted progressive unlock data
        let userWorkoutCount = context.userWorkoutCount
        let restrictToFoundational = context.restrictToFoundational
        
        let foundationalDB = FoundationalExerciseDatabase.shared
        let hasLowerBackIssue = context.hasLowerBackIssue
        
        if restrictToFoundational || userWorkoutCount < 10 {
            let beforeRiskyFilter = allExercises.count
            allExercises = allExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                
                // Pre-filter risky exercises for foundational users
                if foundationalDB.isRiskyExercise(name) {
                    #if DEBUG
                    AppLogger.debug("[RISKY] Pre-filtering '\(exercise.name ?? "")' - risky for foundational user", category: .workout)
                    #endif
                    return false
                }
                return true
            }
            let filteredRisky = beforeRiskyFilter - allExercises.count
            #if DEBUG
            if filteredRisky > 0 {
                AppLogger.debug("[RISKY] Pre-filtered \(filteredRisky) risky exercises for foundational user", category: .workout)
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
                    AppLogger.debug("[BACK SAFETY] Pre-filtering '\(exercise.name ?? "")' - stresses lower back", category: .workout)
                    #endif
                    return false
                }
                return true
            }
            let filteredBack = beforeBackFilter - allExercises.count
            #if DEBUG
            if filteredBack > 0 {
                AppLogger.debug("[BACK SAFETY] Pre-filtered \(filteredBack) lower back stress exercises", category: .workout)
            }
            #endif
        }
        
        // 🆕 PRE-FILTER: Block combo/core moves for foundational users when goal is hypertrophy
        // These are not foundational and add unnecessary complexity
        // COMBO = any "X to Y" pattern where two distinct movements are combined
        if restrictToFoundational || userWorkoutCount < 10 {
            let beforeComboFilter = allExercises.count
            allExercises = allExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                
                // ═══════════════════════════════════════════════════════════════════════════
                // 🚫 CRITICAL: Block ALL "X to Y" combo exercises
                // These are hard to load/progress and reduce hypertrophy quality
                // Pattern: "Bent Over Reverse Fly to Hammer Curl", "Squat to Press", etc.
                // ═══════════════════════════════════════════════════════════════════════════
                
                // Match any " to " pattern (word boundary), excluding cable movement terms
                if name.contains(" to ") {
                    // Allow cable fly positioning terms
                    let allowedToPatterns = ["low to high", "high to low", "low-to-high", "high-to-low"]
                    let isAllowedPattern = allowedToPatterns.contains { name.contains($0) }
                    
                    if !isAllowedPattern {
                        #if DEBUG
                        AppLogger.debug("[COMBO] Pre-filtering '\(exercise.name ?? "")' - combo exercise (X to Y pattern)", category: .workout)
                        #endif
                        return false
                    }
                }
                
                // Block plank-based combo moves
                if name.contains("plank") && (name.contains("push") || name.contains("row") || name.contains("pass") || name.contains("jack") || name.contains("through")) {
                    #if DEBUG
                    AppLogger.debug("[COMBO] Pre-filtering '\(exercise.name ?? "")' - combo/core move not foundational", category: .workout)
                    #endif
                    return false
                }
                
                // Block bear crawl, renegade, man maker, burpee
                if name.contains("bear crawl") || name.contains("renegade") || name.contains("man maker") || name.contains("burpee") {
                    #if DEBUG
                    AppLogger.debug("[COMBO] Pre-filtering '\(exercise.name ?? "")' - complex combo move", category: .workout)
                    #endif
                    return false
                }
                
                return true
            }
            let filteredCombo = beforeComboFilter - allExercises.count
            #if DEBUG
            if filteredCombo > 0 {
                AppLogger.debug("[COMBO] Pre-filtered \(filteredCombo) combo/core exercises for foundational user", category: .workout)
            }
            #endif
        }
        
        guard !allExercises.isEmpty else {
            AppLogger.warning("No exercises in Core Data library (or all filtered for safety)", category: .workout)
            return []
        }
        
        let favorites = context.favorites
        
        let learningEngine = UserBehaviorLearningEngine.shared
        let hasLearnedPreferences = context.hasLearnedPreferences
        
        let currentTierName = context.currentTier
        let varietyPercentage = context.varietyPercentage
        
        #if DEBUG
        if hasLearnedPreferences {
            AppLogger.debug("[SMART GEN] Using learned user preferences for personalized selection", category: .workout)
        }
        AppLogger.debug("[PROGRESSIVE UNLOCK] User workout count: \(userWorkoutCount), Tier: \(currentTierName)", category: .workout)
        AppLogger.debug("[PROGRESSIVE UNLOCK] Restrict to foundational: \(restrictToFoundational), Variety: \(Int(varietyPercentage * 100))%", category: .workout)
        #endif
        
        let userLevel = context.userLevel
        let userGoal = context.userGoal
        let userGender = context.userGender
        let preferredGender = userGender.contains("female") ? "female" : "male"
        let userEnvironment = context.userEnvironment
        let userWeight = context.userWeight
        let userAge = context.userAge
        
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
        let normalizedEquipment = Set(equipment.map { $0.trimmingCharacters(in: .whitespaces) })
        
        #if DEBUG
        AppLogger.debug("[SMART GEN] Starting intelligent workout generation: muscles=\(targetMuscles), expanded=\(normalizedMuscles), equipment=\(normalizedEquipment), level=\(userLevel), goal=\(userGoal), gender=\(preferredGender.uppercased()), weight=\(Int(userWeightLbs))lbs, age=\(userAge), favorites=\(favorites.count), library=\(allExercises.count)", category: .workout)
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
            "upper chest": ["chest"],
            "lower chest": ["chest"],
            "back": ["back"],
            "lats": ["back"],
            "upper back": ["back"],
            "lower back": ["back"],
            "shoulders": ["shoulders"],
            "front delts": ["shoulders"],
            "side delts": ["shoulders"],
            "rear delts": ["shoulders"],
            "rotator cuff": ["shoulders"],
            "arms": ["arms"],
            "biceps": ["arms"],
            "triceps": ["arms"],
            "forearms": ["arms"],
            "legs": ["legs"],
            "quads": ["legs"],
            "hamstrings": ["legs"],
            "glutes": ["legs"],
            "calves": ["legs"],
            "hip flexors": ["legs", "hips"],
            "inner thighs": ["legs", "hips"],
            "hips": ["hips", "legs"],
            "core": ["core"],
            "abs": ["core"],
            "obliques": ["core"],
            "lower abs": ["core"],
            "neck": ["neck"],
            "full body": ["full body"],
            "traps": ["back", "shoulders"],
            "stretch": ["stretch"],
            "stretching": ["stretch"],
            "cardio": ["cardio", "full body"]
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
        let genderVideoCache = context.genderVideoCache
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
                    if !Self.suppressPerExerciseLogs { AppLogger.debug("[EQUIPMENT] Excluded '\(exercise.name ?? "")': requires \(exerciseEquipmentRaw)", category: .workout) }
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
                AppLogger.debug("[LOCATION] Excluded '\(exercise.name ?? "")': not appropriate for \(userEnvironment)", category: .workout)
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
            // Uses normalizeMuscleName on both sides for consistent synonym handling
            let primaryMuscleMatchesTarget = normalizedMuscles.contains { target in
                let normalizedTarget = normalizeMuscleName(target)
                return normalizedExercisePrimary == normalizedTarget ||
                       exercisePrimaryMuscle == target
            }
            
            // Also check category as fallback (for exercises where muscle data might be incomplete)
            let categoryMatchesTarget = targetCategories.contains { target in
                exerciseCategory.contains(target) || target.contains(exerciseCategory)
            }
            
            // STRICT: Exercise must primarily target one of user's selected muscles
            // Category fallback only applies when muscle data is missing AND category is present
            let matchesMuscle = primaryMuscleMatchesTarget || (categoryMatchesTarget && exercisePrimaryMuscle.isEmpty && !exerciseCategory.isEmpty)
            
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
                    if !Self.suppressPerExerciseLogs { AppLogger.debug("[BODY REGION] Excluding '\(exercise.name ?? "")': lower body exercise in upper body workout", category: .workout) }
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
                    if !Self.suppressPerExerciseLogs { AppLogger.debug("[BODY REGION] Excluding '\(exercise.name ?? "")': upper body exercise in lower body workout", category: .workout) }
                    #endif
                    return false
                }
            }
            
            // 🎯 PRACTICALITY FILTER - Use database score to filter unrealistic exercises
            let dbPracticalityScore = Int(exercise.practicalityScore)
            if dbPracticalityScore > 0 && dbPracticalityScore < 30 {
                // Exclude exercises with very low practicality scores (handstands, weird variations, etc.)
                #if DEBUG
                if !Self.suppressPerExerciseLogs { AppLogger.debug("[PRACTICALITY] Excluding '\(exercise.name ?? "")': score=\(dbPracticalityScore)", category: .workout) }
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

            // 👤 GENDER STRICT FILTER (strength only) — Audit 2026-05-08 user request:
            // "Very rarely should a male see female and vice versa in strength workouts."
            // The catalog has both-gender videos for the top ~200 common strength exercises,
            // so when an exercise IS gender-tagged but has no video for the user's gender,
            // we EXCLUDE it from strength workouts (a same-gender alternative exists). For
            // stretch / cardio / plyometrics / specialty (smaller catalog, fewer dual-gender
            // clips), we keep the existing soft fallback so the user always has SOMETHING.
            // Untagged exercises are gender-neutral — always shown.
            let exerciseTypeForGender = ExerciseFilterService.classifyExerciseType(
                name: exercise.name,
                category: exercise.category,
                equipment: exercise.equipment
            )
            if exerciseTypeForGender == .strength {
                let exKey = (exercise.name ?? "").lowercased()
                if let info = genderVideoCache[exKey] {
                    // Exercise IS gender-tagged. Require user's gender video to exist.
                    if info.filename(for: preferredVideoGender) == nil {
                        #if DEBUG
                        if !Self.suppressPerExerciseLogs {
                            AppLogger.debug("[GENDER STRICT] Excluding '\(exercise.name ?? "")': no \(preferredVideoGender.rawValue.lowercased()) video for strength workout", category: .workout)
                        }
                        #endif
                        return false
                    }
                }
                // No gender info → legacy single-video / gender-neutral exercise → keep.
            }

            #if DEBUG
            matchCount += 1
            #endif
            
            return true
        }
        
        #if DEBUG
        AppLogger.debug("[FILTER STATS] Passed: \(matchCount), Failed equipment: \(equipmentFailCount), Failed muscle: \(muscleFailCount), Filtered by profile: \(profileFailCount)", category: .workout)
        
        // Show first 5 ACTUAL barbell exercises if user selected Barbell
        if normalizedEquipment.contains(where: { $0.lowercased().contains("barbell") }) {
            let barbellOnly = matchingExercises.filter { ($0.equipment ?? "").lowercased().contains("barbell") }
            AppLogger.debug("[BARBELL] Barbell exercises found: \(barbellOnly.count)", category: .workout)
            for (idx, ex) in barbellOnly.prefix(5).enumerated() {
                AppLogger.debug("  \(idx+1). \(ex.name ?? "?") - \(ex.equipment ?? "?")", category: .workout)
            }
        }
        #endif
        
        #if DEBUG
        AppLogger.debug("[STRICT FILTER] Equipment: \(normalizedEquipment), Muscles: \(normalizedMuscles), Exercises after filter: \(matchingExercises.count)", category: .workout)
        
        // Show first 10 matching exercises with their equipment and muscles
        AppLogger.debug("[SAMPLE MATCHES]:", category: .workout)
        for (idx, ex) in matchingExercises.prefix(10).enumerated() {
            let muscles = (ex.muscleGroups as? [String]) ?? []
            let equipment = ex.equipment ?? "?"
            let workoutType = ex.workoutType ?? "?"
            AppLogger.debug("  \(idx+1). \(ex.name ?? "?") - Equipment: \(equipment) - Muscles: \(muscles) - Type: \(workoutType)", category: .workout)
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
        AppLogger.debug("Exercises after strict filter: \(matchingExercises.count), Gender-matching: \(genderMatchCount), Fallback: \(genderFallbackCount)", category: .workout)
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
                AppLogger.debug("[BEGINNER] Heavy penalty for '\(exercise.name ?? "")': non-foundational for new user", category: .workout)
                #endif
            }
            
            let foundationalDB = FoundationalExerciseDatabase.shared
            
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
                    AppLogger.warning("[SAFETY] '\(exercise.name ?? "")' penalty: \(Int(riskyPenalty))", category: .workout)
                }
                #endif
            }
            
            // ✅ LOWER BACK SAFE ALTERNATIVE BOOST - Promote chest-supported/machine rows
            if hasLowerBackIssue && foundationalDB.isLowerBackSafeAlternative(name) {
                score += 100
                #if DEBUG
                AppLogger.info("[BACK SAFE] '\(exercise.name ?? "")' boosted +100 (safe for lower back)", category: .workout)
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
                    AppLogger.debug("[SAFETY] '\(exercise.name ?? "")': \(safetyPenalty > 0 ? "-" : "+")\(Int(abs(safetyPenalty)))", category: .workout)
                }
                #endif
            }
            
            // 🏋️ EQUIPMENT QUALITY BOOST - Based on hypertrophy effectiveness (not difficulty)
            // Machines/cables aren't "beginner" - they're effective tools for all levels
            // Advanced = intensity/volume, not equipment type
            let equipQualityBoost = FoundationalExerciseDatabase.shared.getEquipmentQualityBoost(
                equipment: exercise.equipment ?? "",
                exerciseName: name,
                userWorkoutCount: userWorkoutCount,
                userEquipment: Array(userEquipmentLower)
            )
            score += equipQualityBoost
            
            #if DEBUG
            if equipQualityBoost > 0 {
                let equipType = exercise.equipment ?? "unknown"
                if !Self.suppressPerExerciseLogs { AppLogger.debug("[EQUIP QUALITY] '\(exercise.name ?? "")' (\(equipType)): +\(Int(equipQualityBoost))", category: .workout) }
            }
            #endif
            
            // 🪑 FOUNDATIONAL SUPPORTED ROW BONUS - Safer for new users
            // Promote supported rows (chest-supported, machine, seated) over bent-over rows
            // for foundational users to reduce lower back fatigue
            if restrictToFoundational && name.contains("row") {
                let isSupported = ["chest supported", "chest-supported", "machine", "lever", "seated", "cable row"].contains { name.contains($0) }
                let isBentOver = name.contains("bent over") || name.contains("bent-over")
                
                if isSupported {
                    score += 80  // Bonus for supported rows
                    #if DEBUG
                    AppLogger.debug("[FOUNDATIONAL] '\(exercise.name ?? "")' +80 (supported row for new user)", category: .workout)
                    #endif
                } else if isBentOver {
                    score -= 60  // Penalty for bent-over rows (not banned, just discouraged)
                    #if DEBUG
                    AppLogger.debug("[FOUNDATIONAL] '\(exercise.name ?? "")' -60 (bent-over row - prefer supported)", category: .workout)
                    #endif
                }
            }
            
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
            // Only score exercises that have video data; no bonus/penalty for unknowns
            let exerciseKey = name
            if let genderInfo = genderVideoCache[exerciseKey] {
                if genderInfo.filename(for: preferredVideoGender) != nil {
                    score += 200
                } else {
                    score -= 150
                }
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
                let normalizedTarget = normalizeMuscleName(target)
                let hits = allExerciseMuscles.contains { muscle in
                    let normalizedMuscle = normalizeMuscleName(muscle)
                    return normalizedMuscle == normalizedTarget || muscle == target
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
            
            // Truly assisted/guided movement indicators (not equipment types or body positions)
            let beginnerKeywords = ["assisted", "supported", "guided"]
            let isBeginnerFriendly = beginnerKeywords.contains(where: { name.contains($0) })
            
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
                // Advanced: Prefer technical and compound, slight penalty for truly assisted movements
                if isTechnicalExercise {
                    score += 150  // Big boost for technical exercises
                }
                if isBeginnerFriendly {
                    score -= 20  // Small penalty for assisted/guided movements only
                }
                if exerciseDifficulty >= 7 { 
                    score += 60  // Boost hard exercises
                } else if exerciseDifficulty <= 2 { 
                    score -= 30  // Slight penalty for very easy
                }
                // Strongly prefer compound movements
                if isCompound { score += 50 }
                
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
                if equipmentType == "Machines" || equipmentType == "Cables" { score += 10 }
            case "lose fat", "lose weight":
                if category == "cardio" || category == "plyometrics" { score += 35 }
                if name.contains("burpee") || name.contains("jump") { score += 20 }
            case "get stronger":
                if isCompound { score += 35 }
                if equipmentType == "Barbell" { score += 25 }
                if equipmentType == "Machines" { score += 5 }
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
                    if !Self.suppressPerExerciseLogs { AppLogger.debug("[CONTEXT BENCH] '\(exercise.name ?? "")' bench type matches muscle context (+\(Int(benchAdjustment)))", category: .workout) }
                } else if benchScore < 50 {
                    if !Self.suppressPerExerciseLogs { AppLogger.debug("[SMART BENCH] '\(exercise.name ?? "")' requires specialized bench without context (\(exerciseEquipment)) - score: \(Int(benchAdjustment))", category: .workout) }
                }
                #endif
            }
            
            // Small bonus for exercises that DON'T require a bench
            // These are guaranteed to work regardless of bench type
            if userHasBench && !exerciseEquipment.lowercased().contains("bench") {
                score += 5
            }
            
            // ═══════════════════════════════════════════════════════════════════════════════
            // 🎯 UPPER CHEST FOCUS - Boost incline exercises when "upper chest" is targeted
            // ═══════════════════════════════════════════════════════════════════════════════
            let isUpperChestFocus = normalizedMuscles.contains { $0.contains("upper chest") }
            
            if isUpperChestFocus {
                // BOOST incline exercises - these actually hit upper chest
                let inclinePatterns = ["incline press", "incline bench", "incline db", "incline dumbbell",
                                       "low to high", "low-to-high", "low cable fly",
                                       "incline fly", "incline hammer", "incline smith"]
                if inclinePatterns.contains(where: { name.contains($0) }) {
                    score += 150  // Very strong boost for incline work when upper chest is targeted
                    #if DEBUG
                    AppLogger.debug("[UPPER CHEST] '\(exercise.name ?? "")' +150 (incline for upper chest)", category: .workout)
                    #endif
                }
                
                // PENALIZE flat/decline exercises that don't hit upper chest well
                if name.contains("decline") {
                    score -= 100  // Decline hits lower chest, not upper
                }
                
                // Flat bench is okay but incline is better for upper chest
                if name.contains("flat bench") || (name.contains("bench press") && !name.contains("incline") && !name.contains("decline")) {
                    score -= 30  // Slight penalty - flat hits mid chest more
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════════
            // 🎯 FRONT DELT REDUNDANCY - Penalize front raises when chest pressing is in workout
            // Chest pressing already hits front delts heavily - front raises are redundant
            // ═══════════════════════════════════════════════════════════════════════════════
            let isChestDay = normalizedMuscles.contains { $0.contains("chest") }
            let isShoulderDay = normalizedMuscles.contains { $0.contains("shoulder") || $0.contains("delt") }
            let isPressingDay = isChestDay || isShoulderDay
            
            if isPressingDay && name.contains("front raise") {
                score -= 100  // Front delts get hit by pressing - use lateral raises instead
                #if DEBUG
                AppLogger.debug("[REDUNDANT] '\(exercise.name ?? "")' -100 (front delts already hit by pressing)", category: .workout)
                #endif
            }
            
            // ═══════════════════════════════════════════════════════════════════════════════
            // 🎯 LATERAL > FRONT RAISE - Prefer lateral raises over front raises for shoulders
            // Side delts are harder to develop and need direct work, front delts get hit by pressing
            // ═══════════════════════════════════════════════════════════════════════════════
            if isShoulderDay {
                // Boost lateral/side work
                if name.contains("lateral raise") || name.contains("side raise") || name.contains("side delt") {
                    score += 80  // Lateral delts need direct work
                    #if DEBUG
                    AppLogger.debug("[LATERAL] '\(exercise.name ?? "")' +80 (lateral delt focus)", category: .workout)
                    #endif
                }
                
                // Penalize front raises (redundant with pressing)
                if name.contains("front raise") {
                    score -= 80  // Front delts already hit by pressing - low ROI
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════════
            // 🎯 SEATED OVERHEAD PREFERENCE FOR BACK ISSUES - Safer for lower back
            // Standing overhead work can stress lower back; seated is safer
            // ═══════════════════════════════════════════════════════════════════════════════
            if hasLowerBackIssue {
                let isOverhead = name.contains("overhead") || name.contains("shoulder press") ||
                                 name.contains("military press") || name.contains("ohp")
                
                if isOverhead {
                    // BOOST seated variations - no spinal load
                    let equipLower = exerciseEquipment.lowercased()
                    if name.contains("seated") || equipLower.contains("machine") || equipLower.contains("lever") {
                        score += 100  // Much safer for lower back
                        #if DEBUG
                        AppLogger.debug("[BACK SAFE] '\(exercise.name ?? "")' +100 (seated overhead for back safety)", category: .workout)
                        #endif
                    }
                    // PENALIZE standing variations - potential back stress
                    else if name.contains("standing") || (!name.contains("seated") && !equipLower.contains("machine")) {
                        score -= 80  // Standing overhead can stress lower back
                    }
                }
                
                // Also penalize any "twisting" under load - risky for back
                if name.contains("twist") || name.contains("rotating") {
                    score -= 120  // Rotational load is risky for back issues
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════════
            // 🎯 REAR DELT BALANCE - Boost rear delt/face pull when workout is anterior-heavy
            // Pushing workouts (chest/shoulders) should include some rear delt for balance
            // ═══════════════════════════════════════════════════════════════════════════════
            let isPushDay = isChestDay && !normalizedMuscles.contains { $0.contains("back") }
            let isAnteriorHeavy = isChestDay || isPushDay
            
            if isAnteriorHeavy {
                // BOOST rear delt and face pulls for shoulder health/balance
                let rearDeltPatterns = ["face pull", "rear delt", "reverse fly", "posterior delt",
                                        "bent over fly", "bent-over fly", "reverse cable fly"]
                if rearDeltPatterns.contains(where: { name.contains($0) }) {
                    score += 120  // Very important for shoulder health on pressing days
                    #if DEBUG
                    AppLogger.debug("[BALANCE] '\(exercise.name ?? "")' +120 (rear delt for shoulder health)", category: .workout)
                    #endif
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════════
            // 🎯 BENCH DIP PENALTY FOR FOUNDATIONAL USERS - Shoulder impingement risk
            // Bench dips put shoulders in a compromised position; prefer dip machine or pushdowns
            // ═══════════════════════════════════════════════════════════════════════════════
            if restrictToFoundational && name.contains("bench dip") {
                score -= 200  // Bench dips are shoulder-risky for beginners - prefer assisted dip or pushdowns
                #if DEBUG
                AppLogger.debug("[RISKY] '\(exercise.name ?? "")' -200 (bench dip shoulder risk for beginners)", category: .workout)
                #endif
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
                if !Self.suppressPerExerciseLogs { AppLogger.debug("[LOCATION] '\(exercise.name ?? "")' penalized (\(Int(locationPenalty))) - not suitable for \(workoutLocation.displayName)", category: .workout) }
            }
            #endif
            
            // 📦 COOLDOWN PENALTY - Exercises done recently get penalized for freshness
            // This ensures each auto-gen gives different exercises even if same muscles
            if let daysSince = ExerciseCooldownTracker.shared.daysSinceLastDone(name) {
                let cooldown = ExerciseBundleEngine.shared.cooldownDays(for: name)
                if daysSince < cooldown {
                    let freshnessPenalty = Double(cooldown - daysSince) * 15.0
                    score -= freshnessPenalty
                    #if DEBUG
                    if freshnessPenalty > 30 {
                        if !Self.suppressPerExerciseLogs { AppLogger.debug("[COOLDOWN] '\(exercise.name ?? "")' penalty -\(Int(freshnessPenalty)) (done \(daysSince) days ago, cooldown \(cooldown)d)", category: .workout) }
                    }
                    #endif
                }
            }
            
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
        AppLogger.debug("[DIVERSITY] Equipment types: \(selectedEquipmentTypes), Target muscles(\(normalizedTargetMuscles.count)): \(normalizedTargetMuscles), ~\(exercisesPerMuscle) per group", category: .workout)
        #endif
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🎯 EQUIPMENT MIX TARGETS - Declare BEFORE scoring (used in closure)
        // ═══════════════════════════════════════════════════════════════════════════
        // Default mix for 6-exercise workout:
        //   - 2 machine/cable (stable, constant tension)
        //   - 2 dumbbell/barbell (free weight compound work)
        //   - 2 flexible (fill based on focus area)
        // Hard cap: No more than 3 free-weight exercises (DB+BB) for fatigue management
        
        let targetMachineOrCable = count >= 6 ? 2 : max(1, count / 3)
        let targetFreeWeight = count >= 6 ? 2 : max(1, count / 3)
        let maxFreeWeight = count >= 6 ? 3 : max(2, count / 2)
        
        var machineOrCableCount = 0
        var freeWeightCount = 0  // Dumbbell + Barbell combined
        
        #if DEBUG
        AppLogger.debug("[EQUIP MIX] Targets - Machine/Cable: \(targetMachineOrCable), Free-weight: \(targetFreeWeight), Max Free-weight: \(maxFreeWeight)", category: .workout)
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
        var usedExerciseBundles: [String: Int] = [:]  // 📦 Track exercise BUNDLES (press ≈ chest press ≈ push-up)
        var usedBaseMovements: Set<String> = []  // 🆕 Track base movements (prevents Barbell + Smith Machine of same exercise)
        var totalPressCount: Int = 0  // 🆕 Global press cap (max 2 for multi-muscle workouts)
        var hasShoulderExercise: Bool = false  // 🆕 Track if we have at least 1 shoulder exercise when requested
        
        // 🆕 Determine if user wants shoulders (for minimum enforcement)
        let wantsShoulders = normalizedTargetMuscles.contains("shoulders")
        let wantsChestAndShoulders = normalizedTargetMuscles.contains("chest") && wantsShoulders
        
        // 🆕 Global press cap: Max 2 presses for multi-muscle workouts (prevents 3+ press variations)
        let globalPressCapEnabled = normalizedTargetMuscles.count > 1
        let maxGlobalPresses = 2
        
        // 🆕 ROW CAP - Max 2 rows, prefer at least one supported
        var rowCount: Int = 0
        var hasSupportedRow: Bool = false
        let maxRows = 2
        
        // 🆕 HINGE CAP - Max 1 hinge per workout (deadlift/RDL/back extension family)
        var hingeCount: Int = 0
        let maxHinges = 1
        
        // 🆕 ARM ISOLATION CAP - If primary isn't "Arms", cap arm isolations
        let isArmsDay = normalizedTargetMuscles.contains("biceps") || normalizedTargetMuscles.contains("triceps") ||
                        normalizedMuscles.contains { $0.lowercased().contains("arm") }
        var bicepIsolationCount: Int = 0
        var tricepIsolationCount: Int = 0
        let maxArmIsolations = isArmsDay ? 2 : 1
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 FOREARM CAP - Max 1 forearm exercise unless explicitly selected
        // ═══════════════════════════════════════════════════════════════════════════
        let explicitlyWantsForearms = normalizedMuscles.contains { $0.lowercased().contains("forearm") } ||
                                      targetMuscles.contains { $0.lowercased().contains("forearm") }
        var forearmIsolationCount: Int = 0
        let maxForearmIsolations = explicitlyWantsForearms ? 2 : 1
        
        #if DEBUG
        AppLogger.debug("[ARM CAPS] Biceps/Triceps max: \(maxArmIsolations), Forearms max: \(maxForearmIsolations) (explicit: \(explicitlyWantsForearms))", category: .workout)
        #endif
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 BACK MAJORITY SLOTS - When Back is primary, back exercises ≥3 of 6
        // ═══════════════════════════════════════════════════════════════════════════
        let backIsPrimary = normalizedTargetMuscles.contains("back") || normalizedTargetMuscles.contains("lats") ||
                           normalizedMuscles.contains { $0.lowercased().contains("back") || $0.lowercased().contains("lat") }
        var backPatternCount: Int = 0  // row/pull/rear-delt count
        let minBackExercises = backIsPrimary ? max(3, (count / 2)) : 0  // Back gets majority slots
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 TRICEPS GATING - Block triceps unless explicitly selected
        // ═══════════════════════════════════════════════════════════════════════════
        let explicitlyWantsTriceps = normalizedMuscles.contains { $0.lowercased().contains("tricep") } ||
                                     targetMuscles.contains { $0.lowercased().contains("tricep") }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 BICEPS GATING - Block biceps unless explicitly selected (for Push days)
        // ═══════════════════════════════════════════════════════════════════════════
        let explicitlyWantsBiceps = normalizedMuscles.contains { $0.lowercased().contains("bicep") } ||
                                    targetMuscles.contains { $0.lowercased().contains("bicep") }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 PRIMARY MUSCLE MINIMUM SLOTS - Enforce minimum exercises per selected group
        // ═══════════════════════════════════════════════════════════════════════════
        let wantsChest = normalizedTargetMuscles.contains("chest") || normalizedMuscles.contains { $0.lowercased().contains("chest") }
        let wantsCore = normalizedTargetMuscles.contains("core") || normalizedMuscles.contains { $0.lowercased().contains("core") || $0.lowercased().contains("abs") }
        let wantsLegs = normalizedTargetMuscles.contains("legs") || normalizedMuscles.contains { muscle in
            let m = muscle.lowercased()
            return m.contains("quad") || m.contains("ham") || m.contains("glute") || m.contains("leg") || m.contains("calf")
        }
        let wantsGlutes = normalizedMuscles.contains { $0.lowercased().contains("glute") }
        let wantsCalves = normalizedMuscles.contains { $0.lowercased().contains("calf") || $0.lowercased().contains("calves") }
        let wantsTraps = normalizedMuscles.contains { $0.lowercased().contains("trap") }
        
        var chestExerciseCount: Int = 0
        var coreExerciseCount: Int = 0
        var gluteExerciseCount: Int = 0
        var calfExerciseCount: Int = 0
        var shrugCount: Int = 0
        var stretchCount: Int = 0
        var verticalPullCount: Int = 0
        var verticalPullFamilies: Set<String> = []  // Track pulldown vs chin-up vs straight-arm
        
        // 🆕 NEW CAPS from user feedback
        var pulloverCount: Int = 0
        var legPressCount: Int = 0
        var verticalPressCount: Int = 0  // Shoulder/overhead presses
        var tricepsPatternCount: Int = 0  // Track triceps exercises
        var plyoCount: Int = 0
        
        // Determine if user explicitly wants lats/serratus (for pullover allowance)
        let wantsLats = normalizedMuscles.contains { $0.lowercased().contains("lat") }
        let wantsSerratus = normalizedMuscles.contains { $0.lowercased().contains("serratus") }
        
        // Core-only day detection (for blocking squat/hinge/press)
        let isCoreOnlyDay = wantsCore && !wantsChest && !wantsShoulders && !wantsLegs && !backIsPrimary
        
        // Chest+Triceps combo detection (needs 2 triceps patterns)
        let isChestTricepsDay = wantsChest && explicitlyWantsTriceps && !wantsShoulders
        
        // Minimum requirements based on selection
        let minChestExercises = wantsChest ? 2 : 0
        let minCoreExercises = wantsCore ? 2 : 0
        let minGluteExercises = wantsGlutes ? 1 : 0
        let maxCalfExercises = wantsCalves ? 2 : 1
        let maxShrugExercises = wantsTraps ? 2 : 1
        let maxStretchExercises = 0  // Stretches should NOT be in main workout slots
        
        // 🆕 NEW CAPS
        let maxPullovers = (wantsLats || wantsSerratus) ? 2 : 1  // Max 1 pullover unless lats/serratus focus
        let maxLegPress = 1  // Max 1 leg press variant per workout
        let maxVerticalPress = 1  // Max 1 shoulder/overhead press unless front delts focus
        let minTricepsPatterns = isChestTricepsDay ? 2 : 0  // Chest+Triceps needs 2 triceps exercises
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 HARD FAMILY CAPS - Max 1 per specific family (user feedback)
        // These families are prone to "template spam" when duplicated
        // ═══════════════════════════════════════════════════════════════════════════
        var horizontalRowCount: Int = 0
        var tbarRowCount: Int = 0
        var hammerCurlCount: Int = 0
        var preacherCurlCount: Int = 0
        var otherPatternCount: Int = 0  // Unknown/unclassified patterns
        
        // Hard caps: These families should be MAX 1 unless user explicitly wants more
        let maxHorizontalRow = 1  // No 2 bent-over rows or 2 T-bar rows
        let maxVerticalPull = 1   // No 2 pulldowns or 2 chin-ups (enforced via family)
        let maxTbarRow = 1
        let maxHammerCurl = 1     // No 2 hammer curls
        let maxPreacherCurl = 1   // No 2 preacher curls
        let maxOtherPattern = 1   // Max 1 unknown pattern per workout
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 HINGE GATING - Block hinges for Back/Biceps, Pull unless lower_back selected
        // ═══════════════════════════════════════════════════════════════════════════
        let wantsLowerBack = normalizedMuscles.contains { $0.lowercased().contains("lower back") || $0.lowercased().contains("erector") }
        let wantsPosteriorChain = normalizedMuscles.contains { $0.lowercased().contains("posterior") }
        let isFullBody = normalizedTargetMuscles.contains("full body") || (wantsChest && wantsLegs && backIsPrimary)
        
        // Back/Biceps, Back/Rear Delts, Pull days: NO HINGE unless explicitly requested
        let isBackPullDay = backIsPrimary && !wantsChest && !wantsLegs
        let allowHinges = wantsLowerBack || wantsPosteriorChain || isFullBody || wantsLegs
        let shouldBlockHinges = isBackPullDay && !allowHinges
        
        #if DEBUG
        if shouldBlockHinges {
            AppLogger.debug("[HINGE GATE] Blocking hinges for Back/Pull day (no lower_back/posterior_chain/full_body selected)", category: .workout)
        }
        #endif
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 RISKY PATTERN PENALTIES - These should be heavily penalized or blocked
        // ═══════════════════════════════════════════════════════════════════════════
        let riskyPatterns = ["upright row", "high pull", "behind neck", "behind the neck", "guillotine"]
        
        #if DEBUG
        if backIsPrimary {
            AppLogger.debug("[BACK PRIMARY] Minimum back exercises: \(minBackExercises)", category: .workout)
        }
        if wantsChest {
            AppLogger.debug("[CHEST PRIMARY] Minimum chest exercises: \(minChestExercises)", category: .workout)
        }
        if wantsCore {
            AppLogger.debug("[CORE PRIMARY] Minimum core exercises: \(minCoreExercises)", category: .workout)
        }
        AppLogger.debug("[TRICEPS GATE] Explicitly wants triceps: \(explicitlyWantsTriceps)", category: .workout)
        AppLogger.debug("[BICEPS GATE] Explicitly wants biceps: \(explicitlyWantsBiceps)", category: .workout)
        #endif
        
        // 🆕 COMBO RULES - Get applicable combo rule for this workout
        let comboRule = WorkoutComboRules.getComboRule(Array(normalizedTargetMuscles))
        let balanceSlot = WorkoutComboRules.getBalanceSlot(Array(normalizedTargetMuscles))
        var hasBalanceExercise: Bool = false
        
        #if DEBUG
        if let rule = comboRule {
            AppLogger.debug("[COMBO RULES] Detected combo: \(rule.comboName), Must include: \(rule.mustInclude), Avoid: \(rule.avoid)", category: .workout)
        }
        if let balance = balanceSlot {
            AppLogger.debug("[COMBO RULES] Balance slot: \(balance)", category: .workout)
        }
        #endif
        var equipmentTypesRepresented: Set<String> = []  // Which equipment types have at least 1 exercise
        
        // Track which required patterns have been fulfilled
        var requiredPatternsFulfilled: Set<String> = []
        
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
        
        // 📦 Use the centralized ExerciseBundleEngine for family detection
        // This ensures auto-gen, programs, and swaps all use the SAME classification
        let bundleEngine = ExerciseBundleEngine.shared
        
        func getExerciseFamily(_ name: String) -> String {
            return bundleEngine.detectExerciseFamily(name)
        }
        
        /// 📦 Check if adding this exercise would exceed its bundle's max-per-workout limit.
        /// Bundles group SIMILAR exercises (bench press ≈ chest press ≈ smith press ≈ push-ups).
        /// This prevents chest workouts from having 3 different press variations.
        func wouldExceedBundleLimit(_ exerciseName: String) -> Bool {
            let family = bundleEngine.detectExerciseFamily(exerciseName)
            guard let bundle = bundleEngine.bundleForFamily(family) else { return false }
            let currentCount = usedExerciseBundles[bundle.id, default: 0]
            return currentCount >= bundle.maxPerWorkout
        }
        
        /// 📦 Record that an exercise was selected (update bundle tracking).
        func recordBundleSelection(_ exerciseName: String) {
            let family = bundleEngine.detectExerciseFamily(exerciseName)
            if let bundle = bundleEngine.bundleForFamily(family) {
                usedExerciseBundles[bundle.id, default: 0] += 1
            }
        }
        
        // 🆕 Helper: Check if exercise is a combo/core/plank move (not foundational)
        func isComboOrCoreFocusedExercise(_ name: String) -> Bool {
            let n = name.lowercased()
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 COMBO EXERCISE DETECTION - Any "X to Y" two-movement mashup
            // These are hard to load/progress and reduce hypertrophy quality
            // ═══════════════════════════════════════════════════════════════════════════
            
            // Match any " to " pattern, excluding cable fly positioning
            if n.contains(" to ") {
                let allowedToPatterns = ["low to high", "high to low", "low-to-high", "high-to-low"]
                let isAllowedPattern = allowedToPatterns.contains { n.contains($0) }
                if !isAllowedPattern {
                    return true  // This is a combo exercise
                }
            }
            
            // Plank-based combo moves
            if n.contains("plank") && (n.contains("push") || n.contains("row") || n.contains("pass") || n.contains("jack")) { return true }
            // Bear crawl variations
            if n.contains("bear crawl") { return true }
            // Renegade rows
            if n.contains("renegade") { return true }
            // Man makers, burpees, etc.
            if n.contains("man maker") || n.contains("manmaker") { return true }
            if n.contains("burpee") { return true }
            // Pass through / thread the needle
            if n.contains("pass through") || n.contains("thread") { return true }
            return false
        }
        
        // 🆕 Helper: Check if exercise is off-target for the requested muscles
        func isOffTargetIsolation(_ exerciseName: String, primaryMuscle: String, targetMuscles: [String]) -> Bool {
            let n = exerciseName.lowercased()
            let pm = primaryMuscle.lowercased()
            
            // CRITICAL: Block PRESS variations when Back+Arms/Biceps selected (no chest/shoulders)
            let targetHasBack = targetMuscles.contains { $0.lowercased().contains("back") || $0.lowercased().contains("lat") }
            let targetHasBiceps = targetMuscles.contains { $0.lowercased().contains("bicep") }
            let targetHasTriceps = targetMuscles.contains { $0.lowercased().contains("tricep") }
            let targetHasForearms = targetMuscles.contains { $0.lowercased().contains("forearm") }
            let targetHasArms = targetHasBiceps || targetHasTriceps || targetMuscles.contains { $0.lowercased().contains("arm") }
            let targetHasChest = targetMuscles.contains { $0.lowercased().contains("chest") || $0.lowercased().contains("pec") }
            let targetHasShoulders = targetMuscles.contains { $0.lowercased().contains("shoulder") || $0.lowercased().contains("delt") }
            let targetHasLegs = targetMuscles.contains { muscle in
                let m = muscle.lowercased()
                return m.contains("quad") || m.contains("ham") || m.contains("glute") || m.contains("leg") || m.contains("calf")
            }
            let targetHasCore = targetMuscles.contains { $0.lowercased().contains("core") || $0.lowercased().contains("abs") }
            let targetHasLowerBack = targetMuscles.contains { $0.lowercased().contains("lower back") || $0.lowercased().contains("erector") }
            let targetHasTraps = targetMuscles.contains { $0.lowercased().contains("trap") }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 STRETCH/MOBILITY GATING - Stretches are NOT main workout exercises
            // ═══════════════════════════════════════════════════════════════════════════
            let isStretch = n.contains("stretch") || n.contains("mobility") || n.contains("foam roll") ||
                           n.contains("static hold") || n.contains("suspension back stretch")
            if isStretch {
                #if DEBUG
                AppLogger.debug("[STRETCH GATE] Blocking '\(exerciseName)' - Stretches not counted as main exercises", category: .workout)
                #endif
                return true
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 RISKY PATTERN BLOCKING - Upright row, high pull, behind neck are risky
            // ═══════════════════════════════════════════════════════════════════════════
            let isRiskyPattern = n.contains("upright row") || n.contains("high pull") || 
                                n.contains("behind neck") || n.contains("behind the neck") ||
                                n.contains("guillotine") || n.contains("smith high pull")
            if isRiskyPattern {
                #if DEBUG
                AppLogger.debug("[RISKY PATTERN] Blocking '\(exerciseName)' - Shoulder-risky movement pattern", category: .workout)
                #endif
                return true
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 CRITICAL: Block ALL triceps exercises unless explicitly selected
            // ═══════════════════════════════════════════════════════════════════════════
            if !targetHasTriceps {
                let isTricepsExercise = pm.contains("tricep") ||
                    n.contains("tricep") ||
                    n.contains("pushdown") ||
                    n.contains("press down") ||
                    n.contains("skull crusher") ||
                    (n.contains("extension") && !n.contains("leg extension") && !n.contains("back extension") && !n.contains("hip extension")) ||
                    (n.contains("dip") && !n.contains("assisted") && !n.contains("chin")) ||
                    (n.contains("kickback") && !n.contains("glute") && !n.contains("leg"))
                
                if isTricepsExercise {
                    #if DEBUG
                    AppLogger.debug("[TRICEPS GATE] Blocking '\(exerciseName)' - Triceps NOT in target muscles", category: .workout)
                    #endif
                    return true
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 CRITICAL: Block ALL biceps exercises unless explicitly selected
            // (Prevents biceps leaking into Push days or Chest+Shoulders)
            // ═══════════════════════════════════════════════════════════════════════════
            if !targetHasBiceps && !targetHasBack {
                let isBicepsExercise = pm.contains("bicep") || pm.contains("brachialis") ||
                    (n.contains("curl") && !n.contains("leg curl") && !n.contains("hamstring") && !n.contains("wrist"))
                
                if isBicepsExercise {
                    #if DEBUG
                    AppLogger.debug("[BICEPS GATE] Blocking '\(exerciseName)' - Biceps NOT in target muscles", category: .workout)
                    #endif
                    return true
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 FOREARM BLOCKING: Block forearm exercises unless explicitly selected
            // ═══════════════════════════════════════════════════════════════════════════
            let isForearmExercise = pm.contains("forearm") ||
                n.contains("forearm") ||
                n.contains("wrist curl") ||
                n.contains("wrist extension") ||
                n.contains("wrist roller") ||
                n.contains("finger curl") ||
                n.contains("reverse curl") ||
                n.contains("behind back curl") ||
                n.contains("farmers") ||
                n.contains("gripper") ||
                n.contains("forearm pronation") ||
                n.contains("forearm supination")
            
            if isForearmExercise && !targetHasForearms {
                #if DEBUG
                AppLogger.debug("[FOREARM GATE] Blocking '\(exerciseName)' - Forearms NOT explicitly selected", category: .workout)
                #endif
                return true
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 CORE DAY LEAK BLOCKING - Block squat/hinge/press on Core/Abs only days
            // ═══════════════════════════════════════════════════════════════════════════
            let isCoreOnlyWorkout = targetHasCore && !targetHasChest && !targetHasShoulders && !targetHasLegs && !targetHasBack
            if isCoreOnlyWorkout {
                // Block squats
                let isSquat = n.contains("squat") || n.contains("front squat") || n.contains("goblet")
                if isSquat {
                    #if DEBUG
                    AppLogger.debug("[CORE DAY] Blocking '\(exerciseName)' - Squat not for Core/Abs day", category: .workout)
                    #endif
                    return true
                }
                // Block hinges
                let isHinge = n.contains("deadlift") || n.contains("rdl") || n.contains("romanian") || 
                             n.contains("good morning") || n.contains("hip hinge")
                if isHinge {
                    #if DEBUG
                    AppLogger.debug("[CORE DAY] Blocking '\(exerciseName)' - Hinge not for Core/Abs day", category: .workout)
                    #endif
                    return true
                }
                // Block presses (shoulder/chest)
                let isPress = (n.contains("press") && !n.contains("pallof press")) || n.contains("push up")
                if isPress {
                    #if DEBUG
                    AppLogger.debug("[CORE DAY] Blocking '\(exerciseName)' - Press not for Core/Abs day", category: .workout)
                    #endif
                    return true
                }
                // Block lateral raise planks for shoulder-limited users or on core days
                let isLateralRaisePlank = n.contains("lateral raise plank") || n.contains("plank lateral raise")
                if isLateralRaisePlank {
                    #if DEBUG
                    AppLogger.debug("[CORE DAY] Blocking '\(exerciseName)' - Lateral raise plank is shoulder-y, not core", category: .workout)
                    #endif
                    return true
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 PLYO BLOCKING - Only allow plyometrics if explicitly requested
            // ═══════════════════════════════════════════════════════════════════════════
            let isPlyoExercise = n.contains("plyo") || n.contains("jump") || n.contains("bound") ||
                                n.contains("hop") || n.contains("explosive") || n.contains("box jump") ||
                                n.contains("change plyo") || n.contains("shuffle")
            // For now, block plyo exercises by default (can be enabled via specific goal later)
            if isPlyoExercise && !n.contains("step up") {
                #if DEBUG
                AppLogger.debug("[PLYO GATE] Blocking '\(exerciseName)' - Plyo/jump exercises not in default mode", category: .workout)
                #endif
                return true
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 HINGE BLOCKING for Back/Biceps, Back/Rear Delts, Pull days
            // Hinges (deadlifts, RDLs, back extensions) are NOT allowed unless user selected:
            // - lower_back / posterior_chain / full_body / legs
            // ═══════════════════════════════════════════════════════════════════════════
            let isHingeExercise = n.contains("deadlift") || n.contains("rdl") || n.contains("romanian") ||
                n.contains("good morning") || n.contains("back extension") || n.contains("hyperextension") ||
                n.contains("hip hinge") || pm.contains("erector") || pm.contains("lower back")
            
            // Detect Back/Pull day (without legs or chest)
            let isBackPullWorkout = targetHasBack && !targetHasChest && !targetHasLegs
            
            // Check if user explicitly wants lower back / posterior chain / full body
            let wantsLowerBackExplicit = targetMuscles.contains { $0.lowercased().contains("lower back") || $0.lowercased().contains("erector") }
            let wantsPosteriorChainExplicit = targetMuscles.contains { $0.lowercased().contains("posterior") }
            let isFullBodyWorkout = targetMuscles.contains { $0.lowercased().contains("full body") } || (targetHasChest && targetHasLegs && targetHasBack)
            
            // Block hinges on Back/Pull days unless explicitly requested
            let shouldBlockHingesInFilter = isBackPullWorkout && !wantsLowerBackExplicit && !wantsPosteriorChainExplicit && !isFullBodyWorkout && !targetHasLegs
            
            if isHingeExercise && shouldBlockHingesInFilter {
                #if DEBUG
                AppLogger.debug("[HINGE GATE] Blocking '\(exerciseName)' - Hinge not allowed on Back/Pull day (no lower_back/posterior/full_body selected)", category: .workout)
                #endif
                return true
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 BACK EXTENSION / HINGE BLOCKING for Arms-only day
            // Arms day should NOT have back extensions or hinge movements
            // ═══════════════════════════════════════════════════════════════════════════
            let isArmsOnlyDay = targetHasArms && !targetHasBack && !targetHasChest && !targetHasShoulders && !targetHasLegs
            if isArmsOnlyDay && isHingeExercise {
                #if DEBUG
                AppLogger.debug("[ARMS DAY] Blocking '\(exerciseName)' - Hinge/back extension not for Arms-only day", category: .workout)
                #endif
                return true
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 MUSCLE GROUP LEAK BLOCKING - Back+Arms blocks chest press/fly
            // ═══════════════════════════════════════════════════════════════════════════
            if targetHasBack && targetHasArms && !targetHasChest && !targetHasShoulders {
                // Block chest press/fly
                if n.contains("press") && !n.contains("leg press") {
                    #if DEBUG
                    AppLogger.debug("[LEAK BLOCK] Blocking press '\(exerciseName)' in Back+Arms workout", category: .workout)
                    #endif
                    return true
                }
                if n.contains("fly") && !n.contains("reverse fly") && !n.contains("rear delt fly") {
                    #if DEBUG
                    AppLogger.debug("[LEAK BLOCK] Blocking fly '\(exerciseName)' in Back+Arms workout", category: .workout)
                    #endif
                    return true
                }
                if n.contains("dip") && !pm.contains("back") {
                    #if DEBUG
                    AppLogger.debug("[LEAK BLOCK] Blocking dip '\(exerciseName)' in Back+Arms workout", category: .workout)
                    #endif
                    return true
                }
                // Block lateral raises (shoulder, not back)
                if n.contains("lateral raise") && !n.contains("rear") {
                    #if DEBUG
                    AppLogger.debug("[LEAK BLOCK] Blocking lateral raise '\(exerciseName)' in Back+Arms workout", category: .workout)
                    #endif
                    return true
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 HINGE/BACK EXTENSION GATING for non-Lower Back days
            // Only allow if user selected Lower Back, Full Body, or Posterior Chain
            // ═══════════════════════════════════════════════════════════════════════════
            let isBackHinge = n.contains("deadlift") || n.contains("back extension") || n.contains("hyperextension") ||
                             n.contains("good morning") || (n.contains("rdl") && !n.contains("curl"))
            if isBackHinge && !targetHasLowerBack && !targetHasLegs {
                // For Back+Arms, only allow if focus includes lower back
                if targetHasBack && targetHasArms {
                    #if DEBUG
                    AppLogger.debug("[HINGE GATE] Blocking '\(exerciseName)' - Hinge/extension not for Back+Arms (no lower back selected)", category: .workout)
                    #endif
                    return true
                }
            }
            
            // ═══════════════════════════════════════════════════════════════════════════
            // 🚫 SHRUG GATING - Only include if traps selected or as low-priority filler
            // ═══════════════════════════════════════════════════════════════════════════
            let isShrug = n.contains("shrug")
            if isShrug && !targetHasTraps && !targetHasBack {
                #if DEBUG
                AppLogger.debug("[SHRUG GATE] Blocking '\(exerciseName)' - Traps NOT explicitly selected", category: .workout)
                #endif
                return true
            }
            
            // If targets include "shoulders" or "chest" but NOT "biceps/triceps/arms"
            let targetHasChestOrShoulders = targetHasChest || targetHasShoulders
            
            // STRICT: If user wants chest/shoulders but not arms, filter out arm isolation
            if targetHasChestOrShoulders && !targetHasArms {
                // Block bicep isolation
                if (n.contains("curl") && !n.contains("leg curl") && !n.contains("hamstring")) ||
                   pm.contains("bicep") {
                    if n.contains("curl") && !n.contains("press") && !n.contains("row") {
                        return true  // Pure curl isolation - off target
                    }
                }
            }
            return false
        }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🎯 PHASE 0: ENFORCE MUST_INCLUDE COMBO RULE PATTERNS
        // ═══════════════════════════════════════════════════════════════════════════
        // CRITICAL: Reserve slots for required patterns BEFORE equipment diversity
        // Example: Back + Biceps MUST have vertical_pull + horizontal_row + bicep_curl
        
        if let rule = comboRule, !rule.mustInclude.isEmpty {
            #if DEBUG
            AppLogger.debug("[PHASE 0] Enforcing required patterns: \(rule.mustInclude)", category: .workout)
            #endif
            
            // Try to fulfill each required pattern
            for requiredPattern in rule.mustInclude {
                // Check if we already have this pattern
                var hasPattern = false
                for existing in result {
                    let existingPattern = WorkoutComboRules.detectExercisePattern(existing.name ?? "", equipment: existing.equipment ?? "")
                    if existingPattern == requiredPattern {
                        hasPattern = true
                        break
                    }
                    // Handle aliases (horizontal_row can be chest_supported_row)
                    if requiredPattern == "horizontal_row" && existingPattern == "chest_supported_row" {
                        hasPattern = true
                        break
                    }
                    // Handle aliases (bicep_curl can be any curl variant)
                    if requiredPattern == "bicep_curl" && ["bicep_curl", "bicep_neutral", "bicep_preacher"].contains(existingPattern) {
                        hasPattern = true
                        break
                    }
                }
                
                if hasPattern {
                    #if DEBUG
                    AppLogger.info("[PHASE 0] Already have \(requiredPattern)", category: .workout)
                    #endif
                    continue
                }
                
                // Find best exercise matching this pattern
                for scored in scoredExercises {
                    guard result.count < count else { break }
                    
                    let exercise = scored.exercise
                    let name = exercise.name ?? ""
                    let nameLower = name.lowercased()
                    let equipment = exercise.equipment ?? ""
                    
                    // Skip if already used
                    guard !usedNames.contains(nameLower) else { continue }
                    
                    // Check pattern match
                    let pattern = WorkoutComboRules.detectExercisePattern(name, equipment: equipment)
                    
                    // Match required pattern (with aliases)
                    var matchesRequired = false
                    if pattern == requiredPattern {
                        matchesRequired = true
                    } else if requiredPattern == "horizontal_row" && pattern == "chest_supported_row" {
                        matchesRequired = true
                    } else if requiredPattern == "bicep_curl" && ["bicep_curl", "bicep_neutral", "bicep_preacher"].contains(pattern) {
                        matchesRequired = true
                    }
                    
                    guard matchesRequired else { continue }
                    
                    // Check if exercise is off-target
                    let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                    let primaryMuscle = muscleGroups.first?.lowercased() ?? "unknown"
                    if isOffTargetIsolation(name, primaryMuscle: primaryMuscle, targetMuscles: Array(normalizedMuscles)) {
                        continue
                    }
                    
                    // Check avoid rules
                    let (shouldAvoid, avoidReason) = WorkoutComboRules.shouldAvoidExercise(name, comboRule: rule, focusAreas: nil)
                    if shouldAvoid {
                        #if DEBUG
                        AppLogger.debug("[PHASE 0] Skipping '\(name)': \(avoidReason)", category: .workout)
                        #endif
                        continue
                    }
                    
                    // Get exercise family and base movement
                    let exerciseFamily = getExerciseFamily(nameLower)
                    let baseMovement = getBaseMovement(nameLower)
                    
                    // Skip if already have this base movement
                    if usedBaseMovements.contains(baseMovement) {
                        continue
                    }
                    
                    // Skip if already have from this family
                    if exerciseFamily != "other" && (usedExerciseFamilies[exerciseFamily] ?? 0) >= 1 {
                        continue
                    }
                    
                    // 📦 BUNDLE CHECK - Prevent similar exercises (bench press ≈ chest press ≈ push-up)
                    if wouldExceedBundleLimit(name) {
                        #if DEBUG
                        AppLogger.debug("[PHASE 0 BUNDLE] Skipping '\(name)': bundle limit reached", category: .workout)
                        #endif
                        continue
                    }
                    
                    // SELECT THIS EXERCISE for required pattern
                    let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
                    let generated = GeneratedExercise(
                        id: exercise.id?.uuidString ?? UUID().uuidString,
                        name: name,
                        category: exercise.category ?? "Unknown",
                        primaryBodyRegion: exercise.category ?? "Unknown",
                        primaryMuscle: muscleGroups.first ?? "Unknown",
                        secondaryMuscles: secondaryMuscles,
                        equipment: equipment,
                        difficulty: "Intermediate",
                        videoUrl: nil,
                        instructions: exercise.instructions
                    )
                    result.append(generated)
                    usedNames.insert(nameLower)
                    usedBaseMovements.insert(baseMovement)
                    usedExerciseFamilies[exerciseFamily, default: 0] += 1
                    recordBundleSelection(name)  // 📦 Track bundle usage
                    requiredPatternsFulfilled.insert(requiredPattern)
                    
                    // Track equipment type
                    let equipLower = equipment.lowercased()
                    if equipLower.contains("barbell") { equipmentTypesRepresented.insert("barbell") }
                    else if equipLower.contains("dumbbell") { equipmentTypesRepresented.insert("dumbbell") }
                    else if equipLower.contains("cable") { equipmentTypesRepresented.insert("cable") }
                    else if equipLower.contains("machine") || equipLower.contains("lever") || equipLower.contains("smith") {
                        equipmentTypesRepresented.insert("machine")
                    }
                    
                    // 🆕 Track equipment mix for targets
                    let phase0EquipType = ExerciseFilterService.normalizeEquipment(equipment).lowercased()
                    if ["cable", "machine", "smith", "lever"].contains(where: { phase0EquipType.contains($0) }) {
                        machineOrCableCount += 1
                    } else if ["barbell", "dumbbell"].contains(where: { phase0EquipType.contains($0) }) {
                        freeWeightCount += 1
                    }
                    
                    // Track if this is row
                    if pattern == "horizontal_row" || pattern == "chest_supported_row" {
                        rowCount += 1
                        if ["chest supported", "chest-supported", "seated", "lever", "machine"].contains(where: { nameLower.contains($0) }) {
                            hasSupportedRow = true
                        }
                    }
                    
                    // Track if this is hinge
                    let isHinge = ["deadlift", "rdl", "romanian", "good morning", "back extension", "hyperextension"].contains { nameLower.contains($0) }
                    if isHinge {
                        hingeCount += 1
                    }
                    
                    // 🆕 Track back pattern count (row/pull/rear-delt)
                    let backPatterns = ["horizontal_row", "chest_supported_row", "vertical_pull", "rear_delt", "lat_isolation", "shrug"]
                    if backPatterns.contains(pattern) {
                        backPatternCount += 1
                    }
                    
                    // Track normalized muscle
                    let normalizedMuscle = normalizeMuscleName(primaryMuscle)
                    usedNormalizedMuscles[normalizedMuscle, default: 0] += 1
                    usedMuscles[primaryMuscle, default: 0] += 1
                    
                    #if DEBUG
                    AppLogger.info("[PHASE 0] Reserved \(requiredPattern): \(name) (score: \(Int(scored.score)))", category: .workout)
                    #endif
                    break
                }
            }
            
            // Validate we got all required patterns
            let missing = rule.mustInclude.filter { !requiredPatternsFulfilled.contains($0) }
            if !missing.isEmpty {
                #if DEBUG
                AppLogger.warning("[PHASE 0] Could not find exercises for: \(missing)", category: .workout)
                AppLogger.debug("[AUTO-REPAIR] Attempting to find missing patterns...", category: .workout)
                #endif
                
                // 🆕 AUTO-REPAIR: Force-find missing required patterns
                // This ensures we NEVER show a workout that violates combo rules
                for missingPattern in missing {
                    // If we're at count, remove the LOWEST scored non-required exercise to make room
                    if result.count >= count {
                        // Find the lowest scored exercise that isn't a required pattern
                        if let lowestIndex = result.indices.min(by: { i1, i2 in
                            let e1 = result[i1]
                            let e2 = result[i2]
                            let p1 = WorkoutComboRules.detectExercisePattern(e1.name ?? "", equipment: e1.equipment ?? "")
                            let p2 = WorkoutComboRules.detectExercisePattern(e2.name ?? "", equipment: e2.equipment ?? "")
                            let isRequired1 = rule.mustInclude.contains(p1) || requiredPatternsFulfilled.contains(p1)
                            let isRequired2 = rule.mustInclude.contains(p2) || requiredPatternsFulfilled.contains(p2)
                            // If both required or both not required, compare scores
                            if isRequired1 == isRequired2 {
                                return (scoredExercises.first(where: { $0.exercise.name == e1.name })?.score ?? 0) < (scoredExercises.first(where: { $0.exercise.name == e2.name })?.score ?? 0)
                            }
                            // Prefer to remove non-required
                            return !isRequired1 && isRequired2
                        }) {
                            let removed = result[lowestIndex]
                            result.remove(at: lowestIndex)
                            usedNames.remove(removed.name.lowercased())
                            #if DEBUG
                            AppLogger.debug("[AUTO-REPAIR] Removing '\(removed.name)' to make room for \(missingPattern)", category: .workout)
                            #endif
                        }
                    }
                    
                    // Search ALL exercises for this pattern (ignore strict scoring)
                    for scored in scoredExercises {
                        let exercise = scored.exercise
                        let name = exercise.name ?? ""
                        let nameLower = name.lowercased()
                        let equipment = exercise.equipment ?? ""
                        
                        // Skip if already used
                        guard !usedNames.contains(nameLower) else { continue }
                        
                        // Check if this matches the missing pattern
                        let pattern = WorkoutComboRules.detectExercisePattern(name, equipment: equipment)
                        
                        var matches = false
                        if pattern == missingPattern {
                            matches = true
                        } else if missingPattern == "rear_delt" && (nameLower.contains("face pull") || nameLower.contains("reverse fly") || nameLower.contains("rear delt")) {
                            matches = true
                        } else if missingPattern == "horizontal_row" && pattern == "chest_supported_row" {
                            matches = true
                        } else if missingPattern == "bicep_curl" && ["bicep_curl", "bicep_neutral", "bicep_preacher"].contains(pattern) {
                            matches = true
                        }
                        
                        guard matches else { continue }
                        
                        // Check family limits (don't add duplicate families during auto-repair)
                        let exerciseFamily = getExerciseFamily(nameLower)
                        if exerciseFamily != "other" && (usedExerciseFamilies[exerciseFamily] ?? 0) >= 1 {
                            continue  // Already have one from this family
                        }
                        
                        // 📦 BUNDLE CHECK - Prevent similar exercises
                        if wouldExceedBundleLimit(name) {
                            continue
                        }
                        
                        // Found it - add it to results
                        let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                        let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
                        let generated = GeneratedExercise(
                            id: exercise.id?.uuidString ?? UUID().uuidString,
                            name: name,
                            category: exercise.category ?? "Unknown",
                            primaryBodyRegion: exercise.category ?? "Unknown",
                            primaryMuscle: muscleGroups.first ?? "Unknown",
                            secondaryMuscles: secondaryMuscles,
                            equipment: equipment,
                            difficulty: "Intermediate",
                            videoUrl: nil,
                            instructions: exercise.instructions
                        )
                        result.append(generated)
                        usedNames.insert(nameLower)
                        
                        // Track base movement and family
                        let baseMovement = getBaseMovement(nameLower)
                        usedBaseMovements.insert(baseMovement)
                        usedExerciseFamilies[exerciseFamily, default: 0] += 1
                        recordBundleSelection(name)  // 📦 Track bundle usage
                        requiredPatternsFulfilled.insert(missingPattern)
                        
                        #if DEBUG
                        AppLogger.info("[AUTO-REPAIR] Added '\(name)' to fulfill \(missingPattern)", category: .workout)
                        #endif
                        break
                    }
                }
            } else {
                #if DEBUG
                AppLogger.info("[PHASE 0] All required patterns fulfilled: \(requiredPatternsFulfilled.sorted())", category: .workout)
                #endif
            }
        }
        
        // NOTE: Duplicate Phase 0 was removed - the original Phase 0 above already handles
        // required pattern enforcement INCLUDING auto-repair. Having two Phase 0s was causing
        // auto-repair additions to be lost.
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🎯 PHASE 1: ROUND-ROBIN equipment diversity allocation
        // ═══════════════════════════════════════════════════════════════════════════
        // Ensures FAIR distribution across ALL selected equipment types
        // Rather than filling one type completely before moving to next
        if selectedEquipmentTypes.count > 1 {
            // Calculate fair distribution: ensure each equipment type gets at least 1 exercise
            // Then distribute remaining slots evenly
            let equipmentTypesList = Array(selectedEquipmentTypes).sorted()  // Sort for consistency
            let slotsPerType = max(1, count / equipmentTypesList.count)
            let maxSlotsForPhase1 = min(count, equipmentTypesList.count * slotsPerType)
            
            #if DEBUG
            AppLogger.debug("[EQUIP DIVERSITY] Round-robin allocation: \(equipmentTypesList.count) types, \(slotsPerType) per type, \(maxSlotsForPhase1) total Phase 1 slots", category: .workout)
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
                AppLogger.debug("[PHASE 1] Available for \(equipType): \(exercises.count) exercises", category: .workout)
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
                            AppLogger.debug("Skipping '\(name)' - base movement '\(baseMovement)' already used", category: .workout)
                            #endif
                            continue
                        }
                        
                        let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                        let primaryMuscle = muscleGroups.first?.lowercased() ?? "unknown"
                        let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
                        let normalizedMuscle = normalizeMuscleName(primaryMuscle)
                        
                        // 🆕 Muscle balance check: Don't over-represent one muscle group
                        let currentMuscleCount = usedNormalizedMuscles[normalizedMuscle] ?? 0
                        let maxPerMuscle = max(2, Int(ceil(Double(count) / Double(max(1, normalizedTargetMuscles.count)))))
                        if currentMuscleCount >= maxPerMuscle && normalizedTargetMuscles.count > 1 {
                            continue
                        }
                        
                        // 🆕 EXERCISE FAMILY CHECK: Max 2 exercises per family (allows some variety, prevents 3+ of same)
                        let exerciseFamily = getExerciseFamily(nameLower)
                        let familyCount = usedExerciseFamilies[exerciseFamily] ?? 0
                        let maxPerFamily = 2  // Updated: allow up to 2 from same family (e.g., 2 curls OK, 3 not)
                        if exerciseFamily != "other" && familyCount >= maxPerFamily {
                            #if DEBUG
                            AppLogger.debug("[FAMILY CAP] Skipping '\(name)': family '\(exerciseFamily)' already has \(familyCount) exercises (max: \(maxPerFamily))", category: .workout)
                            #endif
                            continue  // Already have max from this family
                        }
                        
                        // 📦 BUNDLE CHECK - Chest press ≈ bench press ≈ smith press = same bundle
                        if wouldExceedBundleLimit(name) {
                            #if DEBUG
                            AppLogger.debug("[BUNDLE] Skipping '\(name)': bundle limit reached", category: .workout)
                            #endif
                            continue
                        }
                        
                        // 🆕 EQUIPMENT MIX CHECK: Enforce balanced mix (machines, cables, free weights)
                        let exerciseEquipType = ExerciseFilterService.normalizeEquipment(exercise.equipment).lowercased()
                        let isMachineOrCable = ["cable", "machine", "smith", "lever"].contains { exerciseEquipType.contains($0) }
                        let isFreeWeight = ["barbell", "dumbbell"].contains { exerciseEquipType.contains($0) }
                        
                        // Check if we're exceeding free-weight cap (max 3 for fatigue management)
                        if isFreeWeight && freeWeightCount >= maxFreeWeight {
                            continue  // Too many free weights already
                        }
                        
                        // Prefer machine/cable if we haven't hit target yet
                        if machineOrCableCount < targetMachineOrCable && !isMachineOrCable {
                            // Need more machine/cable exercises - deprioritize but don't block
                            // (Will be handled by scoring below)
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
                        
                        // 🆕 GLOBAL PRESS CAP: Max 2 total presses for multi-muscle workouts
                        if globalPressCapEnabled && movementKeyword == "press" && totalPressCount >= maxGlobalPresses {
                            #if DEBUG
                            AppLogger.debug("[PRESS CAP] Skipping '\(name)': already have \(totalPressCount) presses (cap: \(maxGlobalPresses))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // 🆕 ROW CAP: Max 2 rows, prefer at least one supported
                        let isRow = (nameLower.contains(" row") || nameLower.hasPrefix("row")) && !nameLower.contains("upright")
                        if isRow {
                            if rowCount >= maxRows {
                                continue
                            }
                            let isSupported = ["chest supported", "chest-supported", "lying", "seated", "lever", "machine"].contains { nameLower.contains($0) }
                            if rowCount == 1 && !hasSupportedRow && !isSupported {
                                continue  // Second row should be supported if first wasn't
                            }
                        }
                        
                        // 🆕 HINGE CAP: Max 1 hinge per workout
                        let isHinge = ["deadlift", "rdl", "romanian", "good morning", "back extension", "hyperextension"].contains { nameLower.contains($0) }
                        if isHinge && hingeCount >= maxHinges {
                            continue
                        }
                        
                        // 🆕 ARM ISOLATION CAP
                        let isBicepIsolation = exerciseFamily == "bicep_curl" || exerciseFamily == "hammer_curl" || exerciseFamily == "preacher_curl"
                        let isTricepIsolation = exerciseFamily == "tricep_extension" || exerciseFamily == "tricep_pushdown" || nameLower.contains("skull crusher")
                        
                        if !isArmsDay {
                            if isBicepIsolation && bicepIsolationCount >= maxArmIsolations {
                                continue
                            }
                            if isTricepIsolation && tricepIsolationCount >= maxArmIsolations {
                                continue
                            }
                        }
                        
                        // 🆕 FOREARM ISOLATION CAP - Max 1 unless explicitly selected
                        let isForearmIsolation = nameLower.contains("wrist") || nameLower.contains("forearm") ||
                                                 nameLower.contains("finger curl") || nameLower.contains("reverse curl") ||
                                                 nameLower.contains("gripper")
                        if isForearmIsolation && forearmIsolationCount >= maxForearmIsolations {
                            #if DEBUG
                            AppLogger.debug("[FOREARM CAP] Skipping '\(name)': already have \(forearmIsolationCount) forearm exercises (max: \(maxForearmIsolations))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // 🆕 CALF CAP - Max 1 calf raise unless calves explicitly selected
                        let isCalfExercise = nameLower.contains("calf") || nameLower.contains("gastrocnemius") ||
                                            nameLower.contains("soleus") || nameLower.contains("toe raise")
                        if isCalfExercise && calfExerciseCount >= maxCalfExercises {
                            #if DEBUG
                            AppLogger.debug("[CALF CAP] Skipping '\(name)': already have \(calfExerciseCount) calf exercises (max: \(maxCalfExercises))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // 🆕 SHRUG CAP - Max 1 shrug unless traps explicitly selected
                        let isShrug = nameLower.contains("shrug")
                        if isShrug && shrugCount >= maxShrugExercises {
                            #if DEBUG
                            AppLogger.debug("[SHRUG CAP] Skipping '\(name)': already have \(shrugCount) shrug exercises (max: \(maxShrugExercises))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // 🆕 VERTICAL PULL FAMILY DUPLICATE CHECK - Second vertical pull must be different family
                        let isVerticalPull = nameLower.contains("pulldown") || nameLower.contains("pull down") || 
                                            nameLower.contains("chin up") || nameLower.contains("chin-up") ||
                                            nameLower.contains("pull up") || nameLower.contains("pull-up") ||
                                            nameLower.contains("lat pull")
                        if isVerticalPull && verticalPullCount >= 1 {
                            // Determine family of this vertical pull
                            let vpFamily: String = {
                                if nameLower.contains("chin up") || nameLower.contains("chin-up") { return "chin_up" }
                                if nameLower.contains("pull up") || nameLower.contains("pull-up") { return "pull_up" }
                                if nameLower.contains("straight arm") { return "straight_arm_pulldown" }
                                if nameLower.contains("pulldown") || nameLower.contains("pull down") { return "pulldown" }
                                return "other_vertical_pull"
                            }()
                            
                            if verticalPullFamilies.contains(vpFamily) {
                                #if DEBUG
                                AppLogger.debug("[VERTICAL PULL DUP] Skipping '\(name)': family '\(vpFamily)' already used", category: .workout)
                                #endif
                                continue  // Already have this family of vertical pull
                            }
                        }
                        
                        // 🆕 PULLOVER CAP - Max 1 pullover unless lats/serratus focus
                        let isPullover = nameLower.contains("pullover")
                        if isPullover && pulloverCount >= maxPullovers {
                            #if DEBUG
                            AppLogger.debug("[PULLOVER CAP] Skipping '\(name)': already have \(pulloverCount) pullovers (max: \(maxPullovers))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // 🆕 LEG PRESS CAP - Max 1 leg press variant per workout
                        let isLegPress = nameLower.contains("leg press") || nameLower.contains("press (plate loaded)") ||
                                        (nameLower.contains("press") && nameLower.contains("leg"))
                        if isLegPress && legPressCount >= maxLegPress {
                            #if DEBUG
                            AppLogger.debug("[LEG PRESS CAP] Skipping '\(name)': already have \(legPressCount) leg press (max: \(maxLegPress))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // 🆕 VERTICAL PRESS CAP - Max 1 shoulder/overhead press unless front delts focus
                        let isVerticalPress = (nameLower.contains("shoulder press") || nameLower.contains("overhead press") ||
                                              nameLower.contains("military press") || nameLower.contains("viking press")) &&
                                             !nameLower.contains("leg")
                        if isVerticalPress && verticalPressCount >= maxVerticalPress {
                            #if DEBUG
                            AppLogger.debug("[VERTICAL PRESS CAP] Skipping '\(name)': already have \(verticalPressCount) vertical press (max: \(maxVerticalPress))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // ═══════════════════════════════════════════════════════════════════════════
                        // 🆕 HARD FAMILY CAPS - Max 1 per specific family (user feedback Dec 27)
                        // ═══════════════════════════════════════════════════════════════════════════
                        
                        // HORIZONTAL ROW CAP - Max 1 (no 2 bent-over rows or 2 cable rows)
                        let isHorizontalRow = (nameLower.contains("row") && !nameLower.contains("upright row")) ||
                                             nameLower.contains("bent over") || nameLower.contains("bent-over")
                        let isTbarRow = nameLower.contains("t bar") || nameLower.contains("t-bar") || nameLower.contains("tbar")
                        
                        if isHorizontalRow && !isTbarRow && horizontalRowCount >= maxHorizontalRow {
                            #if DEBUG
                            AppLogger.debug("[ROW CAP] Skipping '\(name)': already have \(horizontalRowCount) horizontal rows (max: \(maxHorizontalRow))", category: .workout)
                            #endif
                            continue
                        }
                        
                        if isTbarRow && tbarRowCount >= maxTbarRow {
                            #if DEBUG
                            AppLogger.debug("[TBAR CAP] Skipping '\(name)': already have \(tbarRowCount) T-bar rows (max: \(maxTbarRow))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // HAMMER CURL CAP - Max 1 (no 2 hammer curls)
                        let isHammerCurl = nameLower.contains("hammer") && nameLower.contains("curl")
                        if isHammerCurl && hammerCurlCount >= maxHammerCurl {
                            #if DEBUG
                            AppLogger.debug("[HAMMER CURL CAP] Skipping '\(name)': already have \(hammerCurlCount) hammer curls (max: \(maxHammerCurl))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // PREACHER CURL CAP - Max 1 (no 2 preacher curls)
                        let isPreacherCurl = nameLower.contains("preacher") && nameLower.contains("curl")
                        if isPreacherCurl && preacherCurlCount >= maxPreacherCurl {
                            #if DEBUG
                            AppLogger.debug("[PREACHER CURL CAP] Skipping '\(name)': already have \(preacherCurlCount) preacher curls (max: \(maxPreacherCurl))", category: .workout)
                            #endif
                            continue
                        }
                        
                        // UNKNOWN PATTERN CAP - Max 1 exercise with "other" pattern
                        let detectedPatternForCap = WorkoutComboRules.detectExercisePattern(name, equipment: exercise.equipment ?? "")
                        let isOtherPattern = detectedPatternForCap == "other" || detectedPatternForCap.isEmpty
                        if isOtherPattern && otherPatternCount >= maxOtherPattern {
                            #if DEBUG
                            AppLogger.debug("[OTHER PATTERN CAP] Skipping '\(name)': already have \(otherPatternCount) unknown-pattern exercises (max: \(maxOtherPattern))", category: .workout)
                            #endif
                            continue
                        }
                        // 🆕 BACK PRIORITY - If back is primary and we need more back exercises
                        let detectedPatternCheck = WorkoutComboRules.detectExercisePattern(name, equipment: exercise.equipment ?? "")
                        let backPatternsCheck = ["horizontal_row", "chest_supported_row", "vertical_pull", "rear_delt", "lat_isolation", "shrug"]
                        let isBackExercise = backPatternsCheck.contains(detectedPatternCheck) || primaryMuscle.contains("back") || primaryMuscle.contains("lat")
                        
                        // If back is primary and we haven't hit minimum back exercises, prefer back moves
                        if backIsPrimary && backPatternCount < minBackExercises && !isBackExercise {
                            // Deprioritize non-back exercises until we hit minimum
                            // But don't skip entirely - just prefer back exercises first
                            let remainingSlots = count - result.count
                            let neededBackExercises = minBackExercises - backPatternCount
                            if remainingSlots <= neededBackExercises {
                                #if DEBUG
                                AppLogger.debug("[BACK PRIORITY] Skipping '\(name)': need \(neededBackExercises) more back exercises, only \(remainingSlots) slots left", category: .workout)
                                #endif
                                continue
                            }
                        }
                        
                        // 🆕 EQUIPMENT MIX CAP: Max 3 free-weight exercises for fatigue management
                        let exerciseEquipTypeCheck = ExerciseFilterService.normalizeEquipment(exercise.equipment).lowercased()
                        let isFreeWeightCheck = ["barbell", "dumbbell"].contains { exerciseEquipTypeCheck.contains($0) }
                        if isFreeWeightCheck && freeWeightCount >= maxFreeWeight {
                            continue  // At free-weight cap, skip
                        }
                        
                        // 🆕 COMBO RULE AVOIDANCE
                        if let rule = comboRule {
                            let (shouldAvoid, _) = WorkoutComboRules.shouldAvoidExercise(name, comboRule: rule)
                            if shouldAvoid {
                                continue
                            }
                        }
                        
                        // 🆕 MUSCLE GROUP VALIDATION: Block wrong exercise types for this combo
                        let detectedPattern = WorkoutComboRules.detectExercisePattern(name, equipment: exercise.equipment ?? "")
                        
                        // Back+Biceps: NO presses or tricep work
                        if let rule = comboRule, rule.comboName == "Back + Biceps" {
                            if detectedPattern == "press" || detectedPattern == "chest_press" || detectedPattern == "incline_press" || 
                               detectedPattern == "decline_press" || detectedPattern == "shoulder_press" {
                                #if DEBUG
                                AppLogger.debug("[WRONG MUSCLE GROUP] Skipping '\(name)': press exercise in Back+Biceps workout", category: .workout)
                                #endif
                                continue
                            }
                            if detectedPattern == "tricep_pressdown" || detectedPattern == "tricep_overhead" || detectedPattern == "dip" {
                                #if DEBUG
                                AppLogger.debug("[WRONG MUSCLE GROUP] Skipping '\(name)': tricep exercise in Back+Biceps workout", category: .workout)
                                #endif
                                continue
                            }
                        }
                        
                        // Chest/Shoulders: NO back rows or bicep work (unless it's actually a Chest+Back combo)
                        if wantsChestAndShoulders && !normalizedTargetMuscles.contains("back") {
                            if detectedPattern == "horizontal_row" || detectedPattern == "vertical_pull" {
                                #if DEBUG
                                AppLogger.debug("[WRONG MUSCLE GROUP] Skipping '\(name)': back exercise in Chest/Shoulder workout", category: .workout)
                                #endif
                                continue
                            }
                        }
                        
                        // 🆕 OFF-TARGET ISOLATION: Block curls in chest/shoulder workouts (unless arms were requested)
                        let targetHasArms = normalizedTargetMuscles.contains("biceps") || normalizedTargetMuscles.contains("triceps")
                        if !targetHasArms && wantsChestAndShoulders {
                            if movementKeyword == "curl" || exerciseFamily == "bicep_curl" || exerciseFamily == "hammer_curl" || exerciseFamily == "preacher_curl" {
                                #if DEBUG
                                AppLogger.debug("[OFF-TARGET] Skipping '\(name)': bicep isolation in chest/shoulder workout", category: .workout)
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
                        usedMuscles[primaryMuscle] = (usedMuscles[primaryMuscle] ?? 0) + 1
                        usedNormalizedMuscles[normalizedMuscle] = (usedNormalizedMuscles[normalizedMuscle] ?? 0) + 1
                        usedEquipmentTypes[equipType] = (usedEquipmentTypes[equipType] ?? 0) + 1
                        usedExerciseFamilies[exerciseFamily] = (usedExerciseFamilies[exerciseFamily] ?? 0) + 1
                        recordBundleSelection(name)  // 📦 Track bundle usage
                        usedMovementKeywords[movementKeyword] = (usedMovementKeywords[movementKeyword] ?? 0) + 1
                        equipmentTypesRepresented.insert(equipType)
                        takenPerType[equipType] = currentCount + 1
                        addedThisRound = true
                        
                        // 🆕 Track equipment mix for targets
                        let selectedEquipType = ExerciseFilterService.normalizeEquipment(exercise.equipment).lowercased()
                        if ["cable", "machine", "smith", "lever"].contains(where: { selectedEquipType.contains($0) }) {
                            machineOrCableCount += 1
                        } else if ["barbell", "dumbbell"].contains(where: { selectedEquipType.contains($0) }) {
                            freeWeightCount += 1
                        }
                        
                        // 🆕 Track global press count
                        if movementKeyword == "press" {
                            totalPressCount += 1
                        }
                        
                        // 🆕 Track row count and supported status
                        if isRow {
                            rowCount += 1
                            let isSupported = ["chest supported", "chest-supported", "lying", "seated", "lever", "machine"].contains { nameLower.contains($0) }
                            if isSupported {
                                hasSupportedRow = true
                            }
                        }
                        
                        // 🆕 Track hinge count
                        if isHinge {
                            hingeCount += 1
                        }
                        
                        // 🆕 Track arm isolation counts
                        if isBicepIsolation {
                            bicepIsolationCount += 1
                        }
                        if isTricepIsolation {
                            tricepIsolationCount += 1
                        }
                        
                        // 🆕 Track forearm isolation count (uses isForearmIsolation from cap check above)
                        if isForearmIsolation {
                            forearmIsolationCount += 1
                        }
                        
                        // 🆕 Track calf exercise count
                        if isCalfExercise {
                            calfExerciseCount += 1
                        }
                        
                        // 🆕 Track shrug count
                        if isShrug {
                            shrugCount += 1
                        }
                        
                        // 🆕 Track vertical pull families
                        if isVerticalPull {
                            verticalPullCount += 1
                            let vpFamily: String = {
                                if nameLower.contains("chin up") || nameLower.contains("chin-up") { return "chin_up" }
                                if nameLower.contains("pull up") || nameLower.contains("pull-up") { return "pull_up" }
                                if nameLower.contains("straight arm") { return "straight_arm_pulldown" }
                                if nameLower.contains("pulldown") || nameLower.contains("pull down") { return "pulldown" }
                                return "other_vertical_pull"
                            }()
                            verticalPullFamilies.insert(vpFamily)
                        }
                        
                        // 🆕 Track pullover count
                        if isPullover {
                            pulloverCount += 1
                        }
                        
                        // 🆕 Track leg press count
                        if isLegPress {
                            legPressCount += 1
                        }
                        
                        // 🆕 Track vertical press count
                        if isVerticalPress {
                            verticalPressCount += 1
                        }
                        
                        // 🆕 Track triceps pattern count (for Chest+Triceps minimum)
                        if isTricepIsolation || nameLower.contains("tricep") || nameLower.contains("pushdown") || 
                           nameLower.contains("skull crusher") {
                            tricepsPatternCount += 1
                        }
                        
                        // 🆕 Track horizontal row count
                        if isHorizontalRow && !isTbarRow {
                            horizontalRowCount += 1
                        }
                        
                        // 🆕 Track T-bar row count
                        if isTbarRow {
                            tbarRowCount += 1
                        }
                        
                        // 🆕 Track hammer curl count
                        if isHammerCurl {
                            hammerCurlCount += 1
                        }
                        
                        // 🆕 Track preacher curl count
                        if isPreacherCurl {
                            preacherCurlCount += 1
                        }
                        
                        // 🆕 Track "other" pattern count
                        if isOtherPattern {
                            otherPatternCount += 1
                        }
                        
                        // 🆕 Track chest exercise count
                        let isChestExercise = primaryMuscle.contains("chest") || primaryMuscle.contains("pec") ||
                                             nameLower.contains("bench press") || nameLower.contains("chest press") ||
                                             (nameLower.contains("fly") && !nameLower.contains("reverse fly") && !nameLower.contains("rear"))
                        if isChestExercise {
                            chestExerciseCount += 1
                        }
                        
                        // 🆕 Track core exercise count
                        let isCoreExercise = primaryMuscle.contains("ab") || primaryMuscle.contains("core") ||
                                            primaryMuscle.contains("oblique") || nameLower.contains("plank") ||
                                            nameLower.contains("crunch") || nameLower.contains("pallof")
                        if isCoreExercise {
                            coreExerciseCount += 1
                        }
                        
                        // 🆕 Track glute exercise count
                        let isGluteExercise = primaryMuscle.contains("glute") || nameLower.contains("hip thrust") ||
                                             nameLower.contains("kickback") || nameLower.contains("glute bridge") ||
                                             nameLower.contains("pull through") || nameLower.contains("abduction")
                        if isGluteExercise {
                            gluteExerciseCount += 1
                        }
                        
                        // 🆕 Track back pattern count (row/pull/rear-delt)
                        let detectedPatternForBack = WorkoutComboRules.detectExercisePattern(name, equipment: exercise.equipment ?? "")
                        let backPatterns = ["horizontal_row", "chest_supported_row", "vertical_pull", "rear_delt", "lat_isolation", "shrug"]
                        if backPatterns.contains(detectedPatternForBack) {
                            backPatternCount += 1
                        }
                        
                        // 🆕 Track if this is a shoulder exercise
                        if normalizedMuscle == "shoulders" || exerciseFamily == "shoulder_press" || exerciseFamily == "lateral_raise" || exerciseFamily == "rear_delt" {
                            hasShoulderExercise = true
                        }
                        
                        // 🆕 Track balance slot
                        if let balance = balanceSlot {
                            if balance == "rear_delt" && (nameLower.contains("face pull") || nameLower.contains("rear delt") || nameLower.contains("reverse fly")) {
                                hasBalanceExercise = true
                            }
                            if balance == "core_stability" && (nameLower.contains("pallof") || nameLower.contains("dead bug") || nameLower.contains("plank")) {
                                hasBalanceExercise = true
                            }
                        }
                        
                        #if DEBUG
                        AppLogger.debug("[ROUND \(round)] \(equipType): \(name) (\(normalizedMuscle), family: \(exerciseFamily), move: \(movementKeyword)) - slot \(currentCount + 1)/\(slotsPerType)", category: .workout)
                        #endif
                        
                        break  // Move to next equipment type
                    }
                }
                
                round += 1
                // Safety: prevent infinite loop if no exercises available
                if !addedThisRound || round > count * 2 { break }
            }
            
            #if DEBUG
            AppLogger.info("[PHASE 1 COMPLETE] Reserved \(result.count) exercises across \(equipmentTypesRepresented.count) equipment types", category: .workout)
            for (equipType, cnt) in takenPerType.sorted(by: { $0.key < $1.key }) {
                AppLogger.debug("  \(equipType): \(cnt)", category: .workout)
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
                    
                    // 📦 BUNDLE CHECK - Chest press ≈ bench press = same bundle
                    if wouldExceedBundleLimit(name) { continue }
                    
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
                    recordBundleSelection(name)  // 📦 Track bundle usage
                    
                    // 🆕 Track global press count and shoulder exercises
                    if nameLower.contains("press") {
                        totalPressCount += 1
                    }
                    if normalizedMuscle == "shoulders" || exerciseFamily == "shoulder_press" || exerciseFamily == "lateral_raise" || exerciseFamily == "rear_delt" {
                        hasShoulderExercise = true
                    }
                    
                    #if DEBUG
                    AppLogger.debug("[MUSCLE DIVERSITY] Reserved slot for \(targetMuscle): \(name) (\(exerciseEquipType), family: \(exerciseFamily), base: \(baseMovement))", category: .workout)
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
                    AppLogger.debug("[MUSCLE BALANCE] Soft-skipping \(normalizedMuscle) (has \(normalizedMuscleCount)/\(maxPerMuscleGroup)), prefer: \(underrepresentedMuscles)", category: .workout)
                    #endif
                    continue
                }
            }
            
            // 🆕 EXERCISE FAMILY CHECK: Only 1 exercise per family (no 3 bench press variations!)
            let exerciseFamily = getExerciseFamily(nameLower)
            let familyCount = usedExerciseFamilies[exerciseFamily] ?? 0
            if exerciseFamily != "other" && familyCount >= 1 {
                #if DEBUG
                AppLogger.debug("[FAMILY] Skipping '\(name)': already have 1 from \(exerciseFamily) family", category: .workout)
                #endif
                continue
            }
            
            // 📦 BUNDLE CHECK - Bench press ≈ chest press ≈ smith press ≈ dips = same "horizontal_press" bundle
            // This is THE key check that prevents a chest workout from having 3 press variations
            if wouldExceedBundleLimit(name) {
                #if DEBUG
                if let bundle = bundleEngine.bundleForExercise(named: name) {
                    AppLogger.debug("[BUNDLE] Skipping '\(name)': \(bundle.displayName) bundle at max (\(usedExerciseBundles[bundle.id, default: 0])/\(bundle.maxPerWorkout))", category: .workout)
                }
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
                AppLogger.debug("[VARIETY] Skipping '\(name)': already have \(movementKeywordCount) \(movementKeyword) exercises", category: .workout)
                #endif
                continue
            }
            
            // 🆕 GLOBAL PRESS CAP: Max 2 total presses for multi-muscle workouts
            if globalPressCapEnabled && movementKeyword == "press" && totalPressCount >= maxGlobalPresses {
                #if DEBUG
                AppLogger.debug("[PRESS CAP] Skipping '\(name)': already have \(totalPressCount) presses (cap: \(maxGlobalPresses))", category: .workout)
                #endif
                continue
            }
            
            // 🆕 ROW CAP: Max 2 rows, prefer at least one supported
            let isRow = nameLower.contains(" row") || nameLower.hasPrefix("row")
            if isRow {
                if rowCount >= maxRows {
                    continue
                }
                let isSupported = ["chest supported", "chest-supported", "lying", "seated", "lever", "machine"].contains { nameLower.contains($0) }
                if rowCount == 1 && !hasSupportedRow && !isSupported {
                    continue
                }
            }
            
            // 🆕 HINGE CAP: Max 1 hinge per workout
            let isHinge = ["deadlift", "rdl", "romanian", "good morning", "back extension", "hyperextension"].contains { nameLower.contains($0) }
            if isHinge && hingeCount >= maxHinges {
                continue
            }
            
            // 🆕 ARM ISOLATION CAP
            let isBicepIsolation = exerciseFamily == "bicep_curl" || exerciseFamily == "hammer_curl" || exerciseFamily == "preacher_curl"
            let isTricepIsolation = exerciseFamily == "tricep_extension" || exerciseFamily == "tricep_pushdown" || nameLower.contains("skull crusher")
            
            if !isArmsDay {
                if isBicepIsolation && bicepIsolationCount >= maxArmIsolations {
                    continue
                }
                if isTricepIsolation && tricepIsolationCount >= maxArmIsolations {
                    continue
                }
            }
            
            // 🆕 COMBO RULE AVOIDANCE
            if let rule = comboRule {
                let (shouldAvoid, _) = WorkoutComboRules.shouldAvoidExercise(name, comboRule: rule)
                if shouldAvoid {
                    continue
                }
            }
            
            // 🆕 OFF-TARGET ISOLATION: Block curls in chest/shoulder workouts (unless arms were requested)
            let targetHasArms = normalizedTargetMuscles.contains("biceps") || normalizedTargetMuscles.contains("triceps")
            if !targetHasArms && wantsChestAndShoulders {
                if movementKeyword == "curl" || exerciseFamily == "bicep_curl" || exerciseFamily == "hammer_curl" || exerciseFamily == "preacher_curl" {
                    #if DEBUG
                    AppLogger.debug("[OFF-TARGET] Skipping '\(name)': bicep isolation in chest/shoulder workout", category: .workout)
                    #endif
                    continue
                }
            }
            
            // 🆕 DIVERSITY CHECK: Movement pattern from database
            if let pattern = exercise.movementPattern?.lowercased() {
                let patternCount = usedMovementPatterns[pattern] ?? 0
                if patternCount >= maxPerMovement { continue }
            }
            
            // 🎨 BODY POSITION VARIETY: Max 2 per position (avoid 4 lying exercises)
            if bodyPosition != "other" && positionCount >= 2 {
                #if DEBUG
                AppLogger.debug("[VARIETY] Skipping '\(name)': already have \(positionCount) \(bodyPosition) exercises", category: .workout)
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
                    AppLogger.debug("[BALANCE] Soft-skipping \(exerciseEquipType) (has \(equipTypeCount)/\(maxPerEquipType)), prefer: \(underrepresentedTypes)", category: .workout)
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
            recordBundleSelection(nameLower)  // 📦 Track exercise bundle
            if let pattern = exercise.movementPattern?.lowercased() {
                usedMovementPatterns[pattern] = (usedMovementPatterns[pattern] ?? 0) + 1
            }
            
            // 🆕 Track global press count and shoulder exercises
            if movementKeyword == "press" {
                totalPressCount += 1
            }
            
            // 🆕 Track row count and supported status
            if isRow {
                rowCount += 1
                let isSupported = ["chest supported", "chest-supported", "lying", "seated", "lever", "machine"].contains { nameLower.contains($0) }
                if isSupported {
                    hasSupportedRow = true
                }
            }
            
            // 🆕 Track hinge count
            if isHinge {
                hingeCount += 1
            }
            
            // 🆕 Track arm isolation counts
            if isBicepIsolation {
                bicepIsolationCount += 1
            }
            if isTricepIsolation {
                tricepIsolationCount += 1
            }
            
            if normalizedMuscle == "shoulders" || exerciseFamily == "shoulder_press" || exerciseFamily == "lateral_raise" || exerciseFamily == "rear_delt" {
                hasShoulderExercise = true
            }
            
            // 🆕 Track balance slot
            if let balance = balanceSlot {
                if balance == "rear_delt" && (nameLower.contains("face pull") || nameLower.contains("rear delt") || nameLower.contains("reverse fly")) {
                    hasBalanceExercise = true
                }
                if balance == "core_stability" && (nameLower.contains("pallof") || nameLower.contains("dead bug") || nameLower.contains("plank")) {
                    hasBalanceExercise = true
                }
            }
        }
        
        // 🆕 BALANCE SLOT ENFORCEMENT: Add a balance exercise if space allows
        if let balance = balanceSlot, !hasBalanceExercise, result.count < count {
            #if DEBUG
            AppLogger.debug("[BALANCE SLOT] Adding balance exercise: \(balance)", category: .workout)
            #endif
            
            for scored in scoredExercises {
                let exercise = scored.exercise
                let name = exercise.name ?? ""
                let nameLower = name.lowercased()
                
                if usedNames.contains(nameLower) { continue }
                
                var isBalanceMatch = false
                if balance == "rear_delt" && (nameLower.contains("face pull") || nameLower.contains("rear delt") || nameLower.contains("reverse fly")) {
                    isBalanceMatch = true
                }
                if balance == "core_stability" && (nameLower.contains("pallof") || nameLower.contains("dead bug")) {
                    isBalanceMatch = true
                }
                
                if isBalanceMatch {
                    let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                    let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
                    
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
                    hasBalanceExercise = true
                    
                    #if DEBUG
                    AppLogger.info("Added balance exercise: \(name)", category: .workout)
                    #endif
                    break
                }
            }
        }
        
        // 🆕 SHOULDER ENFORCEMENT: If user wanted shoulders but we didn't get any, force-add one
        if wantsShoulders && !hasShoulderExercise && result.count > 0 {
            #if DEBUG
            AppLogger.warning("[SHOULDER ENFORCEMENT] No shoulder exercises selected despite request! Attempting to swap...", category: .workout)
            #endif
            
            // Find a shoulder exercise to swap in
            for scored in scoredExercises {
                let exercise = scored.exercise
                let name = exercise.name ?? ""
                let nameLower = name.lowercased()
                let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                let primaryMuscle = muscleGroups.first?.lowercased() ?? ""
                let exerciseFamily = getExerciseFamily(nameLower)
                
                // Look for a shoulder exercise
                let isShoulderExercise = primaryMuscle.contains("delt") || primaryMuscle.contains("shoulder") ||
                                        exerciseFamily == "shoulder_press" || exerciseFamily == "lateral_raise" || exerciseFamily == "rear_delt"
                
                if isShoulderExercise && !usedNames.contains(nameLower) {
                    // Find the worst-fit exercise to replace (non-compound, non-chest)
                    if let replaceIndex = result.indices.reversed().first(where: { idx in
                        let ex = result[idx]
                        let exPrimary = ex.primaryMuscle.lowercased()
                        let exName = ex.name.lowercased()
                        // Replace isolation moves first, or anything that's not chest
                        return !isCompoundExercise(name: exName) || (!exPrimary.contains("chest") && !exPrimary.contains("pec"))
                    }) {
                        let secondaryMuscles = muscleGroups.count > 1 ? Array(muscleGroups.dropFirst()) : []
                        let generated = GeneratedExercise(
                            id: exercise.id?.uuidString ?? UUID().uuidString,
                            name: name,
                            category: exercise.category ?? "Unknown",
                            primaryBodyRegion: exercise.category ?? "Unknown",
                            primaryMuscle: muscleGroups.first ?? "Shoulders",
                            secondaryMuscles: secondaryMuscles,
                            equipment: exercise.equipment ?? "Bodyweight",
                            difficulty: "Intermediate",
                            videoUrl: nil,
                            instructions: exercise.instructions
                        )
                        
                        #if DEBUG
                        AppLogger.info("[SHOULDER ENFORCEMENT] Replacing '\(result[replaceIndex].name)' with '\(name)'", category: .workout)
                        #endif
                        result[replaceIndex] = generated
                        hasShoulderExercise = true
                        break
                    }
                }
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
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🔍 FINAL VALIDATION: Check all required patterns are present
        // ═══════════════════════════════════════════════════════════════════════════
        if let rule = comboRule, !rule.mustInclude.isEmpty {
            let selectedExerciseData = result.map { (name: $0.name ?? "", equipment: $0.equipment ?? "") }
            let missingPatterns = WorkoutComboRules.validateRequiredPatterns(selectedExercises: selectedExerciseData, comboRule: rule)
            
            if !missingPatterns.isEmpty {
                AppLogger.warning("[VALIDATION] Missing patterns: \(missingPatterns) — returning workout anyway (non-blocking)", category: .workout)
            } else {
                #if DEBUG
                AppLogger.info("[VALIDATION PASSED] All required patterns satisfied", category: .workout)
                #endif
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🆕 PRIMARY MUSCLE MINIMUM VALIDATION - Ensure selected muscles are represented
        // ═══════════════════════════════════════════════════════════════════════════
        #if DEBUG
        if wantsChest && chestExerciseCount < minChestExercises {
            AppLogger.warning("[MUSCLE MIN] Chest selected but only \(chestExerciseCount)/\(minChestExercises) chest exercises", category: .workout)
        }
        if wantsCore && coreExerciseCount < minCoreExercises {
            AppLogger.warning("[MUSCLE MIN] Core selected but only \(coreExerciseCount)/\(minCoreExercises) core exercises", category: .workout)
        }
        if wantsGlutes && gluteExerciseCount < minGluteExercises {
            AppLogger.warning("[MUSCLE MIN] Glutes selected but only \(gluteExerciseCount)/\(minGluteExercises) glute exercises", category: .workout)
        }
        #endif
        
        // Log tracking stats
        #if DEBUG
        AppLogger.debug("[CAPS] Calf: \(calfExerciseCount)/\(maxCalfExercises), Shrug: \(shrugCount)/\(maxShrugExercises), Forearm: \(forearmIsolationCount)/\(maxForearmIsolations)", category: .workout)
        AppLogger.debug("[MUSCLE] Chest: \(chestExerciseCount)/\(minChestExercises), Core: \(coreExerciseCount)/\(minCoreExercises), Glute: \(gluteExerciseCount)/\(minGluteExercises)", category: .workout)
        AppLogger.debug("[VERTICAL PULLS] Count: \(verticalPullCount), Families: \(verticalPullFamilies)", category: .workout)
        #endif
        
        AppLogger.info("[SMART GEN] Final workout (\(result.count) exercises):", category: .workout)
        AppLogger.debug("Gender: \(finalGenderMatchCount) matching, \(finalGenderFallbackCount) fallback", category: .workout)
        AppLogger.debug("Diversity: Positions \(usedBodyPositions.count), Movements \(usedMovementKeywords.count), Families \(usedExerciseFamilies.count), Base movements: \(usedBaseMovements.count)", category: .workout)
        AppLogger.debug("Equipment mix: \(usedEquipmentTypes.map { "\($0.key): \($0.value)" }.joined(separator: ", "))", category: .workout)
        AppLogger.debug("Equipment targets: Machine/Cable: \(machineOrCableCount)/\(targetMachineOrCable) | Free-weight: \(freeWeightCount)/\(targetFreeWeight) (max: \(maxFreeWeight))", category: .workout)
        AppLogger.debug("Muscle mix: \(usedNormalizedMuscles.map { "\($0.key): \($0.value)" }.joined(separator: ", "))", category: .workout)
        AppLogger.debug("Exercise families: \(usedExerciseFamilies.filter { $0.key != "other" }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))", category: .workout)
        for (idx, ex) in result.enumerated() {
            let isFav = favorites.contains(ex.name.lowercased()) ? "⭐" : ""
            AppLogger.debug("  \(idx + 1). \(isFav) \(ex.name) - \(ex.category) - \(ex.equipment)", category: .workout)
        }
        #endif
        
        // 🎯 SMART EXERCISE ORDERING
        // Strategy: Compound first → Isolation last, grouped by equipment for efficiency
        let sortedResult = sortExercisesStrategically(result)
        
        #if DEBUG
        AppLogger.debug("FINAL ORDER (after smart sorting):", category: .workout)
        for (idx, ex) in sortedResult.enumerated() {
            AppLogger.debug("  \(idx + 1). \(ex.name) - \(ex.equipment)", category: .workout)
        }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🔍 FINAL VALIDATION: Verify all combo rule requirements are met
        // ═══════════════════════════════════════════════════════════════════════════
        if let rule = comboRule {
            let exerciseList = sortedResult.map { (name: $0.name, equipment: $0.equipment) }
            let missing = WorkoutComboRules.getMissingRequirements(rule, exercises: exerciseList)
            
            if !missing.isEmpty {
                AppLogger.warning("[VALIDATION WARNING] Workout missing required patterns: \(missing)", category: .workout)
                AppLogger.warning("This workout may not meet user expectations!", category: .workout)
            } else {
                AppLogger.info("[VALIDATION PASSED] All required patterns satisfied", category: .workout)
            }
        }
        #endif
        
        // 📦 Record selected exercises to cooldown tracker for cross-session variety
        // Next time user generates a workout, these exercises will be penalized
        // to encourage fresh movement and equipment variations
        let completedNames = sortedResult.map { $0.name }
        ExerciseCooldownTracker.shared.recordWorkoutExercises(completedNames)
        
        return sortedResult
    }
    
    // MARK: - Smart Exercise Ordering
    
    /// Strategically orders exercises for optimal workout flow
    /// Priority: 1) Compound movements first (need most energy)
    ///           2) Isolation movements after
    ///           3) Spread similar exercises apart (no two dips back-to-back)
    ///           4) Core/abs at the very end
    nonisolated private func sortExercisesStrategically(_ exercises: [GeneratedExercise]) -> [GeneratedExercise] {
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
                    guard let lastExercise = result.last else { break }
                    let lastCategory = getMovementCategory(lastExercise)
                    
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
        AppLogger.debug("[SMART ORDER] Compounds: \(spacedCompounds.count), Isolations: \(spacedIsolations.count), Core: \(coreExercises.count)", category: .workout)
        #endif
        
        return finalOrder
    }
    
    // MARK: - Helper Functions
    
    /// Normalize muscle name to a standard group for diversity tracking
    nonisolated private func normalizeMuscleName(_ muscle: String) -> String {
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
    nonisolated private func getEquipmentType(_ equipment: String) -> String {
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
    
    nonisolated private func isCompoundExercise(name: String) -> Bool {
        let compoundKeywords = ["squat", "deadlift", "press", "bench", "row", "pull-up", "pullup", 
                                "chin-up", "chinup", "lunge", "dip", "clean", "snatch", "thruster"]
        return compoundKeywords.contains { name.contains($0) }
    }
    
    nonisolated private func estimateExerciseDifficulty(name: String) -> Int {
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
