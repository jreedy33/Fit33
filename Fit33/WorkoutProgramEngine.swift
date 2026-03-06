import Foundation
import CoreData

// MARK: - Workout Program Models

struct WorkoutProgram: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let duration: Int // in days
    let difficulty: ProgramDifficulty
    let focus: ProgramFocus
    let schedule: [Int: ProgramDay] // Day number to workout
    let restDays: Set<Int> // Which days are rest days
    let icon: String
    let color: String
    let workoutsPerWeek: Int
    let estimatedTimePerWorkout: Int // in minutes
    let equipment: [String]
    let benefits: [String]
    let preview: String // Short preview of what to expect
    
    // Custom Codable implementation for [Int: ProgramDay] dictionary
    enum CodingKeys: String, CodingKey {
        case id, name, description, duration, difficulty, focus
        case scheduleData, restDays, icon, color, workoutsPerWeek
        case estimatedTimePerWorkout, equipment, benefits, preview
    }
    
    init(id: String, name: String, description: String, duration: Int, difficulty: ProgramDifficulty, focus: ProgramFocus, schedule: [Int: ProgramDay], restDays: Set<Int>, icon: String, color: String, workoutsPerWeek: Int, estimatedTimePerWorkout: Int, equipment: [String], benefits: [String], preview: String) {
        self.id = id
        self.name = name
        self.description = description
        self.duration = duration
        self.difficulty = difficulty
        self.focus = focus
        self.schedule = schedule
        self.restDays = restDays
        self.icon = icon
        self.color = color
        self.workoutsPerWeek = workoutsPerWeek
        self.estimatedTimePerWorkout = estimatedTimePerWorkout
        self.equipment = equipment
        self.benefits = benefits
        self.preview = preview
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        duration = try container.decode(Int.self, forKey: .duration)
        difficulty = try container.decode(ProgramDifficulty.self, forKey: .difficulty)
        focus = try container.decode(ProgramFocus.self, forKey: .focus)
        
        // Decode schedule as array of key-value pairs
        let scheduleArray = try container.decode([[String: ProgramDay]].self, forKey: .scheduleData)
        var scheduleDict: [Int: ProgramDay] = [:]
        for item in scheduleArray {
            if let (key, value) = item.first, let intKey = Int(key) {
                scheduleDict[intKey] = value
            }
        }
        schedule = scheduleDict
        
        restDays = try container.decode(Set<Int>.self, forKey: .restDays)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        workoutsPerWeek = try container.decode(Int.self, forKey: .workoutsPerWeek)
        estimatedTimePerWorkout = try container.decode(Int.self, forKey: .estimatedTimePerWorkout)
        equipment = try container.decode([String].self, forKey: .equipment)
        benefits = try container.decode([String].self, forKey: .benefits)
        preview = try container.decode(String.self, forKey: .preview)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(duration, forKey: .duration)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(focus, forKey: .focus)
        
        // Encode schedule as array of key-value pairs
        let scheduleArray = schedule.map { [String($0.key): $0.value] }
        try container.encode(scheduleArray, forKey: .scheduleData)
        
        try container.encode(restDays, forKey: .restDays)
        try container.encode(icon, forKey: .icon)
        try container.encode(color, forKey: .color)
        try container.encode(workoutsPerWeek, forKey: .workoutsPerWeek)
        try container.encode(estimatedTimePerWorkout, forKey: .estimatedTimePerWorkout)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(benefits, forKey: .benefits)
        try container.encode(preview, forKey: .preview)
    }
}

enum ProgramDifficulty: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

enum ProgramFocus: String, CaseIterable, Codable {
    case strength = "Strength"
    case hypertrophy = "Hypertrophy"
    case endurance = "Endurance"
    case powerbuilding = "Powerbuilding"
    case bodyweight = "Bodyweight"
    case fullBody = "Full Body"
    case upperLower = "Upper/Lower Split"
    case pushPullLegs = "Push/Pull/Legs"
    case bodypart = "Body Part Split"
    case athletic = "Athletic Performance"
}

struct ProgramDay: Codable {
    let dayNumber: Int
    let name: String
    let focus: [String] // e.g., ["Chest", "Triceps"] - PRIMARY muscle groups for the day
    let exerciseCount: Int
    let intensity: DayIntensity
    let workoutTemplate: WorkoutTemplate // Optional template for reference
    let equipment: [String] // Required equipment for this day
    
