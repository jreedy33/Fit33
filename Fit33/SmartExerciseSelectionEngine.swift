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
    
    // ─────────────────────────────────────────────────────────────────────────
    // `doesEquipmentMatch()` (local, buggy substring-match version) was removed
    // 2026-05-08 after the autogen audit identified `equipment_mismatch` as
    // the #1 issue class (79 occurrences in 20-user run). All callers now route
    // through `ExerciseFilterService.userHasRequiredEquipment(...)` — the
    // single canonical equipment matcher. See the call site below for context.
    // ─────────────────────────────────────────────────────────────────────────

    
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
                // 🛡️ Audit 2026-05-08: Single canonical equipment matcher.
                //
                // Previously we had a local `doesEquipmentMatch()` that did substring matching with
                // a buggy whitelist (empty-string bodyweight, bare "bar" → false-positive on Pull-Up
                // Bar). The 20-user audit found `equipment_mismatch` to be the #1 problem class
                // (79 occurrences) — almost all coming from this duplicated path.
                //
                // We now ALWAYS go through `ExerciseFilterService.userHasRequiredEquipment` which:
                //   1. Parses comma-separated exercise equipment (e.g. "Dumbbells, Incline Bench")
                //      and verifies each part.
                //   2. Performs name-based absence checks for barbell / dumbbell / cable / machine /
                //      smith / pull-up bar / dip bars / bench-name (catches exercises where the
                //      equipment field omits a piece of equipment that's clearly in the NAME).
                //   3. Honors the bench-access rule (gym SKUs imply bench access; outdoor users do
                //      not get bench-dependent exercises).
                equipmentMatch = ExerciseFilterService.userHasRequiredEquipment(
                    exerciseEquipment: equipment,
                    exerciseName: exerciseName,
                    userEquipment: userEquipment
                )

                if !equipmentMatch {
                    AppLogger.debug("Excluding '\(exerciseName)': requires '\(equipment)' but user has \(userEquipment)", category: .workout)
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
            // 🚨 FILTER 3.7: AGE-GATED DECLINE BLOCK (Audit 2026-05-08 fix #3)
            // Mirrors the assessExercisePracticality() check, but applied EARLIER
            // so the database-score path (below) cannot bypass it. user-26 (68y)
            // was served 4× decline chest in Round 3 — the DB practicality score
            // for "Decline Bench Press" is high (it IS a foundational exercise),
            // so the assess fallback never fires for that user. We need the hard
            // block at the filter layer.
            // ═══════════════════════════════════════════════════════════════
            let userAgeForFilter = Int(UserManager.shared.currentUser?.age ?? 0)
            if userAgeForFilter >= 65 && nameLower.contains("decline") {
                AppLogger.debug("Excluding '\(exerciseName)': decline-angle blocked for users 65+ (cardiovascular / intracranial-pressure risk)", category: .workout)
                continue
            }

            // ═══════════════════════════════════════════════════════════════
            // 🚨 FILTER 3.8: SPECIALTY VARIANT PRE-CHECK (Audit 2026-05-08 fix)
            // Apply the SpecialtyVariantFilter BEFORE the DB practicality
            // score check below. Otherwise grip variants with high DB scores
            // (e.g. Pendlay Row, Wide Bench Press) bypass the filter entirely
            // and slip through to autogen output. The Round 3 audit saw 43
            // specialty variants slip past — the filter was running only on
            // the fallback `assessExercisePracticality()` path.
            //
            // `.blockUntilEstablished` patterns gate on workout count, so
            // grip / unilateral / stability progression variants stay blocked
            // until the user crosses the per-level threshold (audit users
            // are always at 0 → all blocked).
            // ═══════════════════════════════════════════════════════════════
            let isBeginnerForSpec = experienceLevel.lowercased() == "beginner"
            let isIntermediateForSpec = experienceLevel.lowercased() == "intermediate"
            if let specialtyBlock = SpecialtyVariantFilter.evaluate(
                name: nameLower,
                isBeginner: isBeginnerForSpec,
                isIntermediate: isIntermediateForSpec,
                completedWorkoutCount: userWorkoutCount
            ), specialtyBlock.shouldExclude {
                AppLogger.debug("Excluding '\(exerciseName)': \(specialtyBlock.reason)", category: .workout)
                continue
            }

            // ═══════════════════════════════════════════════════════════════
            // 🚨 FILTER 3.9: TECHNIQUE-EQUIPMENT MISMATCH PRE-CHECK
            // (Audit 2026-05-08 Round 3 fix #6 — early-hard-block mirror)
            //
            // Some training techniques are inherently barbell/dumbbell-only and
            // make no biomechanical sense on cable / smith / band / KB / TRX.
            // The Round 3 audit caught "Pendlay Row (Cable)" — Pendlay is a
            // dead-stop powerlifting variant; cable has no floor reset / no
            // horizontal pull plane. Same for Jefferson, Zercher, Clean Grip,
            // Snatch Grip on non-free-weight equipment.
            //
            // This check lives in assessExercisePracticality() too, but that
            // path is bypassed when the catalog has a practicality_score > 0
            // (most exercises). Mirror here so the block fires unconditionally.
            // ═══════════════════════════════════════════════════════════════
            let barbellTechniques = ["pendlay", "jefferson", "zercher", "clean grip", "snatch grip"]
            if let technique = barbellTechniques.first(where: { nameLower.contains($0) }) {
                let suffixEquip: String? = {
                    guard let openParen = nameLower.lastIndex(of: "("),
                          let closeParen = nameLower.lastIndex(of: ")"),
                          openParen < closeParen else { return nil }
                    let afterOpen = nameLower.index(after: openParen)
                    return String(nameLower[afterOpen..<closeParen]).trimmingCharacters(in: .whitespaces)
                }()
                let allowedEquipment: Set<String> = ["barbell", "dumbbell"]
                let detectedEquipment: String = suffixEquip ?? ""
                let isOnAllowedEquipment: Bool = {
                    if !detectedEquipment.isEmpty {
                        return allowedEquipment.contains(where: { detectedEquipment.contains($0) })
                    }
                    return allowedEquipment.contains(where: { nameLower.contains($0) })
                }()
                if !isOnAllowedEquipment {
                    let equipDescriptor = detectedEquipment.isEmpty ? "non-barbell equipment" : detectedEquipment
                    AppLogger.debug("Excluding '\(exerciseName)': technique-equipment mismatch — '\(technique)' is a barbell technique, not appropriate for \(equipDescriptor)", category: .workout)
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
                    isGymUser: isGymUser,
                    userAge: userAgeForFilter,
                    completedWorkoutCount: userWorkoutCount
                )
            }
            
            if practicalityResult.shouldExclude {
                AppLogger.debug("Excluding '\(exerciseName)': \(practicalityResult.reason)", category: .workout)
                continue
            }

            // ═══════════════════════════════════════════════════════════════
            // 👤 GENDER STRICT FILTER — Audit 2026-05-08 user request
            // ═══════════════════════════════════════════════════════════════
            // For STRENGTH exercises: never serve an opposite-gender-only video.
            // Catalog has both-gender clips for the top ~200 common strength
            // movements; if THIS exercise is gender-tagged but missing the
            // user's gender, an equivalent same-gender alternative exists.
            // For stretch / cardio / plyo / specialty (smaller catalog), keep
            // the soft fallback so the user always sees SOMETHING.
            let genderClassification = ExerciseFilterService.classifyExerciseType(
                name: exercise.name,
                category: exercise.category,
                equipment: exercise.equipment
            )
            if genderClassification == .strength {
                let genderCache = VideoStreamingService.shared.genderVideoCache
                if let info = genderCache[exerciseName] ?? genderCache[nameLower] {
                    let userGenderRaw = UserManager.shared.currentUser?.gender?.lowercased() ?? "male"
                    let preferredGender: VideoStreamingService.VideoGender = userGenderRaw.contains("female") ? .female : .male
                    if info.filename(for: preferredGender) == nil {
                        AppLogger.debug("Excluding '\(exerciseName)': no \(preferredGender.rawValue.lowercased()) video for strength workout", category: .workout)
                        continue
                    }
                }
                // No gender info → gender-neutral / legacy single-video → keep.
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

            // ┌─────────────────────────────────────────────────────────────┐
            // │ GOAL-AWARE MULTIPLIER (Audit 2026-05-08 fix #2)              │
            // │ For "Build Endurance" goal: boost circuit-friendly +         │
            // │ light-load + bodyweight basics; penalize heavy 1RM-style     │
            // │ compound lifts. Other goals → multiplier = 1.0 (no-op).      │
            // │ Authority: FoundationalExerciseDatabase.goalMultiplier (FE). │
            // └─────────────────────────────────────────────────────────────┘
            let goalMult = FoundationalExerciseDatabase.goalMultiplier(
                exerciseName: exerciseName,
                equipment: exercise.equipment,
                category: exercise.category,
                goal: userGoal
            )
            if abs(goalMult - 1.0) > 0.001 {
                let preMult = score
                score *= goalMult
                AppLogger.debug("Goal-mult \(String(format: "%.2f", goalMult)) for '\(exerciseName)' [\(userGoal)]: \(Int(preMult)) → \(Int(score))", category: .workout)
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
            // 🛡️ DIVERSITY CAP CROSS-CHECK (Audit 2026-05-08 fix #5)
            // ═══════════════════════════════════════════════════════════════
            // The 20-user audit caught workouts with 3 pull-up variations
            // slipping past the SelectionMovementPattern check (likely because
            // the granular variants mapped to different coarse patterns). The
            // SmartExercisePairingEngine has a finer-grained MovementPattern
            // classifier; we use it as a backstop. Cap is `movementPatternRepeatCap`.
            let alreadySelected = selectedExercises.map { $0.exercise }
            if SmartExercisePairingEngine.shared.wouldExceedDiversityCap(
                adding: exercise,
                to: alreadySelected
            ) {
                let pp = SmartExercisePairingEngine.shared.movementPattern(for: exercise).rawValue
                AppLogger.debug("Skipping \(exercise.name ?? "") - already at diversity cap (\(SmartExercisePairingEngine.movementPatternRepeatCap)) for granular pattern '\(pp)'", category: .workout)
                continue
            }

            // ═══════════════════════════════════════════════════════════════
            // 🛡️ ANGLE-STACKING CAP (Audit 2026-05-08 fix #2 — Round 3)
            // ═══════════════════════════════════════════════════════════════
            // user-15 / user-26 of the 50-user audit got 4× decline chest in
            // a single workout. Same angle = same shoulder-girdle position =
            // same fiber recruitment bias; stacking 4 of them is a programming
            // defect. Cap = WorkoutComboRules.maxPerAngle (= 2). nil-classified
            // exercises (non-angled press/pull) are unaffected.
            let alreadySelectedNames = selectedExercises.map { $0.name }
            if WorkoutComboRules.wouldExceedAngleCap(
                adding: exercise.name ?? "",
                to: alreadySelectedNames
            ) {
                let angle = WorkoutComboRules.angleClassification(for: exercise.name ?? "") ?? "unknown"
                AppLogger.debug("Skipping \(exercise.name ?? "") - already at angle cap (\(WorkoutComboRules.maxPerAngle)) for angle '\(angle)'", category: .workout)
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
        // TARGET-MUSCLE COVERAGE PASS (Audit 2026-05-08 Round 3 fix #3, #10)
        //
        // The Round 3 50-user audit flagged 4 workouts where `target_muscles`
        // included e.g. "calves" but NO selected exercise actually targeted
        // calves — the workout "promised" the user training for that group
        // and silently dropped it. `validateTargetMuscleCoverage` returns
        // every target muscle that no selected exercise covers (primary OR
        // secondary). We then attempt a foundational fallback swap before
        // the final compound-first sort so the swap-in still gets ordered
        // correctly. If no foundational candidate is available given the
        // user's equipment, we log an `AppLogger.warning` so production
        // monitoring can see the gap (Bug-Intel pickup) instead of silently
        // shipping a workout that violates user expectations.
        // ═══════════════════════════════════════════════════════════════════
        let uncoveredMuscles = validateTargetMuscleCoverage(
            selected: selectedExercises,
            targetMuscles: targetMuscles
        )
        if !uncoveredMuscles.isEmpty {
            selectedExercises = attemptCoverageSwap(
                selected: selectedExercises,
                uncoveredMuscles: uncoveredMuscles,
                userEquipment: userEquipment,
                allExercises: safeExercises
            )
        }

        // ═══════════════════════════════════════════════════════════════════
        // FINAL PASS — Compound-first STABLE sort (Audit 2026-05-08 fix #1)
        //
        // Round 3 50-user audit flagged `compound_after_isolation` 42 times
        // (top-fix #1, #4, #5, #9, #12). The previous reorder used
        // `Array.sort` with a score tiebreaker — not guaranteed stable, and
        // re-shuffled within-bucket order. The new helper is an explicit
        // stable partition: compounds in their original picked order, then
        // isolations in their original picked order. No within-bucket churn.
        //
        // Catalog mis-labeling override (fix #11) is preserved in
        // `effectiveIsCompound` inside `sortCompoundFirst`.
        // ═══════════════════════════════════════════════════════════════════
        selectedExercises = sortCompoundFirst(selectedExercises)

        AppLogger.debug("FINAL RESULTS — Compounds: \(compoundCount), Isolations: \(isolationCount), Patterns: \(patternCounts.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", "))", category: .workout)
        for (index, ex) in selectedExercises.enumerated() {
            AppLogger.debug("  \(index + 1). \(ex.name) [\(ex.equipment)] - \(ex.exerciseType.rawValue)", category: .workout)
        }

        return selectedExercises
    }

    // MARK: - Compound-First Stable Sort (Audit 2026-05-08 fix #1)

    /// Stable-partition `selected` so every effective-compound exercise comes
    /// before every effective-isolation exercise, while preserving each
    /// bucket's original relative order. This is the LAST step before
    /// `selectExercisesForWorkout` returns its workout array.
    ///
    /// "Effective compound" = `ex.exerciseType == .compound` AND the name does
    /// NOT match `FoundationalExerciseDatabase.isSingleJointIsolation` — the
    /// override (fix #11) catches catalog mis-labels (skull crushers,
    /// kickbacks, lateral raises sometimes ship as `compound` from the DB).
    ///
    /// Example: input `[squat, leg_curl, lunge, leg_extension]` →
    /// output `[squat, lunge, leg_curl, leg_extension]`.
    func sortCompoundFirst(_ selected: [SmartSelectedExercise]) -> [SmartSelectedExercise] {
        func effectiveIsCompound(_ ex: SmartSelectedExercise) -> Bool {
            if ex.exerciseType != .compound { return false }
            // Catalog said compound — verify with the name-pattern isolation hint.
            return !FoundationalExerciseDatabase.isSingleJointIsolation(name: ex.name)
        }
        // Two-pass partition preserves original order within each bucket.
        // Swift's Array.sort is NOT stable; we cannot use it for this.
        let compounds = selected.filter { effectiveIsCompound($0) }
        let isolations = selected.filter { !effectiveIsCompound($0) }
        return compounds + isolations
    }

    // MARK: - Target-Muscle Coverage (Audit 2026-05-08 Round 3 fix #3, #10)

    /// Returns the list of target muscles that NO selected exercise covers as
    /// either a primary or secondary muscle. The Round 3 50-user audit caught
    /// 4 workouts that promised calves but delivered no calf exercises —
    /// this validation function is the choke point that catches the gap
    /// before the workout is returned to the user.
    ///
    /// Matching is case-insensitive substring, expanded via the synonym list
    /// in `FoundationalMuscleGroup.relatedMuscles` (so "calves" also accepts
    /// "lower legs"; "back" also accepts "lats", "upper back", "traps", etc.).
    /// Category and primary/secondary muscle arrays are all consulted.
    ///
    /// - Parameters:
    ///   - selected: The workout exercises produced by the main selection loop.
    ///   - targetMuscles: The muscle groups the workout was supposed to hit.
    /// - Returns: Subset of `targetMuscles` not covered by any selected
    ///   exercise's primary or secondary muscles. Empty array = full coverage.
    func validateTargetMuscleCoverage(
        selected: [SmartSelectedExercise],
        targetMuscles: [String]
    ) -> [String] {
        guard !targetMuscles.isEmpty, !selected.isEmpty else { return [] }

        var uncovered: [String] = []
        for target in targetMuscles {
            let targetLower = target.lowercased()
            // Skip "full body" / "upper body" / "lower body" — these are split
            // descriptors, not concrete muscles. Coverage is implicit.
            if targetLower.contains("full body") || targetLower.contains("upper body") || targetLower.contains("lower body") {
                continue
            }
            // Build the synonym set for this target muscle.
            let synonyms = synonymsForMuscle(targetLower)

            let isCovered = selected.contains { ex in
                let primary = (ex.exercise.getMuscleGroups() ?? []).joined(separator: ",").lowercased()
                let secondary = ((ex.exercise.secondaryMuscles as? [String]) ?? []).joined(separator: ",").lowercased()
                let category = (ex.exercise.category ?? "").lowercased()
                let combined = "\(primary),\(secondary),\(category)"
                return synonyms.contains { combined.contains($0) }
            }
            if !isCovered {
                uncovered.append(target)
            }
        }
        return uncovered
    }

    /// Returns the canonical synonym set for a target muscle, mirroring
    /// `FoundationalMuscleGroup.relatedMuscles` plus a few catalog spellings
    /// the live `exercises` table uses (e.g. "gastrocnemius").
    private func synonymsForMuscle(_ targetLower: String) -> Set<String> {
        // Pre-canonicalize: collapse "calves" / "calf", "abs" / "abdominals", etc.
        switch targetLower {
        case let s where s.contains("calf") || s.contains("calves") || s.contains("lower leg"):
            return ["calf", "calves", "lower leg", "gastrocnemius", "soleus"]
        case let s where s.contains("quad") || s.contains("thigh"):
            return ["quad", "quads", "quadriceps", "thigh"]
        case let s where s.contains("hamstring"):
            return ["hamstring", "hamstrings"]
        case let s where s.contains("glute") || s.contains("hip"):
            return ["glute", "glutes", "gluteus", "hip"]
        case let s where s.contains("chest") || s.contains("pec"):
            return ["chest", "pectorals", "pecs", "upper chest", "lower chest"]
        case let s where s.contains("back") || s.contains("lat") || s.contains("rhomboid") || s.contains("trap"):
            return ["back", "lat", "lats", "upper back", "lower back", "rhomboid", "rhomboids", "traps", "middle back"]
        case let s where s.contains("shoulder") || s.contains("delt"):
            return ["shoulder", "shoulders", "delt", "delts", "deltoid", "front delt", "rear delt", "side delt", "lateral delt"]
        case let s where s.contains("bicep"):
            return ["bicep", "biceps"]
        case let s where s.contains("tricep"):
            return ["tricep", "triceps"]
        case let s where s.contains("forearm"):
            return ["forearm", "forearms"]
        case let s where s.contains("core") || s.contains("ab") || s.contains("oblique"):
            return ["core", "abs", "abdominals", "obliques", "abdominal"]
        default:
            return [targetLower]
        }
    }

    /// Attempts to swap in a foundational fallback exercise for each
    /// uncovered target muscle. For each gap:
    ///   1. Walk the foundational exercises for that muscle group (sorted
    ///      essential → variety) looking for a name match in the live catalog.
    ///   2. Filter foundational candidates by user equipment (don't suggest
    ///      a barbell calf raise to a home user with no barbell).
    ///   3. Find the lowest-scored slot in the existing workout that does NOT
    ///      already cover one of the original target muscles uniquely (so
    ///      we don't strip the only chest exercise to add a calf raise on
    ///      a chest day) and swap it.
    ///   4. If no foundational fallback is found, emit `AppLogger.warning`
    ///      so the production gap is observable instead of silent.
    ///
    /// Returns the (possibly-mutated) selected list. Compound-first ordering
    /// is re-applied by the caller AFTER this swap pass.
    private func attemptCoverageSwap(
        selected: [SmartSelectedExercise],
        uncoveredMuscles: [String],
        userEquipment: [String],
        allExercises: [Exercise]
    ) -> [SmartSelectedExercise] {
        var working = selected
        let userEquipNorm = Set(userEquipment.map { $0.lowercased() })
        let foundationalDB = FoundationalExerciseDatabase.shared

        for target in uncoveredMuscles {
            guard let muscleGroup = mapTargetToFoundationalMuscleGroup(target) else {
                AppLogger.warning(
                    "[COVERAGE] Target muscle '\(target)' has no foundational mapping — cannot swap in fallback. Workout shipped without coverage.",
                    category: .workout
                )
                continue
            }

            // Pull foundational exercises for this muscle group, sorted by
            // tier (essential first — most universally recognized).
            let foundationalCandidates = foundationalDB.getFoundationalExercises(for: muscleGroup)
                .sorted { $0.tier.rawValue < $1.tier.rawValue }

            // Find the first foundational exercise that exists in the live
            // catalog AND matches the user's equipment.
            var swapInExercise: Exercise?
            for candidate in foundationalCandidates {
                // Equipment gate: only suggest a foundational that the user
                // can actually perform. Bodyweight is always allowed.
                let candidateEquip = candidate.equipment.rawValue.lowercased()
                let userHasEquipment = candidateEquip == "bodyweight"
                    || userEquipNorm.contains(candidateEquip)
                    || userEquipNorm.contains(where: { $0.contains(candidateEquip) || candidateEquip.contains($0) })
                guard userHasEquipment else { continue }

                // Try the canonical name first, then alternate names.
                let candidateNames = [candidate.name] + candidate.alternateNames
                for nameToTry in candidateNames {
                    if let live = ExerciseLibraryService.shared.getExercise(byName: nameToTry) {
                        swapInExercise = live
                        break
                    }
                }
                if swapInExercise != nil { break }

                // Last-ditch: substring scan of `allExercises` for the
                // canonical name (handles "Standing Calf Raise" → "Calf Raise
                // (Machine)" mismatch in the live catalog).
                let needle = candidate.name.lowercased()
                if let match = allExercises.first(where: {
                    let nameLower = ($0.name ?? "").lowercased()
                    return nameLower.contains(needle) || needle.contains(nameLower)
                }) {
                    swapInExercise = match
                    break
                }
            }

            guard let swapIn = swapInExercise else {
                AppLogger.warning(
                    "[COVERAGE] No foundational fallback found for uncovered target muscle '\(target)' (group: \(muscleGroup.rawValue)) given user equipment \(userEquipment). Workout shipped without coverage — extend FoundationalExerciseDatabase.\(muscleGroup.rawValue)Exercises or audit the catalog.",
                    category: .workout
                )
                continue
            }

            // Find the lowest-scored slot to evict. Skip slots whose primary
            // muscle uniquely covers another target — we don't want to drop
            // the only chest exercise on a chest+calves day.
            let evictIndex = lowestScoredEvictableIndex(in: working, protecting: uncoveredMuscles)
            guard let idx = evictIndex else {
                AppLogger.warning(
                    "[COVERAGE] All slots are protected primary-muscle covers — cannot evict to add '\(swapIn.name ?? "?")' for '\(target)'. Workout will ship under-covered.",
                    category: .workout
                )
                continue
            }

            let evicted = working[idx]
            let pattern = classifyMovementPattern(
                exerciseName: swapIn.name ?? "",
                muscles: (swapIn.getMuscleGroups() ?? []).joined(separator: ",").lowercased()
            )
            let exerciseType: ExerciseType = swapIn.isCompound ? .compound : .isolation
            let replacement = SmartSelectedExercise(
                exercise: swapIn,
                score: max(0, evicted.score - 1),  // Below evicted so subsequent sorts don't re-ordering it ahead of higher-merit picks.
                movementPattern: pattern,
                exerciseType: exerciseType
            )
            working[idx] = replacement
            AppLogger.info(
                "[COVERAGE] Swapped '\(evicted.name)' (score \(Int(evicted.score))) → '\(swapIn.name ?? "?")' to cover target muscle '\(target)' (group: \(muscleGroup.rawValue))",
                category: .workout
            )
        }
        return working
    }

    /// Maps a target-muscle string from the workout slot to a foundational
    /// muscle group enum. Returns nil for unmapped strings — caller logs.
    private func mapTargetToFoundationalMuscleGroup(_ target: String) -> FoundationalMuscleGroup? {
        let t = target.lowercased()
        if t.contains("calf") || t.contains("calves") || t.contains("lower leg") { return .calves }
        if t.contains("quad") || t.contains("thigh") { return .quads }
        if t.contains("hamstring") { return .hamstrings }
        if t.contains("glute") || t.contains("hip") { return .glutes }
        if t.contains("chest") || t.contains("pec") { return .chest }
        if t.contains("back") || t.contains("lat") || t.contains("rhomboid") { return .back }
        if t.contains("shoulder") || t.contains("delt") { return .shoulders }
        if t.contains("bicep") { return .biceps }
        if t.contains("tricep") { return .triceps }
        if t.contains("core") || t.contains("ab") || t.contains("oblique") { return .core }
        return nil
    }

    /// Finds the index of the lowest-scored exercise eligible for eviction.
    /// "Eligible" = the exercise's primary muscle is already double-covered
    /// or is not a uniquely-covered target. Returns nil if every slot is the
    /// sole cover for some target muscle.
    private func lowestScoredEvictableIndex(
        in selected: [SmartSelectedExercise],
        protecting uncoveredMuscles: [String]
    ) -> Int? {
        // Build the cover histogram: for each target muscle in the existing
        // selection, count how many slots cover it.
        var coverCounts: [String: Int] = [:]
        for ex in selected {
            for muscle in (ex.exercise.getMuscleGroups() ?? []) {
                let key = muscle.lowercased()
                coverCounts[key, default: 0] += 1
            }
        }
        // Identify "protected" indices (slots that are the SOLE cover of some
        // muscle). We never evict these.
        var protectedIndices = Set<Int>()
        for (i, ex) in selected.enumerated() {
            for muscle in (ex.exercise.getMuscleGroups() ?? []) {
                let key = muscle.lowercased()
                if (coverCounts[key] ?? 0) == 1 {
                    protectedIndices.insert(i)
                    break
                }
            }
        }

        // Among non-protected slots, return the index of the lowest-scored.
        let evictable = selected.enumerated().filter { !protectedIndices.contains($0.offset) }
        guard let target = evictable.min(by: { $0.element.score < $1.element.score }) else {
            // All slots protected — fall back to the absolute lowest-scored
            // (better to under-cover one muscle than ship a workout missing
            // a promised target). Safer than returning nil.
            return selected.indices.min(by: { selected[$0].score < selected[$1].score })
        }
        return target.offset
    }

    // MARK: - Practicality Assessment
    
    struct PracticalityResult {
        let shouldExclude: Bool
        let scoreModifier: Double
        let reason: String
    }
    
    /// Assesses how "realistic" and practical an exercise is for most users
    /// Filters out exotic, dangerous, or impractical exercises while boosting common ones
    ///
    /// `userAge` was added in the 2026-05-08 Round 3 audit pass to support the
    /// 65+ decline-angle block (user-26, 68y, was served 4× decline chest).
    /// Default `0` keeps legacy callers compatible — the age check no-ops at 0.
    ///
    /// `completedWorkoutCount` (default 0) is consumed by the
    /// `SpecialtyVariantFilter` for `.blockUntilEstablished` patterns —
    /// grip / unilateral / stability progression variants unlock once the
    /// user has crossed the per-level threshold. Audit synthetic users
    /// keep the default of 0 (always blocked); live-app callers pass the
    /// real count from `ProgressiveUnlockCache.shared.workoutCount`.
    private func assessExercisePracticality(
        exerciseName: String,
        experienceLevel: String,
        isGymUser: Bool,
        userAge: Int = 0,
        completedWorkoutCount: Int = 0
    ) -> PracticalityResult {
        let name = exerciseName.lowercased()
        let isBeginnerOrIntermediate = experienceLevel.lowercased() != "advanced"

        // ════════════════════════════════════════════════════════════════════════════
        // 🚨 SAFETY (Audit 2026-05-08 fix #3 — user-26 incident, 68y + 4× decline chest)
        // Decline angle places the head below the heart, which elevates intracranial
        // pressure and systolic blood pressure to the head/eyes. For users 65+, the
        // cardiovascular / stroke risk outweighs the chest-development upside —
        // canonical replacement is a flat or low-incline press at the same loading.
        // ════════════════════════════════════════════════════════════════════════════
        if userAge >= 65 && name.contains("decline") {
            return PracticalityResult(
                shouldExclude: true,
                scoreModifier: 0,
                reason: "Decline-angle exercise blocked for users 65+ — increases intracranial pressure / blood pressure to head"
            )
        }

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
        
        // Obscure/rare exercises most people don't know.
        // Audit 2026-05-08 expansion: added TRX power-pull, kneeling/single-arm cable variants,
        // hybrid plank+leg-extension/march variants, deep-squat-rotation, pallof-twist, lunge-with-
        // internal-rotation, and other "ribbon-cutting / mobility-flow" hybrids that Claude flagged
        // as unsuitable for beginners/intermediates in the 20-user audit.
        let obscureExercises = [
            // Existing
            "zottman", "svend", "jefferson", "zercher", "steinborn",
            "turkish get", "windmill", "sots press", "bradford press",
            "cuban press", "waiter curl", "guillotine press",
            // 2026-05-08 additions — TRX / suspension obscure variants
            "trx power pull", "power pull",
            "trx atomic", "atomic push",
            "trx clock press", "clock press",
            "trx hip press", "trx hip drop",
            // 2026-05-08 additions — hybrid plank / mobility-flow obscure variants
            "leg extension plank", "plank with leg extension",
            "reverse plank march", "reverse plank with march",
            "deep squat turn", "squat with rotation and",  // multi-step flow
            "lunge with internal rotation",
            "pallof twist", "pallof press twist",
            // 2026-05-08 additions — uncommon cable/kneeling variants
            "kneeling pallof", "tall kneeling cable",  // tall-kneeling stability work is specialty
            "high low cable chop", "low to high chop",  // unless explicitly requested
            // 2026-05-08 additions — eccentric-only / partial / overcoming-isometric variants
            "overcoming isometric", "yielding isometric",
            "anti rotation", "anti-rotation hold",  // pallof-equivalent hold
            // Specialty hybrid lower-body
            "cossack squat", "shrimp squat", "skater squat",
            "single leg deadlift to row", "deadlift to row",  // overly complex hybrid
            // Niche shoulder
            "scaption", "scaption raise",  // sub-specialty front/lateral combo
            "klokov press", "rdl to press"  // hybrid lift
        ]
        if isBeginnerOrIntermediate && obscureExercises.contains(where: { name.contains($0) }) {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Obscure exercise")
        }

        // ════════════════════════════════════════════════════════════════════════════
        // COMPLEX-HYBRID NAME DETECTION (Audit 2026-05-08 fix #10)
        // ════════════════════════════════════════════════════════════════════════════
        // Block multi-action exercise names like "Squat to Press to Curl" or "Lunge and
        // Twist and Reach" for non-Advanced users. These are flow / mobility-circuit
        // exercises that don't belong in a strength autogen — they overload the lifter
        // with cues and are usually a worse expression of each component movement.
        //
        // Heuristic:
        //   1. Names containing TWO OR MORE " to " connectors → multi-stage hybrid
        //      (e.g. "Squat to Press to Curl"). One " to " is fine ("Single-Leg
        //      Deadlift to Row" is borderline; we already block the latter via the
        //      obscure list).
        //   2. Names containing " and " followed later by another " and "
        //      (e.g. "Lunge and Twist and Reach").
        //   3. Names with FOUR OR MORE hyphens (e.g. "Side-Lying-Hip-Drop-with-Leg-Lift")
        //      — usually indicates an over-described mobility variant.
        //
        // 2026-05-08 audit fix — Advanced users were also getting catalog-corrupted
        // hybrid entries like "Romanian Deadlift Bicep Curl Kickback" and "Curl Press
        // Extension". These are not legitimate Advanced flow work; they're database
        // junk. Apply the filter to ALL levels, with a stricter movement-noun count
        // check to catch the no-separator hybrids that slipped past the original heuristic.
        let toCount = name.components(separatedBy: " to ").count - 1
        let andCount = name.components(separatedBy: " and ").count - 1
        let hyphenCount = name.filter { $0 == "-" }.count

        let movementNouns: Set<String> = [
            "deadlift", "squat", "lunge", "press", "curl", "row", "fly", "flye",
            "raise", "kickback", "extension", "crunch", "twist", "swing",
            "snatch", "clean", "jerk", "pulldown", "pressdown", "thrust",
            "pushdown", "shrug", "tuck", "march", "carry", "fold", "reach",
            // Bigram movements collapsed to single tokens via _BIGRAM_REWRITES
            "pushup", "pullup", "chinup", "situp", "stepup", "kneeup",
            "thruster", "burpee"
        ]

        // Audit Round 4 fix — collapse bigram movements ("Push Up" → "pushup")
        // BEFORE token analysis so names like "Push Up - Tricep Extension"
        // register movement noun on both sides of the separator.
        var normalized = name
        let bigramRewrites: [(String, String)] = [
            (" push up", " pushup"), (" push-up", " pushup"),
            (" pull up", " pullup"), (" pull-up", " pullup"),
            (" chin up", " chinup"), (" chin-up", " chinup"),
            (" sit up", " situp"),  (" sit-up", " situp"),
            (" step up", " stepup"), (" step-up", " stepup"),
            (" knee up", " kneeup"),
            (" knee tuck", " tuck")
        ]
        let padded = " " + name + " "
        normalized = padded
        for (src, dst) in bigramRewrites {
            normalized = normalized.replacingOccurrences(of: src, with: dst)
        }
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        let nameTokens = normalized.split(separator: " ").map { String($0) }
        let movementNounHits: Set<String> = Set(nameTokens.filter { movementNouns.contains($0) })

        let advancedHyphenCap = 4
        let nonAdvancedHyphenCap = 3
        let hyphenCap = isBeginnerOrIntermediate ? nonAdvancedHyphenCap : advancedHyphenCap

        // " - " separator with a movement noun on BOTH sides — catalog-corrupted
        // hybrid (e.g. "Push Up - Tricep Extension" → pushup | extension).
        // Audit Round 4: this caught hybrid names that have only 2 movement
        // nouns (so the >=3 token rule misses them) but ARE clearly two
        // exercises mashed together.
        var isHyphenSeparatorHybrid = false
        for sep in [" - ", " – ", " — "] {
            if normalized.contains(sep) {
                let parts = normalized.components(separatedBy: sep)
                if parts.count >= 2 {
                    let leftTokens = parts[0].split(separator: " ").map { String($0) }
                    let rightTokens = parts[1].split(separator: " ").map { String($0) }
                    let leftHasMove = leftTokens.contains(where: { movementNouns.contains($0) })
                    let rightHasMove = rightTokens.contains(where: { movementNouns.contains($0) })
                    if leftHasMove && rightHasMove {
                        isHyphenSeparatorHybrid = true
                        break
                    }
                }
            }
        }

        let isMultiStageHybrid =
            toCount >= 2 ||
            andCount >= 2 ||
            hyphenCount >= hyphenCap ||
            movementNounHits.count >= 3 ||  // "Deadlift Curl Kickback" → 3 distinct movement nouns
            isHyphenSeparatorHybrid          // "Push Up - Tricep Extension"
        if isMultiStageHybrid {
            return PracticalityResult(shouldExclude: true, scoreModifier: 0, reason: "Complex multi-stage hybrid name")
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
        // SPECIALTY VARIANT FILTER
        // ════════════════════════════════════════════════════════════════════════════
        // A SPECIALTY VARIANT is a base exercise + programming modifier that
        // requires the lifter to already own the canonical version. Common
        // examples slipping through before this filter existed:
        //   - "Feet On Bench Bench Press"  (specialty stability variant of bench)
        //   - "Pause Squat" / "Tempo Squat" (specialty cadence variants)
        //   - "Pendlay Row" / "Yates Row"   (specialty bent-over row variants)
        //   - "Bicep Curl 21s"              (specialty rep-scheme variant)
        //
        // Authority + canonical pattern list: `scripts/specialty_exercise_filter.py`
        // — when adding/removing a pattern, MIRROR the change in BOTH places. The
        // Python audit simulator (`scripts/autogen_audit_simulator.py`) reads from
        // that module and surfaces residual slips in its .md report.
        //
        // Severity bands:
        //   - .blockBeginner     → never recommend to a Beginner
        //   - .blockIntermediate → block Beginner AND Intermediate
        //   - .blockAll          → block every level (auto-recommend only — still
        //                          available via search/manual add)
        let isIntermediate = experienceLevel.lowercased() == "intermediate"
        if let specialtyResult = SpecialtyVariantFilter.evaluate(
            name: name,
            isBeginner: isBeginner,
            isIntermediate: isIntermediate,
            completedWorkoutCount: completedWorkoutCount
        ) {
            return specialtyResult
        }

        // ════════════════════════════════════════════════════════════════════════════
        // TECHNIQUE-EQUIPMENT MISMATCH (Audit 2026-05-08 Round 3 fix #6)
        // ════════════════════════════════════════════════════════════════════════════
        // Some training techniques are inherently barbell- (or dumbbell-) only and
        // make no biomechanical sense paired with cable / machine / band / smith /
        // kettlebell / TRX equipment. The Round 3 50-user audit caught two
        // "Pendlay Row (Cable)" workouts (user-19, user-41) — Pendlay Row is a
        // dead-stop powerlifting variant where the bar resets on the floor every
        // rep; a cable column has no floor reset, no horizontal pull plane, no
        // explosive concentric. Same logic for Jefferson curl (loaded spinal
        // flexion over the bar), Zercher squat (bar held in elbow crooks), Clean
        // Grip front squat / lunge (Olympic-lifting grip on a bar), and Snatch
        // Grip pulls.
        //
        // Pattern: technique keyword is present AND equipment is NOT barbell or
        // dumbbell → the exercise is a catalog-corruption artifact (someone
        // copy-pasted the technique name to a cable/machine variant). Hard
        // exclude.
        //
        // Equipment is detected from the canonical "(Equipment)" suffix the live
        // catalog uses (e.g. "Pendlay Row (Cable)") — assessExercisePracticality
        // doesn't currently take an equipment param, and we don't want to widen
        // the signature for a single check. Falls back to substring scan if the
        // suffix is missing.
        let barbellTechniques = ["pendlay", "jefferson", "zercher", "clean grip", "snatch grip"]
        if let technique = barbellTechniques.first(where: { name.contains($0) }) {
            // Pull the parenthesized equipment suffix if present. Catalog
            // convention: "<Name> (<Equipment>)" for variant rows.
            let suffixEquip: String? = {
                guard let openParen = name.lastIndex(of: "("),
                      let closeParen = name.lastIndex(of: ")"),
                      openParen < closeParen else { return nil }
                let afterOpen = name.index(after: openParen)
                return String(name[afterOpen..<closeParen]).trimmingCharacters(in: .whitespaces)
            }()
            // Allowed equipment for these techniques: free weights only.
            let allowedEquipment: Set<String> = ["barbell", "dumbbell"]
            let detectedEquipment: String = suffixEquip ?? ""
            // If we have an explicit suffix, trust it. Otherwise scan the full
            // name for the allowed-equipment tokens.
            let isOnAllowedEquipment: Bool = {
                if !detectedEquipment.isEmpty {
                    return allowedEquipment.contains(where: { detectedEquipment.contains($0) })
                }
                return allowedEquipment.contains(where: { name.contains($0) })
            }()
            if !isOnAllowedEquipment {
                let equipDescriptor = detectedEquipment.isEmpty ? "non-barbell equipment" : detectedEquipment
                return PracticalityResult(
                    shouldExclude: true,
                    scoreModifier: 0,
                    reason: "Technique-equipment mismatch — '\(technique)' is a barbell technique, not appropriate for \(equipDescriptor)"
                )
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

// MARK: - Specialty Variant Filter
// ═══════════════════════════════════════════════════════════════════════════
// SPECIALTY / VARIANT EXERCISE FILTER
// ═══════════════════════════════════════════════════════════════════════════
//
// The user-visible bug this fixes: an unmodified beginner sees "Feet On
// Bench Bench Press" or "Pause Squat" recommended before the regular Bench
// Press / Squat. Those are SPECIALTY VARIANTS — exercises that combine a
// base movement with a modifier (tempo / pause / deficit / feet up / 21s /
// etc.). Valid for intermediate/advanced lifters who already own the base
// movement; never auto-recommend them to a beginner ahead of the canonical
// version.
//
// CANONICAL SOURCE: `scripts/specialty_exercise_filter.py` is the single
// source of truth. When you add/remove a pattern:
//   1. Update SPECIALTY_PATTERNS in scripts/specialty_exercise_filter.py
//      (and add a fixture to its self-test).
//   2. Update SpecialtyVariantFilter.patterns below with the same lowercased
//      substring + base movement + severity.
//   3. Re-run `python3 scripts/specialty_exercise_filter.py`.
//   4. Re-run `python3 scripts/autogen_audit_simulator.py --users 100` to
//      confirm the live app and the audit agree.
//
// Authority: Fitness Expert + Product Engineer agents (see
// FITNESS_EXPERT_AGENT.md invariant on specialty variants).

enum SpecialtyVariantFilter {

    enum Severity {
        case blockBeginner             // never recommend to a Beginner
        case blockIntermediate         // block Beginner AND Intermediate
        case blockUntilEstablished     // block at every level UNTIL the user
                                        // has completed `workoutCountThresholds[level]`
                                        // workouts (audit users are always at 0)
        case blockAll                  // block every level (auto-recommend only)
    }

    /// Workout-count threshold by experience level. The
    /// `.blockUntilEstablished` severity unlocks once the user crosses
    /// the threshold for their level. Audit users are always at count=0
    /// → grip / unilateral / stability progression variants are always
    /// blocked in the audit. Live-app users earn the unlock with
    /// completed workouts (sourced from `ProgressiveUnlockCache`).
    static let workoutCountThresholds: [String: Int] = [
        "beginner":     12,    // ~4 weeks @ 3x/week
        "intermediate":  8,    // ~3 weeks
        "advanced":      4,    // ~1.5 weeks (still earn it)
    ]

    struct Pattern {
        let substring: String
        let baseMovement: String
        let severity: Severity
        let rationale: String
    }

    /// Pattern registry — first-match wins. Keep specific (longer) patterns
    /// BEFORE generic modifiers. We test against ` exercise.name.lowercased() `
    /// padded with a leading + trailing space so single-word patterns match
    /// at word boundaries.
    static let patterns: [Pattern] = [
        // ── Kettlebell combo family (.blockAll — must come FIRST) ──
        // Multi-movement KB hybrids ("Swing To Goblet Squat", "Swing Clean
        // Grip Front Squat") combine swing + landed exercise + grip-modifier.
        // These are catalog-corruption combos — never autogen. Listed BEFORE
        // bench/squat so "Swing Clean Grip Front Squat" matches "swing clean
        // grip" (BLOCK_ALL) instead of fragments like "clean grip".
        Pattern(substring: "swing clean grip", baseMovement: "kb_combo", severity: .blockAll,
                rationale: "Swing-clean-grip-X is a multi-movement KB hybrid — catalog corruption"),
        Pattern(substring: "swing to ", baseMovement: "kb_combo", severity: .blockAll,
                rationale: "KB swing-to-X is a mobility-flow combo — base swing and target movement should be separate"),

        // ── Bench Press family ──
        Pattern(substring: "feet on bench", baseMovement: "bench_press", severity: .blockBeginner,
                rationale: "Feet-elevated bench is a specialty stability variant — never the first bench press shown to a beginner"),
        Pattern(substring: "feet up", baseMovement: "bench_press", severity: .blockBeginner,
                rationale: "Feet-up bench removes leg drive — specialty variant"),
        Pattern(substring: "feet elevated", baseMovement: "bench_press", severity: .blockBeginner,
                rationale: "Feet-elevated bench — specialty stability variant"),
        Pattern(substring: "legs raised", baseMovement: "bench_press", severity: .blockBeginner,
                rationale: "Legs-raised bench — specialty stability variant"),
        Pattern(substring: "spoto press", baseMovement: "bench_press", severity: .blockIntermediate,
                rationale: "Spoto press = pause 1-2\" off chest — competition powerlifting specialty"),
        Pattern(substring: "pin press", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Pin press = bottom-position deadstop — show regular bench first regardless of level (audit Round 4: Intermediate user got 'Pin Bench Press Conventional Grip')"),
        Pattern(substring: "pin bench press", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Pin bench press is a specialty deadstop variant — show regular bench first regardless of level"),
        Pattern(substring: "squeeze press", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Squeeze press = chest-squeeze isometric DB press — specialty technique requiring mind-muscle mastery (audit Round 4: 3 instances flagged)"),
        Pattern(substring: "squeeze bench", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Squeeze bench press — specialty technique variant"),
        Pattern(substring: "dead stop bench", baseMovement: "bench_press", severity: .blockIntermediate,
                rationale: "Dead-stop bench — specialty pause variant"),
        Pattern(substring: "paused bench", baseMovement: "bench_press", severity: .blockBeginner,
                rationale: "Paused bench is a powerlifting specialty"),
        Pattern(substring: "long pause", baseMovement: "bench_press", severity: .blockIntermediate,
                rationale: "Long-pause bench — specialty"),
        Pattern(substring: "board press", baseMovement: "bench_press", severity: .blockIntermediate,
                rationale: "Board press = partial range, requires equipment — specialty"),
        Pattern(substring: "slingshot", baseMovement: "bench_press", severity: .blockIntermediate,
                rationale: "Slingshot bench requires the slingshot tool — specialty"),
        Pattern(substring: "guillotine", baseMovement: "bench_press", severity: .blockAll,
                rationale: "Guillotine press = bar to neck — high shoulder injury risk, never auto-recommend"),
        Pattern(substring: "jm press", baseMovement: "bench_press", severity: .blockIntermediate,
                rationale: "JM press is a specialty triceps-bench hybrid"),
        // ── Grip-progression bench variants (.blockUntilEstablished) ──
        // Audit Round 3 (2026-05-08): grip-emphasis variants must NEVER be
        // the first bench press an autogen recommends, regardless of level.
        // Unlocks once the user crosses the per-level workout-count threshold.
        Pattern(substring: "close grip incline", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Close-grip incline — grip-progression variant; show regular incline first"),
        Pattern(substring: "reverse grip", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Reverse-grip bench requires wrist mobility — grip-progression variant"),
        Pattern(substring: "wide grip bench", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Wide-grip bench — grip-progression variant; show regular grip first"),
        Pattern(substring: "wide bench press", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Wide bench press (no 'grip' in name) — grip-progression variant"),
        Pattern(substring: "close grip bench press", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Close-grip bench shifts emphasis to triceps — grip-progression variant"),
        Pattern(substring: "bench press - close grip", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Close-grip bench (DB/SM/BB variant) — grip-progression variant"),
        Pattern(substring: "decline bench press - wide grip", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Wide-grip decline — multi-modifier specialty"),
        Pattern(substring: "3 point bench", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "3-Point bench is an unstable specialty variant — show regular bench first"),
        Pattern(substring: "reverse close grip", baseMovement: "bench_press", severity: .blockUntilEstablished,
                rationale: "Reverse close-grip bench is a multi-modifier specialty — show regular bench first"),

        // ── Squat family ──
        Pattern(substring: "deficit squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "Deficit squat = standing on a plate — specialty range-extension variant"),
        Pattern(substring: "paused squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "Paused squat = bottom-position pause — specialty"),
        Pattern(substring: "pause squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "Pause squat — specialty"),
        Pattern(substring: "anderson squat", baseMovement: "squat", severity: .blockIntermediate,
                rationale: "Anderson squat = bottom-up from pins — specialty"),
        Pattern(substring: "1 1/4 squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "1 1/4 rep squat — specialty tempo variant"),
        Pattern(substring: "1.5 squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "1.5-rep squat — specialty"),
        Pattern(substring: "tempo squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "Tempo-prescribed squat — specialty"),
        Pattern(substring: "pin squat", baseMovement: "squat", severity: .blockIntermediate,
                rationale: "Pin squat — specialty"),
        Pattern(substring: "box squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "Box squat is a specialty depth-controlled variant — show regular squat first"),
        Pattern(substring: "zercher", baseMovement: "squat", severity: .blockIntermediate,
                rationale: "Zercher squat — specialty / advanced"),
        Pattern(substring: "jefferson", baseMovement: "squat", severity: .blockIntermediate,
                rationale: "Jefferson squat / deadlift — specialty / unusual"),
        Pattern(substring: "sissy squat", baseMovement: "squat", severity: .blockBeginner,
                rationale: "Sissy squat = knee-extension under load — specialty / knee stress"),
        Pattern(substring: "heels elevated", baseMovement: "squat", severity: .blockBeginner,
                rationale: "Heels-elevated squat — specialty quad emphasis variant"),
        // 2026-05-08 audit additions
        Pattern(substring: "deep squat turn", baseMovement: "squat", severity: .blockAll,
                rationale: "Deep squat with rotation = mobility-flow hybrid; never an autogen strength pick at any level"),
        Pattern(substring: "lunge with internal rotation", baseMovement: "squat", severity: .blockAll,
                rationale: "Lunge + internal hip rotation = mobility-flow specialty; never appropriate for autogen strength workouts"),
        // ── Round 3 audit additions: Olympic / grip / stability progression variants ──
        // (.blockUntilEstablished — unlocks once the user has completed N workouts)
        Pattern(substring: "clean grip", baseMovement: "squat", severity: .blockUntilEstablished,
                rationale: "Clean-grip front squat is an Olympic-lifting technique variant — grip progression"),
        // 2026-05-08 audit Round 4 — Olympic-derivative WITHOUT the word "Grip"
        // (catalog name "Front Squat - Clean (Barbell)" doesn't contain "Grip"
        // and was bypassing the `clean grip` pattern).
        Pattern(substring: "squat - clean", baseMovement: "squat", severity: .blockUntilEstablished,
                rationale: "Olympic-derivative '<Squat> - Clean' is a technique variant requiring Olympic coaching; show regular squat first"),
        Pattern(substring: "front squat clean", baseMovement: "squat", severity: .blockUntilEstablished,
                rationale: "Front-squat-clean (no separator) — Olympic-derivative technique variant"),
        Pattern(substring: "elevated goblet", baseMovement: "squat", severity: .blockUntilEstablished,
                rationale: "Elevated goblet squat is a stability/depth specialty"),
        Pattern(substring: "front foot elevated", baseMovement: "squat", severity: .blockUntilEstablished,
                rationale: "Front-foot-elevated split squat is a deficit specialty"),
        Pattern(substring: "single leg press", baseMovement: "squat", severity: .blockUntilEstablished,
                rationale: "Single-leg press is a unilateral stability specialty — show bilateral leg press first"),
        Pattern(substring: "split squat front foot elevated", baseMovement: "squat", severity: .blockUntilEstablished,
                rationale: "Front-foot-elevated split squat is a stability/deficit specialty"),
        // ── Round 3 audit additions: catalog-corrupted combo movements (.blockAll) ──
        // Listed BEFORE other squat patterns so multi-keyword names match the
        // BLOCK_ALL combo first instead of fragments like "clean grip".
        // Note: KB combos (swing to/swing clean grip) are handled by the
        // separate KETTLEBELL_COMBO block placed at the top of `patterns`.
        Pattern(substring: "reverse lunge forward lunge", baseMovement: "lunge", severity: .blockAll,
                rationale: "Reverse-lunge-forward-lunge is a catalog-corrupted combo movement — never autogen at any level"),

        // ── Deadlift family ──
        Pattern(substring: "deficit deadlift", baseMovement: "deadlift", severity: .blockIntermediate,
                rationale: "Deficit deadlift — specialty range-extension"),
        Pattern(substring: "snatch grip deadlift", baseMovement: "deadlift", severity: .blockIntermediate,
                rationale: "Snatch-grip deadlift — specialty grip variant"),
        Pattern(substring: "block pull", baseMovement: "deadlift", severity: .blockIntermediate,
                rationale: "Block pulls = elevated deadlift from blocks — specialty"),
        Pattern(substring: "paused deadlift", baseMovement: "deadlift", severity: .blockIntermediate,
                rationale: "Paused deadlift — specialty"),
        Pattern(substring: "tempo deadlift", baseMovement: "deadlift", severity: .blockIntermediate,
                rationale: "Tempo deadlift — specialty"),
        Pattern(substring: "reset deadlift", baseMovement: "deadlift", severity: .blockIntermediate,
                rationale: "Reset every rep — specialty"),
        Pattern(substring: "touch and go", baseMovement: "deadlift", severity: .blockIntermediate,
                rationale: "Touch-and-go deadlift — specialty cadence"),
        Pattern(substring: "stiff leg", baseMovement: "deadlift", severity: .blockBeginner,
                rationale: "Stiff-leg deadlift — high low-back stress, specialty for beginners"),
        Pattern(substring: "trap bar", baseMovement: "deadlift", severity: .blockBeginner,
                rationale: "Trap-bar deadlift is great but show regular deadlift FIRST when introducing the pattern"),
        // 2026-05-08 audit additions
        Pattern(substring: "rack pull", baseMovement: "deadlift", severity: .blockUntilEstablished,
                rationale: "Rack pull = elevated partial deadlift — show full deadlift first regardless of level (audit Round 4: Intermediate user got 'Rack Pull (Smith Machine)')"),

        // ── Row family ──
        // Technique-progression variants (.blockUntilEstablished) — unlock once
        // the user has completed N workouts at their level. Even Advanced lifters
        // shouldn't see Pendlay Row in their first autogen workout — they earn it.
        Pattern(substring: "yates row", baseMovement: "row", severity: .blockUntilEstablished,
                rationale: "Yates row = supinated bent row — technique-progression variant"),
        Pattern(substring: "pendlay row", baseMovement: "row", severity: .blockUntilEstablished,
                rationale: "Pendlay row = strict dead-stop row — technique-progression variant"),
        Pattern(substring: "meadows row", baseMovement: "row", severity: .blockUntilEstablished,
                rationale: "Meadows row = unilateral landmine variant — technique-progression variant"),
        Pattern(substring: "kroc row", baseMovement: "row", severity: .blockUntilEstablished,
                rationale: "Kroc row = ultra-high-rep heavy DB row — technique-progression variant"),
        // Tempo / pause prescription variants (.blockBeginner — keeps standard cadence default)
        Pattern(substring: "paused row", baseMovement: "row", severity: .blockBeginner,
                rationale: "Paused row — specialty tempo"),
        Pattern(substring: "tempo row", baseMovement: "row", severity: .blockBeginner,
                rationale: "Tempo row — specialty"),

        // ── Curl family ──
        Pattern(substring: " 21s", baseMovement: "curl", severity: .blockBeginner,
                rationale: "21s = partial-rep set scheme — specialty programming"),
        Pattern(substring: "21s curl", baseMovement: "curl", severity: .blockBeginner,
                rationale: "21s curl — specialty"),
        Pattern(substring: "drag curl", baseMovement: "curl", severity: .blockBeginner,
                rationale: "Drag curl — specialty (elbow path is unintuitive for beginners)"),
        Pattern(substring: "zottman", baseMovement: "curl", severity: .blockBeginner,
                rationale: "Zottman curl = curl + reverse-curl combo — specialty"),
        Pattern(substring: "waiter curl", baseMovement: "curl", severity: .blockIntermediate,
                rationale: "Waiter curl — specialty"),
        Pattern(substring: "bayesian curl", baseMovement: "curl", severity: .blockIntermediate,
                rationale: "Bayesian curl = behind-body cable curl — specialty"),

        // ── OHP family ──
        Pattern(substring: "z press", baseMovement: "ohp", severity: .blockIntermediate,
                rationale: "Z-press = floor-seated press — specialty"),
        Pattern(substring: "savickas press", baseMovement: "ohp", severity: .blockIntermediate,
                rationale: "Savickas press — specialty"),
        Pattern(substring: "bradford press", baseMovement: "ohp", severity: .blockIntermediate,
                rationale: "Bradford press = front-to-back press — specialty"),
        Pattern(substring: "cuban press", baseMovement: "ohp", severity: .blockIntermediate,
                rationale: "Cuban press — specialty rotator cuff sequence"),
        Pattern(substring: "sots press", baseMovement: "ohp", severity: .blockIntermediate,
                rationale: "Sots press = press from bottom of squat — specialty"),
        Pattern(substring: "viking press", baseMovement: "ohp", severity: .blockIntermediate,
                rationale: "Viking press requires landmine attachment — specialty"),
        Pattern(substring: "landmine press", baseMovement: "ohp", severity: .blockBeginner,
                rationale: "Landmine press is fine but show regular OHP variants first"),

        // ── Core / oblique family (2026-05-08 audit additions) ──
        // Pallof-press WITH rotation defeats the anti-rotation cue. Listed before
        // the shorter "pallof twist" so the longer/more-specific pattern wins.
        Pattern(substring: "pallof press twist", baseMovement: "pallof", severity: .blockAll,
                rationale: "Pallof press WITH rotation contradicts the anti-rotation cue that defines the pallof — never autogen at any level"),
        Pattern(substring: "pallof twist", baseMovement: "pallof", severity: .blockAll,
                rationale: "Pallof press WITH rotation contradicts the anti-rotation cue that defines the pallof — never autogen at any level"),
        // 2026-05-08 audit Round 3 — half-kneeling stance is an anti-rotation progression
        Pattern(substring: "half kneeling pallof", baseMovement: "pallof", severity: .blockBeginner,
                rationale: "Half-kneeling pallof press requires anti-rotation core stability — show standing pallof first for beginners"),

        // ── Plank family (2026-05-08 audit additions) ──
        Pattern(substring: "reverse plank march", baseMovement: "plank", severity: .blockAll,
                rationale: "Reverse-plank-with-marching is an obscure mobility-flow hybrid; never autogen at any level"),
        Pattern(substring: "leg extension plank", baseMovement: "plank", severity: .blockAll,
                rationale: "Leg-extension-plank is a mobility-flow hybrid, not strength; never autogen at any level"),
        // 2026-05-08 audit Round 3 — complex plank progressions
        Pattern(substring: "side bend plank", baseMovement: "plank", severity: .blockBeginner,
                rationale: "Side-bend plank is a complex plank progression — beginners should master standard plank first"),
        Pattern(substring: "elbow to knee side plank", baseMovement: "plank", severity: .blockBeginner,
                rationale: "Elbow-to-knee side plank is an advanced plank progression — beginners should master standard side plank first"),
        // 2026-05-08 audit Round 4 additions — elbow/depth/decline modifier variants.
        // BLOCK_UNTIL_ESTABLISHED so Advanced users at count=0 don't get them
        // either (user feedback: "advanced types come later when progression
        // feels correct, not premature").
        Pattern(substring: "reverse plank on elbows", baseMovement: "plank", severity: .blockUntilEstablished,
                rationale: "Reverse-plank-on-elbows is a forearm-supported variant — show standard reverse plank first regardless of level"),
        Pattern(substring: "plank on elbows", baseMovement: "plank", severity: .blockUntilEstablished,
                rationale: "Plank-on-elbows variants are scapular/forearm progressions — show standard plank first regardless of level"),

        // ── Dip / Shrug families (2026-05-08 audit Round 4) ──
        Pattern(substring: "deep dip", baseMovement: "dip", severity: .blockUntilEstablished,
                rationale: "Deep dip = below-parallel range — show standard dip first regardless of level"),
        Pattern(substring: "decline shrug", baseMovement: "shrug", severity: .blockUntilEstablished,
                rationale: "Decline shrug = lying decline trap shrug — show standard barbell/DB shrug first regardless of level"),

        // ── Pull-up family (2026-05-08 audit Round 3 additions) ──
        // Grip / equipment-context variants of the pull-up. Hammer-grip is a
        // grip-progression variant; dip-cage is a specialty equipment context.
        Pattern(substring: "hammer grip pull up", baseMovement: "pullup", severity: .blockUntilEstablished,
                rationale: "Hammer-grip pull-up — grip-progression variant; show standard pull-up/chin-up first"),
        Pattern(substring: "dip cage", baseMovement: "pullup", severity: .blockBeginner,
                rationale: "Dip-cage exercises are a specialty equipment context — beginners should master standard pull-up first"),

        // ── Generic prescription modifiers ──
        Pattern(substring: " tempo ", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Tempo-prescribed exercise — specialty rep cadence"),
        Pattern(substring: " paused ", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Paused variant — specialty"),
        Pattern(substring: "1 1/4 ", baseMovement: "generic", severity: .blockBeginner,
                rationale: "1 1/4 rep — specialty rep scheme"),
        Pattern(substring: "1.25 ", baseMovement: "generic", severity: .blockBeginner,
                rationale: "1.25 rep — specialty rep scheme"),
        Pattern(substring: "1.5 ", baseMovement: "generic", severity: .blockBeginner,
                rationale: "1.5 rep — specialty rep scheme"),
        Pattern(substring: "rest pause", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Rest-pause set — specialty intensity technique"),
        Pattern(substring: "myo-rep", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Myo-rep set — specialty intensity technique"),
        Pattern(substring: "myo rep", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Myo-rep set — specialty intensity technique"),
        Pattern(substring: "cluster set", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Cluster set — specialty intensity technique"),
        Pattern(substring: "drop set", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Drop-set prescribed in name — specialty technique"),
        Pattern(substring: "with chains", baseMovement: "generic", severity: .blockIntermediate,
                rationale: "Chain-loaded — specialty equipment"),
        Pattern(substring: "eccentric only", baseMovement: "generic", severity: .blockBeginner,
                rationale: "Eccentric-only — specialty programming"),
        Pattern(substring: "isometric hold", baseMovement: "generic", severity: .blockUntilEstablished,
                rationale: "Isometric-hold prescribed — specialty technique requiring mind-muscle mastery; never the first autogen variant of a movement (audit Round 4: Advanced user got 'Isometric Hold Push Up')"),
    ]

    /// Returns a `PracticalityResult` to short-circuit selection if the
    /// exercise is a specialty variant blocked at the caller's experience
    /// level (and progression for `.blockUntilEstablished`). Returns nil
    /// when no block applies.
    ///
    /// `name` MUST already be lowercased (matches the convention of
    /// `assessExercisePracticality()`).
    ///
    /// `completedWorkoutCount` is used by `.blockUntilEstablished`: the
    /// pattern blocks at all levels until the user crosses the per-level
    /// threshold (`workoutCountThresholds`). Audit synthetic users always
    /// pass count=0 → grip / unilateral / stability progression variants
    /// are blocked across the board.
    static func evaluate(
        name: String,
        isBeginner: Bool,
        isIntermediate: Bool,
        completedWorkoutCount: Int = 0
    ) -> SmartExerciseSelectionEngine.PracticalityResult? {
        let haystack = " \(name) "
        for pattern in patterns {
            guard haystack.contains(pattern.substring) else { continue }
            let trimmed = pattern.substring.trimmingCharacters(in: .whitespaces)
            switch pattern.severity {
            case .blockAll:
                return SmartExerciseSelectionEngine.PracticalityResult(
                    shouldExclude: true,
                    scoreModifier: 0,
                    reason: "Specialty variant '\(trimmed)' — \(pattern.rationale)"
                )
            case .blockIntermediate:
                if isBeginner || isIntermediate {
                    return SmartExerciseSelectionEngine.PracticalityResult(
                        shouldExclude: true,
                        scoreModifier: 0,
                        reason: "Specialty variant '\(trimmed)' blocked at this level — \(pattern.rationale)"
                    )
                }
            case .blockBeginner:
                if isBeginner {
                    return SmartExerciseSelectionEngine.PracticalityResult(
                        shouldExclude: true,
                        scoreModifier: 0,
                        reason: "Specialty variant '\(trimmed)' blocked for beginner — \(pattern.rationale)"
                    )
                }
            case .blockUntilEstablished:
                // Use level to look up threshold. Default to beginner threshold
                // (most conservative) when level is unrecognized.
                let levelKey: String = isBeginner ? "beginner" : (isIntermediate ? "intermediate" : "advanced")
                let threshold = workoutCountThresholds[levelKey] ?? workoutCountThresholds["beginner"]!
                if completedWorkoutCount < threshold {
                    return SmartExerciseSelectionEngine.PracticalityResult(
                        shouldExclude: true,
                        scoreModifier: 0,
                        reason: "Specialty variant '\(trimmed)' blocked until \(threshold) workouts (currently \(completedWorkoutCount)) — \(pattern.rationale)"
                    )
                }
            }
        }
        return nil
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

