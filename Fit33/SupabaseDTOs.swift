//
//  SupabaseDTOs.swift
//  Fit33
//
//  Data Transfer Objects for Supabase API communication.
//  Extracted from SupabaseManager.swift for maintainability.
//

import Foundation

// MARK: - Data Transfer Objects (DTOs)

struct UserProfileDTO: Codable {
    let id: String
    let name: String?
    let email: String?
    let birthday: String?
    let age: Int?
    let gender: String?
    let heightCm: Double?
    let heightInches: Int?
    let weightKg: Double?
    let weightLbs: Double?
    let fitnessGoal: String?
    let experienceLevel: String?
    let strengthLevel: String?  // For smart weight recommendations
    let equipment: [String]?
    let availableDays: Int?
    let bmr: Double?
    let tdee: Double?
    let proteinGoalG: Double?
    let carbsGoalG: Double?
    let fatGoalG: Double?
    let dailyCalorieGoal: Int?
    let dailyProteinGoal: Int?
    let dailyCarbsGoal: Int?
    let dailyFatGoal: Int?
    let currentStreak: Int?
    let longestStreak: Int?
    let totalWorkouts: Int?
    let xp: Int?
    let lastWorkoutDate: String?
    let updatedAt: String?
    let hasCompletedOnboarding: Bool?
    let profilePhotoUrl: String?
    // Unit preferences
    let weightUnit: String?
    let heightUnit: String?
    let distanceUnit: String?
    let weekStartDay: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, email, birthday, age, gender, bmr, tdee, equipment, xp
        case heightCm = "height_cm"
        case heightInches = "height_inches"
        case weightKg = "weight_kg"
        case weightLbs = "weight_lbs"
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case strengthLevel = "strength_level"
        case availableDays = "available_days"
        case proteinGoalG = "protein_goal_g"
        case carbsGoalG = "carbs_goal_g"
        case fatGoalG = "fat_goal_g"
        case dailyCalorieGoal = "daily_calorie_goal"
        case dailyProteinGoal = "daily_protein_goal"
        case dailyCarbsGoal = "daily_carbs_goal"
        case dailyFatGoal = "daily_fat_goal"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalWorkouts = "total_workouts"
        case lastWorkoutDate = "last_workout_date"
        case updatedAt = "updated_at"
        case weightUnit = "weight_unit"
        case heightUnit = "height_unit"
        case distanceUnit = "distance_unit"
        case weekStartDay = "week_start_day"
        case hasCompletedOnboarding = "has_completed_onboarding"
        case profilePhotoUrl = "profile_photo_url"
    }
}

struct ExerciseDTO: Codable {
    let id: String?
    let name: String
    let category: String
    let equipment: String?
    let primaryMusclesRaw: MuscleField?   // Can be String or [String] in DB
    let secondaryMusclesRaw: MuscleField? // Can be String or [String] in DB
    let description: String?
    let videoCode: String?          // Unique identifier for the video
    let videoFilename: String?      // Filename for this gender's video (e.g., "44171201-Sumo-Squat.mp4")
    let gender: String?             // "Male" or "Female"
    let isCustom: Bool?
    
    // Enhanced metadata from improved CSV
    let movementPattern: String?
    let forceType: String?
    let movementType: String?
    let laterality: String?
    let planeOfMotion: String?
    let difficultyLevel: Int?
    let complexityScore: Int?
    let strengthRating: Int?
    let hypertrophyRating: Int?
    let powerRating: Int?
    let enduranceRating: Int?
    let bodyPosition: String?
    let benchAngle: String?
    let gripType: String?
    let gripWidth: String?
    let optimalRepRangeMin: Int?
    let optimalRepRangeMax: Int?
    let placementInWorkout: String?
    let fatigabilityRaw: FlexibleInt?
    var fatigability: Int? { fatigabilityRaw?.value }
    let popularityScore: Int?
    let homeGymFriendly: Bool?
    let workoutType: String?
    let practicalityScore: Int?  // 0-100 score for exercise practicality
    
    // Goal-based classification fields (from exercise_goal_classifications.csv)
    let fatLossRating: Int?           // 1-10: How good for Get Lean goal
    let generalFitnessRating: Int?    // 1-10: How good for General Fitness goal
    let isCompound: Bool?             // Multi-joint movement
    let supersetable: Bool?           // Can be done back-to-back
    
