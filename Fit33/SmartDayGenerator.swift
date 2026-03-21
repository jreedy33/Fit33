import Foundation
import CoreData

// MARK: - Smart Day Generator
/// Generates individual workout days with intelligent exercise selection
/// Pulls from actual exercise database, considers muscle recovery, and uses specific day titles

class SmartDayGenerator {
    static let shared = SmartDayGenerator()
    
    private let muscleRecoveryTracker = ProgramMuscleRecoveryTracker.shared
    
    private init() {}
    
    // MARK: - Day Title Templates
    /// Specific, engaging titles for each day based on program type and split
    
    struct DayTitleTemplate {
        let title: String
        let targetMuscles: [String]
        let secondaryMuscles: [String]
    }
    
    // MARK: - Get Day Titles for Split Type
    
    func getDayTitles(
        for split: DynamicProgramGenerator.GeneratedProgram.SplitType,
        programType: DynamicProgramGenerator.GeneratedProgram.ProgramType,
        daysPerWeek: Int
    ) -> [DayTitleTemplate] {
        
        switch split {
        case .pushPullLegs:
            return getPushPullLegsTitles(programType: programType, days: daysPerWeek)
        case .upperLower:
            return getUpperLowerTitles(programType: programType, days: daysPerWeek)
        case .fullBody:
            return getFullBodyTitles(programType: programType, days: daysPerWeek)
        case .broSplit:
            return getBroSplitTitles(programType: programType, days: daysPerWeek)
        case .pushPull:
            return getPushPullTitles(programType: programType, days: daysPerWeek)
        case .arnoldSplit:
            return getArnoldSplitTitles(programType: programType, days: daysPerWeek)
        }
    }
    
    // MARK: - Push/Pull/Legs Titles
    
    private func getPushPullLegsTitles(programType: DynamicProgramGenerator.GeneratedProgram.ProgramType, days: Int) -> [DayTitleTemplate] {
        var titles: [DayTitleTemplate] = []
        
        let pushTitles: [String]
        let pullTitles: [String]
        let legTitles: [String]
        
        switch programType {
        case .hypertrophy:
            pushTitles = ["Chest & Triceps Pump", "Push Power Builder", "Upper Push Hypertrophy"]
            pullTitles = ["Back & Biceps Builder", "Pull Day Mass", "Lats & Arms Volume"]
            legTitles = ["Quad & Glute Growth", "Leg Day Destroyer", "Lower Body Hypertrophy"]
        case .strength:
            pushTitles = ["Heavy Push Day", "Bench & Press Strength", "Push Power"]
            pullTitles = ["Heavy Pull Day", "Row & Deadlift Strength", "Back Power"]
            legTitles = ["Squat & Deadlift Day", "Leg Strength Builder", "Lower Power"]
        case .fatLoss:
            pushTitles = ["Push Circuit Burn", "Chest & Shoulders Torch", "Upper Push HIIT"]
            pullTitles = ["Pull Circuit Burn", "Back & Biceps Torch", "Pull Metabolic"]
            legTitles = ["Leg Burn Circuit", "Lower Body Torch", "Leg Metabolic Blast"]
        case .toning:
            pushTitles = ["Push Sculpt", "Chest & Arms Definition", "Upper Push Tone"]
            pullTitles = ["Pull Sculpt", "Back & Biceps Definition", "Pull Tone"]
            legTitles = ["Leg Sculpt", "Lower Body Definition", "Glute & Leg Tone"]
        case .generalFitness:
            pushTitles = ["Push Day", "Chest & Shoulders", "Upper Push"]
            pullTitles = ["Pull Day", "Back & Biceps", "Upper Pull"]
            legTitles = ["Leg Day", "Lower Body", "Legs & Core"]
        case .powerbuilding:
            pushTitles = ["Power Push", "Bench & Press Power", "Explosive Push"]
            pullTitles = ["Power Pull", "Row & Pull Power", "Explosive Pull"]
            legTitles = ["Power Legs", "Squat Power Day", "Explosive Legs"]
        }
        
        let cycle = ["push", "pull", "legs"]
        for i in 0..<days {
            let dayType = cycle[i % 3]
            switch dayType {
            case "push":
                titles.append(DayTitleTemplate(
                    title: pushTitles[i % pushTitles.count],
                    targetMuscles: ["Chest", "Shoulders", "Triceps"],
                    secondaryMuscles: ["Rear Delts", "Core"]
                ))
            case "pull":
                titles.append(DayTitleTemplate(
                    title: pullTitles[i % pullTitles.count],
                    targetMuscles: ["Back", "Lats", "Biceps"],
                    secondaryMuscles: ["Rear Delts", "Forearms"]
                ))
            case "legs":
                titles.append(DayTitleTemplate(
                    title: legTitles[i % legTitles.count],
                    targetMuscles: ["Quadriceps", "Hamstrings", "Glutes"],
                    secondaryMuscles: ["Calves", "Core"]
                ))
            default:
                break
            }
        }
        
        return titles
    }
    
    // MARK: - Upper/Lower Titles
    
