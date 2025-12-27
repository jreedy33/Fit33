#!/usr/bin/env swift
//
//  ProgressiveLearningAudit.swift
//  Simulates 10 users completing 7 days of workouts
//  Each day builds on previous completions - demonstrating progressive learning
//

import Foundation

// MARK: - Data Structures

struct UserProfile {
    let id: Int
    let name: String
    let age: Int
    let gender: String
    let weight: Int
    let height: String
    let fitnessGoal: String
    let experienceLevel: String
    let workoutLocation: String
    let equipment: [String]
    let daysPerWeek: Int
    let focusAreas: [String]
}

struct Exercise {
    let name: String
    let equipment: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let movementPattern: String
    let exerciseType: String // compound or isolation
    let difficulty: String
}

struct WorkoutExercise {
    let exercise: Exercise
    let sets: Int
    let reps: Int
    let restSeconds: Int
    var completed: Bool = false
}

struct WorkoutDay {
    let dayNumber: Int
    let name: String
    let focusMuscles: [String]
    var exercises: [WorkoutExercise]
    var completed: Bool = false
}

// User's learned preferences (simulates UserBehaviorLearningEngine)
class UserLearningProfile {
    var exerciseAffinities: [String: Double] = [:]  // Exercise name -> affinity score
    var equipmentAffinities: [String: Double] = [:] // Equipment -> affinity
    var muscleAffinities: [String: Double] = [:]    // Muscle group -> affinity
    var patternAffinities: [String: Double] = [:]   // Movement pattern -> affinity
    var completedExercises: Set<String> = []        // All exercises ever completed
    var recentExercises: [String] = []              // Last 10 exercises (for variety)
    var totalWorkoutsCompleted: Int = 0
    
    func recordWorkoutCompletion(exercises: [WorkoutExercise]) {
        totalWorkoutsCompleted += 1
        
        for workoutExercise in exercises where workoutExercise.completed {
            let exercise = workoutExercise.exercise
            let nameLower = exercise.name.lowercased()
            
            // Update exercise affinity (they did it, so they probably like it)
            exerciseAffinities[nameLower, default: 0] += 0.15
            exerciseAffinities[nameLower] = min(1.0, exerciseAffinities[nameLower]!)
            
            // Update equipment affinity
            let equipLower = exercise.equipment.lowercased()
            equipmentAffinities[equipLower, default: 0] += 0.1
            equipmentAffinities[equipLower] = min(1.0, equipmentAffinities[equipLower]!)
            
            // Update muscle affinity
            for muscle in exercise.primaryMuscles {
                muscleAffinities[muscle.lowercased(), default: 0] += 0.1
                muscleAffinities[muscle.lowercased()] = min(1.0, muscleAffinities[muscle.lowercased()]!)
            }
            
            // Update pattern affinity
            patternAffinities[exercise.movementPattern, default: 0] += 0.1
            patternAffinities[exercise.movementPattern] = min(1.0, patternAffinities[exercise.movementPattern]!)
            
            // Track completed exercises
            completedExercises.insert(nameLower)
            
            // Track recent exercises (keep last 10)
            recentExercises.append(nameLower)
            if recentExercises.count > 10 {
                recentExercises.removeFirst()
            }
        }
    }
    
    func getLearnedBoost(for exercise: Exercise) -> Double {
        var boost: Double = 0
        let nameLower = exercise.name.lowercased()
        let equipLower = exercise.equipment.lowercased()
        
        // Direct exercise affinity boost
        boost += (exerciseAffinities[nameLower] ?? 0) * 80
        
        // Equipment affinity boost
        boost += (equipmentAffinities[equipLower] ?? 0) * 50
        
        // Muscle affinity boost
        for muscle in exercise.primaryMuscles {
            boost += (muscleAffinities[muscle.lowercased()] ?? 0) * 30
        }
        
        // Pattern affinity boost
        boost += (patternAffinities[exercise.movementPattern] ?? 0) * 40
        
        // Freshness: penalize recently done exercises
        if recentExercises.contains(nameLower) {
            boost -= 30  // Encourage variety
        }
        
        // Discovery bonus: small boost for exercises never done
        if !completedExercises.contains(nameLower) && totalWorkoutsCompleted > 2 {
            boost += 15  // Try new things occasionally
        }
        
        return boost
    }
}

// MARK: - Exercise Database (Comprehensive)