    // Exercise family & swap system fields
    let exerciseFamily: String?           // Movement family (e.g., "bicep_curl", "bench_press")
    let baseExerciseName: String?         // Canonical name without equipment
    let complementaryFamilies: String?    // Comma-separated related families
    let isEquipmentPrimary: Bool?         // Is this the gold standard variant?
    let equipmentCategory: String?        // Normalized: barbell, dumbbell, cable, etc.
    let durationBased: Bool?              // Track by time instead of reps?
    let recommendedSets: Int?             // Default sets for this exercise
    let restSeconds: Int?                 // Recommended rest between sets
    let musclesWorkedCount: Int?          // Number of muscle groups engaged
    let priorityBuildMuscle: Int?         // Sort priority for Build Muscle goal
    let priorityGetLean: Int?             // Sort priority for Get Lean goal
    let priorityHome: Int?                // Sort priority for home training
    let priorityGym: Int?                 // Sort priority for gym training
    
    // Helper to handle Int fields that might come as String from database
    struct FlexibleInt: Codable {
        let value: Int
        
        // Direct initializer for creating from Int
        init(_ value: Int) {
            self.value = value
        }
        
        // Optional initializer
        init?(_ value: Int?) {
            guard let v = value else { return nil }
            self.value = v
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self.value = intValue
            } else if let stringValue = try? container.decode(String.self), let parsed = Int(stringValue) {
                self.value = parsed
            } else {
                self.value = 0  // Default to 0 if can't parse
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }
    
    // Helper enum to handle both String and [String] from database
    enum MuscleField: Codable {
        case string(String)
        case array([String])
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let arrayValue = try? container.decode([String].self) {
                self = .array(arrayValue)
            } else {
                self = .string("")
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            }
        }
        
        var asArray: [String] {
            switch self {
            case .string(let str):
                return str.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case .array(let arr):
                return arr.filter { !$0.isEmpty }
            }
        }
    }
    
    // Helper to get muscles as array (handles both String and [String] formats)
    var primaryMusclesArray: [String] {
        primaryMusclesRaw?.asArray ?? []
    }
    
    var secondaryMusclesArray: [String] {
        secondaryMusclesRaw?.asArray ?? []
    }
    
    // Helper fields (not directly from DB)
    let instructions: String?
    let stepsToPerform: String?  // How-to steps for the exercise
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, equipment, description, instructions, gender
        case stepsToPerform = "steps_to_perform"
        case primaryMusclesRaw = "primary_muscles"
        case workoutType = "workout_type"
        case secondaryMusclesRaw = "secondary_muscles"
        case videoCode = "video_code"
        case videoFilename = "video_filename"
        case isCustom = "is_custom"
        case movementPattern = "movement_pattern"
        case forceType = "force_type"
        case planeOfMotion = "plane_of_motion"
        case movementType = "movement_type"
        case laterality
        case difficultyLevel = "difficulty_level"
        case complexityScore = "complexity_score"
        case strengthRating = "strength_rating"
        case hypertrophyRating = "hypertrophy_rating"
        case powerRating = "power_rating"
        case enduranceRating = "endurance_rating"
        case bodyPosition = "body_position"
        case benchAngle = "bench_angle"
        case gripType = "grip_type"
        case gripWidth = "grip_width"
        case optimalRepRangeMin = "optimal_rep_range_min"
        case optimalRepRangeMax = "optimal_rep_range_max"
        case placementInWorkout = "placement_in_workout"
        case fatigabilityRaw = "fatigability"
        case popularityScore = "popularity_score"
        case homeGymFriendly = "home_gym_friendly"
        case practicalityScore = "practicality_score"
        case fatLossRating = "fat_loss_rating"
        case generalFitnessRating = "general_fitness_rating"
        case isCompound = "is_compound"
        case supersetable
        case exerciseFamily = "exercise_family"
        case baseExerciseName = "base_exercise_name"
        case complementaryFamilies = "complementary_families"
        case isEquipmentPrimary = "is_equipment_primary"
        case equipmentCategory = "equipment_category"
        case durationBased = "duration_based"
        case recommendedSets = "recommended_sets"
        case restSeconds = "rest_seconds"
        case musclesWorkedCount = "muscles_worked_count"
        case priorityBuildMuscle = "priority_build_muscle"
        case priorityGetLean = "priority_get_lean"
        case priorityHome = "priority_home"
        case priorityGym = "priority_gym"
    }
}

