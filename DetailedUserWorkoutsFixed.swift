#!/usr/bin/env swift
//
//  DetailedUserWorkoutsFixed.swift
//  CORRECTED - Shows actual workout programs with proper equipment filtering
//

import Foundation

// MARK: - Data Structures

struct Exercise {
    let name: String
    let category: String
    let equipment: String
    let primaryMuscles: [String]
    let workoutType: String?
    let bodyPosition: String?
}

struct WorkoutExercise {
    let exercise: Exercise
    let sets: Int
    let reps: String
    let rest: String
    let score: Int
}

struct TestUserProfile {
    let id: Int
    let name: String
    let age: Int
    let gender: String
    let weight: Int
    let fitnessGoal: String
    let experienceLevel: String
    let workoutLocation: String
    let equipment: [String]
}

// MARK: - Exercise Database

func buildExerciseDatabase() -> [Exercise] {
    var exercises: [Exercise] = []
    
    // Chest
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Bench Press", category: "Chest", equipment: "Barbell", primaryMuscles: ["Chest", "Triceps"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Incline Barbell Press", category: "Chest", equipment: "Barbell", primaryMuscles: ["Chest", "Shoulders"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Decline Barbell Press", category: "Chest", equipment: "Barbell", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Dumbbell Bench Press", category: "Chest", equipment: "Dumbbells", primaryMuscles: ["Chest", "Triceps"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Incline Dumbbell Press", category: "Chest", equipment: "Dumbbells", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Dumbbell Fly", category: "Chest", equipment: "Dumbbells", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Cable Fly", category: "Chest", equipment: "Cables", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Crossover", category: "Chest", equipment: "Cables", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Low Cable Fly", category: "Chest", equipment: "Cables", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Chest Press", category: "Chest", equipment: "Machine", primaryMuscles: ["Chest", "Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Pec Deck Machine", category: "Chest", equipment: "Machine", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Push-Up", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest", "Triceps"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Wide Push-Up", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Incline Push-Up", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Decline Push-Up", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest", "Shoulders"], workoutType: "Strength", bodyPosition: "Prone"),
    ])
    
    // Back
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Row", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Deadlift", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Hamstrings", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Pendlay Row", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Lats"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Single-Arm Dumbbell Row", category: "Back", equipment: "Dumbbells", primaryMuscles: ["Back", "Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Pullover", category: "Back", equipment: "Dumbbells", primaryMuscles: ["Lats", "Chest"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Renegade Row", category: "Back", equipment: "Dumbbells", primaryMuscles: ["Back", "Core"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Lat Pulldown", category: "Back", equipment: "Cables", primaryMuscles: ["Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Seated Cable Row", category: "Back", equipment: "Cables", primaryMuscles: ["Back", "Lats"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Face Pull", category: "Back", equipment: "Cables", primaryMuscles: ["Rear Delts", "Upper Back"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Straight Arm Pulldown", category: "Back", equipment: "Cables", primaryMuscles: ["Lats"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Row", category: "Back", equipment: "Machine", primaryMuscles: ["Back", "Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Assisted Pull-Up Machine", category: "Back", equipment: "Machine", primaryMuscles: ["Lats"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Pull-Up", category: "Back", equipment: "Pull-Up Bar", primaryMuscles: ["Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Chin-Up", category: "Back", equipment: "Pull-Up Bar", primaryMuscles: ["Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Inverted Row", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Back", "Biceps"], workoutType: "Strength", bodyPosition: "Supine"),
        Exercise(name: "Superman", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lower Back"], workoutType: "Strength", bodyPosition: "Lying"),
    ])
    
    // Legs
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Back Squat", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Barbell Front Squat", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Barbell Romanian Deadlift", category: "Legs", equipment: "Barbell", primaryMuscles: ["Hamstrings", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Barbell Lunges", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Barbell Hip Thrust", category: "Legs", equipment: "Barbell", primaryMuscles: ["Glutes"], workoutType: "Strength", bodyPosition: "Supine"),
        Exercise(name: "Goblet Squat", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Lunges", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Romanian Deadlift", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Hamstrings", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Step-Up", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Leg Press", category: "Legs", equipment: "Machine", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Leg Extension", category: "Legs", equipment: "Machine", primaryMuscles: ["Quads"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Leg Curl Machine", category: "Legs", equipment: "Machine", primaryMuscles: ["Hamstrings"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Hack Squat Machine", category: "Legs", equipment: "Machine", primaryMuscles: ["Quads"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Pull-Through", category: "Legs", equipment: "Cables", primaryMuscles: ["Glutes", "Hamstrings"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Bodyweight Squat", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Walking Lunges", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Glute Bridge", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Glutes"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Single-Leg Glute Bridge", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Glutes"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Bulgarian Split Squat", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Jump Squat", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], workoutType: "Plyometrics", bodyPosition: "Standing"),
        Exercise(name: "Box Jump", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads"], workoutType: "Plyometrics", bodyPosition: "Standing"),
    ])
    
    // Shoulders
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Overhead Press", category: "Shoulders", equipment: "Barbell", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Push Press", category: "Shoulders", equipment: "Barbell", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Seated Dumbbell Press", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Arnold Press", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Dumbbell Lateral Raise", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Front Raise", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Rear Delt Fly", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Rear Delts"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Lateral Raise", category: "Shoulders", equipment: "Cables", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Front Raise", category: "Shoulders", equipment: "Cables", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Shoulder Press", category: "Shoulders", equipment: "Machine", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Reverse Pec Deck", category: "Shoulders", equipment: "Machine", primaryMuscles: ["Rear Delts"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Pike Push-Up", category: "Shoulders", equipment: "Bodyweight", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Handstand Push-Up", category: "Shoulders", equipment: "Bodyweight", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Inverted"),
    ])
    
    // Arms
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Curl", category: "Arms", equipment: "Barbell", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "EZ Bar Curl", category: "Arms", equipment: "Barbell", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Skull Crusher", category: "Arms", equipment: "Barbell", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Close Grip Bench Press", category: "Arms", equipment: "Barbell", primaryMuscles: ["Triceps", "Chest"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Dumbbell Bicep Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Hammer Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps", "Forearms"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Concentration Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Dumbbell Tricep Kickback", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Overhead Extension", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Bicep Curl", category: "Arms", equipment: "Cables", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Tricep Pushdown", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Rope Tricep Extension", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Overhead Cable Extension", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Preacher Curl Machine", category: "Arms", equipment: "Machine", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Tricep Dip Machine", category: "Arms", equipment: "Machine", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Diamond Push-Up", category: "Arms", equipment: "Bodyweight", primaryMuscles: ["Triceps", "Chest"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Bench Dips", category: "Arms", equipment: "Bodyweight", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Tricep Dips", category: "Arms", equipment: "Bodyweight", primaryMuscles: ["Triceps", "Chest"], workoutType: "Strength", bodyPosition: "Hanging"),
    ])
    
    // Core
    exercises.append(contentsOf: [
        Exercise(name: "Cable Crunch", category: "Core", equipment: "Cables", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Kneeling"),
        Exercise(name: "Cable Woodchop", category: "Core", equipment: "Cables", primaryMuscles: ["Obliques"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Pallof Press", category: "Core", equipment: "Cables", primaryMuscles: ["Core"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Ab Crunch Machine", category: "Core", equipment: "Machine", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Hanging Leg Raise", category: "Core", equipment: "Pull-Up Bar", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Hanging Knee Raise", category: "Core", equipment: "Pull-Up Bar", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Plank", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Side Plank", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Obliques"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Bicycle Crunch", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs", "Obliques"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Leg Raise", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Russian Twist", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Obliques"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Mountain Climber", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], workoutType: "Plyometrics", bodyPosition: "Prone"),
        Exercise(name: "Dead Bug", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "V-Up", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Lying"),
    ])
    
    return exercises
}

// MARK: - Sets/Reps Calculator

func getWorkoutPrescription(goal: String, experience: String) -> (sets: Int, reps: String, rest: String) {
    switch goal.lowercased() {
    case "build muscle", "muscle gain":
        switch experience.lowercased() {
        case "beginner": return (3, "8-12", "60-90s")
        case "advanced": return (4, "8-12", "60-90s")
        default: return (4, "8-12", "60-90s")
        }
    case "get stronger", "strength":
        switch experience.lowercased() {
        case "beginner": return (3, "5-8", "90-120s")
        case "advanced": return (5, "3-6", "2-3min")
        default: return (4, "4-6", "2-3min")
        }
    case "lose weight", "weight loss", "fat loss":
        return (3, "12-15", "30-45s")
    case "tone & define", "toning":
        return (3, "12-15", "45-60s")
    case "endurance":
        return (2, "15-20", "30s")
    default:
        return (3, "10-12", "60s")
    }
}

// MARK: - Exercise Selection (CORRECTED Production Logic)

func selectExercisesForDay(
    targetMuscles: [String],
    userProfile: TestUserProfile,
    exerciseDatabase: [Exercise],
    previousExercises: Set<String>,
    count: Int
) -> [WorkoutExercise] {
    
    let isGymUser = userProfile.workoutLocation == "Gym"
    
    // Normalize user equipment for matching
    let normalizedUserEquipment = Set(userProfile.equipment.map { $0.lowercased() })
    
    let gymEquipmentPriority = ["barbell", "dumbbells", "cables", "machine", "kettlebell"]
    let lyingBodyweightKeywords = ["lying", "dead bug", "superman", "glute bridge"]
    let plyometricKeywords = ["jump", "hop", "bound", "plyo", "explosive", "burpee", "mountain climber"]
    
    var scoredExercises: [(exercise: Exercise, score: Int)] = []
    
    for exercise in exerciseDatabase {
        var score = 100
        
        let exerciseName = exercise.name.lowercased()
        let exerciseEquipment = exercise.equipment.lowercased()
        let workoutType = exercise.workoutType?.lowercased() ?? ""
        let bodyPosition = exercise.bodyPosition?.lowercased() ?? ""
        
        // STRICT FILTER: User must have this equipment
        let hasEquipment: Bool
        if exerciseEquipment == "bodyweight" {
            hasEquipment = true // Everyone can do bodyweight
        } else {
            hasEquipment = normalizedUserEquipment.contains { userEquip in
                exerciseEquipment.contains(userEquip) || userEquip.contains(exerciseEquipment)
            }
        }
        
        guard hasEquipment else { continue }
        
        // FILTER: Muscle match
        let exerciseMuscles = Set(exercise.primaryMuscles.map { $0.lowercased() })
        let targetMusclesLower = Set(targetMuscles.map { $0.lowercased() })
        let muscleMatch = !exerciseMuscles.isDisjoint(with: targetMusclesLower) ||
                         targetMusclesLower.contains { target in
                             exercise.category.lowercased().contains(target)
                         }
        
        guard muscleMatch else { continue }
        
        // SCORING
        if isGymUser {
            // Boost gym equipment for gym users
            if let priorityIndex = gymEquipmentPriority.firstIndex(where: { exerciseEquipment.contains($0) }) {
                score += (gymEquipmentPriority.count - priorityIndex) * 15
            }
            
            // Penalize lying bodyweight for gym users
            let isLyingBodyweight = lyingBodyweightKeywords.contains { exerciseName.contains($0) || bodyPosition.contains($0) } &&
                                   exerciseEquipment == "bodyweight"
            if isLyingBodyweight {
                score -= 60
            }
            
            // Penalize all bodyweight for gym users (except pull-ups, dips)
            if exerciseEquipment == "bodyweight" && !exerciseName.contains("pull-up") && !exerciseName.contains("dip") && !exerciseName.contains("chin-up") {
                score -= 25
            }
            
            // Heavily penalize plyometrics for gym users
            let isPlyometric = plyometricKeywords.contains { exerciseName.contains($0) } || workoutType == "plyometrics"
            if isPlyometric {
                score -= 50
            }
        }
        
        // Variety: Penalize recently used
        if previousExercises.contains(exercise.name) {
            score -= 30
        }
        
        // Boost compound movements
        let compoundKeywords = ["press", "squat", "deadlift", "row", "pull-up", "chin-up", "lunge", "dip", "thrust"]
        if compoundKeywords.contains(where: { exerciseName.contains($0) }) {
            score += 15
        }
        
        scoredExercises.append((exercise, score))
    }
    
    // Sort by score
    scoredExercises.sort { $0.score > $1.score }
    
    // Select exercises with limits
    var selected: [WorkoutExercise] = []
    var selectedNames: Set<String> = []
    var plyoCount = 0
    let maxPlyos = isGymUser ? 1 : 2
    
    let prescription = getWorkoutPrescription(goal: userProfile.fitnessGoal, experience: userProfile.experienceLevel)
    
    for item in scoredExercises {
        guard selected.count < count else { break }
        guard !selectedNames.contains(item.exercise.name) else { continue }
        
        let isPlyometric = plyometricKeywords.contains { item.exercise.name.lowercased().contains($0) }
        if isPlyometric {
            if plyoCount >= maxPlyos { continue }
            plyoCount += 1
        }
        
        let workoutExercise = WorkoutExercise(
            exercise: item.exercise,
            sets: prescription.sets,
            reps: prescription.reps,
            rest: prescription.rest,
            score: item.score
        )
        
        selected.append(workoutExercise)
        selectedNames.insert(item.exercise.name)
    }
    
    return selected
}

// MARK: - Generate Report

func generateDetailedReport() {
    let exerciseDatabase = buildExerciseDatabase()
    
    // Create diverse test users for detailed review
    let testUsers: [TestUserProfile] = [
        // User 1: Male Gym User - Build Muscle (Full gym access)
        TestUserProfile(
            id: 1,
            name: "Mike Johnson",
            age: 28,
            gender: "Male",
            weight: 180,
            fitnessGoal: "Build Muscle",
            experienceLevel: "Intermediate",
            workoutLocation: "Gym",
            equipment: ["Barbell", "Dumbbells", "Cables", "Machine", "Kettlebell", "Pull-Up Bar", "Bodyweight"]
        ),
        // User 2: Female Gym User - Lose Weight (Beginner)
        TestUserProfile(
            id: 2,
            name: "Sarah Williams",
            age: 32,
            gender: "Female",
            weight: 145,
            fitnessGoal: "Lose Weight",
            experienceLevel: "Beginner",
            workoutLocation: "Gym",
            equipment: ["Barbell", "Dumbbells", "Cables", "Machine", "Pull-Up Bar", "Bodyweight"]
        ),
        // User 3: Male Home User - Get Stronger (Dumbbells + Pull-Up Bar)
        TestUserProfile(
            id: 3,
            name: "David Chen",
            age: 35,
            gender: "Male",
            weight: 170,
            fitnessGoal: "Get Stronger",
            experienceLevel: "Advanced",
            workoutLocation: "Home",
            equipment: ["Dumbbells", "Pull-Up Bar", "Bodyweight"]
        ),
        // User 4: Female Home User - Tone & Define (Bodyweight ONLY)
        TestUserProfile(
            id: 4,
            name: "Emily Davis",
            age: 26,
            gender: "Female",
            weight: 130,
            fitnessGoal: "Tone & Define",
            experienceLevel: "Beginner",
            workoutLocation: "Home",
            equipment: ["Bodyweight"]
        ),
        // User 5: Male Gym User - Get Stronger (Advanced)
        TestUserProfile(
            id: 5,
            name: "James Thompson",
            age: 40,
            gender: "Male",
            weight: 200,
            fitnessGoal: "Get Stronger",
            experienceLevel: "Advanced",
            workoutLocation: "Gym",
            equipment: ["Barbell", "Dumbbells", "Cables", "Machine", "Kettlebell", "Pull-Up Bar", "Bodyweight"]
        ),
    ]
    
    let dayTemplates: [(name: String, muscles: [String])] = [
        ("Push Day (Chest, Shoulders, Triceps)", ["Chest", "Shoulders", "Triceps"]),
        ("Pull Day (Back, Biceps)", ["Back", "Lats", "Biceps"]),
        ("Leg Day (Quads, Hamstrings, Glutes)", ["Quads", "Hamstrings", "Glutes"]),
        ("Upper Body (Chest, Back, Shoulders)", ["Chest", "Back", "Shoulders"]),
        ("Core & Conditioning", ["Core", "Abs", "Obliques"]),
    ]
    
    print("""
    ╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
    ║                          DETAILED USER WORKOUT PROGRAMS - CORRECTED                                   ║
    ║                                   For Manual Accuracy Review                                          ║
    ╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
    ║  Generated: \(Date())
    ║  This report shows exercises that properly match user equipment availability.                         ║
    ╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝
    
    """)
    
    for user in testUsers {
        print("""
        
        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
        ▓  USER \(user.id): \(user.name.uppercased())
        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
        
        ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
        │  📋 PROFILE                                                                                        │
        ├────────────────────────────────────────────────────────────────────────────────────────────────────┤
        │  Age:              \(user.age) years old
        │  Gender:           \(user.gender)
        │  Weight:           \(user.weight) lbs
        │  Goal:             🎯 \(user.fitnessGoal)
        │  Experience:       \(user.experienceLevel)
        │  Location:         \(user.workoutLocation == "Gym" ? "🏋️ Gym" : "🏠 Home")
        │  Equipment:        \(user.equipment.joined(separator: ", "))
        └────────────────────────────────────────────────────────────────────────────────────────────────────┘
        
        """)
        
        var previousExercises: Set<String> = []
        
        for (dayIndex, dayTemplate) in dayTemplates.enumerated() {
            let selectedExercises = selectExercisesForDay(
                targetMuscles: dayTemplate.muscles,
                userProfile: user,
                exerciseDatabase: exerciseDatabase,
                previousExercises: previousExercises,
                count: 5
            )
            
            print("""
            ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
            ┃  DAY \(dayIndex + 1): \(dayTemplate.name.uppercased())
            ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
            
            """)
            
            for (index, item) in selectedExercises.enumerated() {
                let exercise = item.exercise
                
                // Determine if this is appropriate
                let isGymEquipment = ["barbell", "dumbbells", "cables", "machine"].contains(exercise.equipment.lowercased())
                let isBodyweight = exercise.equipment.lowercased() == "bodyweight"
                let isGymUser = user.workoutLocation == "Gym"
                
                var verdict = "✅"
                var note = ""
                
                // Check appropriateness
                if isGymUser && isBodyweight {
                    let exerciseName = exercise.name.lowercased()
                    if exerciseName.contains("pull-up") || exerciseName.contains("chin-up") || exerciseName.contains("dip") {
                        verdict = "✅"
                        note = "(Acceptable: Compound bodyweight)"
                    } else if exerciseName.contains("lying") || exerciseName.contains("glute bridge") || exerciseName.contains("dead bug") {
                        verdict = "⚠️"
                        note = "(Review: Lying bodyweight for gym user)"
                    } else {
                        verdict = "⚠️"
                        note = "(Review: Bodyweight for gym user)"
                    }
                } else if isGymUser && isGymEquipment {
                    verdict = "✅"
                    note = "(Good: Using gym equipment)"
                } else if !isGymUser {
                    let hasThisEquipment = user.equipment.contains { equip in
                        exercise.equipment.lowercased().contains(equip.lowercased()) || equip.lowercased().contains(exercise.equipment.lowercased())
                    } || exercise.equipment == "Bodyweight"
                    
                    if hasThisEquipment {
                        verdict = "✅"
                        note = "(Good: Matches available equipment)"
                    } else {
                        verdict = "❌"
                        note = "(ERROR: User doesn't have \(exercise.equipment)!)"
                    }
                }
                
                print("      \(index + 1). \(verdict) \(exercise.name)")
                print("         ├─ Equipment:  \(exercise.equipment)")
                print("         ├─ Targets:    \(exercise.primaryMuscles.joined(separator: ", "))")
                print("         ├─ Sets/Reps:  \(item.sets) sets × \(item.reps) reps")
                print("         ├─ Rest:       \(item.rest)")
                print("         └─ Score:      \(item.score) \(note)")
                print("")
                
                previousExercises.insert(exercise.name)
            }
            
            // Summary for this day
            let gymEquipmentCount = selectedExercises.filter { 
                ["barbell", "dumbbells", "cables", "machine"].contains($0.exercise.equipment.lowercased()) 
            }.count
            let bodyweightCount = selectedExercises.filter { $0.exercise.equipment.lowercased() == "bodyweight" }.count
            
            print("""
                  ┌─ Day Summary ────────────────────────────────────────────────────────────────────────────────┐
                  │ Exercises: \(selectedExercises.count) │ Gym Equipment: \(gymEquipmentCount) (\(selectedExercises.count > 0 ? Int(Double(gymEquipmentCount) / Double(selectedExercises.count) * 100) : 0)%) │ Bodyweight: \(bodyweightCount) (\(selectedExercises.count > 0 ? Int(Double(bodyweightCount) / Double(selectedExercises.count) * 100) : 0)%) │ Avg Score: \(selectedExercises.isEmpty ? 0 : selectedExercises.map { $0.score }.reduce(0, +) / selectedExercises.count)
                  └──────────────────────────────────────────────────────────────────────────────────────────────┘
            
            """)
        }
    }
    
    // Final Summary
    print("""
    
    ╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
    ║                                        REVIEW CHECKLIST                                               ║
    ╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
    
    ✅ WHAT TO VERIFY:
    
    1. GYM USERS (Mike #1, Sarah #2, James #5):
       □ Exercises should be 80%+ gym equipment (Barbell, Dumbbells, Cables, Machines)
       □ Should NOT have lying bodyweight exercises (Dead Bug, Glute Bridge, Superman)
       □ Pull-Ups/Dips are acceptable bodyweight exercises
       □ Should have minimal plyometrics (max 1 per workout)
       
    2. HOME USER WITH DUMBBELLS (David #3):
       □ Should ONLY have Dumbbells, Pull-Up Bar, and Bodyweight exercises
       □ Should NOT have Barbell, Cable, or Machine exercises
       □ Sets/Reps should reflect "Get Stronger" goal (lower reps, more sets)
       
    3. BODYWEIGHT-ONLY USER (Emily #4):
       □ Should ONLY have Bodyweight exercises
       □ No equipment exercises (Dumbbells, Barbell, Cables, Machines)
       □ Sets/Reps should reflect "Tone & Define" goal (higher reps)
       
    4. ALL USERS:
       □ No duplicate exercises within the same day
       □ Exercises target the specified muscle groups
       □ Sets/Reps align with the user's goal
    
    ⚠️  FLAGS TO LOOK FOR:
       • ⚠️  = Review needed (may be acceptable but worth checking)
       • ❌ = Error (equipment mismatch - should NOT happen)
       • ✅ = Good selection
    
    ╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝
    """)
}

// Run
generateDetailedReport()

