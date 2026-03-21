import Foundation
import CoreData

// MARK: - Dynamic Program Generator
/// Generates personalized workout programs based on user onboarding inputs
/// Creates 10 personalized programs specific to user's goals, equipment, experience, and schedule
/// Programs are generated lazily - only Day 1 created upfront, subsequent days generated as user progresses

class DynamicProgramGenerator {
    static let shared = DynamicProgramGenerator()
    
    private init() {}
    
    // MARK: - User Profile for Program Generation
    
    struct UserProgramProfile {
        let goals: [String]              // e.g., ["Build Muscle", "Get Stronger"]
        let experienceLevel: ExperienceLevel
        let daysPerWeek: Int             // 2-7
        let availableEquipment: [String] // e.g., ["Dumbbells", "Barbell", "Bench"]
        let workoutLocation: WorkoutLocation
        let age: Int
        let gender: String?
        let preferredDuration: Int       // Minutes per workout (30, 45, 60, 90)
        
        enum ExperienceLevel: String, CaseIterable {
            case beginner = "Beginner"
            case intermediate = "Intermediate"
            case advanced = "Advanced"
            
            var restBetweenSets: Int {
                switch self {
                case .beginner: return 120
                case .intermediate: return 90
                case .advanced: return 60
                }
            }
            
            var volumeMultiplier: Double {
                switch self {
                case .beginner: return 0.7
                case .intermediate: return 1.0
                case .advanced: return 1.3
                }
            }
        }
        
        enum WorkoutLocation: String, CaseIterable {
            case gym = "Gym"
            case home = "Home"
            case outdoor = "Outdoor"
            case minimal = "Minimal Equipment"
        }
    }
    
    // MARK: - Generated Program Structure
    
    struct GeneratedProgram: Identifiable, Codable {
        let id: String
        let name: String
        let description: String
        let icon: String
        let color: String
        let programType: ProgramType
        let splitType: SplitType
        let durationWeeks: Int
        let daysPerWeek: Int
        let difficulty: String
        let targetGoals: [String]
        let requiredEquipment: [String]
        let benefits: [String]
        let muscleGroupRotation: [MuscleGroupDay]  // Template for each day's focus
        var generatedDays: [GeneratedProgramDay]   // Actually generated workouts
        var isActive: Bool
        let createdAt: Date
        
        enum ProgramType: String, Codable, CaseIterable {
            case hypertrophy = "Hypertrophy"
            case strength = "Strength"
            case fatLoss = "Fat Loss"
            case generalFitness = "General Fitness"
            case toning = "Toning"
            case powerbuilding = "Powerbuilding"
        }
        
        enum SplitType: String, Codable, CaseIterable {
            case fullBody = "Full Body"
            case upperLower = "Upper/Lower"
            case pushPullLegs = "Push/Pull/Legs"
            case broSplit = "Bro Split"
            case pushPull = "Push/Pull"
            case arnoldSplit = "Arnold Split"
            
            var description: String {
                switch self {
                case .fullBody: return "Train your entire body each session"
                case .upperLower: return "Alternate upper and lower body days"
                case .pushPullLegs: return "Divide workouts by movement pattern"
                case .broSplit: return "One muscle group per day"
                case .pushPull: return "Push muscles one day, pull the next"
                case .arnoldSplit: return "Chest+Back, Shoulders+Arms, Legs — antagonist pairing"
                }
            }
        }
        
        struct MuscleGroupDay: Codable {
            let dayNumber: Int
            let name: String
            let primaryMuscles: [String]
            let secondaryMuscles: [String]
            let isRestDay: Bool
            let intensity: Intensity
            
            enum Intensity: String, Codable {
                case light = "Light"
                case moderate = "Moderate"
                case heavy = "Heavy"
                case deload = "Deload"
            }
        }
    }
    
    struct GeneratedProgramDay: Identifiable, Codable {
        let id: String
        let dayNumber: Int
        let weekNumber: Int
        let name: String
        let focusMuscles: [String]
        let exercises: [GeneratedExercise]
        let estimatedDuration: Int
        let intensity: String
        let isCompleted: Bool
        let completedAt: Date?
        let notes: String?
    }
    
    struct GeneratedExercise: Identifiable, Codable {
        let id: String
        let exerciseName: String
        let exerciseId: UUID?
        let order: Int
        let sets: Int
        let repsMin: Int
        let repsMax: Int
        let restSeconds: Int
        let targetRPE: Int?        // Reps in Reserve (0 = failure)
        let notes: String?
        let isWarmup: Bool
        let supersetGroup: Int?
        let isAnchor: Bool         // Anchor lifts stay consistent across weeks for progressive overload
        let movementPattern: String? // Movement pattern for variety tracking
        