    private func getUpperLowerTitles(programType: DynamicProgramGenerator.GeneratedProgram.ProgramType, days: Int) -> [DayTitleTemplate] {
        var titles: [DayTitleTemplate] = []
        
        let upperTitles: [String]
        let lowerTitles: [String]
        
        switch programType {
        case .hypertrophy:
            upperTitles = ["Upper Body Pump", "Chest & Back Builder", "Arms & Shoulders Volume"]
            lowerTitles = ["Leg Day Mass", "Quad & Glute Builder", "Lower Body Volume"]
        case .strength:
            upperTitles = ["Upper Strength", "Heavy Upper Day", "Bench & Row Power"]
            lowerTitles = ["Lower Strength", "Heavy Leg Day", "Squat & Deadlift"]
        case .fatLoss:
            upperTitles = ["Upper Body Burn", "Chest & Back Circuit", "Upper Metabolic"]
            lowerTitles = ["Lower Body Burn", "Leg Circuit", "Lower Metabolic"]
        case .toning:
            upperTitles = ["Upper Sculpt", "Arms & Back Tone", "Upper Definition"]
            lowerTitles = ["Lower Sculpt", "Leg & Glute Tone", "Lower Definition"]
        case .generalFitness:
            upperTitles = ["Upper Body Day", "Chest, Back & Arms", "Upper Workout"]
            lowerTitles = ["Lower Body Day", "Legs & Core", "Lower Workout"]
        case .powerbuilding:
            upperTitles = ["Upper Power", "Heavy Upper", "Explosive Upper"]
            lowerTitles = ["Lower Power", "Heavy Lower", "Explosive Lower"]
        }
        
        for i in 0..<days {
            if i % 2 == 0 {
                // Upper A (even) = Horizontal focus: Bench + Rows + Arms
                // Upper B (odd upper) = Vertical focus: OHP + Pulldowns + Rear Delts
                let upperVariant = (i / 2) % 2
                if upperVariant == 0 {
                    titles.append(DayTitleTemplate(
                        title: upperTitles[i / 2 % upperTitles.count],
                        targetMuscles: ["Chest", "Back", "Triceps"],
                        secondaryMuscles: ["Biceps", "Shoulders", "Core"]
                    ))
                } else {
                    titles.append(DayTitleTemplate(
                        title: upperTitles[i / 2 % upperTitles.count],
                        targetMuscles: ["Shoulders", "Lats", "Biceps"],
                        secondaryMuscles: ["Rear Delts", "Triceps", "Core"]
                    ))
                }
            } else {
                // Lower A (first lower) = Quad-dominant: Squats + Extensions + Calves
                // Lower B (second lower) = Hip-dominant: RDLs + Leg Curls + Glute work
                let lowerVariant = (i / 2) % 2
                if lowerVariant == 0 {
                    titles.append(DayTitleTemplate(
                        title: lowerTitles[i / 2 % lowerTitles.count],
                        targetMuscles: ["Quadriceps", "Glutes", "Calves"],
                        secondaryMuscles: ["Hamstrings", "Core"]
                    ))
                } else {
                    titles.append(DayTitleTemplate(
                        title: lowerTitles[i / 2 % lowerTitles.count],
                        targetMuscles: ["Hamstrings", "Glutes", "Lower Back"],
                        secondaryMuscles: ["Quadriceps", "Calves", "Core"]
                    ))
                }
            }
        }
        
        return titles
    }
    
    // MARK: - Full Body Titles
    
    private func getFullBodyTitles(programType: DynamicProgramGenerator.GeneratedProgram.ProgramType, days: Int) -> [DayTitleTemplate] {
        var titles: [DayTitleTemplate] = []
        
        let dayTitles: [String]
        
        switch programType {
        case .hypertrophy:
            dayTitles = ["Full Body Pump", "Total Body Builder", "Complete Muscle Day", "Full Body Volume"]
        case .strength:
            dayTitles = ["Full Body Strength", "Total Body Power", "Complete Strength", "Full Body Heavy"]
        case .fatLoss:
            dayTitles = ["Full Body Burn", "Total Body Torch", "Complete Circuit", "Full Body HIIT"]
        case .toning:
            dayTitles = ["Full Body Sculpt", "Total Body Tone", "Complete Definition", "Full Body Shape"]
        case .generalFitness:
            dayTitles = ["Full Body Day", "Total Body Workout", "Complete Fitness", "Full Body Training"]
        case .powerbuilding:
            dayTitles = ["Full Body Power", "Total Body Explosive", "Complete Power Day", "Full Body Dynamic"]
        }
        
        for i in 0..<days {
            // Each full body day covers all movement patterns (push, pull, squat, hinge)
            // but varies the specific compound emphasis for exercise variety
            let primaryCompound: String
            switch i % 3 {
            case 0: primaryCompound = "Chest"      // Bench focus day
            case 1: primaryCompound = "Shoulders"   // OHP focus day
            case 2: primaryCompound = "Back"        // Row/DL focus day
            default: primaryCompound = "Chest"
            }
            
            titles.append(DayTitleTemplate(
                title: dayTitles[i % dayTitles.count],
                targetMuscles: [primaryCompound, "Back", "Quadriceps", "Hamstrings"],
                secondaryMuscles: ["Shoulders", "Biceps", "Triceps", "Glutes", "Core", "Calves"]
            ))
        }
        
        return titles
    }
    
    // MARK: - Bro Split Titles
    
    private func getBroSplitTitles(programType: DynamicProgramGenerator.GeneratedProgram.ProgramType, days: Int) -> [DayTitleTemplate] {
        var titles: [DayTitleTemplate] = []
        
        // Classic bro split order: Chest, Back, Shoulders, Arms, Legs
        let broSplitDays: [(title: String, primary: [String], secondary: [String])]
        
        switch programType {
        case .hypertrophy:
            broSplitDays = [
                ("Chest Destroyer", ["Chest"], ["Triceps", "Front Delts"]),
                ("Back Attack", ["Back", "Lats"], ["Biceps", "Rear Delts"]),
                ("Boulder Shoulders", ["Shoulders"], ["Traps", "Triceps"]),
                ("Arm Annihilation", ["Biceps", "Triceps"], ["Forearms"]),
                ("Leg Day Massacre", ["Quadriceps", "Hamstrings", "Glutes"], ["Calves"])
            ]
        case .strength:
            broSplitDays = [
                ("Heavy Chest Day", ["Chest"], ["Triceps"]),
                ("Heavy Back Day", ["Back"], ["Biceps"]),
                ("Heavy Shoulder Day", ["Shoulders"], ["Traps"]),
                ("Arm Strength", ["Biceps", "Triceps"], ["Forearms"]),
                ("Heavy Leg Day", ["Quadriceps", "Hamstrings"], ["Glutes", "Calves"])
            ]
        case .fatLoss:
            broSplitDays = [
                ("Chest & Core Burn", ["Chest"], ["Core", "Triceps"]),
                ("Back & Core Burn", ["Back"], ["Core", "Biceps"]),
                ("Shoulder Torch", ["Shoulders"], ["Core", "Traps"]),
                ("Arm Circuit", ["Biceps", "Triceps"], ["Core"]),
                ("Leg Burn", ["Quadriceps", "Hamstrings", "Glutes"], ["Calves", "Core"])
            ]
        default:
            broSplitDays = [
                ("Chest Day", ["Chest"], ["Triceps"]),
                ("Back Day", ["Back", "Lats"], ["Biceps"]),
                ("Shoulder Day", ["Shoulders"], ["Traps"]),
                ("Arm Day", ["Biceps", "Triceps"], ["Forearms"]),
                ("Leg Day", ["Quadriceps", "Hamstrings", "Glutes"], ["Calves"])
            ]
        }
        
        for i in 0..<min(days, broSplitDays.count) {
            let day = broSplitDays[i]
            titles.append(DayTitleTemplate(
                title: day.title,
                targetMuscles: day.primary,
                secondaryMuscles: day.secondary
            ))
        }
        
        // If more days than 5, cycle back
        if days > 5 {
            for i in 5..<days {
                let day = broSplitDays[i % 5]
                titles.append(DayTitleTemplate(
                    title: "\(day.title) II",
                    targetMuscles: day.primary,
                    secondaryMuscles: day.secondary
                ))
            }
        }
        
        return titles
    }
    
