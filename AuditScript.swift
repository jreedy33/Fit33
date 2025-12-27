#!/usr/bin/env swift
//
//  AuditScript.swift
//  GoFit Program Generation Audit
//
//  Run with: swift AuditScript.swift
//

import Foundation

// MARK: - Test User Profile

struct TestUserProfile {
    let id: Int
    let name: String
    let age: Int
    let gender: String
    let weight: Int
    let fitnessGoal: String
    let experienceLevel: String
    let strengthLevel: String
    let availableDays: Int
    let workoutLocation: String
    let equipment: [String]
    let preferredDuration: Int
}

// MARK: - Exercise Database (Simulated from CSV data)

struct Exercise {
    let name: String
    let category: String
    let equipment: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let workoutType: String?
    let bodyPosition: String?
}

// MARK: - Audit Results

struct ExerciseAuditResult {
    let name: String
    let equipment: String
    let score: Double
    var issues: [String]
}

struct WorkoutAuditResult {
    let dayName: String
    let exercises: [ExerciseAuditResult]
    let totalScore: Double
    var issues: [String]
}

struct ProgramAuditResult {
    let userId: Int
    let userName: String
    let userProfile: TestUserProfile
    let programName: String
    let workoutResults: [WorkoutAuditResult]
    let overallScore: Double
    let exerciseVarietyScore: Double
    let goalAlignmentScore: Double
    let equipmentUtilizationScore: Double
    var issues: [String]
}

// MARK: - Exercise Database Builder

