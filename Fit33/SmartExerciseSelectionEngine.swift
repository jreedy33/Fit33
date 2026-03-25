//
//  SmartExerciseSelectionEngine.swift
//  GoFit
//
//  Intelligent exercise selection engine that:
//  1. Learns from user workout history and preferences
//  2. Enforces smart movement pattern variety (no 3 bench presses!)
//  3. Mixes compound + isolation exercises intelligently
//  4. Rotates equipment for variety
//  5. Applies to both Programs AND Auto-Gen workouts
//
//  Based on proven training principles:
//  - Push Day: 1-2 pressing compounds + 1 fly/isolation + 1 shoulder + 1 tricep
//  - Pull Day: 1-2 rowing compounds + 1 pulldown + 1 isolation + 1 bicep
//  - Leg Day: 1-2 squat/lunge compounds + 1 hinge + 1 isolation + 1 calf/glute
//

import Foundation
import CoreData

// MARK: - Selection Movement Pattern Definitions

enum SelectionMovementPattern: String, CaseIterable {
    case horizontalPress = "horizontal_press"    // Bench press, push-ups
    case verticalPress = "vertical_press"        // Overhead press, push press
    case horizontalPull = "horizontal_pull"      // Rows
    case verticalPull = "vertical_pull"          // Pull-ups, pulldowns
    case chestFly = "chest_fly"                  // Flyes, cable crossovers
    case lateralRaise = "lateral_raise"          // Side raises, front raises
    case rearDelt = "rear_delt"                  // Rear delt flys, face pulls
    case squat = "squat"                         // Squats, hack squats
    case legPress = "leg_press"                  // Leg press variations
    case hinge = "hinge"                         // Deadlifts, RDL, good mornings
    case hipThrust = "hip_thrust"                // Hip thrusts, glute bridges
    case lunge = "lunge"                         // Lunges, split squats
    case legExtension = "leg_extension"          // Leg extensions (quad isolation)
    case legCurl = "leg_curl"                    // Leg curls (hamstring knee-flexion)
    case calfRaise = "calf_raise"                // Calf raises
    case bicepCurl = "bicep_curl"                // Bicep curls
    case tricepExtension = "tricep_extension"    // Tricep pushdowns, extensions
    case shrug = "shrug"                         // Shrugs
    case coreFlexion = "core_flexion"            // Crunches, sit-ups
    case coreStability = "core_stability"        // Planks, dead bugs
    case coreRotation = "core_rotation"          // Woodchops, Russian twists
    case other = "other"
    
    var maxPerWorkout: Int {
        switch self {
        case .horizontalPress, .verticalPress:
            return 2  // Max 2 pressing movements
        case .horizontalPull, .verticalPull:
            return 1  // Limit to 1 each to ensure variety (1 row + 1 pulldown)
        case .squat, .legPress:
            return 1  // Max 1 each for quad compounds
        case .hinge, .lunge:
            return 1  // Max 1 each for posterior chain
        case .hipThrust:
            return 1  // Limit hip thrust variations
        case .chestFly, .lateralRaise, .rearDelt:
            return 1  // Isolation - max 1 each
        case .legExtension, .legCurl, .calfRaise:
            return 1  // Leg isolation - max 1 each
        case .bicepCurl, .tricepExtension:
            return 1  // Arm isolation - max 1 each
        case .shrug:
            return 1
        case .coreFlexion, .coreStability, .coreRotation:
            return 2
        case .other:
            return 2
        }
    }
    
    /// Whether this is an "anchor" pattern that should stay consistent across program weeks
    var isAnchorPattern: Bool {
        switch self {
        case .horizontalPress, .horizontalPull, .verticalPull, .squat, .legPress, .hinge:
            return true
        default:
            return false
        }
    }
}

// MARK: - Exercise Type Classification

enum ExerciseType: String {
    case compound = "compound"      // Multi-joint (bench, squat, row)
    case isolation = "isolation"    // Single-joint (curl, fly, raise)
    case cardio = "cardio"
    case plyometric = "plyometric"
    case stretch = "stretch"
}

// MARK: - Workout Style Variations

enum WorkoutStyle: String, CaseIterable {
    case straight = "straight"           // Standard sets
    case superset = "superset"           // Paired exercises
    case dropSet = "drop_set"            // Decreasing weight
    case pyramid = "pyramid"             // Increasing/decreasing reps
    case cluster = "cluster"             // Rest-pause sets
    case circuit = "circuit"             // Minimal rest rotation
    
    var description: String {
        switch self {
        case .straight: return "Standard Sets"
        case .superset: return "Superset Pairs"
        case .dropSet: return "Drop Sets"
        case .pyramid: return "Pyramid Sets"
        case .cluster: return "Cluster Sets"
        case .circuit: return "Circuit Training"
        }
    }
}

// MARK: - Selected Exercise Model

struct SmartSelectedExercise {
    let exercise: Exercise
    let score: Double
    let movementPattern: SelectionMovementPattern
    let exerciseType: ExerciseType
    
    var name: String { exercise.name ?? "Unknown" }
    var equipment: String { exercise.equipment ?? "Bodyweight" }
    var muscles: [String] { exercise.getMuscleGroups() ?? [] }
}

// MARK: - Smart Exercise Selection Engine

class SmartExerciseSelectionEngine {
    static let shared = SmartExerciseSelectionEngine()
    
    private init() {}
    
    // MARK: - Equipment Normalization
    
    /// Normalizes equipment names between user selection and database values
    /// User selects: "Machines", "Cables", "Barbell", "Dumbbells"
    /// Database has: "Lever Machine", "Cable Machine", "Chest Press Machine", etc.
    private func normalizeEquipmentForMatching(_ equipment: String) -> [String] {
        return ExerciseFilterService.normalizeEquipmentForMatching(equipment)
    }
    
    /// Check if exercise equipment matches any of the user's available equipment
    private func doesEquipmentMatch(exerciseEquipment: String, userEquipment: [String]) -> Bool {
        let exerciseEquipLower = exerciseEquipment.lowercased()
        
        // Handle empty/bodyweight
        if exerciseEquipLower.isEmpty || exerciseEquipLower == "bodyweight" {
            return userEquipment.contains { $0.lowercased().contains("bodyweight") || $0.lowercased().contains("body weight") }
        }
        
        // Parse exercise equipment parts (e.g., "Cable Machine, Flat Bench")
        let exerciseParts = exerciseEquipLower
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Common gym items that are always available
        let commonItems = ["floor", "mat", "wall", "flat bench", "bench", "incline bench", "decline bench", "preacher bench"]
        
        // For each user equipment, get normalized patterns
        for userEquip in userEquipment {
            let patterns = normalizeEquipmentForMatching(userEquip)
            
            // Check if any pattern matches any part of exercise equipment
            for pattern in patterns {
                // Direct match
                if exerciseEquipLower.contains(pattern) {
                    return true
                }
                
                // Check each exercise equipment part (only forward match to avoid false positives)
                for part in exerciseParts {
                    if part.contains(pattern) {
                        return true
                    }
                }
            }
        }
        
        // Check if exercise only requires common items (benches, floor, wall)
        let nonCommonParts = exerciseParts.filter { part in
            !commonItems.contains(where: { part.contains($0) })
        }
        
        // If all parts are common items, check if user has the base equipment
        if nonCommonParts.isEmpty {
            return true
        }
        
        return false
    }
    
    // MARK: - Main Selection Function
    