    // MARK: - Arnold Split Titles
    
    private func getArnoldSplitTitles(programType: DynamicProgramGenerator.GeneratedProgram.ProgramType, days: Int) -> [DayTitleTemplate] {
        var titles: [DayTitleTemplate] = []
        
        // Arnold Split: Chest+Back, Shoulders+Arms, Legs (2x per week for 6 days)
        let arnoldDays: [(title: String, primary: [String], secondary: [String])]
        
        switch programType {
        case .hypertrophy:
            arnoldDays = [
                ("Chest & Back Volume", ["Chest", "Back", "Lats"], ["Core"]),
                ("Shoulders & Arms Pump", ["Shoulders", "Biceps", "Triceps"], ["Rear Delts", "Forearms"]),
                ("Leg Day Mass", ["Quadriceps", "Hamstrings", "Glutes"], ["Calves", "Core"])
            ]
        case .strength:
            arnoldDays = [
                ("Heavy Chest & Back", ["Chest", "Back"], ["Core"]),
                ("Heavy Shoulders & Arms", ["Shoulders", "Biceps", "Triceps"], ["Rear Delts"]),
                ("Heavy Legs", ["Quadriceps", "Hamstrings", "Glutes"], ["Calves", "Lower Back"])
            ]
        default:
            arnoldDays = [
                ("Chest & Back", ["Chest", "Back", "Lats"], ["Core"]),
                ("Shoulders & Arms", ["Shoulders", "Biceps", "Triceps"], ["Rear Delts", "Forearms"]),
                ("Leg Day", ["Quadriceps", "Hamstrings", "Glutes"], ["Calves", "Core"])
            ]
        }
        
        // Cycle through the 3-day rotation for however many days requested
        for i in 0..<days {
            let day = arnoldDays[i % 3]
            let suffix = (i >= 3) ? " II" : ""
            titles.append(DayTitleTemplate(
                title: "\(day.title)\(suffix)",
                targetMuscles: day.primary,
                secondaryMuscles: day.secondary
            ))
        }
        
        return titles
    }
    
    // MARK: - Push/Pull Titles
    
    private func getPushPullTitles(programType: DynamicProgramGenerator.GeneratedProgram.ProgramType, days: Int) -> [DayTitleTemplate] {
        var titles: [DayTitleTemplate] = []
        
        let pushTitles: [String]
        let pullTitles: [String]
        
        switch programType {
        case .hypertrophy:
            pushTitles = ["Push Day Pump", "Chest & Shoulders Volume", "Triceps & Press Day"]
            pullTitles = ["Pull Day Pump", "Back & Biceps Volume", "Lats & Arms Day"]
        case .strength:
            pushTitles = ["Heavy Push", "Bench & Press Strength", "Push Power Day"]
            pullTitles = ["Heavy Pull", "Row & Deadlift Day", "Pull Power Day"]
        case .fatLoss:
            pushTitles = ["Push Burn", "Chest & Triceps Circuit", "Push Metabolic"]
            pullTitles = ["Pull Burn", "Back & Biceps Circuit", "Pull Metabolic"]
        default:
            pushTitles = ["Push Day", "Chest & Shoulders", "Push Workout"]
            pullTitles = ["Pull Day", "Back & Biceps", "Pull Workout"]
        }
        
        for i in 0..<days {
            if i % 2 == 0 {
                titles.append(DayTitleTemplate(
                    title: pushTitles[i / 2 % pushTitles.count],
                    targetMuscles: ["Chest", "Shoulders", "Triceps", "Quadriceps"],
                    secondaryMuscles: ["Core", "Calves"]
                ))
            } else {
                titles.append(DayTitleTemplate(
                    title: pullTitles[i / 2 % pullTitles.count],
                    targetMuscles: ["Back", "Lats", "Biceps", "Hamstrings", "Glutes"],
                    secondaryMuscles: ["Rear Delts", "Forearms", "Lower Back"]
                ))
            }
        }
        
        return titles
    }
    
    // MARK: - Main Generation Method (from Database)
    