        /// Get the suggested sets/reps/RIR based on the week number
        /// VOLUME RULES:
        /// - Anchors: 3-4 sets (only anchors get 4 sets in build weeks)
        /// - Accessories: 2-3 sets (manageable for recovery)
        /// - Peak week: Only LAST SET of anchors goes to 0 RIR
        /// - Glute isolation (kickbacks): Use higher reps (12-20)
        /// - Deload: Compounds 2 min rest, isolation 60-90 sec
        static func getPrescription(weekNumber: Int, isCompound: Bool, isAnchor: Bool, exerciseName: String = "") -> (sets: Int, repsMin: Int, repsMax: Int, rir: Int, rest: Int) {
            // Check for glute isolation work (kickbacks, etc.) - use higher reps
            let nameLower = exerciseName.lowercased()
            let isGluteIsolation = nameLower.contains("kickback") || nameLower.contains("glute bridge") || 
                                   nameLower.contains("fire hydrant") || nameLower.contains("clam")
            
            // Base sets differ by exercise type
            let anchorBaseSets = 3
            let accessoryBaseSets = 2  // Accessories capped lower to manage fatigue
            
            switch weekNumber {
            case 1: // Foundation - focus on form, moderate intensity
                let sets = isAnchor ? anchorBaseSets : accessoryBaseSets
                let repsMin = isGluteIsolation ? 12 : (isCompound ? 6 : 10)
                let repsMax = isGluteIsolation ? 20 : (isCompound ? 10 : 15)
                return (sets: sets, repsMin: repsMin, repsMax: repsMax, rir: 3, rest: isCompound ? 150 : 75)
            case 2: // Build - add set to ANCHORS only
                let sets = isAnchor ? anchorBaseSets + 1 : accessoryBaseSets
                let repsMin = isGluteIsolation ? 12 : (isCompound ? 6 : 10)
                let repsMax = isGluteIsolation ? 20 : (isCompound ? 10 : 15)
                return (sets: sets, repsMin: repsMin, repsMax: repsMax, rir: 2, rest: isCompound ? 150 : 75)
            case 3: // Push - anchors at 4, accessories at 3 max
                let sets = isAnchor ? anchorBaseSets + 1 : min(accessoryBaseSets + 1, 3)
                let repsMin = isGluteIsolation ? 12 : (isCompound ? 6 : 10)
                let repsMax = isGluteIsolation ? 20 : (isCompound ? 10 : 15)
                return (sets: sets, repsMin: repsMin, repsMax: repsMax, rir: 1, rest: isCompound ? 180 : 90)
            case 4: // Peak - only LAST SET of anchors to failure (RIR 1 shown, last set goes to 0)
                let sets = isAnchor ? anchorBaseSets + 1 : accessoryBaseSets
                let repsMin = isGluteIsolation ? 10 : (isCompound ? 4 : 8)
                let repsMax = isGluteIsolation ? 15 : (isCompound ? 8 : 12)
                return (sets: sets, repsMin: repsMin, repsMax: repsMax, rir: 1, rest: isCompound ? 180 : 90)
            default: // Week 5+ = Deload - reduce volume 40-50%, isolation gets shorter rest
                let sets = isAnchor ? max(2, anchorBaseSets - 1) : accessoryBaseSets
                let repsMin = isGluteIsolation ? 12 : (isCompound ? 6 : 10)
                let repsMax = isGluteIsolation ? 20 : (isCompound ? 10 : 15)
                let rest = isCompound ? 120 : 75  // Compounds 2 min, isolation 60-90 sec for deload
                return (sets: sets, repsMin: repsMin, repsMax: repsMax, rir: 4, rest: rest)
            }
        }
    }
    
    // MARK: - Main Generation Method
    
