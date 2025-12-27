#!/usr/bin/env swift
//
//  DetailedUserWorkouts.swift
//  Shows actual workout programs for manual review
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
        Exercise(name: "Machine Chest Press", category: "Chest", equipment: "Machines", primaryMuscles: ["Chest", "Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Pec Deck Machine", category: "Chest", equipment: "Machines", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Push Up", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest", "Triceps"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Wide Push Up", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Lying Floor Chest Fly", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Lying"),
    ])
    
    // Back
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Row", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Deadlift", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Hamstrings", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Pendlay Row", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Lats"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Row", category: "Back", equipment: "Dumbbells", primaryMuscles: ["Back", "Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Pullover", category: "Back", equipment: "Dumbbells", primaryMuscles: ["Lats", "Chest"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Lat Pulldown", category: "Back", equipment: "Cables", primaryMuscles: ["Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Seated Cable Row", category: "Back", equipment: "Cables", primaryMuscles: ["Back", "Lats"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Face Pull", category: "Back", equipment: "Cables", primaryMuscles: ["Rear Delts", "Upper Back"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Straight Arm Pulldown", category: "Back", equipment: "Cables", primaryMuscles: ["Lats"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Row", category: "Back", equipment: "Machines", primaryMuscles: ["Back", "Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Lat Pulldown Machine", category: "Back", equipment: "Machines", primaryMuscles: ["Lats"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Pull Up", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Chin Up", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lats", "Biceps"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Superman Floor Exercise", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lower Back"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Bird Dog Floor", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lower Back", "Core"], workoutType: "Strength", bodyPosition: "Prone"),
    ])
    
    // Legs
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Squat", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Front Squat", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Romanian Deadlift", category: "Legs", equipment: "Barbell", primaryMuscles: ["Hamstrings", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Barbell Lunges", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Hip Thrust Barbell", category: "Legs", equipment: "Barbell", primaryMuscles: ["Glutes"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Dumbbell Squat", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Lunges", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Goblet Squat", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Romanian Deadlift", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Hamstrings", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Leg Press", category: "Legs", equipment: "Machines", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Leg Extension", category: "Legs", equipment: "Machines", primaryMuscles: ["Quads"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Leg Curl Machine", category: "Legs", equipment: "Machines", primaryMuscles: ["Hamstrings"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Hack Squat Machine", category: "Legs", equipment: "Machines", primaryMuscles: ["Quads"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Pull Through", category: "Legs", equipment: "Cables", primaryMuscles: ["Glutes", "Hamstrings"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Kickback", category: "Legs", equipment: "Cables", primaryMuscles: ["Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Bodyweight Squat", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Bodyweight Lunges", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Glute Bridge Floor", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Glutes"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Jump Squat", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], workoutType: "Plyometrics", bodyPosition: "Standing"),
        Exercise(name: "Box Jump", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads"], workoutType: "Plyometrics", bodyPosition: "Standing"),
    ])
    
    // Shoulders
    exercises.append(contentsOf: [
        Exercise(name: "Overhead Press", category: "Shoulders", equipment: "Barbell", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Push Press", category: "Shoulders", equipment: "Barbell", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Shoulder Press", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Arnold Press", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Lateral Raise", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Front Raise", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Rear Delt Fly", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Rear Delts"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Lateral Raise", category: "Shoulders", equipment: "Cables", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Front Raise", category: "Shoulders", equipment: "Cables", primaryMuscles: ["Shoulders"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Shoulder Press", category: "Shoulders", equipment: "Machines", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Reverse Pec Deck", category: "Shoulders", equipment: "Machines", primaryMuscles: ["Rear Delts"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Pike Push Up", category: "Shoulders", equipment: "Bodyweight", primaryMuscles: ["Shoulders", "Triceps"], workoutType: "Strength", bodyPosition: "Prone"),
    ])
    
    // Arms - Biceps & Triceps
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Curl", category: "Arms", equipment: "Barbell", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "EZ Bar Curl", category: "Arms", equipment: "Barbell", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Skull Crusher", category: "Arms", equipment: "Barbell", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Close Grip Bench Press", category: "Arms", equipment: "Barbell", primaryMuscles: ["Triceps", "Chest"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Dumbbell Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Hammer Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps", "Forearms"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Incline Dumbbell Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Tricep Kickback", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Overhead Tricep Extension", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Curl", category: "Arms", equipment: "Cables", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Hammer Curl", category: "Arms", equipment: "Cables", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Tricep Pushdown", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Rope Tricep Extension", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Overhead Cable Extension", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Preacher Curl Machine", category: "Arms", equipment: "Machines", primaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Tricep Dip Machine", category: "Arms", equipment: "Machines", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Diamond Push Up", category: "Arms", equipment: "Bodyweight", primaryMuscles: ["Triceps", "Chest"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Bench Dips", category: "Arms", equipment: "Bodyweight", primaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
    ])
    
    // Core
    exercises.append(contentsOf: [
        Exercise(name: "Cable Crunch", category: "Core", equipment: "Cables", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Kneeling"),
        Exercise(name: "Cable Woodchop", category: "Core", equipment: "Cables", primaryMuscles: ["Obliques"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Pallof Press", category: "Core", equipment: "Cables", primaryMuscles: ["Core"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Crunch", category: "Core", equipment: "Machines", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Hanging Leg Raise", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Hanging Knee Raise", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Captain's Chair Leg Raise", category: "Core", equipment: "Machines", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Plank", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Side Plank", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Obliques"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Dead Bug Floor", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Lying Leg Raise", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Floor Crunch", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Russian Twist", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Obliques"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Mountain Climber", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], workoutType: "Plyometrics", bodyPosition: "Prone"),
    ])
    
    return exercises
}

// MARK: - Exercise Selection (Production Logic)

func selectExercisesForDay(
    targetMuscles: [String],
    userProfile: TestUserProfile,
    exerciseDatabase: [Exercise],
    previousExercises: Set<String>,
    count: Int
) -> [(exercise: Exercise, score: Int)] {
    
    let isGymUser = userProfile.workoutLocation == "Gym" ||
                   userProfile.equipment.contains { ["Barbell", "Cables", "Machines"].contains($0) }
    
    let gymEquipmentPriority = ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell"]
    let lyingBodyweightKeywords = ["lying", "floor", "dead bug", "bird dog", "superman", "prone"]
    let plyometricKeywords = ["jump", "hop", "bound", "plyo", "explosive", "burpee", "mountain climber"]
    
    let normalizedUserEquipment = Set(userProfile.equipment.map { $0.lowercased() })
    
    var scoredExercises: [(exercise: Exercise, score: Int)] = []
    
    for exercise in exerciseDatabase {
        var score = 100
        
        let exerciseName = exercise.name.lowercased()
        let exerciseEquipment = exercise.equipment.lowercased()
        let workoutType = exercise.workoutType?.lowercased() ?? ""
        let bodyPosition = exercise.bodyPosition?.lowercased() ?? ""
        
        // FILTER: Equipment match
        let equipmentMatch = normalizedUserEquipment.isEmpty ||
            normalizedUserEquipment.contains { equip in
                exerciseEquipment.contains(equip) || equip == "bodyweight"
            } ||
            exerciseEquipment == "bodyweight"
        
        guard equipmentMatch else { continue }
        
        // FILTER: Exclude stretching
        let isStretch = workoutType == "stretch"
        guard !isStretch else { continue }
        
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
            if let priorityIndex = gymEquipmentPriority.firstIndex(where: { exerciseEquipment.contains($0.lowercased()) }) {
                score += (gymEquipmentPriority.count - priorityIndex) * 15
            }
            
            let isLyingBodyweight = lyingBodyweightKeywords.contains { exerciseName.contains($0) || bodyPosition.contains($0) } &&
                                   exerciseEquipment == "bodyweight"
            if isLyingBodyweight {
                score -= 80
            }
            
            if exerciseEquipment == "bodyweight" {
                score -= 30
            }
            
            let isPlyometric = plyometricKeywords.contains { exerciseName.contains($0) } || workoutType == "plyometrics"
            if isPlyometric {
                score -= 40
            }
        }
        
        if previousExercises.contains(exercise.name) {
            score -= 25
        }
        
        let compoundKeywords = ["press", "squat", "deadlift", "row", "pull-up", "pull up", "chin-up", "chin up", "lunge", "dip"]
        if compoundKeywords.contains(where: { exerciseName.contains($0) }) {
            score += 20
        }
        
        scoredExercises.append((exercise, score))
    }
    
    scoredExercises.sort { $0.score > $1.score }
    
    var selected: [(exercise: Exercise, score: Int)] = []
    var selectedNames: Set<String> = []
    var plyoCount = 0
    let maxPlyos = isGymUser ? 1 : 2
    
    for item in scoredExercises {
        guard selected.count < count else { break }
        guard !selectedNames.contains(item.exercise.name) else { continue }
        
        let isPlyometric = plyometricKeywords.contains { item.exercise.name.lowercased().contains($0) }
        if isPlyometric {
            if plyoCount >= maxPlyos { continue }
            plyoCount += 1
        }
        
        selected.append(item)
        selectedNames.insert(item.exercise.name)
    }
    
    return selected
}

// MARK: - Generate Report

func generateDetailedReport() {
    let exerciseDatabase = buildExerciseDatabase()
    
    // Create diverse test users for detailed review
    let testUsers: [TestUserProfile] = [
        // User 1: Male Gym User - Build Muscle
        TestUserProfile(
            id: 1,
            name: "Mike Johnson",
            age: 28,
            gender: "Male",
            weight: 180,
            fitnessGoal: "Build Muscle",
            experienceLevel: "Intermediate",
            workoutLocation: "Gym",
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell", "Bench", "Pull-up Bar", "Bodyweight"]
        ),
        // User 2: Female Gym User - Lose Weight
        TestUserProfile(
            id: 2,
            name: "Sarah Williams",
            age: 32,
            gender: "Female",
            weight: 145,
            fitnessGoal: "Lose Weight",
            experienceLevel: "Beginner",
            workoutLocation: "Gym",
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell", "Bench", "Pull-up Bar", "Bodyweight"]
        ),
        // User 3: Male Home User - Get Stronger (Limited Equipment)
        TestUserProfile(
            id: 3,
            name: "David Chen",
            age: 35,
            gender: "Male",
            weight: 170,
            fitnessGoal: "Get Stronger",
            experienceLevel: "Advanced",
            workoutLocation: "Home",
            equipment: ["Bodyweight", "Dumbbells", "Pull-up Bar"]
        ),
        // User 4: Female Home User - Tone & Define (Bodyweight Only)
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
        // User 5: Male Gym User - Get Stronger
        TestUserProfile(
            id: 5,
            name: "James Thompson",
            age: 40,
            gender: "Male",
            weight: 200,
            fitnessGoal: "Get Stronger",
            experienceLevel: "Advanced",
            workoutLocation: "Gym",
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell", "Bench", "Pull-up Bar", "Bodyweight"]
        ),
    ]
    
    let dayTemplates: [(name: String, muscles: [String])] = [
        ("Push Day", ["Chest", "Shoulders", "Triceps"]),
        ("Pull Day", ["Back", "Lats", "Biceps"]),
        ("Leg Day", ["Quads", "Hamstrings", "Glutes"]),
    ]
    
    print("""
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                  DETAILED USER WORKOUT PROGRAMS                              ║
    ║                     For Manual Accuracy Review                               ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
    
    Generated: \(Date())
    
    This report shows the actual exercises selected for 5 diverse users.
    Please review to ensure the algorithm is selecting appropriate exercises.
    
    """)
    
    for user in testUsers {
        print("""
        ═══════════════════════════════════════════════════════════════════════════════
        USER \(user.id): \(user.name.uppercased())
        ═══════════════════════════════════════════════════════════════════════════════
        
        📋 PROFILE:
        ┌─────────────────────────────────────────────────────────────────────────────┐
        │ Age:              \(user.age) years old
        │ Gender:           \(user.gender)
        │ Weight:           \(user.weight) lbs
        │ Goal:             \(user.fitnessGoal)
        │ Experience:       \(user.experienceLevel)
        │ Location:         \(user.workoutLocation)
        │ Equipment:        \(user.equipment.joined(separator: ", "))
        └─────────────────────────────────────────────────────────────────────────────┘
        
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
            ┌─────────────────────────────────────────────────────────────────────────────┐
            │ DAY \(dayIndex + 1): \(dayTemplate.name.uppercased())
            │ Target Muscles: \(dayTemplate.muscles.joined(separator: ", "))
            └─────────────────────────────────────────────────────────────────────────────┘
            
            """)
            
            for (index, item) in selectedExercises.enumerated() {
                let exercise = item.exercise
                let score = item.score
                
                // Determine if this is a good/expected selection
                let isGymEquipment = ["Barbell", "Dumbbells", "Cables", "Machines"].contains(exercise.equipment)
                let isBodyweight = exercise.equipment == "Bodyweight"
                let isGymUser = user.workoutLocation == "Gym"
                
                var verdict = "✅"
                var note = ""
                
                if isGymUser && isBodyweight && !exercise.name.contains("Pull Up") && !exercise.name.contains("Chin Up") && !exercise.name.contains("Dip") {
                    verdict = "⚠️"
                    note = " (Bodyweight for gym user - verify this is intentional)"
                }
                
                if isGymUser && isGymEquipment {
                    verdict = "✅"
                    note = " (Good: Using gym equipment)"
                }
                
                if !isGymUser && isBodyweight {
                    verdict = "✅"
                    note = " (Good: Matches home equipment)"
                }
                
                print("  \(index + 1). \(verdict) \(exercise.name)")
                print("      Equipment: \(exercise.equipment)")
                print("      Targets: \(exercise.primaryMuscles.joined(separator: ", "))")
                print("      Score: \(score)\(note)")
                print("")
                
                previousExercises.insert(exercise.name)
            }
            
            // Summary for this day
            let gymEquipmentCount = selectedExercises.filter { 
                ["Barbell", "Dumbbells", "Cables", "Machines"].contains($0.exercise.equipment) 
            }.count
            let bodyweightCount = selectedExercises.filter { $0.exercise.equipment == "Bodyweight" }.count
            
            print("""
            ┌ Day Summary ─────────────────────────────────────────────────────────────────
            │ Total Exercises: \(selectedExercises.count)
            │ Gym Equipment: \(gymEquipmentCount) (\(Int(Double(gymEquipmentCount) / Double(selectedExercises.count) * 100))%)
            │ Bodyweight: \(bodyweightCount) (\(Int(Double(bodyweightCount) / Double(selectedExercises.count) * 100))%)
            │ Average Score: \(selectedExercises.map { $0.score }.reduce(0, +) / selectedExercises.count)
            └──────────────────────────────────────────────────────────────────────────────
            
            """)
        }
        
        print("\n")
    }
    
    // Overall analysis
    print("""
    ═══════════════════════════════════════════════════════════════════════════════
    ANALYSIS SUMMARY
    ═══════════════════════════════════════════════════════════════════════════════
    
    ✅ EXPECTED BEHAVIOR:
    
    1. GYM USERS (Mike, Sarah, James) should have:
       • Primarily Barbell, Dumbbell, Cable, and Machine exercises
       • Minimal lying/floor bodyweight exercises
       • Pull-ups and Dips are acceptable bodyweight for gym users
    
    2. HOME USERS (David, Emily) should have:
       • Exercises matching their available equipment
       • David: Dumbbells + Bodyweight + Pull-up bar exercises
       • Emily: Bodyweight-only exercises
    
    3. ALL USERS should have:
       • No duplicate exercises within the same day
       • Exercises targeting the specified muscle groups
       • Max 1 plyometric exercise for gym users
       • Max 2 plyometric exercises for home users
    
    ⚠️  THINGS TO CHECK:
    
    1. Are gym users getting too many bodyweight exercises?
    2. Are the exercises appropriate for the user's experience level?
    3. Do the exercises target the correct muscle groups?
    4. Is there good variety across the workout days?
    
    ═══════════════════════════════════════════════════════════════════════════════
    END OF DETAILED REPORT
    ═══════════════════════════════════════════════════════════════════════════════
    """)
}

// Run
generateDetailedReport()