    func generateExercisesForDay(
        targetMuscles: [String],
        availableEquipment: [String],
        experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel,
        programType: DynamicProgramGenerator.GeneratedProgram.ProgramType,
        intensity: DynamicProgramGenerator.GeneratedProgram.MuscleGroupDay.Intensity,
        previousDayExercises: [String],
        dayInProgram: Int
    ) -> [DynamicProgramGenerator.GeneratedExercise] {
        
        #if DEBUG
        AppLogger.debug("🏋️ Generating exercises for day \(dayInProgram)", category: .workout)
        AppLogger.debug("   Target muscles: \(targetMuscles)", category: .workout)
        AppLogger.debug("   Equipment: \(availableEquipment)", category: .workout)
        AppLogger.debug("   Intensity: \(intensity.rawValue)", category: .workout)
        #endif
        
        var selectedExercises: [DynamicProgramGenerator.GeneratedExercise] = []
        var usedExerciseNames: Set<String> = Set(previousDayExercises)
        var bundleCounts: [String: Int] = [:]  // 📦 Track bundle usage
        
        // Determine exercise count based on experience and intensity
        let exerciseCount = getExerciseCount(experience: experience, intensity: intensity, programType: programType)
        
        let bundleEngine = ExerciseBundleEngine.shared
        
        // 🧠 Get user's favorites (same as auto-gen)
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let favorites = Set(allExercises.filter { $0.isFavorite }.compactMap { $0.name?.lowercased() })
        
        #if DEBUG
        if !favorites.isEmpty {
            AppLogger.debug("   ⭐ User has \(favorites.count) favorite exercises - will gently influence selection", category: .workout)
        }
        #endif
        
        // Fetch exercises from database for each target muscle
        for muscle in targetMuscles {
            if selectedExercises.count >= exerciseCount { break }
            
            let exercises = fetchExercisesForMuscle(
                muscle: muscle,
                equipment: availableEquipment,
                exclude: usedExerciseNames,
                count: 2, // Get 2 exercises per muscle group
                favorites: favorites // 🧠 Pass favorites for scoring
            )
            
            // Determine if this is a lower body day (for filtering)
            let lowerBodyMuscles = ["quads", "quadriceps", "hamstrings", "glutes", "calves", "legs"]
            let isLowerBodyDay = targetMuscles.contains { muscle in
                lowerBodyMuscles.contains { muscle.lowercased().contains($0) }
            }
            
            for exercise in exercises {
                if selectedExercises.count >= exerciseCount { break }
                if usedExerciseNames.contains(exercise.name) { continue }
                
                // Determine movement pattern for variety tracking
                let pattern = SmartExerciseSelectionEngine.shared.getMovementPattern(for: exercise.name)
                
                // CRITICAL: Block upper body pressing patterns on lower days
                if isLowerBodyDay {
                    let upperPressPatterns = ["shoulder press", "military press", "overhead press",
                                              "bench press", "chest press", "incline press", "dip",
                                              "pushdown", "tricep", "bicep curl", "lateral raise"]
                    if upperPressPatterns.contains(where: { exercise.name.lowercased().contains($0) }) {
                        continue  // Skip this exercise
                    }
                    
                    // Also block by pattern
                    let upperPatterns: [SelectionMovementPattern] = [.horizontalPress, .verticalPress, .tricepExtension, .bicepCurl, .lateralRaise]
                    if upperPatterns.contains(pattern) {
                        continue
                    }
                }
                
                // 📦 BUNDLE CHECK - Don't exceed max per bundle
                if let bundle = bundleEngine.bundleForExercise(named: exercise.name) {
                    let currentCount = bundleCounts[bundle.id, default: 0]
                    if currentCount >= bundle.maxPerWorkout {
                        #if DEBUG
                        AppLogger.debug("   ⏭️ Bundle limit: skipping \(exercise.name) (\(bundle.displayName) has \(currentCount)/\(bundle.maxPerWorkout))", category: .workout)
                        #endif
                        continue
                    }
                }
                
                // 📦 COOLDOWN CHECK - Skip if exercise was done too recently
                let cooldownTracker = ExerciseCooldownTracker.shared
                let isAnchorLift = exercise.isCompound && pattern.isAnchorPattern
                if cooldownTracker.isOnCooldown(exercise.name, isAnchor: isAnchorLift) {
                    #if DEBUG
                    AppLogger.debug("   ❄️ Cooldown: skipping \(exercise.name)", category: .workout)
                    #endif
                    continue
                }
                
                // Anchor lifts: compounds that should stay consistent across weeks
                let isAnchor = isAnchorLift
                
                let generatedExercise = DynamicProgramGenerator.GeneratedExercise(
                    id: UUID().uuidString,
                    exerciseName: exercise.name,
                    exerciseId: exercise.id,
                    order: selectedExercises.count,
                    sets: getSetsForType(programType, experience: experience, intensity: intensity),
                    repsMin: getRepsRange(programType, experience: experience).lowerBound,
                    repsMax: getRepsRange(programType, experience: experience).upperBound,
                    restSeconds: getRestSeconds(programType, experience: experience),
                    targetRPE: getTargetRPE(intensity: intensity),
                    notes: nil,
                    isWarmup: false,
                    supersetGroup: nil,
                    isAnchor: isAnchor,
                    movementPattern: pattern.rawValue
                )
                
                selectedExercises.append(generatedExercise)
                usedExerciseNames.insert(exercise.name)
                
                // 📦 Track bundle usage
                if let bundle = bundleEngine.bundleForExercise(named: exercise.name) {
                    bundleCounts[bundle.id, default: 0] += 1
                }
            }
        }
        
        // If we still need more exercises, get compound exercises
        if selectedExercises.count < exerciseCount {
            let compoundExercises = fetchCompoundExercises(
                muscles: targetMuscles,
                equipment: availableEquipment,
                exclude: usedExerciseNames,
                count: exerciseCount - selectedExercises.count,
                favorites: favorites // 🧠 Pass favorites for scoring
            )
            
            for exercise in compoundExercises {
                if selectedExercises.count >= exerciseCount { break }
                
                // 📦 BUNDLE CHECK - Don't exceed max per bundle
                if let bundle = bundleEngine.bundleForExercise(named: exercise.name) {
                    let currentCount = bundleCounts[bundle.id, default: 0]
                    if currentCount >= bundle.maxPerWorkout {
                        continue
                    }
                }
                
                // Determine movement pattern for variety tracking
                let pattern = SmartExerciseSelectionEngine.shared.getMovementPattern(for: exercise.name)
                
                // Anchor lifts: compounds that should stay consistent across weeks
                let isAnchor = exercise.isCompound && pattern.isAnchorPattern
                
                let generatedExercise = DynamicProgramGenerator.GeneratedExercise(
                    id: UUID().uuidString,
                    exerciseName: exercise.name,
                    exerciseId: exercise.id,
                    order: selectedExercises.count,
                    sets: getSetsForType(programType, experience: experience, intensity: intensity),
                    repsMin: getRepsRange(programType, experience: experience).lowerBound,
                    repsMax: getRepsRange(programType, experience: experience).upperBound,
                    restSeconds: getRestSeconds(programType, experience: experience),
                    targetRPE: getTargetRPE(intensity: intensity),
                    notes: nil,
                    isWarmup: false,
                    supersetGroup: nil,
                    isAnchor: isAnchor,
                    movementPattern: pattern.rawValue
                )
                
                selectedExercises.append(generatedExercise)
                usedExerciseNames.insert(exercise.name)
                
                // 📦 Track bundle usage
                if let bundle = bundleEngine.bundleForExercise(named: exercise.name) {
                    bundleCounts[bundle.id, default: 0] += 1
                }
            }
        }
        
        #if DEBUG
        AppLogger.info("✅ Generated \(selectedExercises.count) exercises from database", category: .workout)
        #endif
        return selectedExercises
    }
    