    /// Generate 10 personalized programs for the user
    /// Mix of different types, splits, and durations to keep user engaged
    func generatePersonalizedPrograms(for profile: UserProgramProfile) -> [GeneratedProgram] {
        #if DEBUG
        AppLogger.debug("🎯 Generating 10 personalized programs...", category: .workout)
        AppLogger.debug("   Goals: \(profile.goals)", category: .workout)
        AppLogger.debug("   Experience: \(profile.experienceLevel.rawValue)", category: .workout)
        AppLogger.debug("   Days/week: \(profile.daysPerWeek)", category: .workout)
        AppLogger.debug("   Equipment: \(profile.availableEquipment)", category: .workout)
        AppLogger.debug("   Location: \(profile.workoutLocation.rawValue)", category: .workout)
        #endif
        
        var programs: [GeneratedProgram] = []
        
        // Determine best split types based on days per week
        let recommendedSplits = getRecommendedSplits(daysPerWeek: profile.daysPerWeek, experience: profile.experienceLevel)
        
        // Determine program types based on goals
        let programTypes = getProgramTypes(for: profile.goals)
        
        // Generate 10 programs with variety in:
        // 1. Program types (hypertrophy, strength, fat loss, etc.)
        // 2. Split types (PPL, Upper/Lower, Full Body, etc.)
        // 3. Durations (1 week, 2 weeks, 3 weeks, 4 weeks)
        // 4. Focus areas (different muscle emphasis)
        
        let durations = [1, 1, 2, 2, 3, 3, 4, 4, 2, 3] // weeks - varying lengths
        
        for index in 0..<10 {
            let programType = programTypes[index % programTypes.count]
            let split = recommendedSplits[index % recommendedSplits.count]
            let weekDuration = durations[index]
            
            if let program = generateProgram(
                type: programType,
                split: split,
                profile: profile,
                programIndex: index,
                customDuration: weekDuration
            ) {
                programs.append(program)
            }
        }
        
        #if DEBUG
        AppLogger.info("✅ Generated \(programs.count) personalized programs with varying durations", category: .workout)
        #endif
        return programs
    }
    
    // MARK: - Split Type Recommendations
    
    private func getRecommendedSplits(daysPerWeek: Int, experience: UserProgramProfile.ExperienceLevel) -> [GeneratedProgram.SplitType] {
        switch daysPerWeek {
        case 2:
            return [.fullBody, .upperLower]
        case 3:
            return [.fullBody, .pushPullLegs, .upperLower]
        case 4:
            return [.upperLower, .pushPullLegs, .pushPull]
        case 5:
            return [.pushPullLegs, .upperLower, .broSplit]
        case 6:
            return [.pushPullLegs, .arnoldSplit, .broSplit, .upperLower]
        case 7:
            return [.pushPullLegs]
        default:
            return [.fullBody]
        }
    }
    
    // MARK: - Program Type from Goals
    
    private func getProgramTypes(for goals: [String]) -> [GeneratedProgram.ProgramType] {
        var types: [GeneratedProgram.ProgramType] = []
        
        for goal in goals {
            switch goal.lowercased() {
            case let g where g.contains("muscle") || g.contains("size") || g.contains("mass"):
                types.append(.hypertrophy)
            case let g where g.contains("strength") || g.contains("strong") || g.contains("power"):
                types.append(.strength)
            case let g where g.contains("fat") || g.contains("lose") || g.contains("lean") || g.contains("cut"):
                types.append(.fatLoss)
            case let g where g.contains("tone") || g.contains("define"):
                types.append(.toning)
            case let g where g.contains("fit") || g.contains("health"):
                types.append(.generalFitness)
            default:
                types.append(.generalFitness)
            }
        }
        
        // Always include variety
        let allTypes: [GeneratedProgram.ProgramType] = [.hypertrophy, .strength, .fatLoss, .toning, .generalFitness]
        for type in allTypes where !types.contains(type) {
            types.append(type)
        }
        
        return Array(Set(types)).sorted { $0.rawValue < $1.rawValue }
    }
    
    // MARK: - Generate Single Program
    
    private func generateProgram(
        type: GeneratedProgram.ProgramType,
        split: GeneratedProgram.SplitType,
        profile: UserProgramProfile,
        programIndex: Int,
        customDuration: Int? = nil
    ) -> GeneratedProgram? {
        
        let programName = generateProgramName(type: type, split: split, profile: profile, programIndex: programIndex)
        let description = generateProgramDescription(type: type, split: split, profile: profile)
        
        // Use custom duration or calculate based on experience
        let durationWeeks = customDuration ?? getDurationWeeks(for: profile.experienceLevel)
        
        // Generate muscle group rotation based on split
        let muscleRotation = generateMuscleRotation(split: split, daysPerWeek: profile.daysPerWeek, type: type)
        
        // Generate Day 1 immediately (other days generated on-demand as user progresses)
        let day1 = generateDay1(
            muscleRotation: muscleRotation,
            profile: profile,
            programType: type
        )
        
        return GeneratedProgram(
            id: UUID().uuidString,
            name: programName,
            description: description,
            icon: getIconForType(type),
            color: getColorForType(type),
            programType: type,
            splitType: split,
            durationWeeks: durationWeeks, // Now uses custom or calculated duration
            daysPerWeek: profile.daysPerWeek,
            difficulty: profile.experienceLevel.rawValue,
            targetGoals: profile.goals,
            requiredEquipment: profile.availableEquipment,
            benefits: getBenefits(for: type),
            muscleGroupRotation: muscleRotation,
            generatedDays: day1 != nil ? [day1!] : [],
            isActive: false,
            createdAt: Date()
        )
    }
    