let exerciseDatabase: [Exercise] = [
    // ═══════════════════════════════════════════════════════════════════════════
    // CHEST EXERCISES
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Horizontal Press - Compounds
    Exercise(name: "Barbell Bench Press", equipment: "Barbell", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps", "Shoulders"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Incline Barbell Press", equipment: "Barbell", primaryMuscles: ["Upper Chest"], secondaryMuscles: ["Triceps", "Shoulders"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Decline Barbell Press", equipment: "Barbell", primaryMuscles: ["Lower Chest"], secondaryMuscles: ["Triceps"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Dumbbell Bench Press", equipment: "Dumbbells", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps", "Shoulders"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Incline Dumbbell Press", equipment: "Dumbbells", primaryMuscles: ["Upper Chest"], secondaryMuscles: ["Triceps", "Shoulders"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Machine Chest Press", equipment: "Machine", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Smith Machine Bench Press", equipment: "Machine", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Push-Up", equipment: "Bodyweight", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps", "Core"], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Beginner"),
    
    // Chest Fly - Isolation
    Exercise(name: "Cable Fly", equipment: "Cables", primaryMuscles: ["Chest"], secondaryMuscles: [], movementPattern: "chest_fly", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Incline Cable Fly", equipment: "Cables", primaryMuscles: ["Upper Chest"], secondaryMuscles: [], movementPattern: "chest_fly", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Low Cable Fly", equipment: "Cables", primaryMuscles: ["Lower Chest"], secondaryMuscles: [], movementPattern: "chest_fly", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Dumbbell Fly", equipment: "Dumbbells", primaryMuscles: ["Chest"], secondaryMuscles: [], movementPattern: "chest_fly", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Pec Deck Machine", equipment: "Machine", primaryMuscles: ["Chest"], secondaryMuscles: [], movementPattern: "chest_fly", exerciseType: "isolation", difficulty: "Beginner"),
    
    // ═══════════════════════════════════════════════════════════════════════════
    // BACK EXERCISES
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Horizontal Pull - Compounds
    Exercise(name: "Barbell Row", equipment: "Barbell", primaryMuscles: ["Back", "Lats"], secondaryMuscles: ["Biceps", "Rear Delts"], movementPattern: "horizontal_pull", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Pendlay Row", equipment: "Barbell", primaryMuscles: ["Back", "Lats"], secondaryMuscles: ["Biceps"], movementPattern: "horizontal_pull", exerciseType: "compound", difficulty: "Advanced"),
    Exercise(name: "Single-Arm Dumbbell Row", equipment: "Dumbbells", primaryMuscles: ["Lats", "Back"], secondaryMuscles: ["Biceps"], movementPattern: "horizontal_pull", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Seated Cable Row", equipment: "Cables", primaryMuscles: ["Back", "Lats"], secondaryMuscles: ["Biceps"], movementPattern: "horizontal_pull", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Machine Row", equipment: "Machine", primaryMuscles: ["Back"], secondaryMuscles: ["Biceps"], movementPattern: "horizontal_pull", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "T-Bar Row", equipment: "Barbell", primaryMuscles: ["Back", "Lats"], secondaryMuscles: ["Biceps"], movementPattern: "horizontal_pull", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Chest-Supported Row", equipment: "Dumbbells", primaryMuscles: ["Back"], secondaryMuscles: ["Biceps"], movementPattern: "horizontal_pull", exerciseType: "compound", difficulty: "Beginner"),
    
    // Vertical Pull - Compounds
    Exercise(name: "Pull-Up", equipment: "Bodyweight", primaryMuscles: ["Lats", "Back"], secondaryMuscles: ["Biceps"], movementPattern: "vertical_pull", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Chin-Up", equipment: "Bodyweight", primaryMuscles: ["Lats", "Biceps"], secondaryMuscles: ["Back"], movementPattern: "vertical_pull", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Lat Pulldown", equipment: "Cables", primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps"], movementPattern: "vertical_pull", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Wide Grip Pulldown", equipment: "Cables", primaryMuscles: ["Lats"], secondaryMuscles: ["Back"], movementPattern: "vertical_pull", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Close Grip Pulldown", equipment: "Cables", primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps"], movementPattern: "vertical_pull", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Assisted Pull-Up Machine", equipment: "Machine", primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps"], movementPattern: "vertical_pull", exerciseType: "compound", difficulty: "Beginner"),
    
    // Back Isolation
    Exercise(name: "Straight Arm Pulldown", equipment: "Cables", primaryMuscles: ["Lats"], secondaryMuscles: [], movementPattern: "lat_isolation", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Face Pull", equipment: "Cables", primaryMuscles: ["Rear Delts", "Upper Back"], secondaryMuscles: ["Traps"], movementPattern: "rear_delt", exerciseType: "isolation", difficulty: "Beginner"),
    
    // ═══════════════════════════════════════════════════════════════════════════
    // SHOULDER EXERCISES
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Vertical Press - Compounds
    Exercise(name: "Overhead Press", equipment: "Barbell", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], movementPattern: "vertical_press", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Push Press", equipment: "Barbell", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps", "Legs"], movementPattern: "vertical_press", exerciseType: "compound", difficulty: "Advanced"),
    Exercise(name: "Seated Dumbbell Press", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], movementPattern: "vertical_press", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Arnold Press", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], movementPattern: "vertical_press", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Machine Shoulder Press", equipment: "Machine", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], movementPattern: "vertical_press", exerciseType: "compound", difficulty: "Beginner"),
    
    // Shoulder Isolation
    Exercise(name: "Lateral Raise", equipment: "Dumbbells", primaryMuscles: ["Side Delts"], secondaryMuscles: [], movementPattern: "lateral_raise", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Cable Lateral Raise", equipment: "Cables", primaryMuscles: ["Side Delts"], secondaryMuscles: [], movementPattern: "lateral_raise", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Machine Lateral Raise", equipment: "Machine", primaryMuscles: ["Side Delts"], secondaryMuscles: [], movementPattern: "lateral_raise", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Front Raise", equipment: "Dumbbells", primaryMuscles: ["Front Delts"], secondaryMuscles: [], movementPattern: "front_raise", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Rear Delt Fly", equipment: "Dumbbells", primaryMuscles: ["Rear Delts"], secondaryMuscles: [], movementPattern: "rear_delt", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Reverse Pec Deck", equipment: "Machine", primaryMuscles: ["Rear Delts"], secondaryMuscles: [], movementPattern: "rear_delt", exerciseType: "isolation", difficulty: "Beginner"),
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ARM EXERCISES
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Biceps
    Exercise(name: "Barbell Curl", equipment: "Barbell", primaryMuscles: ["Biceps"], secondaryMuscles: ["Forearms"], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "EZ Bar Curl", equipment: "Barbell", primaryMuscles: ["Biceps"], secondaryMuscles: ["Forearms"], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Dumbbell Curl", equipment: "Dumbbells", primaryMuscles: ["Biceps"], secondaryMuscles: [], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Hammer Curl", equipment: "Dumbbells", primaryMuscles: ["Biceps", "Brachialis"], secondaryMuscles: ["Forearms"], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Incline Dumbbell Curl", equipment: "Dumbbells", primaryMuscles: ["Biceps"], secondaryMuscles: [], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Cable Curl", equipment: "Cables", primaryMuscles: ["Biceps"], secondaryMuscles: [], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Preacher Curl", equipment: "Barbell", primaryMuscles: ["Biceps"], secondaryMuscles: [], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Preacher Curl Machine", equipment: "Machine", primaryMuscles: ["Biceps"], secondaryMuscles: [], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Concentration Curl", equipment: "Dumbbells", primaryMuscles: ["Biceps"], secondaryMuscles: [], movementPattern: "curl", exerciseType: "isolation", difficulty: "Beginner"),
    
    // Triceps
    Exercise(name: "Tricep Pushdown", equipment: "Cables", primaryMuscles: ["Triceps"], secondaryMuscles: [], movementPattern: "tricep_extension", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Rope Tricep Extension", equipment: "Cables", primaryMuscles: ["Triceps"], secondaryMuscles: [], movementPattern: "tricep_extension", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Overhead Tricep Extension", equipment: "Dumbbells", primaryMuscles: ["Triceps"], secondaryMuscles: [], movementPattern: "tricep_extension", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Overhead Cable Extension", equipment: "Cables", primaryMuscles: ["Triceps"], secondaryMuscles: [], movementPattern: "tricep_extension", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Skull Crusher", equipment: "Barbell", primaryMuscles: ["Triceps"], secondaryMuscles: [], movementPattern: "tricep_extension", exerciseType: "isolation", difficulty: "Intermediate"),
    Exercise(name: "Close Grip Bench Press", equipment: "Barbell", primaryMuscles: ["Triceps", "Chest"], secondaryMuscles: [], movementPattern: "horizontal_press", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Tricep Dip", equipment: "Bodyweight", primaryMuscles: ["Triceps", "Chest"], secondaryMuscles: [], movementPattern: "vertical_press", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Tricep Dip Machine", equipment: "Machine", primaryMuscles: ["Triceps"], secondaryMuscles: [], movementPattern: "tricep_extension", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Tricep Kickback", equipment: "Dumbbells", primaryMuscles: ["Triceps"], secondaryMuscles: [], movementPattern: "tricep_extension", exerciseType: "isolation", difficulty: "Beginner"),
    
    // ═══════════════════════════════════════════════════════════════════════════
    // LEG EXERCISES
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Squat Pattern - Compounds
    Exercise(name: "Barbell Back Squat", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Hamstrings", "Core"], movementPattern: "squat", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Barbell Front Squat", equipment: "Barbell", primaryMuscles: ["Quads"], secondaryMuscles: ["Glutes", "Core"], movementPattern: "squat", exerciseType: "compound", difficulty: "Advanced"),
    Exercise(name: "Goblet Squat", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Core"], movementPattern: "squat", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Leg Press", equipment: "Machine", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Hamstrings"], movementPattern: "squat", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Hack Squat Machine", equipment: "Machine", primaryMuscles: ["Quads"], secondaryMuscles: ["Glutes"], movementPattern: "squat", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Smith Machine Squat", equipment: "Machine", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], movementPattern: "squat", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Bodyweight Squat", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], movementPattern: "squat", exerciseType: "compound", difficulty: "Beginner"),
    
    // Hinge Pattern - Compounds
    Exercise(name: "Conventional Deadlift", equipment: "Barbell", primaryMuscles: ["Back", "Hamstrings", "Glutes"], secondaryMuscles: ["Core", "Traps"], movementPattern: "hinge", exerciseType: "compound", difficulty: "Advanced"),
    Exercise(name: "Romanian Deadlift", equipment: "Barbell", primaryMuscles: ["Hamstrings", "Glutes"], secondaryMuscles: ["Back"], movementPattern: "hinge", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Dumbbell Romanian Deadlift", equipment: "Dumbbells", primaryMuscles: ["Hamstrings", "Glutes"], secondaryMuscles: [], movementPattern: "hinge", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Sumo Deadlift", equipment: "Barbell", primaryMuscles: ["Glutes", "Quads", "Hamstrings"], secondaryMuscles: ["Back"], movementPattern: "hinge", exerciseType: "compound", difficulty: "Advanced"),
    Exercise(name: "Hip Thrust", equipment: "Barbell", primaryMuscles: ["Glutes"], secondaryMuscles: ["Hamstrings"], movementPattern: "hinge", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Cable Pull-Through", equipment: "Cables", primaryMuscles: ["Glutes", "Hamstrings"], secondaryMuscles: [], movementPattern: "hinge", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Good Morning", equipment: "Barbell", primaryMuscles: ["Hamstrings", "Back"], secondaryMuscles: ["Glutes"], movementPattern: "hinge", exerciseType: "compound", difficulty: "Advanced"),
    
    // Lunge Pattern - Compounds
    Exercise(name: "Barbell Lunges", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Hamstrings"], movementPattern: "lunge", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Dumbbell Lunges", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Hamstrings"], movementPattern: "lunge", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Walking Lunges", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Hamstrings"], movementPattern: "lunge", exerciseType: "compound", difficulty: "Beginner"),
    Exercise(name: "Bulgarian Split Squat", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Hamstrings"], movementPattern: "lunge", exerciseType: "compound", difficulty: "Intermediate"),
    Exercise(name: "Step-Up", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], movementPattern: "lunge", exerciseType: "compound", difficulty: "Beginner"),
    
    // Leg Isolation
    Exercise(name: "Leg Extension", equipment: "Machine", primaryMuscles: ["Quads"], secondaryMuscles: [], movementPattern: "leg_extension", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Leg Curl", equipment: "Machine", primaryMuscles: ["Hamstrings"], secondaryMuscles: [], movementPattern: "leg_curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Seated Leg Curl", equipment: "Machine", primaryMuscles: ["Hamstrings"], secondaryMuscles: [], movementPattern: "leg_curl", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Standing Calf Raise", equipment: "Machine", primaryMuscles: ["Calves"], secondaryMuscles: [], movementPattern: "calf_raise", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Seated Calf Raise", equipment: "Machine", primaryMuscles: ["Calves"], secondaryMuscles: [], movementPattern: "calf_raise", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Hip Adductor Machine", equipment: "Machine", primaryMuscles: ["Adductors"], secondaryMuscles: [], movementPattern: "adduction", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Hip Abductor Machine", equipment: "Machine", primaryMuscles: ["Abductors", "Glutes"], secondaryMuscles: [], movementPattern: "abduction", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Glute Kickback Machine", equipment: "Machine", primaryMuscles: ["Glutes"], secondaryMuscles: [], movementPattern: "glute_isolation", exerciseType: "isolation", difficulty: "Beginner"),
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE EXERCISES
    // ═══════════════════════════════════════════════════════════════════════════
    
    Exercise(name: "Cable Crunch", equipment: "Cables", primaryMuscles: ["Abs"], secondaryMuscles: [], movementPattern: "core_flexion", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Ab Crunch Machine", equipment: "Machine", primaryMuscles: ["Abs"], secondaryMuscles: [], movementPattern: "core_flexion", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Hanging Leg Raise", equipment: "Bodyweight", primaryMuscles: ["Abs", "Hip Flexors"], secondaryMuscles: [], movementPattern: "core_flexion", exerciseType: "isolation", difficulty: "Intermediate"),
    Exercise(name: "Hanging Knee Raise", equipment: "Bodyweight", primaryMuscles: ["Abs"], secondaryMuscles: [], movementPattern: "core_flexion", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Cable Woodchop", equipment: "Cables", primaryMuscles: ["Obliques", "Core"], secondaryMuscles: [], movementPattern: "rotation", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Pallof Press", equipment: "Cables", primaryMuscles: ["Core", "Obliques"], secondaryMuscles: [], movementPattern: "anti_rotation", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Plank", equipment: "Bodyweight", primaryMuscles: ["Core"], secondaryMuscles: [], movementPattern: "core_stability", exerciseType: "isolation", difficulty: "Beginner"),
    Exercise(name: "Dead Bug", equipment: "Bodyweight", primaryMuscles: ["Core"], secondaryMuscles: [], movementPattern: "core_stability", exerciseType: "isolation", difficulty: "Beginner"),
]

// MARK: - Smart Exercise Selection (Mirrors Production Logic)

func selectExercisesForWorkout(
    targetMuscles: [String],
    exerciseCount: Int,
    userEquipment: [String],
    isGymUser: Bool,
    previousDayExercises: Set<String>,
    userGoal: String,
    experienceLevel: String,
    learningProfile: UserLearningProfile
) -> [WorkoutExercise] {
    
    // Movement pattern limits
    let patternLimits: [String: Int] = [
        "horizontal_press": 2,
        "vertical_press": 2,
        "horizontal_pull": 2,
        "vertical_pull": 2,
        "chest_fly": 1,
        "lateral_raise": 1,
        "front_raise": 1,
        "rear_delt": 1,
        "curl": 1,
        "tricep_extension": 1,
        "squat": 2,
        "hinge": 2,
        "lunge": 2,
        "leg_extension": 1,
        "leg_curl": 1,
        "calf_raise": 1,
        "core_flexion": 2,
        "core_stability": 1
    ]
    
    var scoredExercises: [(exercise: Exercise, score: Double)] = []
    
    for exercise in exerciseDatabase {
        var score: Double = 100
        
        // ═══════════════════════════════════════════════════════════════
        // FILTER 1: Muscle match
        // ═══════════════════════════════════════════════════════════════
        let allMuscles = exercise.primaryMuscles + exercise.secondaryMuscles
        let muscleMatch = targetMuscles.contains { target in
            allMuscles.contains { muscle in
                muscle.lowercased().contains(target.lowercased()) ||
                target.lowercased().contains(muscle.lowercased())
            }
        }
        guard muscleMatch else { continue }
        
        // ═══════════════════════════════════════════════════════════════
        // FILTER 2: Equipment match
        // ═══════════════════════════════════════════════════════════════
        let equipmentMatch = userEquipment.isEmpty ||
            userEquipment.contains { exercise.equipment.lowercased().contains($0.lowercased()) } ||
            exercise.equipment == "Bodyweight"
        guard equipmentMatch else { continue }
        
        // ═══════════════════════════════════════════════════════════════
        // FILTER 3: Experience level match
        // ═══════════════════════════════════════════════════════════════
        if experienceLevel == "Beginner" && exercise.difficulty == "Advanced" {
            continue  // Skip advanced exercises for beginners
        }
        
        // ═══════════════════════════════════════════════════════════════
        // SCORING: User Learning Boost (Most Important!)
        // ═══════════════════════════════════════════════════════════════
        score += learningProfile.getLearnedBoost(for: exercise)
        
        // ═══════════════════════════════════════════════════════════════
        // SCORING: Gym equipment (EQUAL for all gym equipment)
        // ═══════════════════════════════════════════════════════════════
        if isGymUser {
            let equip = exercise.equipment.lowercased()
            if ["barbell", "dumbbells", "cables", "machine"].contains(where: { equip.contains($0) }) {
                score += 60  // Equal for all gym equipment
            } else if equip == "bodyweight" {
                if ["pull-up", "chin-up", "dip"].contains(where: { exercise.name.lowercased().contains($0) }) {
                    score += 45
                } else if ["dead bug", "plank", "lying", "floor"].contains(where: { exercise.name.lowercased().contains($0) }) {
                    score -= 40  // Penalize lying bodyweight for gym users
                }
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // SCORING: Compound boost
        // ═══════════════════════════════════════════════════════════════
        if exercise.exerciseType == "compound" {
            score += 25
        }
        
        // ═══════════════════════════════════════════════════════════════
        // SCORING: Variety - penalize exercises from previous days
        // ═══════════════════════════════════════════════════════════════
        if previousDayExercises.contains(exercise.name.lowercased()) {
            score -= 50
        }
        
        // ═══════════════════════════════════════════════════════════════
        // SCORING: Goal alignment
        // ═══════════════════════════════════════════════════════════════
        switch userGoal.lowercased() {
        case "build muscle":
            if exercise.exerciseType == "compound" { score += 10 }
        case "get stronger":
            if exercise.exerciseType == "compound" { score += 20 }
            if exercise.equipment == "Barbell" { score += 10 }
        case "lose weight":
            if exercise.exerciseType == "compound" { score += 15 }
        default:
            break
        }
        
        scoredExercises.append((exercise, score))
    }
    
    // Sort by score
    scoredExercises.sort { $0.score > $1.score }
    
    // Select with pattern limits
    var selected: [WorkoutExercise] = []
    var selectedNames: Set<String> = []
    var patternCounts: [String: Int] = [:]
    var compoundCount = 0
    var isolationCount = 0
    
    let targetCompounds = max(2, Int(Double(exerciseCount) * 0.6))
    
    for (exercise, _) in scoredExercises {
        guard selected.count < exerciseCount else { break }
        guard !selectedNames.contains(exercise.name.lowercased()) else { continue }
        
        // Pattern limit check
        let currentPatternCount = patternCounts[exercise.movementPattern, default: 0]
        let maxForPattern = patternLimits[exercise.movementPattern] ?? 2
        if currentPatternCount >= maxForPattern {
            continue
        }
        
        // Compound/Isolation balance
        if exercise.exerciseType == "compound" && compoundCount >= targetCompounds {
            if selected.count < exerciseCount - 2 { continue }
        }
        
        // Calculate sets/reps based on goal
        let (sets, reps, rest) = calculatePrescription(goal: userGoal, isCompound: exercise.exerciseType == "compound")
        
        selected.append(WorkoutExercise(
            exercise: exercise,
            sets: sets,
            reps: reps,
            restSeconds: rest,
            completed: false
        ))
        
        selectedNames.insert(exercise.name.lowercased())
        patternCounts[exercise.movementPattern, default: 0] += 1
        if exercise.exerciseType == "compound" { compoundCount += 1 }
        if exercise.exerciseType == "isolation" { isolationCount += 1 }
    }
    
    // Reorder: Compounds first
    selected.sort { e1, e2 in
        if e1.exercise.exerciseType == "compound" && e2.exercise.exerciseType != "compound" { return true }
        if e1.exercise.exerciseType != "compound" && e2.exercise.exerciseType == "compound" { return false }
        return false
    }
    
    return selected
}

func calculatePrescription(goal: String, isCompound: Bool) -> (sets: Int, reps: Int, rest: Int) {
    switch goal.lowercased() {
    case "get stronger":
        return isCompound ? (5, 5, 180) : (4, 8, 120)
    case "build muscle":
        return isCompound ? (4, 8, 90) : (3, 12, 60)
    case "lose weight":
        return (3, 12, 45)
    case "tone & define":
        return (3, 15, 45)
    default:
        return (3, 10, 60)
    }
}

// MARK: - Program Templates

struct ProgramTemplate {
    let name: String
    let daysPerWeek: Int
    let split: [[String]]  // Muscles per day
    let dayNames: [String]
}

let programTemplates: [ProgramTemplate] = [
    ProgramTemplate(name: "Push/Pull/Legs", daysPerWeek: 6, 
        split: [["Chest", "Shoulders", "Triceps"], ["Back", "Biceps"], ["Quads", "Hamstrings", "Glutes"], 
                ["Chest", "Shoulders", "Triceps"], ["Back", "Biceps"], ["Quads", "Hamstrings", "Glutes"]],
        dayNames: ["Push A", "Pull A", "Legs A", "Push B", "Pull B", "Legs B"]),
    
    ProgramTemplate(name: "Upper/Lower", daysPerWeek: 4,
        split: [["Chest", "Back", "Shoulders", "Biceps", "Triceps"], ["Quads", "Hamstrings", "Glutes", "Calves"],
                ["Chest", "Back", "Shoulders", "Biceps", "Triceps"], ["Quads", "Hamstrings", "Glutes", "Calves"]],
        dayNames: ["Upper A", "Lower A", "Upper B", "Lower B"]),
    
    ProgramTemplate(name: "Full Body", daysPerWeek: 3,
        split: [["Chest", "Back", "Shoulders", "Quads", "Hamstrings"], 
                ["Chest", "Back", "Shoulders", "Quads", "Hamstrings"],
                ["Chest", "Back", "Shoulders", "Quads", "Hamstrings"]],
        dayNames: ["Full Body A", "Full Body B", "Full Body C"]),
    
    ProgramTemplate(name: "Bro Split", daysPerWeek: 5,
        split: [["Chest"], ["Back"], ["Shoulders"], ["Quads", "Hamstrings", "Glutes"], ["Biceps", "Triceps"]],
        dayNames: ["Chest Day", "Back Day", "Shoulder Day", "Leg Day", "Arm Day"]),
]

// MARK: - Test Users

let testUsers: [UserProfile] = [
    UserProfile(id: 1, name: "Mike", age: 28, gender: "Male", weight: 180, height: "5'10\"", fitnessGoal: "Build Muscle", experienceLevel: "Intermediate", workoutLocation: "Gym", equipment: ["Barbell", "Dumbbells", "Cables", "Machine"], daysPerWeek: 6, focusAreas: ["Chest", "Back"]),
    
    UserProfile(id: 2, name: "Sarah", age: 32, gender: "Female", weight: 140, height: "5'5\"", fitnessGoal: "Lose Weight", experienceLevel: "Beginner", workoutLocation: "Gym", equipment: ["Dumbbells", "Cables", "Machine"], daysPerWeek: 4, focusAreas: ["Glutes", "Core"]),
    
    UserProfile(id: 3, name: "James", age: 45, gender: "Male", weight: 200, height: "6'0\"", fitnessGoal: "Get Stronger", experienceLevel: "Advanced", workoutLocation: "Gym", equipment: ["Barbell", "Dumbbells", "Cables", "Machine"], daysPerWeek: 4, focusAreas: ["Back", "Legs"]),
    
    UserProfile(id: 4, name: "Emily", age: 26, gender: "Female", weight: 130, height: "5'4\"", fitnessGoal: "Tone & Define", experienceLevel: "Beginner", workoutLocation: "Gym", equipment: ["Dumbbells", "Cables", "Machine"], daysPerWeek: 3, focusAreas: ["Glutes", "Arms"]),
    
    UserProfile(id: 5, name: "David", age: 35, gender: "Male", weight: 170, height: "5'9\"", fitnessGoal: "Build Muscle", experienceLevel: "Intermediate", workoutLocation: "Home", equipment: ["Dumbbells", "Bodyweight"], daysPerWeek: 4, focusAreas: ["Chest", "Arms"]),
    
    UserProfile(id: 6, name: "Jessica", age: 29, gender: "Female", weight: 145, height: "5'6\"", fitnessGoal: "Get Stronger", experienceLevel: "Intermediate", workoutLocation: "Gym", equipment: ["Barbell", "Dumbbells", "Cables", "Machine"], daysPerWeek: 5, focusAreas: ["Legs", "Back"]),
    
    UserProfile(id: 7, name: "Chris", age: 22, gender: "Male", weight: 165, height: "5'11\"", fitnessGoal: "Build Muscle", experienceLevel: "Beginner", workoutLocation: "Gym", equipment: ["Barbell", "Dumbbells", "Cables", "Machine"], daysPerWeek: 6, focusAreas: ["Chest", "Shoulders"]),
    
    UserProfile(id: 8, name: "Amanda", age: 38, gender: "Female", weight: 155, height: "5'7\"", fitnessGoal: "Lose Weight", experienceLevel: "Intermediate", workoutLocation: "Gym", equipment: ["Dumbbells", "Cables", "Machine"], daysPerWeek: 4, focusAreas: ["Full Body"]),
    
    UserProfile(id: 9, name: "Tom", age: 50, gender: "Male", weight: 190, height: "5'10\"", fitnessGoal: "Get Stronger", experienceLevel: "Advanced", workoutLocation: "Gym", equipment: ["Barbell", "Dumbbells", "Cables", "Machine"], daysPerWeek: 3, focusAreas: ["Back", "Legs"]),
    
    UserProfile(id: 10, name: "Rachel", age: 24, gender: "Female", weight: 125, height: "5'3\"", fitnessGoal: "Build Muscle", experienceLevel: "Beginner", workoutLocation: "Gym", equipment: ["Dumbbells", "Cables", "Machine"], daysPerWeek: 5, focusAreas: ["Glutes", "Shoulders"]),
]

// MARK: - Review Functions

struct ExerciseReview {
    let exercise: WorkoutExercise
    let flags: [String]
    let isGood: Bool
    let reasoning: String
}

func reviewExercise(
    exercise: WorkoutExercise,
    dayFocus: [String],
    previousExercises: [String],
    allDayExercises: [WorkoutExercise],
    user: UserProfile,
    dayNumber: Int
) -> ExerciseReview {
    var flags: [String] = []
    var reasoning: [String] = []
    
    let ex = exercise.exercise
    let nameLower = ex.name.lowercased()
    
    // Check 1: Muscle match
    let allMuscles = ex.primaryMuscles + ex.secondaryMuscles
    let muscleMatch = dayFocus.contains { focus in
        allMuscles.contains { muscle in
            muscle.lowercased().contains(focus.lowercased()) ||
            focus.lowercased().contains(muscle.lowercased())
        }
    }
    if !muscleMatch {
        flags.append("❌ WRONG MUSCLE: \(ex.primaryMuscles.joined(separator: ", ")) doesn't match \(dayFocus.joined(separator: ", "))")
    } else {
        reasoning.append("✓ Targets: \(ex.primaryMuscles.joined(separator: ", "))")
    }
    
    // Check 2: Equipment match
    let hasEquipment = user.equipment.contains { ex.equipment.lowercased().contains($0.lowercased()) } || ex.equipment == "Bodyweight"
    if !hasEquipment {
        flags.append("❌ NO EQUIPMENT: User doesn't have \(ex.equipment)")
    }
    
    // Check 3: Experience level match
    if user.experienceLevel == "Beginner" && ex.difficulty == "Advanced" {
        flags.append("⚠️ TOO ADVANCED: \(ex.name) is advanced for beginner user")
    }
    
    // Check 4: Gym user doing floor bodyweight
    if user.workoutLocation == "Gym" && ex.equipment == "Bodyweight" {
        if ["dead bug", "plank", "lying", "floor", "bird dog", "superman"].contains(where: { nameLower.contains($0) }) {
            flags.append("⚠️ FLOOR EXERCISE AT GYM: Gym user should use equipment instead of \(ex.name)")
        }
    }
    
    // Check 5: Repetitive patterns in same workout
    let samePatternCount = allDayExercises.filter { $0.exercise.movementPattern == ex.movementPattern }.count
    if samePatternCount > 2 && ex.exerciseType == "compound" {
        flags.append("⚠️ TOO MANY \(ex.movementPattern.uppercased()): Already have \(samePatternCount) exercises with this pattern")
    }
    
    // Check 6: Same exercise in recent days
    if previousExercises.contains(nameLower) {
        flags.append("⚠️ REPETITIVE: \(ex.name) was done in a recent workout - consider variety")
    }
    
    // Check 7: Smart pairing validation
    if dayFocus.contains("Chest") || dayFocus.contains("Shoulders") || dayFocus.contains("Triceps") {
        // Push day - should have mix of press + fly + tricep
        if ex.movementPattern == "horizontal_press" {
            let pressCount = allDayExercises.filter { $0.exercise.movementPattern == "horizontal_press" }.count
            if pressCount > 2 {
                flags.append("❌ TOO MANY PRESSES: Push day has \(pressCount) horizontal presses - max should be 2")
            }
        }
    }
    
    // Check 8: Isolation before compound
    let exerciseIndex = allDayExercises.firstIndex { $0.exercise.name == ex.name } ?? 0
    if exerciseIndex < 2 && ex.exerciseType == "isolation" {
        let compoundsAfter = allDayExercises.dropFirst(exerciseIndex + 1).filter { $0.exercise.exerciseType == "compound" }.count
        if compoundsAfter > 0 {
            flags.append("⚠️ ORDER ISSUE: Isolation \(ex.name) is before compound exercises")
        }
    }
    
    // Build reasoning
    if flags.isEmpty {
        reasoning.append("✓ Equipment: \(ex.equipment)")
        reasoning.append("✓ Type: \(ex.exerciseType.capitalized)")
        reasoning.append("✓ Pattern: \(ex.movementPattern)")
    }
    
    return ExerciseReview(
        exercise: exercise,
        flags: flags,
        isGood: flags.filter { $0.hasPrefix("❌") }.isEmpty,
        reasoning: flags.isEmpty ? reasoning.joined(separator: " | ") : flags.joined(separator: " | ")
    )
}

// MARK: - Main Simulation

func runProgressiveLearningAudit() {
    print("""
    ╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
    ║                           PROGRESSIVE LEARNING AUDIT                                                              ║
    ║                   10 Users × 7 Days - Each Day Builds on Previous                                                 ║
    ╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
    
    This simulation demonstrates how the recommendation engine LEARNS from user behavior.
    Day 2 recommendations are influenced by Day 1 completions, Day 3 by Day 1+2, etc.
    
    """)
    
    var totalExercises = 0
    var flaggedExercises = 0
    var criticalIssues: [String] = []
    var allFlags: [String: Int] = [:]  // Track frequency of each issue type
    
    for user in testUsers {
        print("""
        
        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
        ▓  USER \(user.id): \(user.name.uppercased())
        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
        
        📋 Profile:
        │ Age: \(user.age) | Gender: \(user.gender) | Weight: \(user.weight) lbs
        │ Goal: \(user.fitnessGoal) | Experience: \(user.experienceLevel)
        │ Location: \(user.workoutLocation) | Days/Week: \(user.daysPerWeek)
        │ Equipment: \(user.equipment.joined(separator: ", "))
        │ Focus Areas: \(user.focusAreas.joined(separator: ", "))
        
        """)
        
        // Select program template based on days per week
        let template: ProgramTemplate
        switch user.daysPerWeek {
        case 6: template = programTemplates[0]  // PPL
        case 5: template = programTemplates[3]  // Bro Split
        case 4: template = programTemplates[1]  // Upper/Lower
        case 3: template = programTemplates[2]  // Full Body
        default: template = programTemplates[1]
        }
        
        print("        📅 Program: \(template.name)\n")
        
        // Create learning profile for this user
        let learningProfile = UserLearningProfile()
        
        // Track exercises across days for variety checking
        var allPreviousExercises: Set<String> = []
        
        // Generate 7 days
        for dayNumber in 1...7 {
            let dayIndex = (dayNumber - 1) % template.daysPerWeek
            let dayMuscles = template.split[dayIndex]
            let dayName = template.dayNames[dayIndex]
            
            print("        ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("        ┃  DAY \(dayNumber): \(dayName.uppercased()) - \(dayMuscles.joined(separator: ", "))")
            print("        ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            // Show learning state
            if learningProfile.totalWorkoutsCompleted > 0 {
                print("        │ 🧠 Learning from \(learningProfile.totalWorkoutsCompleted) completed workouts")
                if !learningProfile.equipmentAffinities.isEmpty {
                    let topEquip = learningProfile.equipmentAffinities.sorted { $0.value > $1.value }.prefix(2)
                    print("        │    Preferred equipment: \(topEquip.map { "\($0.key) (\(Int($0.value * 100))%)" }.joined(separator: ", "))")
                }
                if !learningProfile.recentExercises.isEmpty {
                    print("        │    Recent exercises (avoiding): \(learningProfile.recentExercises.suffix(3).joined(separator: ", "))")
                }
            }
            print("")
            
            // Select exercises using the learning profile
            let exercises = selectExercisesForWorkout(
                targetMuscles: dayMuscles,
                exerciseCount: 5,
                userEquipment: user.equipment,
                isGymUser: user.workoutLocation == "Gym",
                previousDayExercises: allPreviousExercises,
                userGoal: user.fitnessGoal,
                experienceLevel: user.experienceLevel,
                learningProfile: learningProfile
            )
            
            // Review each exercise
            var dayExercisesForReview: [WorkoutExercise] = exercises
            
            for (index, workoutExercise) in exercises.enumerated() {
                let review = reviewExercise(
                    exercise: workoutExercise,
                    dayFocus: dayMuscles,
                    previousExercises: Array(allPreviousExercises),
                    allDayExercises: dayExercisesForReview,
                    user: user,
                    dayNumber: dayNumber
                )
                
                totalExercises += 1
                
                let typeIcon = workoutExercise.exercise.exerciseType == "compound" ? "💪" : "🎯"
                let statusIcon = review.isGood ? "✅" : (review.flags.contains { $0.hasPrefix("❌") } ? "❌" : "⚠️")
                
                print("           \(index + 1). \(typeIcon) \(statusIcon) \(workoutExercise.exercise.name)")
                print("              Equipment: \(workoutExercise.exercise.equipment) | \(workoutExercise.sets)×\(workoutExercise.reps) | Rest: \(workoutExercise.restSeconds)s")
                
                if !review.flags.isEmpty {
                    flaggedExercises += 1
                    for flag in review.flags {
                        print("              \(flag)")
                        
                        // Track flag frequency
                        let flagType = flag.components(separatedBy: ":").first ?? flag
                        allFlags[flagType, default: 0] += 1
                        
                        if flag.hasPrefix("❌") {
                            criticalIssues.append("User \(user.name) Day \(dayNumber): \(flag)")
                        }
                    }
                }
                print("")
            }
            
            // Simulate user completing the workout
            var completedExercises = exercises
            for i in 0..<completedExercises.count {
                completedExercises[i].completed = true
                allPreviousExercises.insert(completedExercises[i].exercise.name.lowercased())
            }
            
            // Update learning profile (THIS IS THE KEY - Day 2 will use this!)
            learningProfile.recordWorkoutCompletion(exercises: completedExercises)
            
            print("        │ ✅ Day \(dayNumber) completed - Learning profile updated")
            print("        │    Total exercises learned: \(learningProfile.completedExercises.count)")
            print("")
        }
    }
    
    // Final summary
    print("""
    
    ╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
    ║                                          AUDIT SUMMARY                                                            ║
    ╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
    
    📊 STATISTICS:
    │ Total Exercises Generated: \(totalExercises)
    │ Exercises with Flags: \(flaggedExercises) (\(Int(Double(flaggedExercises) / Double(totalExercises) * 100))%)
    │ Pass Rate: \(Int(Double(totalExercises - flaggedExercises) / Double(totalExercises) * 100))%
    
    ⚠️ FLAG FREQUENCY:
    """)
    
    for (flag, count) in allFlags.sorted(by: { $0.value > $1.value }) {
        print("    │ \(flag): \(count) occurrences")
    }
    
    if !criticalIssues.isEmpty {
        print("""
        
    ❌ CRITICAL ISSUES TO FIX:
    """)
        for issue in criticalIssues.prefix(10) {
            print("    │ \(issue)")
        }
        if criticalIssues.count > 10 {
            print("    │ ... and \(criticalIssues.count - 10) more")
        }
    }
    
    print("""
    
    🧠 PROGRESSIVE LEARNING DEMONSTRATED:
    │ • Day 1: Base recommendations from user profile
    │ • Day 2+: Recommendations influenced by completed exercises
    │ • Equipment preferences learned from usage patterns
    │ • Recent exercises avoided for variety
    │ • New exercises occasionally suggested for discovery
    
    ╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
    """)
}

// Run the audit
runProgressiveLearningAudit()