    // MARK: - Database Exercise Fetch Methods
    
    private struct FetchedExercise {
        let name: String
        let id: UUID?
        let isCompound: Bool
        var learnedScore: Double = 0  // 🧠 Score from UserBehaviorLearningEngine
    }
    
    private func fetchExercisesForMuscle(
        muscle: String,
        equipment: [String],
        exclude: Set<String>,
        count: Int,
        favorites: Set<String> = []
    ) -> [FetchedExercise] {
        
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        // ═══════════════════════════════════════════════════════════════════
        // SAFETY FILTER: Remove exercises that could aggravate user's limitations
        // ═══════════════════════════════════════════════════════════════════
        var safeExercises = LimitationsService.shared.filterSafeExercises(allExercises)
        
        // 🚫 PRE-FILTER: Remove risky/complex exercises
        // Mirrors Python script's RISKY_EXERCISES filtering
        let foundationalDB = FoundationalExerciseDatabase.shared
        let hasLowerBackIssue = LimitationsService.shared.hasLowerBackLimitation
        let userWorkoutCount = ProgressiveUnlockCache.shared.workoutCount
        let restrictToFoundational = ProgressiveUnlockCache.shared.shouldRestrictToFoundational
        
        if restrictToFoundational || userWorkoutCount < 10 {
            safeExercises = safeExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                return !foundationalDB.isRiskyExercise(name)
            }
        }
        