    // MARK: - Muscle Group Rotation (Using SmartDayGenerator for specific titles)
    
    private func generateMuscleRotation(
        split: GeneratedProgram.SplitType,
        daysPerWeek: Int,
        type: GeneratedProgram.ProgramType
    ) -> [GeneratedProgram.MuscleGroupDay] {
        
        // Get specific day titles from SmartDayGenerator
        let dayTitles = SmartDayGenerator.shared.getDayTitles(
            for: split,
            programType: type,
            daysPerWeek: daysPerWeek
        )
        
        var rotation: [GeneratedProgram.MuscleGroupDay] = []
        
        for (index, template) in dayTitles.enumerated() {
            // Determine intensity based on day position
            let intensity: GeneratedProgram.MuscleGroupDay.Intensity
            switch index % 4 {
            case 0: intensity = .heavy
            case 1: intensity = .moderate
            case 2: intensity = .heavy
            case 3: intensity = .light
            default: intensity = .moderate
            }
            
            rotation.append(GeneratedProgram.MuscleGroupDay(
                dayNumber: index + 1,
                name: template.title,  // Use the specific title from SmartDayGenerator
                primaryMuscles: template.targetMuscles,
                secondaryMuscles: template.secondaryMuscles,
                isRestDay: false,
                intensity: intensity
            ))
        }
        
        return rotation
    }
    
    // MARK: - Generate Day 1
    
    private func generateDay1(
        muscleRotation: [GeneratedProgram.MuscleGroupDay],
        profile: UserProgramProfile,
        programType: GeneratedProgram.ProgramType
    ) -> GeneratedProgramDay? {
        
        guard let day1Template = muscleRotation.first else { return nil }
        
        // Get exercises for Day 1
        let exercises = SmartDayGenerator.shared.generateExercisesForDay(
            targetMuscles: day1Template.primaryMuscles + day1Template.secondaryMuscles,
            availableEquipment: profile.availableEquipment,
            experience: profile.experienceLevel,
            programType: programType,
            intensity: day1Template.intensity,
            previousDayExercises: [],
            dayInProgram: 1
        )
        
        return GeneratedProgramDay(
            id: UUID().uuidString,
            dayNumber: 1,
            weekNumber: 1,
            name: day1Template.name,
            focusMuscles: day1Template.primaryMuscles,
            exercises: exercises,
            estimatedDuration: calculateDuration(exercises: exercises, restSeconds: profile.experienceLevel.restBetweenSets),
            intensity: day1Template.intensity.rawValue,
            isCompleted: false,
            completedAt: nil,
            notes: nil
        )
    }
    
    // MARK: - Generate Next Day
    
    /// Call this when user completes a day to generate the next day
    func generateNextDay(
        for program: inout GeneratedProgram,
        profile: UserProgramProfile,
        completedExercises: [String]
    ) -> GeneratedProgramDay? {
        
        let nextDayNumber = program.generatedDays.count + 1
        let weekNumber = ((nextDayNumber - 1) / program.daysPerWeek) + 1
        let dayInWeek = ((nextDayNumber - 1) % program.daysPerWeek) + 1
        
        // Get the template for this day
        guard dayInWeek <= program.muscleGroupRotation.count else { return nil }
        let dayTemplate = program.muscleGroupRotation[dayInWeek - 1]
        
        // Get previous day's exercises to avoid
        let previousExercises = program.generatedDays.last?.exercises.map { $0.exerciseName } ?? []
        
        // Generate exercises considering recovery and previous workouts
        let exercises = SmartDayGenerator.shared.generateExercisesForDay(
            targetMuscles: dayTemplate.primaryMuscles + dayTemplate.secondaryMuscles,
            availableEquipment: profile.availableEquipment,
            experience: profile.experienceLevel,
            programType: program.programType,
            intensity: dayTemplate.intensity,
            previousDayExercises: previousExercises,
            dayInProgram: nextDayNumber
        )
        
        let newDay = GeneratedProgramDay(
            id: UUID().uuidString,
            dayNumber: nextDayNumber,
            weekNumber: weekNumber,
            name: dayTemplate.name,
            focusMuscles: dayTemplate.primaryMuscles,
            exercises: exercises,
            estimatedDuration: calculateDuration(exercises: exercises, restSeconds: profile.experienceLevel.restBetweenSets),
            intensity: dayTemplate.intensity.rawValue,
            isCompleted: false,
            completedAt: nil,
            notes: nil
        )
        
        program.generatedDays.append(newDay)
        return newDay
    }
    