    // Use this to generate fresh workouts instead of fixed template
    var shouldUseIntelligentGenerator: Bool {
        return true // Always use intelligent generator for variety
    }
    
    enum CodingKeys: String, CodingKey {
        case dayNumber, name, focus, exerciseCount, intensity, workoutTemplate, equipment
    }
}

enum DayIntensity: String, Codable {
    case light = "Light"
    case moderate = "Moderate"
    case heavy = "Heavy"
    case deload = "Deload"
}

struct WorkoutTemplate: Codable {
    let name: String
    let exercises: [ExerciseTemplate]
}

struct ExerciseTemplate: Codable {
    let exerciseName: String
    let sets: Int
    let reps: String // e.g., "8-12", "15-20", "AMRAP"
    let restSeconds: Int
    let notes: String?
}

// MARK: - Program Generator Engine

class WorkoutProgramEngine {
    static let shared = WorkoutProgramEngine()
    
    private init() {}
    
    // MARK: - Exercise Database Access
    
    private func findExercise(byName name: String) -> ExerciseData? {
        return ExerciseDataProvider.shared.exercises.first { $0.name == name }
    }
    
    // MARK: - Generate Actual Workout from ProgramDay
    
    func generateWorkoutFromProgramDay(_ programDay: ProgramDay, context: NSManagedObjectContext) -> (Workout, [Exercise]) {
        let workout = Workout(context: context)
        workout.id = UUID()
        workout.name = programDay.name
        workout.date = Date()
        workout.duration = 0
        workout.isCompleted = false
        
        print("🎯 Generating workout for: \(programDay.name)")
        print("   Focus areas: \(programDay.focus)")
        print("   Equipment: \(programDay.equipment)")
        print("   Exercise count: \(programDay.exerciseCount)")
        print("   Intensity: \(programDay.intensity.rawValue)")
        
        // Use intelligent generator with the day's specific focus
        let focusAreas = Set(programDay.focus.map { $0.lowercased() })
        let equipment = Set(programDay.equipment.map { $0.lowercased() })
        
        // Map intensity to difficulty
        let difficulty: IntelligentWorkoutGenerator.ExerciseComplexity
        switch programDay.intensity {
        case .light, .deload:
            difficulty = .beginner
        case .moderate:
            difficulty = .intermediate
        case .heavy:
            difficulty = .advanced
        }
        
        let intelligentGenerator = IntelligentWorkoutGenerator.shared
        let generatedExerciseData = intelligentGenerator.generateIntelligentWorkout(
            targetBodyParts: focusAreas,
            availableEquipment: equipment,
            difficulty: difficulty,
            exerciseCount: programDay.exerciseCount,
            avoidRecentExercises: true,
            balanceMovementPatterns: true
        )
        
        // Convert to Core Data exercises
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let exercises = generatedExerciseData.compactMap { exerciseData in
            allExercises.first { $0.name == exerciseData.name }
        }
        
        print("✅ Generated \(exercises.count) fresh exercises for Day \(programDay.dayNumber)")
        
        return (workout, exercises)
    }
    
    // Legacy method - kept for backward compatibility
    func generateWorkoutFromTemplate(_ template: WorkoutTemplate, context: NSManagedObjectContext, useIntelligentGenerator: Bool = true) -> (Workout, [Exercise]) {
        // Create a basic program day from template
        let programDay = ProgramDay(
            dayNumber: 1,
            name: template.name,
            focus: ["Full Body"],
            exerciseCount: template.exercises.count,
            intensity: .moderate,
            workoutTemplate: template,
            equipment: ["All"]
        )
        return generateWorkoutFromProgramDay(programDay, context: context)
    }
    
    // MARK: - Pre-Made Programs Library
    
    func getAllPrograms() -> [WorkoutProgram] {
        return [
            // Beginner Programs
            create30DayBeginnerProgram(),
            create7DayFullBodyIntro(),
            
            // Intermediate Programs
            create90DayMuscleBuilding(),
            create30DayPushPullLegs(),
            create7DayArmBlitz(),
            create7DayChestBack(),
            
            // Advanced Programs
            create90DayStrengthAndSize(),
            create30DayPowerbuilding(),
            
            // Specialized Programs
            create30DayBodyweight(),
            create14DayUpperBodyIntensity()
        ]
    }
    