        // 🚫 PRE-FILTER: Remove lower back stress exercises if user has back issues
        if hasLowerBackIssue {
            safeExercises = safeExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                return !foundationalDB.isLowerBackStressExercise(name)
            }
        }
        
        let normalizedEquipment = Set(equipment.map { $0.lowercased() })
        let normalizedMuscle = muscle.lowercased()
        
        // 🧠 Get learning engine for personalized scoring
        let learningEngine = UserBehaviorLearningEngine.shared
        
        // ═══════════════════════════════════════════════════════════════════
        // AUDIT FIX: Detect if user has gym equipment
        // ═══════════════════════════════════════════════════════════════════
        let gymEquipmentTypes = ["barbell", "cables", "cable", "machines", "machine", "lever"]
        let hasGymEquipment = normalizedEquipment.contains { equip in
            gymEquipmentTypes.contains { equip.contains($0) }
        }
        
        // Gym equipment priority order - MACHINES FIRST!
        // Lever machines and cable machines are the hallmark of gym training
        let gymEquipmentPriority = ["lever", "machine", "machines", "cable", "cables", "barbell", "dumbbells", "dumbbell", "kettlebell"]
        
        // Keywords for exercises to HARD EXCLUDE for gym users - these have no place in a gym
        let floorExerciseKeywords = [
            "floor", "lying", "prone", "supine", "ground",  // Position keywords
            "dead bug", "bird dog", "superman", "plank",     // Specific floor exercises
            "crunches", "sit-up", "sit up", "crunch",        // Floor ab exercises
            "leg raise", "bicycle", "mountain climber",      // Floor cardio/abs
            "renegade", "burpee", "bear crawl", "inchworm",  // Floor movements
            "glute bridge", "hip thrust on floor",           // Floor glute work
            "fire hydrant", "donkey kick", "clam"            // Floor isolation
        ]
        let plyometricKeywords = ["jump", "hop", "bound", "plyo", "explosive", "box jump"]
        
        // Map muscle names to database muscle group names
        let muscleMapping: [String: [String]] = [
            "chest": ["chest", "upper chest", "lower chest"],
            "upper chest": ["upper chest", "chest"],
            "lower chest": ["lower chest", "chest"],
            "back": ["back", "lats", "upper back", "lower back"],
            "lats": ["lats", "back"],
            "upper back": ["upper back", "back", "traps"],
            "lower back": ["lower back", "back"],
            "shoulders": ["shoulders", "front delts", "side delts", "rear delts"],
            "front delts": ["front delts", "shoulders"],
            "side delts": ["side delts", "shoulders"],
            "rear delts": ["rear delts", "shoulders"],
            "biceps": ["biceps"],
            "triceps": ["triceps"],
            "quadriceps": ["quads", "quadriceps"],
            "quads": ["quads", "quadriceps"],
            "hamstrings": ["hamstrings"],
            "glutes": ["glutes"],
            "calves": ["calves"],
            "core": ["core", "abs", "obliques", "lower abs"],
            "abs": ["abs", "core", "lower abs"],
            "obliques": ["obliques", "core"],
            "forearms": ["forearms"],
            "traps": ["traps", "upper back"],
            "rotator cuff": ["rotator cuff", "shoulders"],
            "hip flexors": ["hip flexors", "hips"],
            "hips": ["hips", "hip flexors", "inner thighs"],
            "inner thighs": ["inner thighs", "hips"],
            "neck": ["neck"],
            "full body": ["full body"]
        ]
        
        let searchTerms = muscleMapping[normalizedMuscle] ?? [normalizedMuscle]
        
        var scoredResults: [(exercise: FetchedExercise, score: Int)] = []
        
        for exercise in safeExercises {
            let exerciseName = exercise.name ?? ""
            if exclude.contains(exerciseName) { continue }
            
            var score = 100  // Base score
            
            // Check equipment match
            let exerciseEquipment = (exercise.equipment ?? "").lowercased()
            let workoutType = (exercise.workoutType ?? "").lowercased()
            
            // 🔧 Use smart equipment matching for database format
            // Database: "Lever Machine", "Cable Machine", etc.
            // User: "Machines", "Cables", etc.
            let equipmentMatch = normalizedEquipment.isEmpty ||
                doesEquipmentMatchForGeneration(exerciseEquipment: exerciseEquipment, userEquipment: equipment)
            
            guard equipmentMatch else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // AUDIT FIX: Exclude stretching from main workouts
            // ═══════════════════════════════════════════════════════════════
            let isStretch = workoutType == "stretch" || workoutType == "stretching" ||
                           exerciseName.lowercased().contains("stretch")
            guard !isStretch else { continue }
            
            // Check muscle match - use muscleGroups array and category
            let muscleGroupsArray = (exercise.muscleGroups as? [String]) ?? []
            let muscleGroupsText = muscleGroupsArray.joined(separator: " ").lowercased()
            let category = (exercise.category ?? "").lowercased()
            let description = (exercise.exerciseDescription ?? "").lowercased()
            
            let muscleMatch = searchTerms.contains { term in
                muscleGroupsText.contains(term) ||
                category.contains(term) ||
                description.contains(term)
            }
            
            guard muscleMatch else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // 🔥🔥🔥 GYM USER FILTERING - STRICT MODE 🔥🔥🔥
            // User selected GYM - they want MACHINES, BARBELLS, CABLES, DUMBBELLS
            // NOT floor exercises, NOT bodyweight, NOT home workout stuff
            // ═══════════════════════════════════════════════════════════════
            if hasGymEquipment {
                let nameLower = exerciseName.lowercased()
                let isBodyweight = exerciseEquipment == "bodyweight" || exerciseEquipment.isEmpty
                
                // 🚫🚫🚫 HARD EXCLUDE #1: ANY exercise with floor/lying keywords
                // These have NO PLACE in a gym workout
                let isFloorExercise = floorExerciseKeywords.contains { nameLower.contains($0) }
                if isFloorExercise {
                    continue  // SKIP - NO floor exercises for gym users, PERIOD
                }
                
                // 🚫🚫🚫 HARD EXCLUDE #2: Plyometrics
                let isPlyometric = plyometricKeywords.contains { nameLower.contains($0) }
                if isPlyometric {
                    continue  // SKIP - gym is for weights, not jumping
                }
                
                // ✅ GYM-APPROPRIATE BODYWEIGHT (ONLY these few are allowed)
                // These are exercises you'd actually do at a gym with equipment
                let gymAppropriateBodyweight = [
                    "pull-up", "pullup", "chin-up", "chinup",  // Pull-up bar
                    "dip",                                       // Dip station (NOT floor dips!)
                    "hanging",                                   // Hanging exercises
                    "muscle up",                                 // Bar work
                    "inverted row"                               // Smith machine rows
                ]
                let isGymAppropriateBodyweight = gymAppropriateBodyweight.contains { nameLower.contains($0) }
                
                // 🚫 BUT EXCLUDE "floor" variants of gym-appropriate exercises
                if isGymAppropriateBodyweight && nameLower.contains("floor") {
                    continue  // SKIP - "Floor Dip" is NOT a gym exercise
                }
                
                // 🚫🚫🚫 HARD EXCLUDE #3: ALL other bodyweight for gym users
                if isBodyweight && !isGymAppropriateBodyweight {
                    continue  // SKIP - user has gym equipment, USE IT!
                }
                
                // ✅ Check if exercise actually uses gym equipment
                let usesGymEquipment = gymEquipmentPriority.contains { exerciseEquipment.contains($0) }
                
                // 🏆🏆🏆 MASSIVE BOOST: Gym equipment exercises
                if usesGymEquipment {
                    if let priorityIndex = gymEquipmentPriority.firstIndex(where: { exerciseEquipment.contains($0) }) {
                        score += (gymEquipmentPriority.count - priorityIndex) * 30  // HUGE boost for gym equipment
                    }
                }
            }
            
            let isCompound = isCompoundExercise(exercise)
            
            // BOOST: Compound movements
            if isCompound {
                score += 15
            }
            
            // 🧠 Calculate learning engine boost for personalization
            let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
            let learnedBoost = learningEngine.calculateLearnedBoostScore(
                exerciseName: exerciseName,
                equipment: exercise.equipment ?? "",
                muscleGroups: muscleGroups,
                category: category
            )
            
            // Convert learned boost to int score (0-20 range)
            score += Int(learnedBoost * 20)
            
            // ⭐ FAVORITES - GENTLE INFLUENCE (same as auto-gen)
            // Give favorites a small boost (+20) to influence but not dominate
            if favorites.contains(exerciseName.lowercased()) {
                score += 20
            }
            
            scoredResults.append((
                FetchedExercise(
                    name: exerciseName,
                    id: exercise.id,
                    isCompound: isCompound,
                    learnedScore: learnedBoost
                ),
                score
            ))
        }
        
        // Sort by score (highest first), then add some randomization within tiers
        scoredResults.sort { a, b in
            let tierA = a.score / 15
            let tierB = b.score / 15
            if tierA != tierB {
                return tierA > tierB
            }
            return Bool.random()
        }
        
        // Return top results
        return Array(scoredResults.prefix(count * 2).map { $0.exercise })
    }
    
    private func fetchCompoundExercises(
        muscles: [String],
        equipment: [String],
        exclude: Set<String>,
        count: Int,
        favorites: Set<String> = []
    ) -> [FetchedExercise] {
        
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        // ═══════════════════════════════════════════════════════════════════
        // SAFETY FILTER: Remove exercises that could aggravate user's limitations
        // ═══════════════════════════════════════════════════════════════════
        var safeExercises = LimitationsService.shared.filterSafeExercises(allExercises)
        
        // 🚫 PRE-FILTER: Remove risky/complex exercises
        // Mirrors Python script's RISKY_EXERCISES filtering
        let foundationalDB = FoundationalExerciseDatabase.shared
        let hasLowerBackIssue = LimitationsService.shared.hasLowerBackLimitation
        let userWorkoutCount = ProgressiveUnlockCache.shared.workoutCount
        let restrictToFoundational = ProgressiveUnlockCache.shared.shouldRestrictToFoundational
        
        if restrictToFoundational || userWorkoutCount < 10 {
            safeExercises = safeExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                return !foundationalDB.isRiskyExercise(name)
            }
        }
        
        // 🚫 PRE-FILTER: Remove lower back stress exercises if user has back issues
        if hasLowerBackIssue {
            safeExercises = safeExercises.filter { exercise in
                let name = exercise.name?.lowercased() ?? ""
                return !foundationalDB.isLowerBackStressExercise(name)
            }
        }
        
        let normalizedEquipment = Set(equipment.map { $0.lowercased() })
        
        // 🧠 Get learning engine for personalized scoring
        let learningEngine = UserBehaviorLearningEngine.shared
        
        // ═══════════════════════════════════════════════════════════════════
        // AUDIT FIX: Detect if user has gym equipment
        // ═══════════════════════════════════════════════════════════════════
        let gymEquipmentTypes = ["barbell", "cables", "cable", "machines", "machine", "lever"]
        let hasGymEquipment = normalizedEquipment.contains { equip in
            gymEquipmentTypes.contains { equip.contains($0) }
        }
        
        // Gym equipment priority order - MACHINES FIRST!
        // Lever machines and cable machines are the hallmark of gym training
        let gymEquipmentPriority = ["lever", "machine", "machines", "cable", "cables", "barbell", "dumbbells", "dumbbell", "kettlebell"]
        
        // Keywords for exercises to HARD EXCLUDE for gym users
        let floorExerciseKeywords = [
            "floor", "lying", "prone", "supine", "ground",
            "dead bug", "bird dog", "superman", "plank",
            "crunches", "sit-up", "sit up", "crunch",
            "leg raise", "bicycle", "mountain climber",
            "renegade", "burpee", "bear crawl", "inchworm",
            "glute bridge", "hip thrust on floor",
            "fire hydrant", "donkey kick", "clam"
        ]
        let plyometricKeywords = ["jump", "hop", "bound", "plyo", "explosive", "box jump"]
        
        var scoredResults: [(exercise: FetchedExercise, score: Int)] = []
        
        // Look for compound exercises that hit multiple target muscles
        for exercise in safeExercises {
            let exerciseName = exercise.name ?? ""
            if exclude.contains(exerciseName) { continue }
            
            var score = 100  // Base score
            
            // Check equipment
            let exerciseEquipment = (exercise.equipment ?? "").lowercased()
            let workoutType = (exercise.workoutType ?? "").lowercased()
            
            let equipmentMatch = normalizedEquipment.isEmpty ||
                normalizedEquipment.contains { equip in
                    exerciseEquipment.contains(equip) || equip.contains(exerciseEquipment)
                } ||
                exerciseEquipment.contains("body")
            
            guard equipmentMatch else { continue }
            
            // Exclude stretching
            let isStretch = workoutType == "stretch" || workoutType == "stretching"
            guard !isStretch else { continue }
            
            // Must be compound
            guard isCompoundExercise(exercise) else { continue }
            
            // Check if hits any target muscle
            let muscleGroupsArray = (exercise.muscleGroups as? [String]) ?? []
            let muscleGroupsText = muscleGroupsArray.joined(separator: " ").lowercased()
            let category = (exercise.category ?? "").lowercased()
            
            let muscleHit = muscles.contains { muscle in
                muscleGroupsText.contains(muscle.lowercased()) ||
                category.contains(muscle.lowercased())
            }
            
            guard muscleHit else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // 🔥🔥🔥 GYM USER COMPOUND FILTERING - STRICT MODE 🔥🔥🔥
            // Gym compounds = BARBELL, DUMBBELLS, CABLES, MACHINES
            // ═══════════════════════════════════════════════════════════════
            if hasGymEquipment {
                let nameLower = exerciseName.lowercased()
                let isBodyweight = exerciseEquipment == "bodyweight" || exerciseEquipment.isEmpty
                
                // 🚫🚫🚫 HARD EXCLUDE: ANY floor exercise
                let isFloorExercise = floorExerciseKeywords.contains { nameLower.contains($0) }
                if isFloorExercise {
                    continue  // SKIP - NO floor exercises for gym users
                }
                
                // 🚫🚫🚫 HARD EXCLUDE: Plyometrics
                let isPlyometric = plyometricKeywords.contains { nameLower.contains($0) }
                if isPlyometric {
                    continue  // SKIP - gym compounds are for strength
                }
                
                // ✅ VERY LIMITED gym-appropriate compound bodyweight
                let gymAppropriateCompound = ["pull-up", "pullup", "chin-up", "chinup", "dip", "muscle up", "inverted row"]
                let isGymAppropriate = gymAppropriateCompound.contains { nameLower.contains($0) }
                
                // 🚫 Exclude "floor" variants
                if isGymAppropriate && nameLower.contains("floor") {
                    continue  // SKIP - floor dips etc.
                }
                
                // 🚫🚫🚫 HARD EXCLUDE: ALL other bodyweight compounds for gym users
                if isBodyweight && !isGymAppropriate {
                    continue  // SKIP - user has gym equipment, USE IT for compounds!
                }
                
                // 🏆🏆🏆 MASSIVE BOOST: Gym equipment compounds
                if let priorityIndex = gymEquipmentPriority.firstIndex(where: { exerciseEquipment.contains($0) }) {
                    score += (gymEquipmentPriority.count - priorityIndex) * 35  // HUGE boost
                }
            }
            
            // 🧠 Calculate learning engine boost
            let learnedBoost = learningEngine.calculateLearnedBoostScore(
                exerciseName: exerciseName,
                equipment: exercise.equipment ?? "",
                muscleGroups: muscleGroupsArray,
                category: category
            )
            
            score += Int(learnedBoost * 20)
            
            // ⭐ FAVORITES - GENTLE INFLUENCE (same as auto-gen)
            // Give favorites a small boost (+20) to influence but not dominate
            if favorites.contains(exerciseName.lowercased()) {
                score += 20
            }
            
            scoredResults.append((
                FetchedExercise(
                    name: exerciseName,
                    id: exercise.id,
                    isCompound: true,
                    learnedScore: learnedBoost
                ),
                score
            ))
        }
        
        // Sort by score (highest first)
        scoredResults.sort { $0.score > $1.score }
        
        return Array(scoredResults.prefix(count).map { $0.exercise })
    }
    
    private func isCompoundExercise(_ exercise: Exercise) -> Bool {
        let name = (exercise.name ?? "").lowercased()
        let compoundKeywords = [
            "press", "squat", "deadlift", "row", "pull-up", "pullup",
            "dip", "lunge", "clean", "snatch", "thruster", "burpee",
            "push-up", "pushup", "chin-up", "chinup"
        ]
        return compoundKeywords.contains { name.contains($0) }
    }
    
    // MARK: - Equipment Matching Helper
    
    /// Smart equipment matching that handles database format
    /// Database uses: "Lever Machine", "Cable Machine", "Chest Press Machine"
    /// User selects: "Machines", "Cables", "Barbell"
    private func doesEquipmentMatchForGeneration(exerciseEquipment: String, userEquipment: [String]) -> Bool {
        let equip = exerciseEquipment.lowercased()
        
        // Empty/bodyweight handling
        if equip.isEmpty || equip == "bodyweight" || equip.contains("body weight") {
            return userEquipment.contains { $0.lowercased().contains("bodyweight") || $0.lowercased().contains("body weight") }
        }
        
        // Equipment mapping: user selection -> database patterns
        let equipmentPatterns: [String: [String]] = [
            "machines": ["machine", "lever", "press machine", "curl machine", "row machine", 
                        "extension machine", "leg press", "hack squat", "smith", "pec deck"],
            "cables": ["cable", "cable machine", "pulley", "pulldown"],
            "barbell": ["barbell", "bar", "olympic", "ez bar"],
            "dumbbells": ["dumbbell", "dumbbells", "db"],
            "bodyweight": ["bodyweight", "body weight"],
            "kettlebell": ["kettlebell", "kb"],
            "resistance bands": ["band", "resistance band", "resistance"],
            "resistance band": ["band", "resistance band", "resistance"]
        ]
        
        // Common gym items always available
        let commonItems = ["floor", "mat", "wall", "bench", "flat bench", "incline bench", "decline bench", "preacher bench"]
        
        // Parse exercise equipment parts
        let exerciseParts = equip.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for userEquip in userEquipment {
            let userEquipLower = userEquip.lowercased()
            
            // Get patterns for this user equipment
            let patterns = equipmentPatterns[userEquipLower] ?? [userEquipLower]
            
            // Check if any pattern matches
            for pattern in patterns {
                if equip.contains(pattern) {
                    return true
                }
                for part in exerciseParts {
                    if part.contains(pattern) || pattern.contains(part) {
                        return true
                    }
                }
            }
        }
        
        // Check if only common items are required
        let nonCommonParts = exerciseParts.filter { part in
            !commonItems.contains(where: { part.contains($0) || $0.contains(part) })
        }
        
        return nonCommonParts.isEmpty
    }
    
    // MARK: - Helper Methods
    
    private func getExerciseCount(
        experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel,
        intensity: DynamicProgramGenerator.GeneratedProgram.MuscleGroupDay.Intensity,
        programType: DynamicProgramGenerator.GeneratedProgram.ProgramType
    ) -> Int {
        
        let baseCount: Int
        switch experience {
        case .beginner: baseCount = 4
        case .intermediate: baseCount = 5
        case .advanced: baseCount = 6
        }
        
        let intensityModifier: Int
        switch intensity {
        case .light, .deload: intensityModifier = -1
        case .moderate: intensityModifier = 0
        case .heavy: intensityModifier = 1
        }
        
        let typeModifier: Int
        switch programType {
        case .fatLoss: typeModifier = 1
        case .strength: typeModifier = -1
        default: typeModifier = 0
        }
        
        return max(3, baseCount + intensityModifier + typeModifier)
    }
    
    private func getSetsForType(
        _ type: DynamicProgramGenerator.GeneratedProgram.ProgramType,
        experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel,
        intensity: DynamicProgramGenerator.GeneratedProgram.MuscleGroupDay.Intensity
    ) -> Int {
        
        let baseSets: Int
        switch type {
        case .strength: baseSets = 5
        case .hypertrophy: baseSets = 4
        case .fatLoss: baseSets = 3
        case .toning: baseSets = 3
        case .generalFitness: baseSets = 3
        case .powerbuilding: baseSets = 4
        }
        
        let expModifier: Int
        switch experience {
        case .beginner: expModifier = -1
        case .intermediate: expModifier = 0
        case .advanced: expModifier = 1
        }
        
        let intensityModifier: Int
        switch intensity {
        case .light, .deload: intensityModifier = -1
        case .moderate: intensityModifier = 0
        case .heavy: intensityModifier = 1
        }
        
        return max(2, baseSets + expModifier + intensityModifier)
    }
    
    private func getRepsRange(
        _ type: DynamicProgramGenerator.GeneratedProgram.ProgramType,
        experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel
    ) -> ClosedRange<Int> {
        
        switch type {
        case .strength:
            return experience == .advanced ? 1...5 : 3...6
        case .hypertrophy:
            return 8...12
        case .fatLoss:
            return 12...15
        case .toning:
            return 12...15
        case .generalFitness:
            return 10...15
        case .powerbuilding:
            return 6...10
        }
    }
    
    private func getRestSeconds(
        _ type: DynamicProgramGenerator.GeneratedProgram.ProgramType,
        experience: DynamicProgramGenerator.UserProgramProfile.ExperienceLevel
    ) -> Int {
        
        let baseRest: Int
        switch type {
        case .strength: baseRest = 180
        case .hypertrophy: baseRest = 90
        case .fatLoss: baseRest = 45
        case .toning: baseRest = 60
        case .generalFitness: baseRest = 60
        case .powerbuilding: baseRest = 120
        }
        
        let expModifier: Int
        switch experience {
        case .beginner: expModifier = 30
        case .intermediate: expModifier = 0
        case .advanced: expModifier = -15
        }
        
        return baseRest + expModifier
    }
    
    private func getTargetRPE(intensity: DynamicProgramGenerator.GeneratedProgram.MuscleGroupDay.Intensity) -> Int {
        switch intensity {
        case .light, .deload: return 6
        case .moderate: return 7
        case .heavy: return 8
        }
    }
}