    // MARK: - Sequel Program Generation
    
    /// Generate a sequel/continuation program that builds on completed program
    /// Creates progression with similar focus but increased challenge
    func generateSequelProgram(
        previousProgram: GeneratedProgram,
        profile: UserProgramProfile,
        sequelName: String
    ) -> GeneratedProgram? {
        
        #if DEBUG
        AppLogger.debug("🎬 Creating sequel for: \(previousProgram.name)", category: .workout)
        #endif
        
        // Keep same type and split for continuity
        let type = previousProgram.programType
        let split = previousProgram.splitType
        
        // Increase duration slightly (but keep variety)
        let newDuration = min(previousProgram.durationWeeks + 1, 6) // Cap at 6 weeks
        
        let description = "\(previousProgram.description) This advanced phase builds on your previous progress."
        
        // Generate muscle group rotation (same as before for continuity)
        let muscleRotation = generateMuscleRotation(split: split, daysPerWeek: profile.daysPerWeek, type: type)
        
        // Generate Day 1 immediately
        let day1 = generateDay1(
            muscleRotation: muscleRotation,
            profile: profile,
            programType: type
        )
        
        return GeneratedProgram(
            id: UUID().uuidString,
            name: sequelName,
            description: description,
            icon: getIconForType(type),
            color: getColorForType(type),
            programType: type,
            splitType: split,
            durationWeeks: newDuration,
            daysPerWeek: profile.daysPerWeek,
            difficulty: profile.experienceLevel.rawValue,
            targetGoals: profile.goals,
            requiredEquipment: profile.availableEquipment,
            benefits: getBenefits(for: type),
            muscleGroupRotation: muscleRotation,
            generatedDays: day1 != nil ? [day1!] : [],
            isActive: false,
            createdAt: Date()
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateProgramName(type: GeneratedProgram.ProgramType, split: GeneratedProgram.SplitType, profile: UserProgramProfile, programIndex: Int) -> String {
        // More diverse and engaging program names
        let typeNames: [GeneratedProgram.ProgramType: [String]] = [
            .hypertrophy: ["Muscle Builder", "Size Surge", "Growth Phase", "Mass Maker", "Volume Protocol", "Hypertrophy Block", "Size & Strength", "Muscle Matrix", "Build Phase", "Mass Protocol"],
            .strength: ["Strength Foundation", "Power Protocol", "Strong Basics", "Force Builder", "Power Block", "Strength Cycle", "Max Strength", "Heavy Lifts", "Foundation Build", "Strength Matrix"],
            .fatLoss: ["Lean Machine", "Burn & Build", "Cut Cycle", "Shred Program", "Fat Loss Protocol", "Lean & Mean", "Get Shredded", "Metabolic Burn", "Cut Phase", "Lean Protocol"],
            .toning: ["Definition Drive", "Tone & Sculpt", "Shape Up", "Body Sculpt", "Define & Refine", "Tone Protocol", "Sculpt Phase", "Body Shaper", "Definition Block", "Tone Matrix"],
            .generalFitness: ["Fit Foundations", "Total Fitness", "Balanced Body", "Well Rounded", "Fitness Protocol", "Complete Fitness", "Balanced Approach", "Fitness Matrix", "All-Around Fit", "Total Body"]
        ]
        
        let names = typeNames[type] ?? ["Custom Program"]
        let baseName = names[programIndex % names.count] // Use index for variety
        
        // Add split descriptor
        let splitDescriptor: String
        switch split {
        case .pushPullLegs:
            splitDescriptor = "PPL"
        case .upperLower:
            splitDescriptor = "Upper/Lower"
        case .fullBody:
            splitDescriptor = "Full Body"
        case .broSplit:
            splitDescriptor = "Split"
        case .pushPull:
            splitDescriptor = "Push/Pull"
        case .arnoldSplit:
            splitDescriptor = "Arnold"
        }
        
        return "\(baseName) - \(splitDescriptor)"
    }
    
    private func generateProgramDescription(type: GeneratedProgram.ProgramType, split: GeneratedProgram.SplitType, profile: UserProgramProfile) -> String {
        let typeDesc: [GeneratedProgram.ProgramType: String] = [
            .hypertrophy: "Focus on building muscle size through optimal volume and progressive overload.",
            .strength: "Build raw strength with compound movements and progressive loading.",
            .fatLoss: "Burn fat while maintaining muscle with high-intensity training and smart exercise selection.",
            .toning: "Sculpt and define your physique with targeted exercises and moderate intensity.",
            .generalFitness: "Improve overall fitness, strength, and endurance with balanced training."
        ]
        
        let base = typeDesc[type] ?? "Customized workout program."
        return "\(base) Using a \(split.rawValue.lowercased()) split, \(profile.daysPerWeek) days per week."
    }
    
    private func getIconForType(_ type: GeneratedProgram.ProgramType) -> String {
        switch type {
        case .hypertrophy: return "figure.strengthtraining.traditional"
        case .strength: return "dumbbell.fill"
        case .fatLoss: return "flame.fill"
        case .toning: return "sparkles"
        case .generalFitness: return "figure.run"
        case .powerbuilding: return "bolt.fill"
        }
    }
    
    private func getColorForType(_ type: GeneratedProgram.ProgramType) -> String {
        switch type {
        case .hypertrophy: return "blue"
        case .strength: return "red"
        case .fatLoss: return "orange"
        case .toning: return "purple"
        case .generalFitness: return "green"
        case .powerbuilding: return "yellow"
        }
    }
    
    private func getDurationWeeks(for experience: UserProgramProfile.ExperienceLevel) -> Int {
        switch experience {
        case .beginner: return 4
        case .intermediate: return 6
        case .advanced: return 8
        }
    }
    
    private func getBenefits(for type: GeneratedProgram.ProgramType) -> [String] {
        switch type {
        case .hypertrophy:
            return ["Build muscle mass", "Improve body composition", "Increase strength", "Boost metabolism"]
        case .strength:
            return ["Get stronger", "Build functional power", "Improve bone density", "Enhance performance"]
        case .fatLoss:
            return ["Burn body fat", "Boost metabolism", "Build lean muscle", "Improve endurance"]
        case .toning:
            return ["Define muscles", "Improve shape", "Build endurance", "Enhance flexibility"]
        case .generalFitness:
            return ["Improve overall health", "Build balanced strength", "Increase energy", "Better daily function"]
        case .powerbuilding:
            return ["Build size and strength", "Functional power", "Athletic performance", "Balanced development"]
        }
    }
    
    private func calculateDuration(exercises: [GeneratedExercise], restSeconds: Int) -> Int {
        var totalSeconds = 0
        
        for exercise in exercises {
            // Estimate 30-45 seconds per rep depending on exercise
            let timePerSet = 40 + (exercise.repsMax * 3) // seconds
            totalSeconds += exercise.sets * timePerSet
            totalSeconds += exercise.sets * restSeconds
        }
        
        return totalSeconds / 60 // Convert to minutes
    }
    
    // MARK: - Create Profile from User
    
    func createProfileFromUser(_ user: User) -> UserProgramProfile {
        let goals = (user.fitnessGoal ?? "General Fitness").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        let experience: UserProgramProfile.ExperienceLevel
        switch (user.experienceLevel ?? "Beginner").lowercased() {
        case "advanced": experience = .advanced
        case "intermediate": experience = .intermediate
        default: experience = .beginner
        }
        
        let equipment = (user.equipment as? [String]) ?? ["Bodyweight"]
        
        let location: UserProgramProfile.WorkoutLocation
        if equipment.contains(where: { $0.lowercased().contains("machine") || $0.lowercased().contains("cable") }) {
            location = .gym
        } else if equipment.count <= 2 {
            location = .minimal
        } else {
            location = .home
        }
        
        return UserProgramProfile(
            goals: goals,
            experienceLevel: experience,
            daysPerWeek: Int(user.availableDays),
            availableEquipment: equipment,
            workoutLocation: location,
            age: Int(user.age),
            gender: user.gender,
            preferredDuration: 45 // Default, can be made configurable
        )
    }
}