struct CustomExerciseDTO: Codable {
    let id: String
    let userId: String
    let name: String
    let category: String?
    let primaryMuscles: [String]?
    let secondaryMuscles: [String]?
    let equipment: String?
    let instructions: String?
    let iconName: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, equipment, instructions
        case userId = "user_id"
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case iconName = "icon_name"
    }
}

struct ExercisePairingDTO: Codable {
    let primaryExercise: String
    let secondaryExercise: String
    let pairingFocus: [String]?
    let rationale: String?
    let intensityBalance: String?
    let recommendedTempos: [String]?
    let equipmentContext: [String: String]?
    let synergyScore: Double?
    
    enum CodingKeys: String, CodingKey {
        case primaryExercise = "primary_exercise"
        case secondaryExercise = "secondary_exercise"
        case pairingFocus = "pairing_focus"
        case rationale
        case intensityBalance = "intensity_balance"
        case recommendedTempos = "recommended_tempos"
        case equipmentContext = "equipment_context"
        case synergyScore = "synergy_score"
    }
}

struct EquipmentSubstitutionDTO: Codable {
    let sourceEquipment: String
    let substituteEquipment: String
    let qualityScore: Double?
    let cues: String?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case sourceEquipment = "source_equipment"
        case substituteEquipment = "substitute_equipment"
        case qualityScore = "quality_score"
        case cues, notes
    }
}

struct WorkoutDTO: Codable {
    let id: String
    let userId: String
    let name: String?
    let date: String
    let durationSeconds: Int
    let xpEarned: Int
    let programId: String?
    let programDay: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, date
        case userId = "user_id"
        case durationSeconds = "duration_seconds"
        case xpEarned = "xp_earned"
        case programId = "program_id"
        case programDay = "program_day"
    }
}

struct UserProgressDTO: Codable {
    let id: String
    let userId: String
    let totalXp: Int
    let currentLevel: Int
    let workoutStreak: Int
    let lastWorkoutDate: String?
    let totalWorkouts: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case totalXp = "total_xp"
        case currentLevel = "current_level"
        case workoutStreak = "workout_streak"
        case lastWorkoutDate = "last_workout_date"
        case totalWorkouts = "total_workouts"
    }
}

struct UserFavoriteDTO: Codable {
    let id: String
    let userId: String
    let exerciseId: String
    let exerciseType: String
    let exerciseName: String?  // Added for reliable syncing (IDs change, names don't)
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case exerciseType = "exercise_type"
        case exerciseName = "exercise_name"
    }
}

struct FavoriteWorkoutDTO: Codable {
    let id: String
    let userId: String
    let workoutName: String
    let exerciseNames: [String]
    let originalWorkoutId: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workoutName = "workout_name"
        case exerciseNames = "exercise_names"
        case originalWorkoutId = "original_workout_id"
        case createdAt = "created_at"
    }
}

struct PopularExerciseDTO: Codable {
    let exerciseId: String
    let exerciseName: String
    let totalUses: Int
    let uniqueUsers: Int
    let popularityScore: Double
    let trendingScore: Double
    let avgSetsPerUse: Double
    let completionRate: Double
    let usesLast7Days: Int
    let usesLast30Days: Int
    let favoriteCount: Int
    
    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case totalUses = "total_uses"
        case uniqueUsers = "unique_users"
        case popularityScore = "popularity_score"
        case trendingScore = "trending_score"
        case avgSetsPerUse = "avg_sets_per_use"
        case completionRate = "completion_rate"
        case usesLast7Days = "uses_last_7_days"
        case usesLast30Days = "uses_last_30_days"
        case favoriteCount = "favorite_count"
    }
}

// MARK: - Step Tracking DTOs

struct StepDataDTO: Codable {
    let id: String?
    let userId: String
    let date: String
    let steps: Int
    let goal: Int
    let syncedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case steps
        case goal
        case syncedAt = "synced_at"
    }
}

struct StepStatisticsDTO: Codable {
    let totalSteps: Int
    let averageSteps: Int
    let maxSteps: Int
    let daysTracked: Int
    let daysGoalMet: Int
    let goalCompletionRate: Double
}

// MARK: - Admin Analytics DTOs