    /// Selects exercises for a workout day using intelligent algorithms
    /// - Parameters:
    ///   - targetMuscles: Primary muscles to target
    ///   - exerciseCount: Number of exercises needed
    ///   - userEquipment: Equipment user has access to
    ///   - isGymUser: Whether user works out at a gym
    ///   - previousDayExercises: Exercises from previous days (for variety)
    ///   - userGoal: User's fitness goal
    ///   - experienceLevel: User's experience level
    /// - Returns: Array of selected exercises with smart pairing
    func selectExercisesForWorkout(
        targetMuscles: [String],
        exerciseCount: Int,
        userEquipment: [String],
        isGymUser: Bool,
        previousDayExercises: Set<String>,
        userGoal: String,
        experienceLevel: String
    ) -> [SmartSelectedExercise] {
        
        // ═══════════════════════════════════════════════════════════════════════════
        // EQUIPMENT DIVERSITY LIMITS
        // For foundational users: allow MORE repetition (focus on progression, not variety)
        // For experienced users: enforce diversity
        // ═══════════════════════════════════════════════════════════════════════════
        
        // Get progressive unlock status (from thread-safe cache)
        let progressiveCache = ProgressiveUnlockCache.shared
        let userWorkoutCount = progressiveCache.workoutCount
        let currentTier = progressiveCache.currentTier
        let restrictToFoundational = progressiveCache.shouldRestrictToFoundational
        let varietyPercentage = progressiveCache.varietyPercentage
        
        // 🔧 FIX: Relax equipment diversity for foundational users
        // Foundational = prioritize progression + safety, NOT variety
        let maxPerEquipmentType: Int
        if restrictToFoundational || userWorkoutCount < 10 {
            maxPerEquipmentType = max(3, exerciseCount / 2 + 1)  // Allow 3 per equipment type for foundational
        } else {
            maxPerEquipmentType = max(2, exerciseCount / 2)  // Standard diversity for experienced users
        }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // CHECK FOR LOWER BACK LIMITATION
        // ═══════════════════════════════════════════════════════════════════════════
        let hasLowerBackIssue = LimitationsService.shared.hasLowerBackLimitation
        
        AppLogger.debug("SMART EXERCISE SELECTION — Muscles: \(targetMuscles.joined(separator: ", ")), Count: \(exerciseCount), Gym: \(isGymUser), Equipment: \(userEquipment.joined(separator: ", ")), Goal: \(userGoal), Level: \(experienceLevel), PrevDay: \(previousDayExercises.count), MaxPerEquip: \(maxPerEquipmentType)", category: .workout)
        AppLogger.debug("PROGRESSIVE UNLOCK — Workouts: \(userWorkoutCount), Tier: \(currentTier.displayName), Foundational: \(restrictToFoundational), Variety: \(Int(varietyPercentage * 100))%", category: .workout)
        
        // Get all exercises from library
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        // ═══════════════════════════════════════════════════════════════════════════
        // SAFETY FILTER: Remove exercises that could aggravate user's limitations
        // ═══════════════════════════════════════════════════════════════════════════
        let safeExercises = LimitationsService.shared.filterSafeExercises(allExercises)
        let filteredOutCount = allExercises.count - safeExercises.count
        AppLogger.debug("LIMITATION FILTERING — Available: \(allExercises.count), Safe: \(safeExercises.count), Filtered: \(filteredOutCount), Active limitations: \(LimitationsService.shared.hasActiveLimitationsSync)", category: .workout)
        
        // Get user behavior learning data
        let learningEngine = UserBehaviorLearningEngine.shared
        
        // Score all exercises
        var scoredExercises: [(exercise: Exercise, score: Double, pattern: SelectionMovementPattern, type: ExerciseType)] = []
        
        for exercise in safeExercises {
            guard let exerciseName = exercise.name else { continue }
            
            let nameLower = exerciseName.lowercased()
            let exerciseMuscles = (exercise.getMuscleGroups() ?? []).joined(separator: ",").lowercased()
            let category = (exercise.category ?? "").lowercased()
            let equipment = (exercise.equipment ?? "Bodyweight").lowercased()
            let workoutType = (exercise.workoutType ?? "").lowercased()
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 1: Must match target muscles
            // ═══════════════════════════════════════════════════════════════
            let muscleMatch = targetMuscles.contains { muscle in
                let muscleLower = muscle.lowercased()
                return exerciseMuscles.contains(muscleLower) ||
                       category.contains(muscleLower) ||
                       matchBroadMuscleGroup(muscleLower, exerciseMuscles: exerciseMuscles, category: category)
            }
            guard muscleMatch else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 2: Must match user equipment - ALL required equipment must be available!
            // 🔥 CRITICAL FIX: Gym users should NOT get random bodyweight floor exercises
            // ═══════════════════════════════════════════════════════════════
            let equipmentMatch: Bool
            let userEquipmentNormalized = Set(userEquipment.map { $0.lowercased() })
            let isBodyweightExercise = equipment.isEmpty || equipment == "bodyweight"
            
            // GYM USER BODYWEIGHT FILTER
            // Gym users primarily want machines, barbells, cables, dumbbells.
            // Gym-appropriate bodyweight (pull-ups, dips) always allowed.
            // Floor bodyweight deprioritized via score penalty, available for fat loss / circuits.
            var gymBodyweightPenalty = false
            if isGymUser && isBodyweightExercise {
                let hardExcludeFloor = [
                    "floor", "lying", "prone", "supine", "ground",
                    "dead bug", "bird dog", "superman",
                    "sit-up", "sit up", "bicycle",
                    "bear crawl", "inchworm",
                    "glute bridge", "hip thrust on floor", "hip raise",
                    "fire hydrant", "donkey kick", "clam", "flutter kick"
                ]
                
                let contextualBodyweight = [
                    "push-up", "pushup", "push up", "pike push",
                    "plank", "crunches", "crunch",
                    "mountain climber", "burpee", "renegade", "leg raise"
                ]
                
                let gymAppropriateBodyweight = [
                    "pull-up", "pullup", "chin-up", "chinup",
                    "dip", "hanging", "muscle up", "muscle-up", "inverted row"
                ]
                
                let isFloorExercise = hardExcludeFloor.contains { nameLower.contains($0) }
                let isContextual = contextualBodyweight.contains { nameLower.contains($0) }
                let isGymAppropriate = gymAppropriateBodyweight.contains { nameLower.contains($0) }
                
                if isFloorExercise && !isContextual {
                    equipmentMatch = false
                } else if isGymAppropriate && !nameLower.contains("floor") {
                    equipmentMatch = true
                } else if isContextual {
                    equipmentMatch = true
                    gymBodyweightPenalty = true
                } else if !isGymAppropriate {
                    equipmentMatch = false
                } else {
                    equipmentMatch = true
                }
            } else if userEquipment.isEmpty {
                // No equipment specified = allow everything
                equipmentMatch = true
            } else if isBodyweightExercise {
                // 🏠 HOME/NON-GYM USER: Only include bodyweight if explicitly selected
                equipmentMatch = userEquipmentNormalized.contains { 
                    $0.contains("bodyweight") || $0.contains("body weight")
                }
                if !equipmentMatch {
                    AppLogger.debug("Excluding '\(exerciseName)': bodyweight not in user equipment", category: .workout)
                }
            } else {
                // 🛡️ SAFETY CHECK: Check exercise NAME for equipment keywords
                // This catches exercises like "Banded Bench Press" where name indicates bands but equipment field doesn't
                
                // Check for band-related keywords in name
                let bandKeywords = ["banded", "band", "resistance band", "(band)"]
                let nameIndicatesBands = bandKeywords.contains { nameLower.contains($0) }
                let userHasBands = userEquipmentNormalized.contains { $0.contains("band") || $0.contains("resistance") }
                
                if nameIndicatesBands && !userHasBands {
                    AppLogger.debug("Excluding '\(exerciseName)': name indicates bands but user doesn't have bands", category: .workout)
                    equipmentMatch = false
                } else {
                    // 🔧 Use smart equipment matching that handles database format
                    // Database uses: "Lever Machine", "Cable Machine", "Chest Press Machine"
                    // User selects: "Machines", "Cables", "Barbell"
                    equipmentMatch = doesEquipmentMatch(exerciseEquipment: equipment, userEquipment: userEquipment)
                    
                    // Log equipment exclusions for debugging
                    if !equipmentMatch {
                        AppLogger.debug("Excluding '\(exerciseName)': requires '\(equipment)' but user has \(userEquipment)", category: .workout)
                    }
                }
            }
            guard equipmentMatch else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 3: Exclude stretching from main workouts
            // ═══════════════════════════════════════════════════════════════
            let isStretch = workoutType.contains("stretch") || nameLower.contains("stretch")
            guard !isStretch else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 3.5: 🚫 PRE-FILTER RISKY EXERCISES FOR FOUNDATIONAL USERS
            // Block complex/dangerous exercises before they even get scored
            // ═══════════════════════════════════════════════════════════════
            if restrictToFoundational || userWorkoutCount < 10 {
                let foundationalDB = FoundationalExerciseDatabase.shared
                if foundationalDB.isRiskyExercise(nameLower) {
                    AppLogger.debug("Excluding '\(exerciseName)' - risky exercise blocked for foundational user", category: .workout)
                    continue
                }
            }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 3.6: 🚫 PRE-FILTER LOWER BACK STRESS EXERCISES
            // If user has lower back limitation, block stressful exercises
            // ═══════════════════════════════════════════════════════════════
            if hasLowerBackIssue {
                let foundationalDB = FoundationalExerciseDatabase.shared
                if foundationalDB.isLowerBackStressExercise(nameLower) {
                    AppLogger.debug("Excluding '\(exerciseName)' - lower back stress exercise blocked for user with back limitation", category: .workout)
                    continue
                }
            }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 4: PRACTICALITY FILTER - Use database score if available
            // ═══════════════════════════════════════════════════════════════
            let dbPracticalityScore = Int(exercise.practicalityScore)  // From database (0-100)
            let hasDatabaseScore = dbPracticalityScore > 0
            
            // Use database score if available, otherwise calculate
            let practicalityResult: PracticalityResult
            if hasDatabaseScore {
                // Database-driven filtering (much more accurate!)
                let shouldExclude = dbPracticalityScore < 30  // Exclude scores below 30
                let scoreModifier = Double(dbPracticalityScore - 50) * 0.8  // Center at 50, scale to ±40
                practicalityResult = PracticalityResult(
                    shouldExclude: shouldExclude,
                    scoreModifier: scoreModifier,
                    reason: "DB Score: \(dbPracticalityScore)"
                )
            } else {
                // Fallback to calculated assessment
                practicalityResult = assessExercisePracticality(
                    exerciseName: nameLower,
                    experienceLevel: experienceLevel,
                    isGymUser: isGymUser
                )
            }
            
            if practicalityResult.shouldExclude {
                AppLogger.debug("Excluding '\(exerciseName)': \(practicalityResult.reason)", category: .workout)
                continue
            }
            
            // ═══════════════════════════════════════════════════════════════
            // Classify exercise
            // ═══════════════════════════════════════════════════════════════
            let pattern = classifyMovementPattern(exerciseName: nameLower, muscles: exerciseMuscles)
            let exerciseType = classifyExerciseType(exerciseName: nameLower, workoutType: workoutType)
            
            // ═══════════════════════════════════════════════════════════════
            // SCORING
            // ═══════════════════════════════════════════════════════════════
            var score: Double = 100.0
            
            if gymBodyweightPenalty {
                score -= 80
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ 🌟 FOUNDATIONAL EXERCISE BOOST (For New Users)              │
            // │ Prioritizes well-known, common exercises for beginners      │
            // │ Prevents weird exercises like "Behind Back Tricep Extension"│
            // └─────────────────────────────────────────────────────────────┘
            let foundationalBoost = FoundationalExerciseDatabase.shared.getFoundationalBoostScore(
                exerciseName: exerciseName,
                userWorkoutCount: userWorkoutCount,
                experienceLevel: experienceLevel
            )
            score += foundationalBoost
            
            // Check if user should be restricted to foundational exercises only
            if restrictToFoundational && foundationalBoost < 0 {
                // New user + non-foundational exercise = heavy penalty (but don't always skip)
                AppLogger.debug("Heavy penalty for '\(exerciseName)': non-foundational for new user", category: .workout)
                score -= 200  // Heavy penalty instead of hard skip to allow some flexibility
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ 🚫 RISKY EXERCISE PENALTY (For exercises that passed filter)│
            // │ Even if not pre-filtered, risky exercises get heavy penalty │
            // └─────────────────────────────────────────────────────────────┘
            let foundationalDB = FoundationalExerciseDatabase.shared
            let riskyPenalty = foundationalDB.getRiskyExercisePenalty(
                exerciseName: nameLower,
                userWorkoutCount: userWorkoutCount,
                restrictToFoundational: restrictToFoundational,
                hasLowerBackIssue: hasLowerBackIssue
            )
            if riskyPenalty != 0 {
                score += riskyPenalty
                if riskyPenalty < -100 {
                    AppLogger.warning("'\(exerciseName)' safety penalty: \(Int(riskyPenalty))", category: .workout)
                }
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ ✅ LOWER BACK SAFE ALTERNATIVE BOOST                        │
            // │ If user has back issues, boost chest-supported/machine rows │
            // └─────────────────────────────────────────────────────────────┘
            if hasLowerBackIssue && foundationalDB.isLowerBackSafeAlternative(nameLower) {
                score += 100
                AppLogger.debug("'\(exerciseName)' boosted +100 (safe for lower back)", category: .workout)
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ USER PREFERENCE LEARNING BOOST (Individual)                 │
            // └─────────────────────────────────────────────────────────────┘
            let learnedBoost = learningEngine.calculateLearnedBoostScore(
                exerciseName: exerciseName,
                equipment: equipment,
                muscleGroups: exercise.getMuscleGroups() ?? [],
                category: category
            )
            score += learnedBoost
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ COLLABORATIVE BOOST (What works for similar users)          │
            // └─────────────────────────────────────────────────────────────┘
            // Note: This is async but we cache it, so we check the cache synchronously
            if let globalTrends = CollaborativeLearningEngine.shared.globalTrendsCache {
                // Boost popular exercises among all users
                if let popularity = globalTrends.exercisePopularity[nameLower] {
                    score += popularity * 15  // Up to +15 for very popular exercises
                }
                
                // Boost exercises with high success rates
                if let successRate = globalTrends.exerciseSuccessRates[nameLower] {
                    score += successRate * 10  // Up to +10 for high success exercises
                }
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ GYM USER EQUIPMENT PRIORITIZATION                           │
            // └─────────────────────────────────────────────────────────────┘
            if isGymUser {
                score += scoreGymEquipmentPriority(equipment: equipment, exerciseName: nameLower)
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ GENDER VIDEO MATCH SCORING                                  │
            // │ Prefer exercises with videos matching user's gender          │
            // └─────────────────────────────────────────────────────────────┘
            let genderVideoCache = VideoStreamingService.shared.genderVideoCache
            if let genderInfo = genderVideoCache[exerciseName] ?? genderVideoCache[nameLower] {
                let userGender = UserManager.shared.currentUser?.gender?.lowercased() ?? "male"
                let preferredGender: VideoStreamingService.VideoGender = userGender.contains("female") ? .female : .male
                if genderInfo.filename(for: preferredGender) != nil {
                    score += 150
                } else if genderInfo.filenameWithFallback(preferred: preferredGender) != nil {
                    score -= 100
                }
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ VARIETY SCORING - Critical for fresh workouts!              │
            // │ Uses ExerciseCooldownTracker for 7-14 day anti-repeat       │
            // └─────────────────────────────────────────────────────────────┘
            if previousDayExercises.contains(nameLower) {
                score -= 60  // Heavy penalty for exact same exercise in recent days
            }
            
            // 📦 COOLDOWN CHECK - Penalize exercises done recently (within cooldown window)
            let cooldownTracker = ExerciseCooldownTracker.shared
            if let daysSince = cooldownTracker.daysSinceLastDone(exerciseName) {
                let cooldownDays = ExerciseBundleEngine.shared.cooldownDays(for: exerciseName)
                if daysSince < cooldownDays {
                    let cooldownPenalty = Double(cooldownDays - daysSince) * 20  // Stronger penalty the more recent
                    score -= cooldownPenalty
                }
            }
            
            // 📦 BUNDLE VARIETY - Penalize if same bundle was used in previous days
            if let exerciseBundle = ExerciseBundleEngine.shared.bundleForExercise(named: exerciseName) {
                let previousInBundle = previousDayExercises.filter { prev in
                    ExerciseBundleEngine.shared.bundleForExercise(named: prev)?.id == exerciseBundle.id
                }.count
                if previousInBundle > 0 {
                    score -= Double(previousInBundle) * 25
                }
            }
            
            // Penalize similar exercises (same movement pattern keyword)
            let similarPatterns = ["bench", "squat", "deadlift", "row", "press", "curl", "fly", "raise", "pulldown", "extension", "lunge"]
            for pattern in similarPatterns {
                if nameLower.contains(pattern) {
                    let similarCount = previousDayExercises.filter { $0.contains(pattern) }.count
                    if similarCount > 0 {
                        score -= Double(similarCount) * 15  // Penalize for each similar exercise done recently
                    }
                    break
                }
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ BEGINNER COMPLEXITY PENALTY                                 │
            // │ Combo moves, complex plank variations are too hard for      │
            // │ beginners - they should focus on simple, foundational moves │
            // └─────────────────────────────────────────────────────────────┘
            if experienceLevel.lowercased() == "beginner" {
                // COMBO EXERCISES: "Biceps Curl Squat", "Rear Lunge Biceps Curl", etc.
                // These combine two movements and are too complex for beginners
                let comboPatterns = [
                    "curl squat", "squat curl", "lunge curl", "curl lunge",
                    "biceps curl", // when combined with lunges
                    "press squat", "squat press", "lunge press", "press lunge",
                    "row lunge", "lunge row", "deadlift to", "to row", "to curl",
                    "to press", "and curl", "and press", "and row", "renegade"
                ]
                // Also check for "lunge" + "curl" combo (like "Rear Lunge Biceps Curl")
                let isLungeCurlCombo = nameLower.contains("lunge") && nameLower.contains("curl")
                let isLungePressCombo = nameLower.contains("lunge") && nameLower.contains("press")
                
                if comboPatterns.contains(where: { nameLower.contains($0) }) || isLungeCurlCombo || isLungePressCombo {
                    score -= 200  // VERY heavy penalty - exclude combo moves for beginners
                    AppLogger.debug("Penalizing combo exercise for beginner: \(exerciseName)", category: .workout)
                }
                
                // COMPLEX PLANK VARIATIONS: Plank with dumbbells, rows, raises
                // These require too much shoulder stability for beginners
                let complexPlankPatterns = [
                    "plank row", "plank raise", "plank lateral", "plank front",
                    "plank with", "renegade", "commandos", "plank arm"
                ]
                // Also check for "plank" combined with other movements
                let isPlankCombo = nameLower.contains("plank") && 
                    (nameLower.contains("raise") || nameLower.contains("row") || 
                     nameLower.contains("lateral") || nameLower.contains("dumbbell"))
                
                if complexPlankPatterns.contains(where: { nameLower.contains($0) }) || isPlankCombo {
                    score -= 200  // VERY heavy penalty for complex plank variations
                    AppLogger.debug("Penalizing complex plank for beginner: \(exerciseName)", category: .workout)
                }
                
                // TWISTING/ROTATING - too much coordination for beginners
                let complexMovementPatterns = [
                    "twisting", "rotating", "alternating", "switching", 
                    "curtsey", "curtsy", "change"  // "Change Lateral Raise Curtsey Lunge"
                ]
                if complexMovementPatterns.contains(where: { nameLower.contains($0) }) {
                    score -= 150  // Heavy penalty for coordination-heavy movements
                    AppLogger.debug("Penalizing complex movement for beginner: \(exerciseName)", category: .workout)
                }
                
                // OVERLY COMPLEX NAMES (usually indicate complex movements)
                let wordCount = exerciseName.split(separator: " ").count
                if wordCount > 7 {
                    score -= 30  // Exercises with very long names are often complex
                }
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ ANCHOR QUALITY SCORING - Prefer loadable exercises          │
            // │ Standard bilateral RDL > single-leg machine variants        │
            // └─────────────────────────────────────────────────────────────┘
            
            if nameLower.contains("deadlift") || nameLower.contains("rdl") || nameLower.contains("romanian") {
                // Prefer bilateral RDL for anchors
                if (nameLower.contains("romanian") || nameLower.contains("rdl")) &&
                   !nameLower.contains("single") && !nameLower.contains("one leg") && !nameLower.contains("alternate") {
                    score += 40  // Great anchor choice
                }
                
                // Demote single-leg for anchors
                if nameLower.contains("single leg") || nameLower.contains("one leg") || nameLower.contains("alternate") {
                    score -= 30  // Good accessory, not ideal anchor
                }
                
                // Demote unusual setups
                if nameLower.contains("on hack") || nameLower.contains("on leg press") {
                    score -= 50  // Hard to standardize
                }
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ WORKOUT CATEGORY MISMATCH PENALTIES                         │
            // │ Shrugs don't belong on push days, squats don't belong on    │
            // │ core days, upright rows irritate shoulders, etc.            │
            // └─────────────────────────────────────────────────────────────┘
            
            // Define workout types based on target muscles
            let targetMusclesLower = targetMuscles.map { $0.lowercased() }
            let isPushDay = targetMusclesLower.contains(where: { 
                $0.contains("chest") || $0.contains("shoulder") || $0.contains("tricep") 
            }) && !targetMusclesLower.contains(where: {
                $0.contains("back") || $0.contains("bicep") || $0.contains("trap")
            })
            let isCoreDay = targetMusclesLower.contains(where: { 
                $0.contains("core") || $0.contains("abs") || $0.contains("oblique")
            }) && targetMusclesLower.count <= 2  // Only core-focused days
            
            // SHRUGS on Push Day = Wrong category (shrugs are traps/pull movement)
            if isPushDay && nameLower.contains("shrug") {
                score -= 150  // Heavy penalty - shrugs don't belong on push days
                AppLogger.debug("Penalizing shrug on push day: \(exerciseName)", category: .workout)
            }
            
            // SQUATS/LEG PRESS on Core Day = Wrong category
            if isCoreDay && (nameLower.contains("squat") || nameLower.contains("leg press") || 
                            nameLower.contains("lunge") || nameLower.contains("deadlift")) {
                score -= 200  // Heavy penalty - big lifts don't belong on core days
                AppLogger.debug("Penalizing compound leg move on core day: \(exerciseName)", category: .workout)
            }
            
            // UPRIGHT ROWS - Shoulder irritation risk for many users
            if nameLower.contains("upright row") {
                score -= 80  // Moderate penalty - risky for shoulders
                AppLogger.warning("Penalizing upright row (shoulder risk): \(exerciseName)", category: .workout)
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ COMPOUND MOVEMENT BOOST                                     │
            // └─────────────────────────────────────────────────────────────┘
            if exerciseType == .compound {
                score += 25
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ POPULAR/PROVEN EXERCISES BOOST                              │
            // └─────────────────────────────────────────────────────────────┘
            if isProvenEffective(exerciseName: nameLower) {
                score += 20
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ PRACTICALITY SCORE - Realistic, common exercises get boost  │
            // └─────────────────────────────────────────────────────────────┘
            score += practicalityResult.scoreModifier
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ COMBO EXERCISE PENALTY - For ALL users                       │
            // │ Exercises combining two movements are impractical in gym     │
            // └─────────────────────────────────────────────────────────────┘
            let comboExercisePatterns = [
                "curl squat", "squat curl", "lunge curl", "curl lunge",
                "curtsey", "curtsy", "change lateral",
                "deadlift to", "to row", "to curl", "to press",
                "renegade row", "and row", "and curl"
            ]
            let isLungeCurl = nameLower.contains("lunge") && nameLower.contains("curl")
            let isCombo = comboExercisePatterns.contains(where: { nameLower.contains($0) }) || isLungeCurl
            
            if isCombo {
                score -= 150  // Heavy penalty for ALL users - these are impractical
                AppLogger.debug("Penalizing combo exercise: \(exerciseName)", category: .workout)
            }
            
            // COMPLEX PLANK PENALTY - For ALL users (shoulder stability heavy)
            let complexPlankPatterns = [
                "plank row", "plank raise", "plank lateral", "plank front",
                "plank with", "renegade", "commandos", "plank arm",
                "lateral raise plank", "raise plank"  // Catch variations with plank at end
            ]
            let isPlankCombo = nameLower.contains("plank") && 
                (nameLower.contains("raise") || nameLower.contains("row") ||
                 nameLower.contains("lateral") || nameLower.contains("dumbbell"))
            
            if complexPlankPatterns.contains(where: { nameLower.contains($0) }) || isPlankCombo {
                score -= 250  // Very strong penalty for complex planks (all users)
                AppLogger.debug("Penalizing complex plank: \(exerciseName)", category: .workout)
            }
            
            // ┌─────────────────────────────────────────────────────────────┐
            // │ NICHE EXERCISE PENALTY - Prefer simple staples              │
            // │ "Reverse grip decline press" is niche; "Incline DB press"   │
            // │ is a staple that's easy to repeat in any gym                │
            // └─────────────────────────────────────────────────────────────┘
            let nichePatterns = [
                "reverse grip", "close grip", "wide grip",  // Grip variations
                "twisting", "rotating", "alternating",       // Complex movements
                "v-bar", "v bar", "sz bar", "ez bar",       // Unusual attachments
                "unilateral", "one arm", "single arm"        // Single-limb (harder to progress)
            ]
            let nicheCount = nichePatterns.filter { nameLower.contains($0) }.count
            if nicheCount > 0 {
                score -= Double(nicheCount) * 25  // Penalty per niche modifier
            }
            
            // Exercises with very specific names are usually niche
            if nameLower.contains("narrow stance") || nameLower.contains("wide stance") ||
               nameLower.contains("split stance") || nameLower.contains("staggered") {
                score -= 20
            }
            
            scoredExercises.append((exercise, score, pattern, exerciseType))
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // SMART SELECTION WITH MOVEMENT PATTERN LIMITS
        // ═══════════════════════════════════════════════════════════════════
        
        // Sort by score
        scoredExercises.sort { $0.score > $1.score }
        
        var selectedExercises: [SmartSelectedExercise] = []
        var selectedNames: Set<String> = []
        var patternCounts: [SelectionMovementPattern: Int] = [:]
        var equipmentCounts: [String: Int] = [:]  // Track equipment diversity
        var exerciseBundleCounts: [String: Int] = [:]   // 📦 Track exercise BUNDLES (not just families)
        var exerciseFamilyCounts: [String: Int] = [:]    // Also track families within bundles
        var compoundCount = 0
        var isolationCount = 0
        
        // Target: 60% compounds, 40% isolation (approximately)
        let targetCompounds = max(2, Int(Double(exerciseCount) * 0.6))
        let targetIsolations = exerciseCount - targetCompounds
        
        // 📦 Bundle engine handles max-per-workout limits intelligently
        let bundleEngine = ExerciseBundleEngine.shared
        
        AppLogger.debug("Target mix: \(targetCompounds) compounds, \(targetIsolations) isolations, max \(maxPerEquipmentType) per equipment type", category: .workout)
        
        for (exercise, score, pattern, type) in scoredExercises {
            guard selectedExercises.count < exerciseCount else { break }
            
            let nameLower = (exercise.name ?? "").lowercased()
            let equipmentLower = (exercise.equipment ?? "bodyweight").lowercased()
            
            // Normalize equipment name for counting
            let equipmentCategory: String
            if equipmentLower.contains("barbell") { equipmentCategory = "barbell" }
            else if equipmentLower.contains("dumbbell") { equipmentCategory = "dumbbells" }
            else if equipmentLower.contains("cable") { equipmentCategory = "cables" }
            else if equipmentLower.contains("machine") || equipmentLower.contains("smith") { equipmentCategory = "machine" }
            else { equipmentCategory = equipmentLower }
            
            // Skip duplicates
            guard !selectedNames.contains(nameLower) else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // 📦 EXERCISE BUNDLE CHECK - Prevent exercises that are essentially the same
            // e.g., Bench Press AND Chest Press Machine are in the same "horizontal_press" bundle
            // ═══════════════════════════════════════════════════════════════
            let exerciseFamily = bundleEngine.detectExerciseFamily(nameLower)
            let bundle = bundleEngine.bundleForFamily(exerciseFamily)
            
            // Check bundle limit (e.g., max 2 horizontal presses per workout)
            if let bundle = bundle {
                let currentBundleCount = exerciseBundleCounts[bundle.id, default: 0]
                if currentBundleCount >= bundle.maxPerWorkout {
                    AppLogger.debug("Skipping \(exercise.name ?? "") - already have \(currentBundleCount)/\(bundle.maxPerWorkout) '\(bundle.displayName)' exercises", category: .workout)
                    continue
                }
            }
            
            // Also check exact family within bundle (max 1 per family)
            let currentFamilyCount = exerciseFamilyCounts[exerciseFamily, default: 0]
            if exerciseFamily != "other" && currentFamilyCount >= 1 {
                AppLogger.debug("Skipping \(exercise.name ?? "") - already have a '\(exerciseFamily)' exercise", category: .workout)
                continue
            }
            
            // ═══════════════════════════════════════════════════════════════
            // EQUIPMENT DIVERSITY CHECK - Don't overload one equipment type!
            // ═══════════════════════════════════════════════════════════════
            let currentEquipmentCount = equipmentCounts[equipmentCategory, default: 0]
            if currentEquipmentCount >= maxPerEquipmentType {
                AppLogger.debug("Skipping \(exercise.name ?? "") - already have \(currentEquipmentCount) \(equipmentCategory) exercises (max: \(maxPerEquipmentType))", category: .workout)
                continue
            }
            
            // ═══════════════════════════════════════════════════════════════
            // MOVEMENT PATTERN LIMIT CHECK (Critical for variety!)
            // ═══════════════════════════════════════════════════════════════
            let currentPatternCount = patternCounts[pattern, default: 0]
            if currentPatternCount >= pattern.maxPerWorkout {
                AppLogger.debug("Skipping \(exercise.name ?? "") - already have \(currentPatternCount) \(pattern.rawValue) exercises", category: .workout)
                continue
            }
            
            // ═══════════════════════════════════════════════════════════════
            // COMPOUND/ISOLATION BALANCE CHECK
            // ═══════════════════════════════════════════════════════════════
            if type == .compound && compoundCount >= targetCompounds {
                // Already have enough compounds, skip unless we need to fill
                if selectedExercises.count < exerciseCount - 2 {
                    continue
                }
            }
            
            if type == .isolation && isolationCount >= targetIsolations && compoundCount < targetCompounds {
                // Already have enough isolations and need more compounds
                continue
            }
            
            // ═══════════════════════════════════════════════════════════════
            // SELECT THIS EXERCISE
            // ═══════════════════════════════════════════════════════════════
            selectedExercises.append(SmartSelectedExercise(
                exercise: exercise,
                score: score,
                movementPattern: pattern,
                exerciseType: type
            ))
            
            selectedNames.insert(nameLower)
            patternCounts[pattern, default: 0] += 1
            equipmentCounts[equipmentCategory, default: 0] += 1  // Track equipment used
            exerciseFamilyCounts[exerciseFamily, default: 0] += 1  // Track exercise family
            if let bundle = bundle {
                exerciseBundleCounts[bundle.id, default: 0] += 1  // 📦 Track exercise bundle
            }
            
            if type == .compound { compoundCount += 1 }
            if type == .isolation { isolationCount += 1 }
            
            AppLogger.debug("Selected: \(exercise.name ?? "") (\(pattern.rawValue), \(type.rawValue), \(equipmentCategory), score: \(Int(score)))", category: .workout)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // REORDER: Compounds first, then isolations
        // ═══════════════════════════════════════════════════════════════════
        selectedExercises.sort { exercise1, exercise2 in
            // Compounds before isolations
            if exercise1.exerciseType == .compound && exercise2.exerciseType != .compound {
                return true
            }
            if exercise1.exerciseType != .compound && exercise2.exerciseType == .compound {
                return false
            }
            // Within same type, keep score order
            return exercise1.score > exercise2.score
        }
        
        AppLogger.debug("FINAL RESULTS — Compounds: \(compoundCount), Isolations: \(isolationCount), Patterns: \(patternCounts.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", "))", category: .workout)
        for (index, ex) in selectedExercises.enumerated() {
            AppLogger.debug("  \(index + 1). \(ex.name) [\(ex.equipment)] - \(ex.exerciseType.rawValue)", category: .workout)
        }
        
        return selectedExercises
    }
    
    // MARK: - Practicality Assessment
    
    struct PracticalityResult {
        let shouldExclude: Bool
        let scoreModifier: Double
        let reason: String
    }
    
    /// Assesses how "realistic" and practical an exercise is for most users
    /// Filters out exotic, dangerous, or impractical exercises while boosting common ones
    private func assessExercisePracticality(
        exerciseName: String,
        experienceLevel: String,
        isGymUser: Bool
    ) -> PracticalityResult {
        let name = exerciseName.lowercased()
        let isBeginnerOrIntermediate = experienceLevel.lowercased() != "advanced"
        
        // ════════════════════════════════════════════════════════════════════════════
        // HARD EXCLUDES - These exercises are unrealistic for most users
        // ════════════════════════════════════════════════════════════════════════════
        
        // Advanced gymnastics/calisthenics - exclude for non-advanced users
        let advancedGymnastics = [
            "handstand", "planche", "muscle up", "muscle-up", "iron cross",
            "human flag", "front lever", "back lever", "l-sit", "v-sit",
            "one arm pull", "one arm push", "pistol squat", "dragon flag",
            "hollow back press", "maltese", "victorian"
        ]
        if isBeginnerOrIntermediate && advancedGymnastics.contains(where: { name.contains($0) }) {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Advanced gymnastics")
        }
        
        // Bottle/improvised equipment - always exclude (unprofessional)
        let improvisedEquipment = [
            "bottle weighted", "water bottle", "backpack", "towel row",
            "chair dip", "couch", "bed", "door frame", "stairs"
        ]
        if improvisedEquipment.contains(where: { name.contains($0) }) {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Improvised equipment")
        }
        
        // Obscure/rare exercises most people don't know
        let obscureExercises = [
            "zottman", "svend", "jefferson", "zercher", "steinborn",
            "turkish get", "windmill", "sots press", "bradford press",
            "cuban press", "waiter curl", "guillotine press"
        ]
        if isBeginnerOrIntermediate && obscureExercises.contains(where: { name.contains($0) }) {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Obscure exercise")
        }
        
        // "Cat cow", "child pose", "downward dog" etc are yoga/stretching - exclude from strength
        let yogaPoses = [
            "cat cow", "child pose", "downward dog", "upward dog", "cobra pose",
            "warrior pose", "tree pose", "pigeon", "child's pose", "corpse pose",
            "mountain pose", "sun salutation", "namaste"
        ]
        if yogaPoses.contains(where: { name.contains($0) }) {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Yoga/stretching pose")
        }
        
        // Clapping/jumping movements in unexpected places
        let clappingMoves = ["clap back clap", "top clap back clap", "butt kick pulldown"]
        if clappingMoves.contains(where: { name.contains($0) }) {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Unusual movement")
        }
        
        // ════════════════════════════════════════════════════════════════════════════
        // HIGH-RISK EXERCISE BLOCKS - These should never be auto-generated defaults
        // ════════════════════════════════════════════════════════════════════════════
        
        // GOOD MORNING - High low-back injury risk for all users
        if name.contains("good morning") {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "High injury risk - good morning")
        }
        
        // UPRIGHT ROW - Shoulder impingement risk for all users
        if name.contains("upright row") || name.contains("upright pull") || name.contains("lying upright") {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Shoulder impingement risk - upright row")
        }
        
        // BEHIND NECK - Shoulder injury risk
        if name.contains("behind neck") || name.contains("behind the neck") {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Shoulder injury risk - behind neck")
        }
        
        // BEGINNER-SPECIFIC HARD BLOCKS
        let isBeginner = experienceLevel.lowercased() == "beginner"
        if isBeginner {
            // Hanging exercises - too advanced for beginners
            let hanginExercises = ["hanging pike", "hanging leg raise", "toes to bar", "hanging knee"]
            if hanginExercises.contains(where: { name.contains($0) }) {
                return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Too advanced for beginner - hanging exercise")
            }
            
            // Plyometric exercises - injury risk for beginners
            let plyoExercises = ["split jump", "jump squat", "box jump", "lunge jump", "squat jump", "bound"]
            if plyoExercises.contains(where: { name.contains($0) }) {
                return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Injury risk for beginner - plyometric")
            }
        }
        
        // ════════════════════════════════════════════════════════════════════════════
        // SCORING MODIFIERS - Boost practical exercises, penalize unusual ones
        // ════════════════════════════════════════════════════════════════════════════
        
        var modifier: Double = 0
        
        // ┌─────────────────────────────────────────────────────────────────────────┐
        // │ HIGHLY PRACTICAL - Well-known, effective exercises everyone recognizes │
        // └─────────────────────────────────────────────────────────────────────────┘
        let highlyPractical = [
            "bench press", "squat", "deadlift", "overhead press", "military press",
            "barbell row", "dumbbell row", "lat pulldown", "pull-up", "chin-up",
            "bicep curl", "tricep extension", "tricep pushdown", "leg press",
            "leg curl", "leg extension", "calf raise", "lateral raise",
            "front raise", "face pull", "cable fly", "dumbbell fly",
            "incline press", "decline press", "romanian deadlift", "hip thrust",
            "lunges", "split squat", "step up", "shrug", // upright row removed - injury risk
            "hammer curl", "preacher curl", "concentration curl", "skull crusher",
            "close grip bench", "dip", "push-up", "pushup", "plank",
            "crunch", "leg raise", "cable row", "seated row", "t-bar row",
            "chest press", "shoulder press", "arnold press"
        ]
        if highlyPractical.contains(where: { name.contains($0) }) {
            modifier += 35  // Strong boost for well-known exercises
        }
        
        // ┌─────────────────────────────────────────────────────────────────────────┐
        // │ MODERATE PRACTICAL - Good exercises but less common                     │
        // └─────────────────────────────────────────────────────────────────────────┘
        let moderatePractical = [
            "cable crossover", "pec deck", "machine fly", "hack squat",
            "goblet squat", "sumo deadlift", "stiff leg deadlift", // good morning removed - injury risk
            "hyperextension", "reverse fly", "rear delt", "cable curl",
            "overhead tricep", "rope pushdown", "v-bar pushdown",
            "incline curl", "spider curl", "drag curl", "ez bar curl",
            "close grip row", "wide grip pulldown", "straight arm pulldown",
            "machine row", "machine press", "smith machine", "landmine",
            "farmer walk", "farmer carry", "kettlebell swing"
        ]
        if moderatePractical.contains(where: { name.contains($0) }) {
            modifier += 20  // Good boost for practical variations
        }
        
        // ┌─────────────────────────────────────────────────────────────────────────┐
        // │ HOME GYM PRACTICAL - Prioritize for home users                         │
        // └─────────────────────────────────────────────────────────────────────────┘
        if !isGymUser {
            let homePractical = [
                "push-up", "pushup", "dumbbell", "band", "bodyweight squat",
                "lunge", "plank", "mountain climber", "burpee", "jumping jack",
                "resistance band", "floor press", "glute bridge"
            ]
            if homePractical.contains(where: { name.contains($0) }) {
                modifier += 25  // Boost home-friendly exercises
            }
            
            // Penalize exercises that need gym equipment for home users
            let needsGym = ["cable", "machine", "smith", "hack", "leg press", "pec deck"]
            if needsGym.contains(where: { name.contains($0) }) {
                modifier -= 30  // Home users shouldn't see cable/machine exercises
            }
        }
        
        // ┌─────────────────────────────────────────────────────────────────────────┐
        // │ GYM PRACTICAL - Prioritize proper gym exercises for gym users          │
        // └─────────────────────────────────────────────────────────────────────────┘
        if isGymUser {
            // Boost exercises that take advantage of gym equipment
            let gymOptimal = [
                "cable", "machine", "smith", "barbell", "ez bar", "preacher",
                "pec deck", "leg press", "hack squat", "lat pulldown"
            ]
            if gymOptimal.contains(where: { name.contains($0) }) {
                modifier += 20  // Boost gym equipment exercises
            }
            
            // Penalize low-intensity bodyweight for gym users (unless it's a compound)
            let lowIntensityBodyweight = [
                "lying leg raise", "floor crunch", "bird dog", "dead bug",
                "arm circle", "hip circle", "neck", "wrist"
            ]
            if lowIntensityBodyweight.contains(where: { name.contains($0) }) {
                modifier -= 20
            }
        }
        
        // ┌─────────────────────────────────────────────────────────────────────────┐
        // │ PENALTY FOR UNUSUAL PATTERNS                                           │
        // └─────────────────────────────────────────────────────────────────────────┘
        
        // Long/complex exercise names often indicate unusual variations
        if name.count > 50 {
            modifier -= 15  // Penalize overly complex exercise names
        }
        
        // Very long names (>7 words) are usually too complex
        let wordCount = name.split(separator: " ").count
        if wordCount > 7 {
            modifier -= 25
        }
        
        // Multiple parentheses often indicate obscure variations
        let parenthesesCount = name.filter { $0 == "(" }.count
        if parenthesesCount > 1 {
            modifier -= 10
        }
        
        // Exercises with "alternate", "twisting", "rotating" are often less practical
        let complexModifiers = ["twisting", "rotating", "alternating", "switching", "pulse"]
        if complexModifiers.contains(where: { name.contains($0) }) && !name.contains("curl") {
            modifier -= 10
        }
        
        // ┌─────────────────────────────────────────────────────────────────────────┐
        // │ COMBO EXERCISE PENALTIES - These are overly complex for most users      │
        // └─────────────────────────────────────────────────────────────────────────┘
        
        // Combo exercises (two exercises in one) - penalize heavily
        let comboPatterns = [
            "curl squat", "squat curl", "lunge curl", "curl lunge",
            "press squat", "squat press", "lunge press", "press lunge",
            "deadlift to", "to row", "to curl", "to press",
            "and curl", "and press", "and row", "renegade",
            "front raise", "squat front raise", "sumo squat front"  // Front raise combos
        ]
        // Also catch squat + raise combinations
        let isSquatRaise = name.contains("squat") && name.contains("raise")
        
        if comboPatterns.contains(where: { name.contains($0) }) || isSquatRaise {
            modifier -= 300  // VERY heavy penalty for combo moves
        }
        
        // Complex plank variations - stability over strength training
        let complexPlankPatterns = [
            "plank row", "plank raise", "plank lateral", "plank front",
            "plank with", "commandos", "plank arm", "superman lift"
        ]
        if complexPlankPatterns.contains(where: { name.contains($0) }) {
            modifier -= 200  // Heavy penalty for complex planks
        }
        
        // Coordination movements - harder to load progressively
        let coordinationPatterns = ["twisting", "rotating", "alternating"]
        if coordinationPatterns.contains(where: { name.contains($0) }) {
            modifier -= 25
        }
        
        // Niche exercise penalties - less effective for most users
        let nichePatterns: [(String, Double)] = [
            ("reverse grip", -25), ("close grip", -20), ("wide grip", -20),
            ("v-bar", -25), ("sz bar", -20), ("ez bar", -15),
            ("unilateral", -15), ("one arm", -15), ("single arm", -15),
            ("narrow stance", -15), ("wide stance", -15), ("split stance", -15)
        ]
        for (pattern, penalty) in nichePatterns {
            if name.contains(pattern) {
                modifier += penalty
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════════════
        // ADDITIONAL HIGH-RISK PENALTIES (for exercises not hard-blocked)
        // ═══════════════════════════════════════════════════════════════════════════════
        
        // HIGH PULL - Similar shoulder stress as upright row
        if name.contains("high pull") {
            modifier -= 120
        }
        
        // HANGING exercises - Advanced, not for defaults
        if name.contains("hanging") {
            modifier -= 200
        }
        
        // PLYO/JUMP penalties for all users (not just beginners)
        let plyoPatterns = ["split jump", "jump squat", "box jump", "lunge jump", "squat jump"]
        if plyoPatterns.contains(where: { name.contains($0) }) {
            modifier -= 280  // Very high penalty
        }
        
        // SHRUG penalty - Often selected instead of curls on back days
        if name.contains("shrug") {
            modifier -= 60
        }
        
        // DIPS penalty for beginners
        if isBeginner && name.contains("dip") {
            modifier -= 80  // Deprioritize dips for beginners
        }
        
        // SUPERMAN exercises - Low-back stress
        if name.contains("superman") {
            modifier -= 150
        }
        
        // ═══════════════════════════════════════════════════════════════════════════════
        // BEGINNER-SPECIFIC PENALTIES AND BOOSTS
        // ═══════════════════════════════════════════════════════════════════════════════
        
        // Note: isBeginner already declared above in hard blocks section
        
        if isBeginner {
            // BEGINNER ROW PREFERENCE - Chest-supported/seated > bent-over
            // Bent-over rows stress the low back which often limits beginners before back is trained
            let isRow = name.contains(" row") || name.hasPrefix("row")
            
            if isRow {
                // BOOST: Chest-supported, seated, cable rows (low-back friendly)
                if name.contains("chest supported") || name.contains("chest-supported") {
                    modifier += 80  // Best for beginners - no low-back stress
                } else if name.contains("seated") && name.contains("cable") {
                    modifier += 70  // Seated cable row - stable, easy to learn
                } else if name.contains("lever") || name.contains("machine") {
                    modifier += 60  // Machine rows - stable path
                } else if name.contains("cable") {
                    modifier += 50  // Cable rows - good tension
                }
                
                // PENALIZE: Bent-over rows (low-back limiting for beginners)
                if name.contains("bent over") || name.contains("bent-over") {
                    modifier -= 60  // Low back often limits before back is trained
                }
                if name.contains("barbell") && name.contains("bent") {
                    modifier -= 40  // Barbell bent-over even harder to stabilize
                }
            }
            
            // COMPLEX SQUAT PENALTIES - Beginners need simple, loadable patterns
            // "Goblet Squat Side Shuffle" is hard to progress; "Goblet Squat" or "Leg Press" is better
            let complexSquatPatterns = [
                "side shuffle", "shuffle", "lateral walk", "walk out",
                "jump", "pulse", "hold", "pause at bottom",
                "to press", "to curl", "to raise",
                "twist", "rotation", "sumo to", "alternating"
            ]
            let isSquat = name.contains("squat")
            let isComplexSquat = isSquat && complexSquatPatterns.contains(where: { name.contains($0) })
            
            if isComplexSquat {
                modifier -= 250  // VERY heavy penalty - use simple squat or leg press instead
            }
        }
        
        return PracticalityResult(shouldExclude: false, scoreModifier: modifier, reason: "Assessed")
    }
    
    // MARK: - Movement Pattern Classification
    
    private func classifyMovementPattern(exerciseName: String, muscles: String) -> SelectionMovementPattern {
        let name = exerciseName.lowercased()
        
        // === SHRUGS (check before presses due to name overlap) ===
        if name.contains("shrug") {
            return .shrug
        }
        
        // === ARM ISOLATION (check first to catch specific patterns) ===
        
        // Bicep curls - any curl that's not leg curl
        if name.contains("curl") && !name.contains("leg") && !name.contains("ham") {
            return .bicepCurl
        }
        
        // Triceps work
        if name.contains("tricep") || name.contains("pushdown") || name.contains("press down") ||
           name.contains("skull crusher") || name.contains("skull press") || name.contains("french press") ||
           (name.contains("extension") && name.contains("tricep")) {
            return .tricepExtension
        }
        
        // === SHOULDER ISOLATION ===
        
        // Lateral raises (side delts)
        if name.contains("lateral raise") || name.contains("side raise") || name.contains("side lateral") {
            return .lateralRaise
        }
        
        // Rear delt work
        if name.contains("rear delt") || name.contains("reverse fly") || name.contains("reverse flye") ||
           name.contains("face pull") || name.contains("rear fly") {
            return .rearDelt
        }
        
        // === PRESSING MOVEMENTS ===
        
        // Horizontal press (chest focus)
        if name.contains("bench press") || name.contains("push-up") || name.contains("pushup") ||
           name.contains("chest press") || name.contains("floor press") || name.contains("dip") {
            return .horizontalPress
        }
        
        // Vertical press (shoulder focus)
        if name.contains("overhead press") || name.contains("shoulder press") || name.contains("shoulders press") ||
           name.contains("military press") || name.contains("push press") || name.contains("arnold press") ||
           name.contains("viking press") || name.contains("pike") || name.contains("handstand") {
            return .verticalPress
        }
        
        // === PULLING MOVEMENTS ===
        
        // Vertical pull (lats) - CRITICAL for balanced program
        if name.contains("pull-up") || name.contains("pullup") || name.contains("chin-up") ||
           name.contains("chinup") || name.contains("pulldown") || name.contains("lat pull") ||
           name.contains("pull down") || name.contains("assisted pull") {
            return .verticalPull
        }
        
        // Horizontal pull (rows) - include ALL row variations (narrow grip, wide grip, etc.)
        // CRITICAL: Check for " row" (with space) to avoid matching "narrow" in leg press names
        if (name.contains(" row") || name.hasPrefix("row") || name.contains("rowing")) && !name.contains("upright") {
            return .horizontalPull
        }
        
        // === CHEST ISOLATION ===
        if (name.contains("fly") || name.contains("flye") || name.contains("crossover") || name.contains("pec deck")) &&
           !name.contains("rear") && !name.contains("reverse") {
            return .chestFly
        }
        
        // === LEG MOVEMENTS ===
        
        // Leg curl (knee flexion hamstrings) - CRITICAL
        if name.contains("leg curl") || name.contains("hamstring curl") || name.contains("lying curl") ||
           name.contains("seated curl") || name.contains("prone curl") {
            return .legCurl
        }
        
        // Leg extension (quad isolation)
        if name.contains("leg extension") || name.contains("knee extension") {
            return .legExtension
        }
        
        // Calf work
        if name.contains("calf") || name.contains("heel raise") || name.contains("gastrocnemius") {
            return .calfRaise
        }
        
        // Hip thrust specifically (separate from hinge)
        if name.contains("hip thrust") || name.contains("glute bridge") ||
           (name.contains("kickback") && (name.contains("glute") || name.contains("donkey"))) ||
           name.contains("glute press") {
            return .hipThrust
        }
        
        // Leg press (separate from squat for variety)
        if name.contains("leg press") {
            return .legPress
        }
        
        // Squat patterns
        if name.contains("squat") || name.contains("hack") {
            return .squat
        }
        
        // Hinge patterns (RDL, good morning, deadlift)
        if name.contains("deadlift") || name.contains("rdl") || name.contains("romanian") ||
           name.contains("good morning") || name.contains("hyperextension") || name.contains("back extension") {
            return .hinge
        }
        
        // Lunge patterns
        if name.contains("lunge") || name.contains("split squat") || name.contains("step up") || name.contains("step-up") {
            return .lunge
        }
        
        // === CORE (CRITICAL for fat loss programs) ===
        
        // Core flexion (crunches, sit-ups, leg raises)
        if name.contains("crunch") || name.contains("sit-up") || name.contains("situp") ||
           name.contains("leg raise") || name.contains("knee raise") || name.contains("toes to bar") {
            return .coreFlexion
        }
        
        // Core stability (planks, Pallof press, dead bugs, hollow holds)
        if name.contains("plank") || name.contains("dead bug") || name.contains("hollow") ||
           name.contains("pallof") || name.contains("anti-rotation") || name.contains("bird dog") ||
           name.contains("stir the pot") || name.contains("ab wheel") || name.contains("rollout") {
            return .coreStability
        }
        
        // Core rotation (woodchops, Russian twists)
        if name.contains("woodchop") || name.contains("wood chop") || name.contains("russian twist") {
            return .coreRotation
        }
        
        // Legacy leg extension catch-all (for backwards compatibility)
        if name.contains("leg extension") || name.contains("leg curl") ||
           name.contains("hamstring curl") || name.contains("calf") {
            return .legExtension
        }
        
        // Arm isolation
        if name.contains("curl") && (muscles.contains("bicep") || name.contains("bicep")) {
            return .bicepCurl
        }
        if name.contains("tricep") || name.contains("pushdown") || name.contains("skull") ||
           name.contains("kickback") || (name.contains("extension") && muscles.contains("tricep")) {
            return .tricepExtension
        }
        
        // Core
        if name.contains("crunch") || name.contains("sit-up") || name.contains("leg raise") {
            return .coreFlexion
        }
        if name.contains("plank") || name.contains("dead bug") || name.contains("pallof") ||
           name.contains("bird dog") {
            return .coreStability
        }
        
        return .other
    }
    
    // MARK: - Public Movement Pattern Accessor
    
    /// Get the movement pattern for an exercise (public accessor for SmartDayGenerator)
    func getMovementPattern(for exerciseName: String) -> SelectionMovementPattern {
        return classifyMovementPattern(exerciseName: exerciseName.lowercased(), muscles: "")
    }
    
    // MARK: - Exercise Type Classification
    
    private func classifyExerciseType(exerciseName: String, workoutType: String) -> ExerciseType {
        let name = exerciseName.lowercased()
        let type = workoutType.lowercased()
        
        if type.contains("stretch") { return .stretch }
        if type.contains("cardio") { return .cardio }
        if type.contains("plyo") || name.contains("jump") || name.contains("hop") || name.contains("bound") {
            return .plyometric
        }
        
        // Compound exercises (multi-joint)
        let compoundKeywords = [
            "press", "squat", "deadlift", "row", "pull-up", "pullup", "chin-up", "chinup",
            "dip", "lunge", "thrust", "clean", "snatch", "push-up", "pushup"
        ]
        if compoundKeywords.contains(where: { name.contains($0) }) {
            return .compound
        }
        
        // Isolation exercises (single-joint)
        let isolationKeywords = [
            "curl", "fly", "flye", "raise", "extension", "kickback", "pullover",
            "shrug", "crunch", "twist", "pulldown"  // lat pulldown is debatable
        ]
        if isolationKeywords.contains(where: { name.contains($0) }) {
            return .isolation
        }
        
        // Default based on muscle count
        return .compound
    }
    
    // MARK: - Gym Equipment Scoring
    
    /// 🏋️ HEAVILY prioritizes exercises that USE gym equipment
    /// User is paying for a gym - they should get exercises that UTILIZE the gym!
    private func scoreGymEquipmentPriority(equipment: String, exerciseName: String) -> Double {
        let equip = equipment.lowercased()
        let nameLower = exerciseName.lowercased()
        var score: Double = 0
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🔥 MASSIVE BOOST for gym equipment - user is paying for gym access!
        // MACHINES and CABLES are hallmarks of gym training - prioritize them!
        // ═══════════════════════════════════════════════════════════════════════════
        
        // 🏆 LEVER MACHINES (plate-loaded) - Top tier gym equipment
        if equip.contains("lever") || equip.contains("chest press machine") || 
           equip.contains("leg press machine") || equip.contains("seated row machine") ||
           equip.contains("leg curl machine") {
            score += 115  // 🥇 LEVER MACHINES are peak gym experience!
        }
        // Other machines (selectorized, etc.)
        else if equip.contains("machine") && !equip.contains("cable") && !equip.contains("smith") {
            score += 110  // 🥈 Other machines - great for targeted isolation
        }
        // Cable machines - excellent constant tension
        else if equip.contains("cable") { 
            score += 105  // 🥉 Cables - amazing for controlled movements
        }
        // Barbells - traditional strength training
        else if equip.contains("barbell") { 
            score += 100  // Barbells - classic but available at home gyms too
        }
        // Smith machine - guided barbell movements
        else if equip.contains("smith") {
            score += 95  // Good for controlled movements
        }
        // Dumbbells - versatile but can be done at home
        else if equip.contains("dumbbell") { 
            score += 85  // Great for unilateral work
        }
        else if equip.contains("ez bar") || equip.contains("ez-bar") {
            score += 75  // Good for curls, skull crushers
        }
        else if equip.contains("kettlebell") { 
            score += 60  // Good for functional movements
        }
        else if equip.isEmpty || equip.contains("bodyweight") {
            // Bodyweight exercises in gym context
            let gymAppropriateBodyweight = ["pull-up", "pullup", "chin-up", "chinup", "dip", "hanging", "muscle-up", "muscle up"]
            if gymAppropriateBodyweight.contains(where: { nameLower.contains($0) }) {
                score += 70  // These are legit gym exercises that need gym equipment (pull-up bar, dip station)
            } else {
                // Other bodyweight exercises get NO bonus for gym users
                // (They pass the filter but won't beat equipment-based exercises)
                score += 0
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🏆 COMPOUND MOVEMENT BONUS - These are the most effective exercises
        // ═══════════════════════════════════════════════════════════════════════════
        let majorCompounds = ["deadlift", "squat", "bench press", "overhead press", "row", "pull-up", "chin-up", "hip thrust", "lunge", "leg press"]
        if majorCompounds.contains(where: { nameLower.contains($0) }) {
            score += 30  // Extra boost for major compound movements
        }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🎯 PROVEN EFFECTIVE EXERCISES - These have decades of research
        // ═══════════════════════════════════════════════════════════════════════════
        let goldStandardExercises = [
            "barbell squat", "back squat", "front squat",
            "barbell bench press", "incline bench press", "decline bench press",
            "barbell deadlift", "romanian deadlift", "sumo deadlift",
            "barbell row", "pendlay row", "t-bar row",
            "lat pulldown", "cable row", "seated row",
            "leg press", "hack squat",
            "cable fly", "cable crossover",
            "tricep pushdown", "rope pushdown",
            "barbell curl", "preacher curl"
        ]
        if goldStandardExercises.contains(where: { nameLower.contains($0) }) {
            score += 25  // Extra boost for gold-standard exercises
        }
        
        return score
    }
    
    // MARK: - Helper Functions
    
    private func matchBroadMuscleGroup(_ muscle: String, exerciseMuscles: String, category: String) -> Bool {
        switch muscle {
        case "chest", "upper chest", "lower chest":
            return exerciseMuscles.contains("chest") || category.contains("chest")
        case "back", "upper back", "lower back", "lats":
            return exerciseMuscles.contains("lat") || exerciseMuscles.contains("trap") || exerciseMuscles.contains("back") || category.contains("back")
        case "legs", "quadriceps", "quads":
            return exerciseMuscles.contains("quad") || exerciseMuscles.contains("ham") || exerciseMuscles.contains("glut") || exerciseMuscles.contains("calf") || category.contains("leg")
        case "arms":
            return exerciseMuscles.contains("bicep") || exerciseMuscles.contains("tricep") || exerciseMuscles.contains("forearm") || category.contains("arm")
        case "shoulders", "front delts", "side delts", "rear delts", "rotator cuff":
            return exerciseMuscles.contains("delt") || exerciseMuscles.contains("shoulder") || exerciseMuscles.contains("rotator") || category.contains("shoulder")
        case "core", "abs", "obliques", "lower abs":
            return exerciseMuscles.contains("ab") || exerciseMuscles.contains("oblique") || exerciseMuscles.contains("core") || category.contains("core")
        case "hips", "hip flexors", "inner thighs":
            return exerciseMuscles.contains("hip") || exerciseMuscles.contains("inner thigh") || exerciseMuscles.contains("adduct") || category.contains("hip")
        case "neck":
            return exerciseMuscles.contains("neck") || category.contains("neck")
        case "full body":
            return exerciseMuscles.contains("full body") || category.contains("full body")
        case "traps":
            return exerciseMuscles.contains("trap") || category.contains("back")
        case "forearms":
            return exerciseMuscles.contains("forearm") || exerciseMuscles.contains("grip")
        case "calves":
            return exerciseMuscles.contains("calf") || exerciseMuscles.contains("calves")
        default: return false
        }
    }
    
    /// Detects the "family" of an exercise to prevent selecting multiple variations.
    /// Delegates to the centralized ExerciseBundleEngine for consistent classification.
    private func detectExerciseFamily(_ exerciseName: String) -> String {
        return ExerciseBundleEngine.shared.detectExerciseFamily(exerciseName)
    }
    
    private func isProvenEffective(exerciseName: String) -> Bool {
        let provenExercises = [
            "bench press", "squat", "deadlift", "overhead press", "barbell row",
            "pull-up", "chin-up", "dip", "romanian deadlift", "hip thrust",
            "lat pulldown", "cable fly", "incline press", "leg press",
            "dumbbell curl", "tricep pushdown", "face pull", "lateral raise"
        ]
        return provenExercises.contains { exerciseName.contains($0) }
    }
    
    // MARK: - Workout Style Selection
    
    /// Selects an appropriate workout style based on user preferences and history
    func selectWorkoutStyle(
        userGoal: String,
        experienceLevel: String,
        recentStyles: [WorkoutStyle]
    ) -> WorkoutStyle {
        
        // Beginners get straight sets
        if experienceLevel.lowercased() == "beginner" {
            return .straight
        }
        
        // Avoid recently used styles
        let availableStyles = WorkoutStyle.allCases.filter { !recentStyles.suffix(3).contains($0) }
        
        // Goal-based preference
        switch userGoal.lowercased() {
        case "build muscle", "hypertrophy":
            let preferred: [WorkoutStyle] = [.straight, .superset, .dropSet]
            return preferred.first { availableStyles.contains($0) } ?? .straight
        case "get stronger", "strength":
            let preferred: [WorkoutStyle] = [.straight, .cluster, .pyramid]
            return preferred.first { availableStyles.contains($0) } ?? .straight
        case "lose weight", "fat loss":
            let preferred: [WorkoutStyle] = [.circuit, .superset, .straight]
            return preferred.first { availableStyles.contains($0) } ?? .circuit
        default:
            return availableStyles.randomElement() ?? .straight
        }
    }
}

// MARK: - Extension for SmartProgramEngine Integration

extension SmartExerciseSelectionEngine {
    
    /// Convert selected exercises to SmartProgramExercise format
    func convertToSmartProgramExercises(
        selectedExercises: [SmartSelectedExercise],
        userGoal: String,
        experienceLevel: String,
        intensity: Double
    ) -> [SmartProgramExercise] {
        
        return selectedExercises.enumerated().map { index, selected in
            let prescription = calculateExercisePrescription(
                exerciseType: selected.exerciseType,
                userGoal: userGoal,
                experienceLevel: experienceLevel,
                intensity: intensity,
                exerciseOrder: index
            )
            
            return SmartProgramExercise(
                id: UUID().uuidString,
                exerciseName: selected.name,
                exerciseId: selected.exercise.id,
                sets: prescription.sets,
                reps: prescription.reps,
                suggestedWeight: nil,
                restSeconds: prescription.restSeconds,
                notes: prescription.notes,
                isSuperset: false,
                supersetWith: nil
            )
        }
    }
    
    private func calculateExercisePrescription(
        exerciseType: ExerciseType,
        userGoal: String,
        experienceLevel: String,
        intensity: Double,
        exerciseOrder: Int
    ) -> (sets: Int, reps: Int, restSeconds: Int, notes: String?) {
        
        let goalLower = userGoal.lowercased()
        let isCompound = exerciseType == .compound
        
        // Base prescription by goal
        var sets: Int
        var reps: Int
        var rest: Int
        var notes: String?
        
        switch goalLower {
        case "get stronger", "strength":
            sets = isCompound ? 5 : 4
            reps = isCompound ? 5 : 8
            rest = isCompound ? 180 : 120
            notes = isCompound ? "Focus on progressive overload" : nil
            
        case "build muscle", "hypertrophy", "muscle gain":
            sets = 4
            reps = isCompound ? 8 : 12
            rest = isCompound ? 120 : 90
            notes = exerciseOrder == 0 ? "Primary compound - go heavy" : nil
            
        case "lose weight", "fat loss", "weight loss":
            sets = 3
            reps = isCompound ? 12 : 15
            rest = 45
            notes = "Keep rest periods short"
            
        case "tone & define", "toning":
            sets = 3
            reps = 15
            rest = 60
            
        case "endurance":
            sets = 2
            reps = 20
            rest = 30
            
        default:
            sets = 3
            reps = 10
            rest = 90
        }
        
        // Adjust for intensity
        if intensity > 0.8 {
            sets += 1
            rest += 15
        } else if intensity < 0.6 {
            sets = max(2, sets - 1)
            rest = max(30, rest - 15)
        }
        
        // Adjust for experience
        if experienceLevel.lowercased() == "beginner" {
            sets = max(2, sets - 1)
            reps = min(12, reps)
            rest = max(rest, 90)
        } else if experienceLevel.lowercased() == "advanced" {
            if isCompound { sets += 1 }
        }
        
        return (sets, reps, rest, notes)
    }
}

// MARK: - Sample Workout Templates (Best Practices)

struct OptimalWorkoutTemplates {
    
    /// Optimal Push Day structure
    static let pushDay: [(pattern: SelectionMovementPattern, equipment: String?, notes: String)] = [
        (.horizontalPress, "Barbell", "Primary compound - flat or incline bench press"),
        (.horizontalPress, "Dumbbells", "Secondary press - different angle"),
        (.chestFly, "Cables", "Chest isolation - stretch under load"),
        (.verticalPress, "Dumbbells", "Shoulder compound"),
        (.tricepExtension, "Cables", "Tricep finisher")
    ]
    
    /// Optimal Pull Day structure
    static let pullDay: [(pattern: SelectionMovementPattern, equipment: String?, notes: String)] = [
        (.horizontalPull, "Barbell", "Primary compound - barbell or cable row"),
        (.verticalPull, nil, "Secondary pull - pulldowns or pull-ups"),
        (.horizontalPull, "Dumbbells", "Unilateral row variation"),
        (.lateralRaise, "Cables", "Rear delt work - face pulls"),
        (.bicepCurl, "Dumbbells", "Bicep finisher")
    ]
    
    /// Optimal Leg Day structure
    static let legDay: [(pattern: SelectionMovementPattern, equipment: String?, notes: String)] = [
        (.squat, "Barbell", "Primary compound - back squat or front squat"),
        (.hinge, "Barbell", "Hip hinge - RDL or deadlift variation"),
        (.lunge, "Dumbbells", "Unilateral - lunges or split squats"),
        (.legExtension, "Machine", "Quad isolation"),
        (.legCurl, "Machine", "Hamstring isolation")
    ]
}