func buildExerciseDatabase() -> [Exercise] {
    var exercises: [Exercise] = []
    
    // Gym Equipment Exercises - Chest
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Bench Press", category: "Chest", equipment: "Barbell", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps", "Shoulders"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Incline Barbell Press", category: "Chest", equipment: "Barbell", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps", "Shoulders"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Dumbbell Bench Press", category: "Chest", equipment: "Dumbbells", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Incline Dumbbell Press", category: "Chest", equipment: "Dumbbells", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Cable Fly", category: "Chest", equipment: "Cables", primaryMuscles: ["Chest"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Crossover", category: "Chest", equipment: "Cables", primaryMuscles: ["Chest"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Chest Press", category: "Chest", equipment: "Machines", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Pec Deck Machine", category: "Chest", equipment: "Machines", primaryMuscles: ["Chest"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Push Up", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Lying Floor Fly", category: "Chest", equipment: "Bodyweight", primaryMuscles: ["Chest"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
    ])
    
    // Gym Equipment Exercises - Back
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Row", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Lats"], secondaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Deadlift", category: "Back", equipment: "Barbell", primaryMuscles: ["Back", "Hamstrings"], secondaryMuscles: ["Glutes"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Row", category: "Back", equipment: "Dumbbells", primaryMuscles: ["Back", "Lats"], secondaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Lat Pulldown", category: "Back", equipment: "Cables", primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Seated Cable Row", category: "Back", equipment: "Cables", primaryMuscles: ["Back"], secondaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Face Pull", category: "Back", equipment: "Cables", primaryMuscles: ["Rear Delts", "Upper Back"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Row", category: "Back", equipment: "Machines", primaryMuscles: ["Back"], secondaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Assisted Pull Up Machine", category: "Back", equipment: "Machines", primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Pull Up", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps"], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Superman Lying", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lower Back"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Bird Dog Floor", category: "Back", equipment: "Bodyweight", primaryMuscles: ["Lower Back"], secondaryMuscles: ["Core"], workoutType: "Strength", bodyPosition: "Prone"),
    ])
    
    // Gym Equipment Exercises - Legs
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Squat", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Hamstrings"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Romanian Deadlift", category: "Legs", equipment: "Barbell", primaryMuscles: ["Hamstrings", "Glutes"], secondaryMuscles: ["Lower Back"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Barbell Lunges", category: "Legs", equipment: "Barbell", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Squat", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Lunges", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Goblet Squat", category: "Legs", equipment: "Dumbbells", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Leg Press", category: "Legs", equipment: "Machines", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Leg Extension", category: "Legs", equipment: "Machines", primaryMuscles: ["Quads"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Leg Curl Machine", category: "Legs", equipment: "Machines", primaryMuscles: ["Hamstrings"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Cable Pull Through", category: "Legs", equipment: "Cables", primaryMuscles: ["Glutes", "Hamstrings"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Bodyweight Squat", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Lying Leg Curl Floor", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Hamstrings"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Jump Squat", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Plyometrics", bodyPosition: "Standing"),
        Exercise(name: "Box Jump", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Plyometrics", bodyPosition: "Standing"),
    ])
    
    // Gym Equipment Exercises - Shoulders
    exercises.append(contentsOf: [
        Exercise(name: "Overhead Press", category: "Shoulders", equipment: "Barbell", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Dumbbell Shoulder Press", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Lateral Raise", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Front Raise", category: "Shoulders", equipment: "Dumbbells", primaryMuscles: ["Shoulders"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Lateral Raise", category: "Shoulders", equipment: "Cables", primaryMuscles: ["Shoulders"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Shoulder Press", category: "Shoulders", equipment: "Machines", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Pike Push Up", category: "Shoulders", equipment: "Bodyweight", primaryMuscles: ["Shoulders"], secondaryMuscles: ["Triceps"], workoutType: "Strength", bodyPosition: "Prone"),
    ])
    
    // Gym Equipment Exercises - Arms
    exercises.append(contentsOf: [
        Exercise(name: "Barbell Curl", category: "Arms", equipment: "Barbell", primaryMuscles: ["Biceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "EZ Bar Curl", category: "Arms", equipment: "Barbell", primaryMuscles: ["Biceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Skull Crusher", category: "Arms", equipment: "Barbell", primaryMuscles: ["Triceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Dumbbell Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Hammer Curl", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Biceps"], secondaryMuscles: ["Forearms"], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Tricep Kickback", category: "Arms", equipment: "Dumbbells", primaryMuscles: ["Triceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Cable Curl", category: "Arms", equipment: "Cables", primaryMuscles: ["Biceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Tricep Pushdown", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Rope Tricep Extension", category: "Arms", equipment: "Cables", primaryMuscles: ["Triceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Preacher Curl Machine", category: "Arms", equipment: "Machines", primaryMuscles: ["Biceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Tricep Dip Machine", category: "Arms", equipment: "Machines", primaryMuscles: ["Triceps"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Diamond Push Up", category: "Arms", equipment: "Bodyweight", primaryMuscles: ["Triceps"], secondaryMuscles: ["Chest"], workoutType: "Strength", bodyPosition: "Prone"),
    ])
    
    // Gym Equipment Exercises - Core
    exercises.append(contentsOf: [
        Exercise(name: "Cable Crunch", category: "Core", equipment: "Cables", primaryMuscles: ["Abs"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Kneeling"),
        Exercise(name: "Cable Woodchop", category: "Core", equipment: "Cables", primaryMuscles: ["Obliques"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Standing"),
        Exercise(name: "Machine Crunch", category: "Core", equipment: "Machines", primaryMuscles: ["Abs"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Seated"),
        Exercise(name: "Hanging Leg Raise", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Hanging"),
        Exercise(name: "Plank", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Prone"),
        Exercise(name: "Dead Bug Floor", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Core"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Lying Leg Raise", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Floor Crunch", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Abs"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Lying"),
        Exercise(name: "Russian Twist", category: "Core", equipment: "Bodyweight", primaryMuscles: ["Obliques"], secondaryMuscles: [], workoutType: "Strength", bodyPosition: "Seated"),
    ])
    
    // Additional Plyometrics
    exercises.append(contentsOf: [
        Exercise(name: "Burpee", category: "Full Body", equipment: "Bodyweight", primaryMuscles: ["Full Body"], secondaryMuscles: [], workoutType: "Plyometrics", bodyPosition: "Standing"),
        Exercise(name: "Mountain Climber", category: "Full Body", equipment: "Bodyweight", primaryMuscles: ["Core"], secondaryMuscles: [], workoutType: "Plyometrics", bodyPosition: "Prone"),
        Exercise(name: "Jumping Lunge", category: "Legs", equipment: "Bodyweight", primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: [], workoutType: "Plyometrics", bodyPosition: "Standing"),
        Exercise(name: "Tuck Jump", category: "Full Body", equipment: "Bodyweight", primaryMuscles: ["Quads"], secondaryMuscles: [], workoutType: "Plyometrics", bodyPosition: "Standing"),
        Exercise(name: "Hop Forward", category: "Full Body", equipment: "Bodyweight", primaryMuscles: ["Quads"], secondaryMuscles: [], workoutType: "Plyometrics", bodyPosition: "Standing"),
    ])
    
    // Stretching (should be filtered out)
    exercises.append(contentsOf: [
        Exercise(name: "Hamstring Stretch", category: "Stretching", equipment: "Bodyweight", primaryMuscles: ["Hamstrings"], secondaryMuscles: [], workoutType: "Stretch", bodyPosition: "Seated"),
        Exercise(name: "Quad Stretch", category: "Stretching", equipment: "Bodyweight", primaryMuscles: ["Quads"], secondaryMuscles: [], workoutType: "Stretch", bodyPosition: "Standing"),
        Exercise(name: "Chest Stretch", category: "Stretching", equipment: "Bodyweight", primaryMuscles: ["Chest"], secondaryMuscles: [], workoutType: "Stretch", bodyPosition: "Standing"),
    ])
    
    return exercises
}

// MARK: - User Generation

func generateTestUsers() -> [TestUserProfile] {
    var users: [TestUserProfile] = []
    
    let maleNames = ["James", "John", "Michael", "David", "Chris", "Daniel", "Matthew", "Andrew", "Joshua", "Ryan", 
                     "Kevin", "Brian", "Steven", "Jason", "Timothy", "Eric", "Mark", "Jeffrey", "Scott", "Patrick",
                     "Brandon", "Justin", "Tyler", "Aaron", "Adam", "Nathan", "Jonathan", "Kyle", "Derek", "Sean"]
    let femaleNames = ["Emily", "Sarah", "Jessica", "Ashley", "Amanda", "Jennifer", "Samantha", "Elizabeth", "Nicole", "Stephanie",
                      "Michelle", "Rachel", "Lauren", "Megan", "Brittany", "Rebecca", "Christina", "Amber", "Heather", "Melissa",
                      "Kelly", "Danielle", "Tiffany", "Lindsay", "Katherine", "Courtney", "Victoria", "Hannah", "Olivia", "Emma"]
    
    let goals = ["Build Muscle", "Lose Weight", "Get Stronger", "Get Fit", "Tone & Define"]
    let experienceLevels = ["Beginner", "Intermediate", "Advanced"]
    let strengthLevels = ["Very Light", "Light", "Moderate", "Strong", "Very Strong"]
    
    let gymEquipment = ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell", "Bench", "Pull-up Bar", "Bodyweight"]
    let homeEquipmentSets: [[String]] = [
        ["Bodyweight"],
        ["Bodyweight", "Dumbbells"],
        ["Bodyweight", "Resistance Bands"],
        ["Bodyweight", "Dumbbells", "Resistance Bands"],
        ["Bodyweight", "Dumbbells", "Kettlebell"],
        ["Bodyweight", "Dumbbells", "Pull-up Bar"],
        ["Bodyweight", "Dumbbells", "Resistance Bands", "Bench"],
        ["Bodyweight", "Barbell", "Dumbbells", "Bench", "Pull-up Bar"]
    ]
    
    for i in 0..<100 {
        let isFemale = i % 2 == 0
        let name = isFemale ? femaleNames[i % femaleNames.count] : maleNames[i % maleNames.count]
        let age = 18 + (i * 47 / 100) + Int.random(in: 0...5)
        let baseWeight = isFemale ? 130 : 170
        let weight = baseWeight + Int.random(in: -30...50)
        let goal = goals[i % goals.count]
        
        let experienceIndex: Int
        if age < 25 {
            experienceIndex = min(i % 3, 1)
        } else if age < 40 {
            experienceIndex = i % 3
        } else {
            experienceIndex = max(0, (i % 3) - 1)
        }
        let experience = experienceLevels[experienceIndex]
        
        let strengthIndex: Int
        switch experience {
        case "Beginner": strengthIndex = Int.random(in: 0...2)
        case "Intermediate": strengthIndex = Int.random(in: 1...3)
        case "Advanced": strengthIndex = Int.random(in: 2...4)
        default: strengthIndex = 2
        }
        let strengthLevel = strengthLevels[strengthIndex]
        
        let availableDays = 2 + (i % 5)
        let isGym = i % 5 != 0 && i % 5 != 3  // 60% gym
        let location = isGym ? "Gym" : "Home"
        let equipment = isGym ? gymEquipment : homeEquipmentSets[i % homeEquipmentSets.count]
        let duration = 30 + (i % 4) * 15
        
        users.append(TestUserProfile(
            id: i + 1,
            name: "\(name) \(i + 1)",
            age: age,
            gender: isFemale ? "Female" : "Male",
            weight: weight,
            fitnessGoal: goal,
            experienceLevel: experience,
            strengthLevel: strengthLevel,
            availableDays: availableDays,
            workoutLocation: location,
            equipment: equipment,
            preferredDuration: duration
        ))
    }
    
    return users
}

// MARK: - Exercise Selection Logic (Simulating Production Code)

func selectExercisesForDay(
    targetMuscles: [String],
    userProfile: TestUserProfile,
    exerciseDatabase: [Exercise],
    previousExercises: Set<String>,
    count: Int
) -> [Exercise] {
    
    let isGymUser = userProfile.workoutLocation == "Gym" ||
                   userProfile.equipment.contains { ["Barbell", "Cables", "Machines"].contains($0) }
    
    let gymEquipmentPriority = ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell"]
    let lyingBodyweightKeywords = ["lying", "floor", "dead bug", "bird dog", "superman", "prone"]
    let plyometricKeywords = ["jump", "hop", "bound", "plyo", "explosive", "burpee"]
    
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
        let isStretch = workoutType == "stretch" || exercise.category == "Stretching"
        guard !isStretch else { continue }
        
        // FILTER: Muscle match
        let exerciseMuscles = Set(exercise.primaryMuscles.map { $0.lowercased() })
        let targetMusclesLower = Set(targetMuscles.map { $0.lowercased() })
        let muscleMatch = !exerciseMuscles.isDisjoint(with: targetMusclesLower) ||
                         targetMusclesLower.contains { target in
                             exercise.category.lowercased().contains(target)
                         }
        
        guard muscleMatch else { continue }
        
        // SCORING: Gym user adjustments
        if isGymUser {
            // BOOST: Gym equipment priority
            if let priorityIndex = gymEquipmentPriority.firstIndex(where: { exerciseEquipment.contains($0.lowercased()) }) {
                score += (gymEquipmentPriority.count - priorityIndex) * 15
            }
            
            // PENALIZE: Lying/floor bodyweight for gym users
            let isLyingBodyweight = lyingBodyweightKeywords.contains { exerciseName.contains($0) || bodyPosition.contains($0) } &&
                                   exerciseEquipment == "bodyweight"
            if isLyingBodyweight {
                score -= 80
            }
            
            // PENALIZE: Pure bodyweight for gym users
            if exerciseEquipment == "bodyweight" {
                score -= 30
            }
            
            // PENALIZE: Plyometrics for gym sessions
            let isPlyometric = plyometricKeywords.contains { exerciseName.contains($0) } || workoutType == "plyometrics"
            if isPlyometric {
                score -= 40
            }
        }
        
        // PENALIZE: Recently used
        if previousExercises.contains(exercise.name) {
            score -= 25
        }
        
        // BOOST: Compound movements
        let compoundKeywords = ["press", "squat", "deadlift", "row", "pull-up", "lunge", "dip"]
        if compoundKeywords.contains(where: { exerciseName.contains($0) }) {
            score += 20
        }
        
        scoredExercises.append((exercise, score))
    }
    
    // Sort and select
    scoredExercises.sort { $0.score > $1.score }
    
    var selected: [Exercise] = []
    var selectedNames: Set<String> = []
    var plyoCount = 0
    let maxPlyos = isGymUser ? 1 : 2
    
    for (exercise, _) in scoredExercises {
        guard selected.count < count else { break }
        guard !selectedNames.contains(exercise.name) else { continue }
        
        let isPlyometric = plyometricKeywords.contains { exercise.name.lowercased().contains($0) }
        if isPlyometric {
            if plyoCount >= maxPlyos { continue }
            plyoCount += 1
        }
        
        selected.append(exercise)
        selectedNames.insert(exercise.name)
    }
    
    return selected
}

// MARK: - Grading Functions

func gradeExercise(
    exercise: Exercise,
    userProfile: TestUserProfile,
    targetMuscles: [String],
    allExercisesInDay: [Exercise]
) -> ExerciseAuditResult {
    
    var score: Double = 100
    var issues: [String] = []
    
    let isGymUser = userProfile.workoutLocation == "Gym"
    let exerciseEquipment = exercise.equipment.lowercased()
    let exerciseName = exercise.name.lowercased()
    let bodyPosition = exercise.bodyPosition?.lowercased() ?? ""
    let workoutType = exercise.workoutType?.lowercased() ?? ""
    
    // 1. Equipment Appropriateness (25 pts)
    let normalizedUserEquipment = Set(userProfile.equipment.map { $0.lowercased() })
    if !normalizedUserEquipment.contains(exerciseEquipment) && exerciseEquipment != "bodyweight" {
        score -= 25
        issues.append("Equipment '\(exercise.equipment)' not available")
    }
    
    // 2. Location Appropriateness (20 pts)
    if isGymUser {
        let lyingBodyweightKeywords = ["lying", "floor", "dead bug", "bird dog", "superman", "prone"]
        let isLyingBodyweight = lyingBodyweightKeywords.contains { exerciseName.contains($0) || bodyPosition.contains($0) } &&
                               exerciseEquipment == "bodyweight"
        
        if isLyingBodyweight {
            score -= 15
            issues.append("Lying bodyweight exercise for gym user: \(exercise.name)")
        }
        
        if exerciseEquipment == "bodyweight" {
            score -= 5
            issues.append("Bodyweight when gym equipment available")
        }
    }
    
    // 3. Plyometric Check (5 pts)
    let plyometricKeywords = ["jump", "hop", "bound", "plyo"]
    let isPlyometric = plyometricKeywords.contains { exerciseName.contains($0) } || workoutType == "plyometrics"
    
    if isPlyometric && isGymUser {
        let plyoCount = allExercisesInDay.filter { ex in
            plyometricKeywords.contains { ex.name.lowercased().contains($0) } ||
            ex.workoutType?.lowercased() == "plyometrics"
        }.count
        
        if plyoCount > 1 {
            score -= 10
            issues.append("Multiple plyometrics in gym workout")
        }
    }
    
    // 4. Duplicate Check (15 pts)
    let duplicateCount = allExercisesInDay.filter { $0.name == exercise.name }.count
    if duplicateCount > 1 {
        score -= 15 * Double(duplicateCount - 1)
        issues.append("Exercise duplicated \(duplicateCount)x")
    }
    
    return ExerciseAuditResult(
        name: exercise.name,
        equipment: exercise.equipment,
        score: max(0, score),
        issues: issues
    )
}

func gradeWorkout(
    exercises: [Exercise],
    userProfile: TestUserProfile,
    dayName: String,
    targetMuscles: [String]
) -> WorkoutAuditResult {
    
    var exerciseResults: [ExerciseAuditResult] = []
    var issues: [String] = []
    
    for exercise in exercises {
        let result = gradeExercise(
            exercise: exercise,
            userProfile: userProfile,
            targetMuscles: targetMuscles,
            allExercisesInDay: exercises
        )
        exerciseResults.append(result)
    }
    
    let avgScore = exerciseResults.isEmpty ? 0 :
        exerciseResults.reduce(0) { $0 + $1.score } / Double(exerciseResults.count)
    
    // Check workout-level issues
    if exercises.count < 3 {
        issues.append("Too few exercises (\(exercises.count))")
    }
    
    if userProfile.workoutLocation == "Gym" {
        let equipmentUsed = Set(exercises.map { $0.equipment.lowercased() })
        let bodyweightOnly = equipmentUsed.count == 1 && equipmentUsed.contains("bodyweight")
        
        if bodyweightOnly && exercises.count >= 3 {
            issues.append("Gym workout using only bodyweight")
        }
        
        let gymEquipmentUsed = equipmentUsed.filter { ["barbell", "dumbbells", "cables", "machines", "kettlebell"].contains($0) }
        if gymEquipmentUsed.isEmpty && exercises.count >= 3 {
            issues.append("No gym equipment utilized")
        }
    }
    
    return WorkoutAuditResult(
        dayName: dayName,
        exercises: exerciseResults,
        totalScore: avgScore,
        issues: issues
    )
}

// MARK: - Run Audit

func runAudit() {
    print("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║           PROGRAM GENERATION AUDIT SCRIPT                        ║
    ║                 \(Date())                                        ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)
    
    print("\n🔄 Generating 100 test users...")
    let testUsers = generateTestUsers()
    
    print("📚 Building exercise database...")
    let exerciseDatabase = buildExerciseDatabase()
    print("   Loaded \(exerciseDatabase.count) exercises")
    
    print("\n🏋️ Running simulation for each user...\n")
    
    var allResults: [ProgramAuditResult] = []
    var totalGymUsers = 0
    var totalHomeUsers = 0
    var gymEquipmentScores: [Double] = []
    var homeEquipmentScores: [Double] = []
    var goalScores: [String: [Double]] = [:]
    var allIssues: [String: Int] = [:]
    
    // Day templates for testing
    let dayTemplates: [(name: String, muscles: [String])] = [
        ("Push Day", ["Chest", "Shoulders", "Triceps"]),
        ("Pull Day", ["Back", "Lats", "Biceps"]),
        ("Leg Day", ["Quads", "Hamstrings", "Glutes"]),
        ("Upper Body", ["Chest", "Back", "Shoulders"]),
        ("Full Body", ["Chest", "Back", "Legs", "Core"])
    ]
    
    for user in testUsers {
        var workoutResults: [WorkoutAuditResult] = []
        var previousExercises: Set<String> = []
        var allUserIssues: [String] = []
        
        // Simulate 5 workout days
        for (dayIndex, dayTemplate) in dayTemplates.prefix(5).enumerated() {
            let exercises = selectExercisesForDay(
                targetMuscles: dayTemplate.muscles,
                userProfile: user,
                exerciseDatabase: exerciseDatabase,
                previousExercises: previousExercises,
                count: 5
            )
            
            let workoutResult = gradeWorkout(
                exercises: exercises,
                userProfile: user,
                dayName: dayTemplate.name,
                targetMuscles: dayTemplate.muscles
            )
            
            workoutResults.append(workoutResult)
            allUserIssues.append(contentsOf: workoutResult.issues)
            
            // Track for variety
            for ex in exercises {
                previousExercises.insert(ex.name)
            }
        }
        
        // Calculate user scores
        let avgWorkoutScore = workoutResults.reduce(0) { $0 + $1.totalScore } / Double(workoutResults.count)
        
        // Variety score
        let totalExerciseCount = workoutResults.reduce(0) { $0 + $1.exercises.count }
        let uniqueExerciseNames = Set(workoutResults.flatMap { $0.exercises.map { $0.name } })
        let varietyRatio = Double(uniqueExerciseNames.count) / Double(max(1, totalExerciseCount))
        let varietyScore = min(100, varietyRatio * 120)
        
        // Equipment utilization
        let allEquipment = workoutResults.flatMap { $0.exercises.map { $0.equipment.lowercased() } }
        let bodyweightCount = allEquipment.filter { $0 == "bodyweight" }.count
        let bodyweightRatio = Double(bodyweightCount) / Double(max(1, allEquipment.count))
        
        var equipmentScore: Double = 100
        if user.workoutLocation == "Gym" && bodyweightRatio > 0.5 {
            equipmentScore -= (bodyweightRatio - 0.5) * 60
            allUserIssues.append("High bodyweight ratio (\(Int(bodyweightRatio * 100))%) for gym user")
        }
        
        // Track scores by location
        if user.workoutLocation == "Gym" {
            totalGymUsers += 1
            gymEquipmentScores.append(equipmentScore)
        } else {
            totalHomeUsers += 1
            homeEquipmentScores.append(equipmentScore)
        }
        
        // Track by goal
        goalScores[user.fitnessGoal, default: []].append(avgWorkoutScore)
        
        // Track issues
        for issue in allUserIssues {
            let normalized = normalizeIssue(issue)
            allIssues[normalized, default: 0] += 1
        }
        
        let overallScore = (avgWorkoutScore * 0.5) + (varietyScore * 0.2) + (equipmentScore * 0.3)
        
        let result = ProgramAuditResult(
            userId: user.id,
            userName: user.name,
            userProfile: user,
            programName: "\(user.name)'s Program",
            workoutResults: workoutResults,
            overallScore: overallScore,
            exerciseVarietyScore: varietyScore,
            goalAlignmentScore: avgWorkoutScore,
            equipmentUtilizationScore: equipmentScore,
            issues: allUserIssues
        )
        
        allResults.append(result)
        
        // Progress indicator
        if user.id % 10 == 0 {
            print("   Processed \(user.id)/100 users...")
        }
    }
    
    // Calculate summary stats
    let avgScore = allResults.reduce(0) { $0 + $1.overallScore } / Double(allResults.count)
    let passingCount = allResults.filter { $0.overallScore >= 70 }.count
    let passRate = Double(passingCount) / Double(allResults.count) * 100
    
    let avgGymEquip = gymEquipmentScores.isEmpty ? 0 : gymEquipmentScores.reduce(0, +) / Double(gymEquipmentScores.count)
    let avgHomeEquip = homeEquipmentScores.isEmpty ? 0 : homeEquipmentScores.reduce(0, +) / Double(homeEquipmentScores.count)
    
    let sortedIssues = allIssues.sorted { $0.value > $1.value }
    
    // Print results
    print("""
    
    ┌──────────────────────────────────────────────────────────────────┐
    │ AUDIT SUMMARY                                                    │
    └──────────────────────────────────────────────────────────────────┘
    
    Total Users Tested:     100
    Total Workouts:         500
    
    """)
    
    let scoreEmoji: String
    if avgScore >= 90 { scoreEmoji = "🟢" }
    else if avgScore >= 70 { scoreEmoji = "🟡" }
    else if avgScore >= 50 { scoreEmoji = "🟠" }
    else { scoreEmoji = "🔴" }
    
    print("   \(scoreEmoji) OVERALL SCORE:      \(String(format: "%.1f", avgScore))/100")
    print("   📊 PASS RATE (≥70):   \(String(format: "%.1f", passRate))%")
    
    print("""
    
    ┌──────────────────────────────────────────────────────────────────┐
    │ EQUIPMENT UTILIZATION BY LOCATION                                │
    └──────────────────────────────────────────────────────────────────┘
    
       Gym Users (\(totalGymUsers)):    \(String(format: "%.1f", avgGymEquip))/100
       Home Users (\(totalHomeUsers)):   \(String(format: "%.1f", avgHomeEquip))/100
    
    ┌──────────────────────────────────────────────────────────────────┐
    │ GOAL ALIGNMENT SCORES                                            │
    └──────────────────────────────────────────────────────────────────┘
    
    """)
    
    for (goal, scores) in goalScores.sorted(by: { $0.key < $1.key }) {
        let avg = scores.reduce(0, +) / Double(scores.count)
        print("   \(goal.padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%.1f", avg))/100")
    }
    
    print("""
    
    ┌──────────────────────────────────────────────────────────────────┐
    │ TOP ISSUES FOUND                                                 │
    └──────────────────────────────────────────────────────────────────┘
    
    """)
    
    for (index, issue) in sortedIssues.prefix(10).enumerated() {
        let emoji = index < 2 ? "🔴" : (index < 5 ? "🟡" : "🟢")
        print("   \(emoji) \(String(issue.value).padding(toLength: 4, withPad: " ", startingAt: 0))x - \(issue.key)")
    }
    
    if sortedIssues.isEmpty {
        print("   ✅ No major issues found!")
    }
    
    print("""
    
    ┌──────────────────────────────────────────────────────────────────┐
    │ SCORE DISTRIBUTION                                               │
    └──────────────────────────────────────────────────────────────────┘
    
    """)
    
    let excellent = allResults.filter { $0.overallScore >= 90 }.count
    let good = allResults.filter { $0.overallScore >= 70 && $0.overallScore < 90 }.count
    let fair = allResults.filter { $0.overallScore >= 50 && $0.overallScore < 70 }.count
    let poor = allResults.filter { $0.overallScore < 50 }.count
    
    print("   🟢 Excellent (90-100): \(excellent) users")
    print("   🟡 Good (70-89):       \(good) users")
    print("   🟠 Fair (50-69):       \(fair) users")
    print("   🔴 Poor (<50):         \(poor) users")
    
    print("""
    
    ┌──────────────────────────────────────────────────────────────────┐
    │ SAMPLE RESULTS (Top 5 & Bottom 5)                                │
    └──────────────────────────────────────────────────────────────────┘
    
    TOP 5:
    """)
    
    let sorted = allResults.sorted { $0.overallScore > $1.overallScore }
    for result in sorted.prefix(5) {
        print("   ✅ \(result.userName) - \(String(format: "%.1f", result.overallScore)) (\(result.userProfile.workoutLocation), \(result.userProfile.fitnessGoal))")
    }
    
    print("\n   BOTTOM 5:")
    for result in sorted.suffix(5).reversed() {
        print("   ⚠️ \(result.userName) - \(String(format: "%.1f", result.overallScore)) (\(result.userProfile.workoutLocation), \(result.userProfile.fitnessGoal))")
        if let firstIssue = result.issues.first {
            print("      Issue: \(firstIssue)")
        }
    }
    
    print("""
    
    ═══════════════════════════════════════════════════════════════════
                          END OF AUDIT REPORT
    ═══════════════════════════════════════════════════════════════════
    """)
}

func normalizeIssue(_ issue: String) -> String {
    if issue.contains("bodyweight") && issue.contains("gym") { return "Bodyweight exercises for gym users" }
    if issue.contains("bodyweight ratio") { return "High bodyweight ratio for gym users" }
    if issue.contains("Lying bodyweight") { return "Lying bodyweight exercises for gym users" }
    if issue.contains("No gym equipment") { return "No gym equipment utilized" }
    if issue.contains("plyometric") { return "Too many plyometric exercises" }
    if issue.contains("duplicate") { return "Exercise duplication" }
    if issue.contains("Too few") { return "Insufficient exercises" }
    if issue.contains("Equipment") { return "Equipment mismatch" }
    return issue
}

// MARK: - Execute

runAudit()