struct WorkoutAnalyticsDTO: Codable {
    let totalWorkouts: Int
    let uniqueUsers: Int
    let workoutsLast7Days: Int
    let avgWorkoutsPerUser: Double
}

struct TopWorkoutDTO: Codable {
    let workoutName: String
    let completionCount: Int
}

struct UserStatisticsDTO: Codable {
    let totalUsers: Int
    let activeUsersLast30Days: Int
    let avgStreakLength: Int
    let avgTotalWorkouts: Int
}

struct StepAnalyticsDTO: Codable {
    let totalStepsAllUsers: Int
    let avgStepsPerDay: Int
    let usersTrackingSteps: Int
    let goalCompletionRate: Double
    let daysTracked: Int
}

struct WorkoutCountDTO: Codable {
    let id: String
}

struct UniqueUserDTO: Codable {
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: - Workout History DTOs
struct WorkoutHistoryDTO: Codable {
    let id: String
    let userId: String
    let name: String
    let date: String
    let duration: Int
    let isCompleted: Bool
    let xpEarned: Int
    let notes: String?
    let exercises: [WorkoutExerciseDTO]
    let completionRate: Double?
    let totalSetsPlanned: Int?
    let totalSetsCompleted: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, date, duration, notes, exercises
        case userId = "user_id"
        case isCompleted = "is_completed"
        case xpEarned = "xp_earned"
        case completionRate = "completion_rate"
        case totalSetsPlanned = "total_sets_planned"
        case totalSetsCompleted = "total_sets_completed"
    }
}

struct WorkoutExerciseDTO: Codable {
    let id: String
    let exerciseName: String
    let order: Int
    let sets: [WorkoutSetDTO]
    
    enum CodingKeys: String, CodingKey {
        case id, order, sets
        case exerciseName = "exercise_name"
    }
}

struct WorkoutSetDTO: Codable {
    let id: String
    let setNumber: Int
    let reps: Int
    let weight: Double
    let isCompleted: Bool
    let setType: String?  // Warmup, Dropset, Failure, AMRAP, etc.
    
    enum CodingKeys: String, CodingKey {
        case id, reps, weight
        case setNumber = "set_number"
        case isCompleted = "is_completed"
        case setType = "set_type"
    }
}

// MARK: - Meal Log DTOs
struct MealLogDTO: Codable {
    let id: String
    let userId: String
    let date: String
    let mealType: String
    let foodName: String
    let quantity: Double
    let unit: String?
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fdcId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, date, quantity, unit, calories, protein, carbs, fat
        case userId = "user_id"
        case mealType = "meal_type"
        case foodName = "food_name"
        case fdcId = "fdc_id"
    }
}

// MARK: - Cardio Workout DTOs

/// Data structure for creating a new cardio workout
struct CardioWorkoutData {
    let activityType: String
    let workoutName: String?
    let goalType: String
    let goalValue: Double?
    let goalAchieved: Bool
    let durationSeconds: Int
    let distanceMeters: Double
    let caloriesBurned: Double
    let averagePace: Double?
    let bestPace: Double?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let cadence: Int?
    let averagePower: Int?
    let equipmentName: String?
    let equipmentType: String?
    let routeCoordinatesJSON: String?
    let splitsJSON: String?
    let startedAt: Date
    let completedAt: Date
    