    // MARK: - Program Builders
    
    private func create30DayBeginnerProgram() -> WorkoutProgram {
        var schedule: [Int: ProgramDay] = [:]
        
        // Week 1: Foundation (3 days per week - Full Body)
        schedule[1] = ProgramDay(
            dayNumber: 1,
            name: "Full Body Foundation A",
            focus: ["Full Body", "Compound Movements"],
            exerciseCount: 6,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Beginner Full Body A", exercises: [
                ExerciseTemplate(exerciseName: "Bodyweight Squat", sets: 3, reps: "12-15", restSeconds: 60, notes: "Focus on form"),
                ExerciseTemplate(exerciseName: "Push Up", sets: 3, reps: "8-12", restSeconds: 60, notes: "Modify on knees if needed"),
                ExerciseTemplate(exerciseName: "Dumbbell Row", sets: 3, reps: "10-12", restSeconds: 60, notes: "Control the movement"),
                ExerciseTemplate(exerciseName: "Dumbbell Shoulder Press", sets: 3, reps: "10-12", restSeconds: 60, notes: nil),
                ExerciseTemplate(exerciseName: "Plank", sets: 3, reps: "30 sec", restSeconds: 45, notes: "Maintain straight body"),
                ExerciseTemplate(exerciseName: "Dumbbell Biceps Curl", sets: 2, reps: "12-15", restSeconds: 45, notes: nil)
            ]),
            equipment: ["Bodyweight", "Dumbbells"]
        )
        
        schedule[3] = ProgramDay(
            dayNumber: 3,
            name: "Full Body Foundation B",
            focus: ["Full Body", "Stability"],
            exerciseCount: 6,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Beginner Full Body B", exercises: [
                ExerciseTemplate(exerciseName: "Dumbbell Goblet Squat", sets: 3, reps: "12-15", restSeconds: 60, notes: "Keep chest up"),
                ExerciseTemplate(exerciseName: "Dumbbell Bench Press", sets: 3, reps: "10-12", restSeconds: 60, notes: "Full range of motion"),
                ExerciseTemplate(exerciseName: "Lat Pulldown", sets: 3, reps: "10-12", restSeconds: 60, notes: "Pull to chest"),
                ExerciseTemplate(exerciseName: "Dumbbell Lateral Raise", sets: 3, reps: "12-15", restSeconds: 45, notes: "Light weight"),
                ExerciseTemplate(exerciseName: "Crunch", sets: 3, reps: "15-20", restSeconds: 45, notes: "Slow and controlled"),
                ExerciseTemplate(exerciseName: "Dumbbell Hammer Curl", sets: 2, reps: "12-15", restSeconds: 45, notes: nil)
            ]),
            equipment: ["Dumbbells", "Cables", "Machines"]
        )
        
        schedule[5] = ProgramDay(
            dayNumber: 5,
            name: "Full Body Foundation C",
            focus: ["Full Body", "Endurance"],
            exerciseCount: 6,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Beginner Full Body C", exercises: [
                ExerciseTemplate(exerciseName: "Dumbbell Lunge", sets: 3, reps: "10 each leg", restSeconds: 60, notes: "Alternate legs"),
                ExerciseTemplate(exerciseName: "Dumbbell Incline Bench Press", sets: 3, reps: "10-12", restSeconds: 60, notes: "Upper chest focus"),
                ExerciseTemplate(exerciseName: "Cable Seated Row", sets: 3, reps: "12-15", restSeconds: 60, notes: "Squeeze shoulder blades"),
                ExerciseTemplate(exerciseName: "Dumbbell Front Raise", sets: 3, reps: "12-15", restSeconds: 45, notes: "Controlled tempo"),
                ExerciseTemplate(exerciseName: "Bicycle Crunch", sets: 3, reps: "20 total", restSeconds: 45, notes: "Touch elbow to knee"),
                ExerciseTemplate(exerciseName: "Cable Triceps Pushdown", sets: 2, reps: "12-15", restSeconds: 45, notes: nil)
            ]),
            equipment: ["Dumbbells", "Cables"]
        )
        
        // Weeks 2-4: Progressive overload with same structure
        // Add more days with increasing volume and intensity
        
        return WorkoutProgram(
            id: "30_day_beginner",
            name: "30-Day Beginner Builder",
            description: "Perfect introduction to strength training. Build foundational strength, learn proper form, and establish a consistent workout habit.",
            duration: 30,
            difficulty: .beginner,
            focus: .fullBody,
            schedule: schedule,
            restDays: Set([2, 4, 6, 7, 9, 11, 13, 14, 16, 18, 20, 21, 23, 25, 27, 28, 30]),
            icon: "figure.strengthtraining.traditional",
            color: "blue",
            workoutsPerWeek: 3,
            estimatedTimePerWorkout: 45,
            equipment: ["Dumbbells", "Bodyweight", "Bench"],
            benefits: [
                "Build strength foundation",
                "Learn proper form",
                "Establish workout habit",
                "Increase energy levels",
                "Improve overall fitness"
            ],
            preview: "3 full-body workouts per week focusing on compound movements and proper technique"
        )
    }
    
    private func create90DayMuscleBuilding() -> WorkoutProgram {
        var schedule: [Int: ProgramDay] = [:]
        
        // Phase 1 (Days 1-30): Foundation & Volume - Push/Pull/Legs split, 6 days per week
        let pushPullLegsPattern = [
            ("Push - Chest Focus", ["Chest", "Shoulders", "Triceps"], 8),
            ("Pull - Back Width", ["Back", "Biceps"], 8),
            ("Legs - Quad Focus", ["Legs", "Glutes"], 7),
            ("Push - Shoulder Focus", ["Shoulders", "Chest", "Triceps"], 8),
            ("Pull - Back Thickness", ["Back", "Biceps", "Traps"], 8),
            ("Legs - Hamstring Focus", ["Hamstrings", "Glutes", "Calves"], 7)
        ]
        
        // Generate 90 days with cycling pattern
        var dayCounter = 1
        for week in 1...13 { // 13 weeks = 91 days
            for (index, pattern) in pushPullLegsPattern.enumerated() {
                if dayCounter <= 90 {
                    let intensity: DayIntensity = (week % 4 == 0) ? .deload : (index < 3 ? .heavy : .moderate)
                    schedule[dayCounter] = ProgramDay(
                        dayNumber: dayCounter,
                        name: pattern.0,
                        focus: pattern.1,
                        exerciseCount: pattern.2,
                        intensity: intensity,
                        workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
                        equipment: ["Barbell", "Dumbbells", "Cables", "Machines"]
                    )
                    dayCounter += 1
                }
            }
        }
        
        return WorkoutProgram(
            id: "90_day_muscle_building",
            name: "90-Day Muscle Building",
            description: "Comprehensive 3-month program designed for serious muscle growth. Push/Pull/Legs split with progressive overload and strategic deloads.",
            duration: 90,
            difficulty: .intermediate,
            focus: .hypertrophy,
            schedule: schedule,
            restDays: Set([7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84]), // Rest Sundays
            icon: "figure.strengthtraining.traditional",
            color: "purple",
            workoutsPerWeek: 6,
            estimatedTimePerWorkout: 75,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines", "Bench"],
            benefits: [
                "Maximize muscle growth",
                "Increase strength significantly",
                "Progressive overload system",
                "Balanced physique development",
                "Enhanced work capacity"
            ],
            preview: "Push/Pull/Legs split 6x per week with strategic volume progression and deload weeks"
        )
    }
    
    private func create7DayArmBlitz() -> WorkoutProgram {
        var schedule: [Int: ProgramDay] = [:]
        
        // All 7 days focused on arms with varied approaches
        // Day 1: Biceps Heavy Focus
        schedule[1] = ProgramDay(
            dayNumber: 1,
            name: "Biceps Heavy",
            focus: ["Biceps"],
            exerciseCount: 6,
            intensity: .heavy,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Barbell", "Dumbbells", "Cables"]
        )
        
        // Day 2: Triceps Heavy Focus
        schedule[2] = ProgramDay(
            dayNumber: 2,
            name: "Triceps Heavy",
            focus: ["Triceps"],
            exerciseCount: 6,
            intensity: .heavy,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Barbell", "Dumbbells", "Cables"]
        )
        
        // Day 3: Forearms & Grip
        schedule[3] = ProgramDay(
            dayNumber: 3,
            name: "Forearms & Grip",
            focus: ["Forearms", "Biceps"],
            exerciseCount: 5,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Barbell", "Dumbbells", "Cables"]
        )
        
        // Day 4: Arms Superset (Both)
        schedule[4] = ProgramDay(
            dayNumber: 4,
            name: "Biceps & Triceps",
            focus: ["Biceps", "Triceps"],
            exerciseCount: 8,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Cables"]
        )
        
        // Day 5: Biceps Volume
        schedule[5] = ProgramDay(
            dayNumber: 5,
            name: "Biceps Volume",
            focus: ["Biceps", "Forearms"],
            exerciseCount: 5,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Barbell", "Dumbbells", "Cables"]
        )
        
        // Day 6: Triceps Volume
        schedule[6] = ProgramDay(
            dayNumber: 6,
            name: "Triceps Volume",
            focus: ["Triceps"],
            exerciseCount: 5,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Cables"]
        )
        
        // Day 7: Arms Finisher
        schedule[7] = ProgramDay(
            dayNumber: 7,
            name: "Arms Pump Finisher",
            focus: ["Biceps", "Triceps"],
            exerciseCount: 6,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Cables", "Dumbbells"]
        )
        
        return WorkoutProgram(
            id: "7_day_arm_blitz",
            name: "7-Day Arm Blitz",
            description: "Intense one-week program dedicated to maximum arm growth. High volume, varied angles, and daily arm training.",
            duration: 7,
            difficulty: .intermediate,
            focus: .bodypart,
            schedule: schedule,
            restDays: Set([]), // No rest days
            icon: "figure.arms.open",
            color: "orange",
            workoutsPerWeek: 7,
            estimatedTimePerWorkout: 45,
            equipment: ["Barbell", "Dumbbells", "Cables", "Bench"],
            benefits: [
                "Maximum arm pump",
                "Biceps and triceps growth",
                "Varied training angles",
                "Increased arm strength",
                "Enhanced mind-muscle connection"
            ],
            preview: "7 days of intense arm training with strategic focus rotation"
        )
    }
    
    // Additional program builders (simplified for space)
    
    private func create7DayFullBodyIntro() -> WorkoutProgram {
        var schedule: [Int: ProgramDay] = [:]
        
        // All 7 days with predetermined focus groups - beginner friendly
        // Day 1: Chest & Shoulders
        schedule[1] = ProgramDay(
            dayNumber: 1,
            name: "Chest & Shoulders",
            focus: ["Chest", "Shoulders"],
            exerciseCount: 5,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Bodyweight", "Dumbbells"]
        )
        
        // Day 2: Back & Core
        schedule[2] = ProgramDay(
            dayNumber: 2,
            name: "Back & Core",
            focus: ["Back", "Core"],
            exerciseCount: 5,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Bodyweight"]
        )
        
        // Day 3: Legs & Glutes
        schedule[3] = ProgramDay(
            dayNumber: 3,
            name: "Legs & Glutes",
            focus: ["Legs", "Glutes"],
            exerciseCount: 5,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Bodyweight", "Dumbbells"]
        )
        
        // Day 4: Arms & Shoulders
        schedule[4] = ProgramDay(
            dayNumber: 4,
            name: "Arms & Shoulders",
            focus: ["Biceps", "Triceps", "Shoulders"],
            exerciseCount: 5,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Bodyweight"]
        )
        
        // Day 5: Chest & Back
        schedule[5] = ProgramDay(
            dayNumber: 5,
            name: "Chest & Back",
            focus: ["Chest", "Back"],
            exerciseCount: 6,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Bodyweight"]
        )
        
        // Day 6: Legs & Core
        schedule[6] = ProgramDay(
            dayNumber: 6,
            name: "Legs & Core",
            focus: ["Legs", "Core"],
            exerciseCount: 5,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Bodyweight", "Dumbbells"]
        )
        
        // Day 7: Full Body Finisher
        schedule[7] = ProgramDay(
            dayNumber: 7,
            name: "Full Body Flow",
            focus: ["Chest", "Back", "Legs"],
            exerciseCount: 6,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Bodyweight", "Dumbbells"]
        )
        
        return WorkoutProgram(
            id: "7_day_intro",
            name: "7-Day Full Body Intro",
            description: "Perfect for absolute beginners. Learn basic movements and build confidence in one week.",
            duration: 7,
            difficulty: .beginner,
            focus: .fullBody,
            schedule: schedule,
            restDays: Set([]), // No rest days - every day has a workout
            icon: "star.fill",
            color: "green",
            workoutsPerWeek: 7,
            estimatedTimePerWorkout: 30,
            equipment: ["Bodyweight", "Dumbbells"],
            benefits: ["Learn basics", "Build confidence", "Establish routine"],
            preview: "7 days of varied full-body workouts to kickstart your fitness"
        )
    }
    
    private func create30DayPushPullLegs() -> WorkoutProgram {
        var schedule: [Int: ProgramDay] = [:]
        
        let pplPattern = [
            ("Push - Chest", ["Chest", "Shoulders", "Triceps"], 7),
            ("Pull - Back", ["Back", "Biceps"], 7),
            ("Legs", ["Legs", "Glutes", "Calves"], 7),
            ("Push - Shoulders", ["Shoulders", "Chest", "Triceps"], 7),
            ("Pull - Lats", ["Back", "Biceps", "Traps"], 7),
            ("Legs - Quad Focus", ["Legs", "Glutes"], 7)
        ]
        
        var dayCounter = 1
        while dayCounter <= 30 {
            for (index, pattern) in pplPattern.enumerated() {
                if dayCounter <= 30 && ![7, 14, 21, 28].contains(dayCounter) {
                    schedule[dayCounter] = ProgramDay(
                        dayNumber: dayCounter,
                        name: pattern.0,
                        focus: pattern.1,
                        exerciseCount: pattern.2,
                        intensity: .moderate,
                        workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
                        equipment: ["Barbell", "Dumbbells", "Cables", "Machines"]
                    )
                }
                dayCounter += 1
            }
        }
        
        return WorkoutProgram(
            id: "30_day_ppl",
            name: "30-Day Push/Pull/Legs",
            description: "Classic split for balanced development. Train each muscle group twice per week.",
            duration: 30,
            difficulty: .intermediate,
            focus: .pushPullLegs,
            schedule: schedule,
            restDays: Set([7, 14, 21, 28]),
            icon: "figure.strengthtraining.traditional",
            color: "red",
            workoutsPerWeek: 6,
            estimatedTimePerWorkout: 60,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            benefits: ["Balanced development", "High frequency", "Optimal recovery"],
            preview: "Push/Pull/Legs split training each muscle group twice weekly"
        )
    }
    
    private func create7DayChestBack() -> WorkoutProgram {
        var schedule: [Int: ProgramDay] = [:]
        
        // All 7 days with alternating chest/back focus
        schedule[1] = ProgramDay(
            dayNumber: 1,
            name: "Chest Power",
            focus: ["Chest", "Triceps"],
            exerciseCount: 6,
            intensity: .heavy,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Barbell", "Dumbbells", "Cables"]
        )
        
        schedule[2] = ProgramDay(
            dayNumber: 2,
            name: "Back Thickness",
            focus: ["Back", "Biceps"],
            exerciseCount: 6,
            intensity: .heavy,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Barbell", "Dumbbells", "Cables"]
        )
        
        schedule[3] = ProgramDay(
            dayNumber: 3,
            name: "Chest Volume",
            focus: ["Chest", "Shoulders"],
            exerciseCount: 6,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Cables"]
        )
        
        schedule[4] = ProgramDay(
            dayNumber: 4,
            name: "Back Width",
            focus: ["Back", "Traps"],
            exerciseCount: 6,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Bodyweight", "Dumbbells", "Cables"]
        )
        
        schedule[5] = ProgramDay(
            dayNumber: 5,
            name: "Chest Pump",
            focus: ["Chest", "Triceps"],
            exerciseCount: 5,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Cables"]
        )
        
        schedule[6] = ProgramDay(
            dayNumber: 6,
            name: "Back Detail",
            focus: ["Back", "Biceps"],
            exerciseCount: 5,
            intensity: .moderate,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Dumbbells", "Cables"]
        )
        
        schedule[7] = ProgramDay(
            dayNumber: 7,
            name: "Upper Body Finisher",
            focus: ["Chest", "Back"],
            exerciseCount: 6,
            intensity: .light,
            workoutTemplate: WorkoutTemplate(name: "Reference", exercises: []),
            equipment: ["Bodyweight", "Dumbbells"]
        )
        
        return WorkoutProgram(
            id: "7_day_chest_back",
            name: "7-Day Chest & Back Blitz",
            description: "Build a powerful upper body with dedicated chest and back training every day.",
            duration: 7,
            difficulty: .intermediate,
            focus: .bodypart,
            schedule: schedule,
            restDays: Set([]),
            icon: "figure.strengthtraining.traditional",
            color: "cyan",
            workoutsPerWeek: 7,
            estimatedTimePerWorkout: 55,
            equipment: ["Barbell", "Dumbbells", "Cables", "Pull-Up Bar"],
            benefits: ["Upper body mass", "V-taper development", "Push/pull balance"],
            preview: "7 days of alternating chest and back workouts for maximum growth"
        )
    }
    
    private func create90DayStrengthAndSize() -> WorkoutProgram {
        return WorkoutProgram(
            id: "90_day_strength_size",
            name: "90-Day Strength & Size",
            description: "Advanced program combining powerlifting principles with hypertrophy training.",
            duration: 90,
            difficulty: .advanced,
            focus: .powerbuilding,
            schedule: [:],
            restDays: Set([7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84]),
            icon: "bolt.fill",
            color: "red",
            workoutsPerWeek: 5,
            estimatedTimePerWorkout: 90,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines", "Bench"],
            benefits: ["Maximum strength", "Muscle mass", "Athletic power", "Progressive overload"],
            preview: "Advanced powerbuilding with periodized training for strength and size"
        )
    }
    
    private func create30DayPowerbuilding() -> WorkoutProgram {
        return WorkoutProgram(
            id: "30_day_powerbuilding",
            name: "30-Day Powerbuilding",
            description: "Blend strength and hypertrophy for the best of both worlds.",
            duration: 30,
            difficulty: .advanced,
            focus: .powerbuilding,
            schedule: [:],
            restDays: Set([4, 7, 11, 14, 18, 21, 25, 28]),
            icon: "bolt.shield.fill",
            color: "purple",
            workoutsPerWeek: 5,
            estimatedTimePerWorkout: 75,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            benefits: ["Strength gains", "Muscle growth", "Power development"],
            preview: "Heavy compound lifts followed by hypertrophy accessory work"
        )
    }
    
    private func create30DayBodyweight() -> WorkoutProgram {
        return WorkoutProgram(
            id: "30_day_bodyweight",
            name: "30-Day Bodyweight Challenge",
            description: "No equipment needed. Build strength and muscle using only your body.",
            duration: 30,
            difficulty: .intermediate,
            focus: .bodyweight,
            schedule: [:],
            restDays: Set([7, 14, 21, 28]),
            icon: "figure.run",
            color: "green",
            workoutsPerWeek: 6,
            estimatedTimePerWorkout: 40,
            equipment: ["Bodyweight", "Pull-Up Bar"],
            benefits: ["Train anywhere", "Functional strength", "No equipment needed"],
            preview: "Progressive calisthenics program for strength and mobility"
        )
    }
    
    private func create14DayUpperBodyIntensity() -> WorkoutProgram {
        return WorkoutProgram(
            id: "14_day_upper",
            name: "14-Day Upper Body Intensity",
            description: "Two weeks of focused upper body training for maximum growth.",
            duration: 14,
            difficulty: .intermediate,
            focus: .upperLower,
            schedule: [:],
            restDays: Set([4, 7, 11, 14]),
            icon: "figure.arms.open",
            color: "indigo",
            workoutsPerWeek: 5,
            estimatedTimePerWorkout: 60,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            benefits: ["Upper body mass", "Strength increase", "Defined physique"],
            preview: "High-frequency upper body training with strategic volume"
        )
    }
}