    init(
        activityType: String,
        workoutName: String? = nil,
        goalType: String,
        goalValue: Double? = nil,
        goalAchieved: Bool,
        durationSeconds: Int,
        distanceMeters: Double,
        caloriesBurned: Double,
        averagePace: Double? = nil,
        bestPace: Double? = nil,
        averageSpeed: Double? = nil,
        maxSpeed: Double? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        cadence: Int? = nil,
        averagePower: Int? = nil,
        equipmentName: String? = nil,
        equipmentType: String? = nil,
        routeCoordinatesJSON: String? = nil,
        splitsJSON: String? = nil,
        startedAt: Date,
        completedAt: Date
    ) {
        self.activityType = activityType
        self.workoutName = workoutName
        self.goalType = goalType
        self.goalValue = goalValue
        self.goalAchieved = goalAchieved
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.caloriesBurned = caloriesBurned
        self.averagePace = averagePace
        self.bestPace = bestPace
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.cadence = cadence
        self.averagePower = averagePower
        self.equipmentName = equipmentName
        self.equipmentType = equipmentType
        self.routeCoordinatesJSON = routeCoordinatesJSON
        self.splitsJSON = splitsJSON
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// DTO for fetching cardio workouts from database
struct CardioWorkoutDTO: Codable, Hashable {
    let id: String
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CardioWorkoutDTO, rhs: CardioWorkoutDTO) -> Bool { lhs.id == rhs.id }
    let activityType: String
    let workoutName: String?
    let goalType: String
    let goalValue: Double?
    let goalAchieved: Bool
    let durationSeconds: Int
    let distanceMeters: Double
    let caloriesBurned: Double
    let averagePace: Double?
    let bestPace: Double?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let cadence: Int?
    let averagePower: Int?
    let equipmentName: String?
    let equipmentType: String?
    let startedAt: String
    let completedAt: String
    
    // Source tracking (for Strava, Apple Health, etc.)
    let source: String?
    let externalId: String?
    let externalUrl: String?
    let totalElevationGain: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case activityType = "activity_type"
        case workoutName = "workout_name"
        case goalType = "goal_type"
        case goalValue = "goal_value"
        case goalAchieved = "goal_achieved"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case caloriesBurned = "calories_burned"
        case averagePace = "average_pace"
        case bestPace = "best_pace"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case cadence
        case averagePower = "average_power"
        case equipmentName = "equipment_name"
        case equipmentType = "equipment_type"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case source
        case externalId = "external_id"
        case externalUrl = "external_url"
        case totalElevationGain = "total_elevation_gain"
    }
    
    /// Whether this workout was synced from Strava
    var isFromStrava: Bool {
        source == "strava"
    }
}

/// DTO for personal records
struct CardioPRDTO: Codable {
    let id: String
    let activityType: String
    let recordType: String
    let recordCategory: String
    let value: Double
    let unit: String
    let workoutId: String?
    let previousValue: Double?
    let improvementPercentage: Double?
    let achievedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case activityType = "activity_type"
        case recordType = "record_type"
        case recordCategory = "record_category"
        case value, unit
        case workoutId = "workout_id"
        case previousValue = "previous_value"
        case improvementPercentage = "improvement_percentage"
        case achievedAt = "achieved_at"
    }
}

/// DTO for cardio statistics
struct CardioStatsDTO {
    let totalWorkouts: Int
    let totalDuration: Int
    let totalDistance: Double
    let totalCalories: Double
    let workoutsByType: [String: Int]
}

/// DTO for cardio streak
struct CardioStreakDTO: Codable {
    let id: String
    let streakType: String
    let activityType: String?
    let currentStreak: Int
    let longestStreak: Int
    let lastActivityDate: String?
    let streakStartDate: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case streakType = "streak_type"
        case activityType = "activity_type"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastActivityDate = "last_activity_date"
        case streakStartDate = "streak_start_date"
    }
}

/// DTO for weekly summaries
struct CardioWeeklySummaryDTO: Codable {
    let id: String
    let weekStart: String
    let weekEnd: String
    let totalWorkouts: Int
    let totalDurationSeconds: Int
    let totalDistanceMeters: Double
    let totalCalories: Double
    let avgWorkoutDuration: Int?
    let avgPace: Double?
    let avgHeartRate: Int?
    let goalsCompleted: Int
    let prsAchieved: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case totalWorkouts = "total_workouts"
        case totalDurationSeconds = "total_duration_seconds"
        case totalDistanceMeters = "total_distance_meters"
        case totalCalories = "total_calories"
        case avgWorkoutDuration = "avg_workout_duration"
        case avgPace = "avg_pace"
        case avgHeartRate = "avg_heart_rate"
        case goalsCompleted = "goals_completed"
        case prsAchieved = "prs_achieved"
    }
}

/// DTO for cardio goals
struct CardioGoalDTO: Codable {
    let id: String
    let goalName: String
    let goalType: String
    let activityType: String?
    let targetValue: Double
    let currentValue: Double
    let unit: String
    let periodType: String
    let periodStart: String
    let periodEnd: String
    let isActive: Bool
    let isCompleted: Bool
    let completedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case goalName = "goal_name"
        case goalType = "goal_type"
        case activityType = "activity_type"
        case targetValue = "target_value"
        case currentValue = "current_value"
        case unit
        case periodType = "period_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case isActive = "is_active"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
    }
}
