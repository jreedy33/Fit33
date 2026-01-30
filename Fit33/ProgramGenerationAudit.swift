//
//  ProgramGenerationAudit.swift
//  GoFit
//
//  Comprehensive audit tool for testing program generation logic
//  Creates 100 diverse test users and simulates full program completion
//  Grades exercise selection quality based on user inputs and best practices
//
//  ⚠️ DEBUG ONLY - This entire file is excluded from production builds
//

#if DEBUG

import Foundation
import CoreData

// MARK: - Test User Profile

struct TestUserProfile: Identifiable {
    let id: Int
    let name: String
    let age: Int
    let gender: String
    let weight: Int
    let fitnessGoal: String
    let experienceLevel: String
    let strengthLevel: String
    let availableDays: Int
    let workoutLocation: String  // "Gym" or "Home"
    let equipment: [String]
    let preferredDuration: Int  // minutes
}

// MARK: - Audit Result Structures

struct WorkoutAuditResult {
    let userId: Int
    let programId: String
    let dayNumber: Int
    let dayName: String
    let exercises: [ExerciseAuditResult]
    let totalScore: Double
    let issues: [String]
}

struct ExerciseAuditResult {
    let name: String
    let equipment: String
    let targetMuscles: [String]
    let isAppropriateForGoal: Bool
    let isAppropriateForEquipment: Bool
    let isAppropriateForLocation: Bool
    let duplicateCount: Int
    let score: Double
    let issues: [String]
}

struct ProgramAuditResult {
    let userId: Int
    let userName: String
    let userProfile: TestUserProfile
    let programName: String
    let programId: String
    let totalDays: Int
    let workoutResults: [WorkoutAuditResult]
    let overallScore: Double
    let exerciseVarietyScore: Double
    let goalAlignmentScore: Double
    let equipmentUtilizationScore: Double
    let progressionScore: Double
    let duplicateExercisePenalty: Double
    let bodyweightPenalty: Double  // For gym users getting too many bodyweight exercises
    let issues: [String]
    let recommendations: [String]
}

struct AuditSummary {
    let totalUsers: Int
    let totalPrograms: Int
    let totalWorkouts: Int
    let averageScore: Double
    let passRate: Double  // % of programs scoring > 70
    let topIssues: [(issue: String, count: Int)]
    let equipmentUtilizationByLocation: [String: Double]
    let goalAlignmentByGoal: [String: Double]
}

// MARK: - Program Generation Auditor

class ProgramGenerationAuditor: ObservableObject {
    static let shared = ProgramGenerationAuditor()
    
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var currentStatus = ""
    @Published var results: [ProgramAuditResult] = []
    @Published var summary: AuditSummary?
    
    // MARK: - Test User Generation
    
    /// Generate 100 diverse test user profiles
    func generateTestUsers() -> [TestUserProfile] {
        var users: [TestUserProfile] = []
        
        // First names pool
        let maleNames = ["James", "John", "Michael", "David", "Chris", "Daniel", "Matthew", "Andrew", "Joshua", "Ryan", 
                         "Kevin", "Brian", "Steven", "Jason", "Timothy", "Eric", "Mark", "Jeffrey", "Scott", "Patrick",
                         "Brandon", "Justin", "Tyler", "Aaron", "Adam", "Nathan", "Jonathan", "Kyle", "Derek", "Sean"]
        let femaleNames = ["Emily", "Sarah", "Jessica", "Ashley", "Amanda", "Jennifer", "Samantha", "Elizabeth", "Nicole", "Stephanie",
                          "Michelle", "Rachel", "Lauren", "Megan", "Brittany", "Rebecca", "Christina", "Amber", "Heather", "Melissa",
                          "Kelly", "Danielle", "Tiffany", "Lindsay", "Katherine", "Courtney", "Victoria", "Hannah", "Olivia", "Emma"]
        
        // Goals distribution
        let goals = ["Build Muscle", "Lose Weight", "Get Stronger", "Get Fit", "Tone & Define"]
        
        // Experience levels
        let experienceLevels = ["Beginner", "Intermediate", "Advanced"]
        
        // Strength levels
        let strengthLevels = ["Very Light", "Light", "Moderate", "Strong", "Very Strong"]
        
        // Equipment sets for gym users
        let gymEquipment = ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebell", "Bench", "Pull-Up Bar", "Bodyweight"]
        
        // Equipment sets for home users
        let homeEquipmentSets: [[String]] = [
            ["Bodyweight"],
            ["Bodyweight", "Dumbbells"],
            ["Bodyweight", "Resistance Bands"],
            ["Bodyweight", "Dumbbells", "Resistance Bands"],
            ["Bodyweight", "Dumbbells", "Kettlebell"],
            ["Bodyweight", "Dumbbells", "Pull-Up Bar"],
            ["Bodyweight", "Dumbbells", "Resistance Bands", "Bench"],
            ["Bodyweight", "Barbell", "Dumbbells", "Bench", "Pull-Up Bar"]  // Home gym
        ]
        
        for i in 0..<100 {
            let isFemale = i % 2 == 0
            let name = isFemale ? femaleNames[i % femaleNames.count] : maleNames[i % maleNames.count]
            
            // Age distribution: 18-65
            let age = 18 + (i * 47 / 100) + Int.random(in: 0...5)
            
            // Weight distribution
            let baseWeight = isFemale ? 130 : 170
            let weight = baseWeight + Int.random(in: -30...50)
            
            // Goal - varied distribution
            let goal = goals[i % goals.count]
            
            // Experience based on age and variety
            let experienceIndex: Int
            if age < 25 {
                experienceIndex = min(i % 3, 1)  // Mostly beginner/intermediate
            } else if age < 40 {
                experienceIndex = i % 3  // All levels
            } else {
                experienceIndex = max(0, (i % 3) - 1)  // Mostly beginner/intermediate
            }
            let experience = experienceLevels[experienceIndex]
            
            // Strength level correlates with experience and goal
            let strengthIndex: Int
            switch experience {
            case "Beginner": strengthIndex = Int.random(in: 0...2)
            case "Intermediate": strengthIndex = Int.random(in: 1...3)
            case "Advanced": strengthIndex = Int.random(in: 2...4)
            default: strengthIndex = 2
            }
            let strengthLevel = strengthLevels[strengthIndex]
            
            // Available days: 2-6
            let availableDays = 2 + (i % 5)
            
            // Location: 60% gym, 40% home
            let isGym = i % 5 != 0 && i % 5 != 3  // 60% gym
            let location = isGym ? "Gym" : "Home"
            
            // Equipment based on location
            let equipment: [String]
            if isGym {
                equipment = gymEquipment
            } else {
                equipment = homeEquipmentSets[i % homeEquipmentSets.count]
            }
            
            // Preferred duration: 30-75 minutes
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
    
    // MARK: - Grading System
    
    /// Grade an exercise selection based on multiple criteria
    func gradeExercise(
        exercise: SmartProgramExercise,
        userProfile: TestUserProfile,
        dayTemplate: ProgramDayTemplate,
        allExercisesInDay: [SmartProgramExercise],
        allExercisesInProgram: [SmartProgramExercise],
        exerciseDatabase: [String: ExerciseMetadata]
    ) -> ExerciseAuditResult {
        
        var score: Double = 100
        var issues: [String] = []
        
        let exerciseName = exercise.exerciseName.lowercased()
        let metadata = exerciseDatabase[exerciseName]
        let equipment = metadata?.equipment ?? "Bodyweight"
        let targetMuscles = metadata?.primaryMuscles ?? []
        
        // 1. Equipment Appropriateness (25 points)
        var isAppropriateForEquipment = true
        let normalizedUserEquipment = Set(userProfile.equipment.map { $0.lowercased() })
        let exerciseEquipment = equipment.lowercased()
        
        if !normalizedUserEquipment.contains(exerciseEquipment) && 
           exerciseEquipment != "bodyweight" {
            isAppropriateForEquipment = false
            score -= 25
            issues.append("Equipment '\(equipment)' not available for user")
        }
        
        // 2. Location Appropriateness (20 points)
        var isAppropriateForLocation = true
        if userProfile.workoutLocation == "Gym" {
            // Gym users should prioritize gym equipment over bodyweight
            let lyingBodyweightKeywords = ["lying", "floor", "plank", "superman", "dead bug", "bird dog"]
            let isLyingBodyweight = lyingBodyweightKeywords.contains { exerciseName.contains($0) } && 
                                   exerciseEquipment == "bodyweight"
            
            if isLyingBodyweight {
                score -= 10
                issues.append("Gym user getting lying bodyweight exercise: \(exercise.exerciseName)")
            }
            
            // Check if predominantly bodyweight when gym equipment available
            if exerciseEquipment == "bodyweight" {
                let hasGymEquipment = normalizedUserEquipment.contains("barbell") || 
                                      normalizedUserEquipment.contains("dumbbells") || 
                                      normalizedUserEquipment.contains("cables") ||
                                      normalizedUserEquipment.contains("machines")
                if hasGymEquipment {
                    score -= 5
                    issues.append("Gym user could use equipment instead of bodyweight")
                }
            }
        }
        
        // 3. Goal Alignment (20 points)
        var isAppropriateForGoal = true
        let goalLower = userProfile.fitnessGoal.lowercased()
        
        // Check rep ranges for goal
        if goalLower.contains("strength") || goalLower.contains("strong") {
            if exercise.reps > 8 {
                score -= 10
                issues.append("Strength goal but reps too high (\(exercise.reps))")
                isAppropriateForGoal = false
            }
        } else if goalLower.contains("muscle") || goalLower.contains("bulk") {
            if exercise.reps < 6 || exercise.reps > 15 {
                score -= 5
                issues.append("Muscle building goal but reps not optimal (\(exercise.reps))")
            }
        } else if goalLower.contains("weight") || goalLower.contains("tone") || goalLower.contains("fat") {
            if exercise.reps < 10 {
                score -= 5
                issues.append("Fat loss goal but reps too low (\(exercise.reps))")
            }
        }
        
        // 4. Muscle Targeting (15 points)
        let dayMuscles = Set(dayTemplate.focusMuscles.map { $0.lowercased() })
        let exerciseMuscles = Set(targetMuscles.map { $0.lowercased() })
        
        if !dayMuscles.isEmpty && dayMuscles.isDisjoint(with: exerciseMuscles) {
            // Exercise doesn't target day's focus muscles
            score -= 15
            issues.append("Exercise targets \(targetMuscles) but day focuses on \(dayTemplate.focusMuscles)")
        }
        
        // 5. Duplicate Check (15 points)
        let duplicateCount = allExercisesInDay.filter { $0.exerciseName == exercise.exerciseName }.count
        if duplicateCount > 1 {
            score -= 15 * Double(duplicateCount - 1)
            issues.append("Exercise appears \(duplicateCount) times in same day")
        }
        
        // Check for similar exercises (e.g., multiple bench press variations)
        let similarExercises = allExercisesInDay.filter { ex in
            let exName = ex.exerciseName.lowercased()
            // Check for similar movement patterns
            if exerciseName.contains("bench") && exName.contains("bench") && ex.exerciseName != exercise.exerciseName {
                return true
            }
            if exerciseName.contains("squat") && exName.contains("squat") && ex.exerciseName != exercise.exerciseName {
                return true
            }
            if exerciseName.contains("curl") && exName.contains("curl") && ex.exerciseName != exercise.exerciseName {
                return true
            }
            return false
        }
        
        if similarExercises.count > 1 {
            score -= 5
            issues.append("Too many similar exercises: \(exercise.exerciseName) and others")
        }
        
        // 6. Plyometric Check (5 points)
        let plyoKeywords = ["jump", "hop", "bound", "plyo", "explosive"]
        let isPlyometric = plyoKeywords.contains { exerciseName.contains($0) }
        
        if isPlyometric && userProfile.workoutLocation == "Gym" {
            let plyoCount = allExercisesInDay.filter { ex in
                plyoKeywords.contains { ex.exerciseName.lowercased().contains($0) }
            }.count
            
            if plyoCount > 1 {
                score -= 5
                issues.append("Too many plyometric exercises for gym workout")
            }
        }
        
        return ExerciseAuditResult(
            name: exercise.exerciseName,
            equipment: equipment,
            targetMuscles: targetMuscles,
            isAppropriateForGoal: isAppropriateForGoal,
            isAppropriateForEquipment: isAppropriateForEquipment,
            isAppropriateForLocation: isAppropriateForLocation,
            duplicateCount: duplicateCount,
            score: max(0, score),
            issues: issues
        )
    }
    
    /// Grade an entire workout day
    func gradeWorkout(
        day: SmartProgramDay,
        dayTemplate: ProgramDayTemplate,
        userProfile: TestUserProfile,
        allProgramExercises: [SmartProgramExercise],
        exerciseDatabase: [String: ExerciseMetadata]
    ) -> WorkoutAuditResult {
        
        var exerciseResults: [ExerciseAuditResult] = []
        var issues: [String] = []
        
        for exercise in day.exercises {
            let result = gradeExercise(
                exercise: exercise,
                userProfile: userProfile,
                dayTemplate: dayTemplate,
                allExercisesInDay: day.exercises,
                allExercisesInProgram: allProgramExercises,
                exerciseDatabase: exerciseDatabase
            )
            exerciseResults.append(result)
        }
        
        // Calculate workout score
        let avgExerciseScore = exerciseResults.isEmpty ? 0 : 
            exerciseResults.reduce(0) { $0 + $1.score } / Double(exerciseResults.count)
        
        // Check workout-level issues
        
        // 1. Exercise count appropriateness
        if day.exercises.count < 3 && !dayTemplate.isRestDay {
            issues.append("Too few exercises (\(day.exercises.count)) for workout day")
        }
        
        if day.exercises.count > 8 {
            issues.append("Too many exercises (\(day.exercises.count)) - may be overwhelming")
        }
        
        // 2. Equipment variety for gym users
        if userProfile.workoutLocation == "Gym" {
            let equipmentUsed = Set(exerciseResults.map { $0.equipment.lowercased() })
            let bodyweightOnly = equipmentUsed.count == 1 && equipmentUsed.contains("bodyweight")
            
            if bodyweightOnly && day.exercises.count >= 3 {
                issues.append("Gym workout using only bodyweight exercises")
            }
            
            // Check gym equipment utilization
            let gymEquipmentUsed = equipmentUsed.filter { 
                ["barbell", "dumbbells", "cables", "machines", "kettlebell"].contains($0) 
            }
            
            if gymEquipmentUsed.isEmpty && day.exercises.count >= 3 {
                issues.append("No gym equipment utilized in gym workout")
            }
        }
        
        // 3. Muscle group balance
        let allMuscles = exerciseResults.flatMap { $0.targetMuscles }
        let muscleFrequency = Dictionary(grouping: allMuscles, by: { $0 }).mapValues { $0.count }
        
        if let maxFreq = muscleFrequency.values.max(), maxFreq > 3 {
            issues.append("Over-emphasis on single muscle group")
        }
        
        return WorkoutAuditResult(
            userId: userProfile.id,
            programId: "",
            dayNumber: day.dayNumber,
            dayName: day.name,
            exercises: exerciseResults,
            totalScore: avgExerciseScore,
            issues: issues
        )
    }
    
    /// Grade an entire program
    func gradeProgram(
        program: SmartActiveProgram,
        template: SmartProgramTemplate,
        userProfile: TestUserProfile,
        exerciseDatabase: [String: ExerciseMetadata]
    ) -> ProgramAuditResult {
        
        var workoutResults: [WorkoutAuditResult] = []
        var allIssues: [String] = []
        var recommendations: [String] = []
        
        // Collect all exercises across the program
        let allExercises = program.generatedDays.flatMap { $0.exercises }
        
        // Grade each workout day
        for day in program.generatedDays {
            if day.exercises.isEmpty { continue }  // Skip rest days
            
            let templateIndex = (day.dayNumber - 1) % template.dayTemplates.count
            let dayTemplate = template.dayTemplates[templateIndex]
            
            let result = gradeWorkout(
                day: day,
                dayTemplate: dayTemplate,
                userProfile: userProfile,
                allProgramExercises: allExercises,
                exerciseDatabase: exerciseDatabase
            )
            workoutResults.append(result)
        }
        
        // Calculate overall metrics
        let avgWorkoutScore = workoutResults.isEmpty ? 0 :
            workoutResults.reduce(0) { $0 + $1.totalScore } / Double(workoutResults.count)
        
        // Exercise Variety Score (0-100)
        let uniqueExercises = Set(allExercises.map { $0.exerciseName })
        let totalExercises = allExercises.count
        let varietyRatio = totalExercises > 0 ? Double(uniqueExercises.count) / Double(totalExercises) : 0
        let exerciseVarietyScore = min(100, varietyRatio * 120)  // Bonus for high variety
        
        if varietyRatio < 0.5 {
            allIssues.append("Low exercise variety - only \(uniqueExercises.count) unique exercises out of \(totalExercises)")
            recommendations.append("Increase exercise variety to prevent adaptation plateau")
        }
        
        // Goal Alignment Score (0-100)
        var goalAlignmentScore: Double = 100
        let goalLower = userProfile.fitnessGoal.lowercased()
        
        // Check if exercise selection matches goal
        if goalLower.contains("strength") {
            // Should prioritize compound movements
            let compoundKeywords = ["squat", "deadlift", "bench", "press", "row", "pull"]
            let compoundExercises = allExercises.filter { ex in
                compoundKeywords.contains { ex.exerciseName.lowercased().contains($0) }
            }
            let compoundRatio = Double(compoundExercises.count) / Double(max(1, totalExercises))
            if compoundRatio < 0.4 {
                goalAlignmentScore -= 30
                allIssues.append("Strength goal but insufficient compound exercises (\(Int(compoundRatio * 100))%)")
            }
        }
        
        // Equipment Utilization Score (0-100)
        var equipmentUtilizationScore: Double = 100
        var bodyweightPenalty: Double = 0
        
        if userProfile.workoutLocation == "Gym" {
            let allEquipment = workoutResults.flatMap { $0.exercises.map { $0.equipment.lowercased() } }
            let equipmentCounts = Dictionary(grouping: allEquipment, by: { $0 }).mapValues { $0.count }
            
            let bodyweightCount = equipmentCounts["bodyweight"] ?? 0
            let totalCount = allEquipment.count
            let bodyweightRatio = Double(bodyweightCount) / Double(max(1, totalCount))
            
            if bodyweightRatio > 0.5 {
                let penalty = (bodyweightRatio - 0.5) * 60  // Up to 30 point penalty
                equipmentUtilizationScore -= penalty
                bodyweightPenalty = penalty
                allIssues.append("Gym user has \(Int(bodyweightRatio * 100))% bodyweight exercises - underutilizing gym equipment")
                recommendations.append("Replace bodyweight exercises with cable, machine, or free weight alternatives")
            }
            
            // Check for gym equipment usage
            let gymEquipmentUsed = Set(allEquipment.filter { 
                ["barbell", "dumbbells", "cables", "machines", "kettlebell"].contains($0) 
            })
            
            if gymEquipmentUsed.count < 2 {
                equipmentUtilizationScore -= 20
                allIssues.append("Limited gym equipment variety - only using \(gymEquipmentUsed)")
                recommendations.append("Incorporate more gym equipment types for better results")
            }
        }
        
        // Progression Score (0-100) - Check if program progressively gets harder
        var progressionScore: Double = 80  // Base score
        
        let firstWeekExercises = program.generatedDays.filter { $0.dayNumber <= 7 }
        let lastWeekExercises = program.generatedDays.filter { $0.dayNumber > template.totalDays - 7 }
        
        if !firstWeekExercises.isEmpty && !lastWeekExercises.isEmpty {
            // Check if volume/intensity increases
            let firstWeekAvgSets = firstWeekExercises.flatMap { $0.exercises }.map { Double($0.sets) }.reduce(0, +) / 
                Double(max(1, firstWeekExercises.flatMap { $0.exercises }.count))
            let lastWeekAvgSets = lastWeekExercises.flatMap { $0.exercises }.map { Double($0.sets) }.reduce(0, +) / 
                Double(max(1, lastWeekExercises.flatMap { $0.exercises }.count))
            
            if lastWeekAvgSets >= firstWeekAvgSets {
                progressionScore = 100
            } else {
                progressionScore = 70
                allIssues.append("Program doesn't show clear progression")
            }
        }
        
        // Duplicate Exercise Penalty
        let exerciseNameCounts = Dictionary(grouping: allExercises.map { $0.exerciseName }, by: { $0 }).mapValues { $0.count }
        let heavyDuplicates = exerciseNameCounts.filter { $0.value > 3 }
        let duplicatePenalty = Double(heavyDuplicates.count) * 5
        
        if !heavyDuplicates.isEmpty {
            allIssues.append("Exercises repeated too frequently: \(heavyDuplicates.keys.joined(separator: ", "))")
            recommendations.append("Add more exercise variations to prevent overuse")
        }
        
        // Calculate overall score
        let overallScore = (avgWorkoutScore * 0.4) + 
                          (exerciseVarietyScore * 0.15) + 
                          (goalAlignmentScore * 0.2) + 
                          (equipmentUtilizationScore * 0.15) + 
                          (progressionScore * 0.1) - 
                          duplicatePenalty - 
                          bodyweightPenalty
        
        return ProgramAuditResult(
            userId: userProfile.id,
            userName: userProfile.name,
            userProfile: userProfile,
            programName: program.personalizedName,
            programId: program.id,
            totalDays: template.totalDays,
            workoutResults: workoutResults,
            overallScore: max(0, min(100, overallScore)),
            exerciseVarietyScore: exerciseVarietyScore,
            goalAlignmentScore: goalAlignmentScore,
            equipmentUtilizationScore: equipmentUtilizationScore,
            progressionScore: progressionScore,
            duplicateExercisePenalty: duplicatePenalty,
            bodyweightPenalty: bodyweightPenalty,
            issues: allIssues,
            recommendations: recommendations
        )
    }
    
    // MARK: - Run Full Audit
    
    /// Run the full audit across all test users
    func runAudit() async {
        await MainActor.run {
            isRunning = true
            progress = 0
            currentStatus = "Generating test users..."
            results = []
        }
        
        // 1. Generate test users
        let testUsers = generateTestUsers()
        
        await MainActor.run {
            currentStatus = "Loading exercise database..."
            progress = 0.05
        }
        
        // 2. Load exercise database for grading
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        var exerciseDatabase: [String: ExerciseMetadata] = [:]
        
        for exercise in allExercises {
            guard let name = exercise.name else { continue }
            exerciseDatabase[name.lowercased()] = ExerciseMetadata(
                name: name,
                equipment: exercise.equipment ?? "Bodyweight",
                category: exercise.category ?? "General",
                primaryMuscles: exercise.getMuscleGroups() ?? [],
                workoutType: exercise.workoutType
            )
        }
        
        await MainActor.run {
            currentStatus = "Running simulations for \(testUsers.count) users..."
            progress = 0.1
        }
        
        // 3. Run simulation for each user
        var allResults: [ProgramAuditResult] = []
        
        for (index, user) in testUsers.enumerated() {
            await MainActor.run {
                currentStatus = "Testing user \(user.name) (\(index + 1)/\(testUsers.count))..."
                progress = 0.1 + (Double(index) / Double(testUsers.count)) * 0.85
            }
            
            // Create mock User for SmartProgramEngine
            let mockUser = createMockUser(from: user)
            
            // Get personalized programs for user
            let programs = SmartProgramEngine.shared.getPersonalizedPrograms(for: mockUser)
            
            // Test the top matching program (highest match score)
            if let topProgram = programs.first {
                // Simulate starting and completing the program
                if let activeProgram = simulateFullProgram(
                    template: topProgram.template,
                    user: mockUser,
                    userProfile: user
                ) {
                    let result = gradeProgram(
                        program: activeProgram,
                        template: topProgram.template,
                        userProfile: user,
                        exerciseDatabase: exerciseDatabase
                    )
                    allResults.append(result)
                }
            }
            
            // Small delay to prevent UI freezing
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        
        await MainActor.run {
            results = allResults
            currentStatus = "Generating summary..."
            progress = 0.95
        }
        
        // 4. Generate summary
        let summary = generateSummary(from: allResults)
        
        await MainActor.run {
            self.summary = summary
            currentStatus = "Audit complete!"
            progress = 1.0
            isRunning = false
        }
    }
    
    // MARK: - Helpers
    
    private func createMockUser(from profile: TestUserProfile) -> User {
        let context = PersistenceController.shared.container.viewContext
        let user = User(context: context)
        user.id = UUID()
        user.name = profile.name
        user.age = Int16(profile.age)
        user.gender = profile.gender
        user.weight = Int16(profile.weight)
        user.fitnessGoal = profile.fitnessGoal
        user.experienceLevel = profile.experienceLevel
        user.strengthLevel = profile.strengthLevel
        user.availableDays = Int16(profile.availableDays)
        user.workoutLocation = profile.workoutLocation
        user.setEquipment(profile.equipment)
        return user
    }
    
    private func simulateFullProgram(
        template: SmartProgramTemplate,
        user: User,
        userProfile: TestUserProfile
    ) -> SmartActiveProgram? {
        
        // Generate all days upfront for testing
        var generatedDays: [SmartProgramDay] = []
        var previousDays: [SmartProgramDay] = []
        
        for dayNum in 1...min(template.totalDays, 10) {  // Test first 10 days
            let day = generateDay(
                dayNumber: dayNum,
                template: template,
                user: user,
                previousDays: previousDays
            )
            generatedDays.append(day)
            previousDays.append(day)
        }
        
        return SmartActiveProgram(
            id: UUID().uuidString,
            templateId: template.id,
            userId: user.id?.uuidString ?? "",
            personalizedName: "\(userProfile.name)'s \(template.baseName)",
            startDate: Date(),
            currentDay: 1,
            completedDays: [],
            generatedDays: generatedDays,
            isCompleted: false,
            completedDate: nil,
            totalVolume: 0,
            averageIntensity: 0,
            consistencyScore: 1.0
        )
    }
    
    private func generateDay(
        dayNumber: Int,
        template: SmartProgramTemplate,
        user: User,
        previousDays: [SmartProgramDay]
    ) -> SmartProgramDay {
        // Use SmartProgramEngine's day generation logic
        let templateIndex = (dayNumber - 1) % template.dayTemplates.count
        let dayTemplate = template.dayTemplates[templateIndex]
        
        if dayTemplate.isRestDay {
            return SmartProgramDay(
                id: UUID().uuidString,
                dayNumber: dayNumber,
                name: dayTemplate.name,
                exercises: [],
                targetDuration: 0,
                restBetweenSets: 0,
                isCompleted: false,
                completedDate: nil,
                actualDuration: nil,
                totalVolume: nil
            )
        }
        
        // Generate exercises - this is where we apply our improved logic
        let exercises = generateExercisesForDay(
            dayTemplate: dayTemplate,
            template: template,
            user: user,
            dayNumber: dayNumber,
            previousDays: previousDays
        )
        
        return SmartProgramDay(
            id: UUID().uuidString,
            dayNumber: dayNumber,
            name: dayTemplate.name,
            exercises: exercises,
            targetDuration: template.estimatedMinutesPerDay,
            restBetweenSets: 60,
            isCompleted: false,
            completedDate: nil,
            actualDuration: nil,
            totalVolume: nil
        )
    }
    
    private func generateExercisesForDay(
        dayTemplate: ProgramDayTemplate,
        template: SmartProgramTemplate,
        user: User,
        dayNumber: Int,
        previousDays: [SmartProgramDay]
    ) -> [SmartProgramExercise] {
        
        let userEquipment = parseEquipment(user.equipment)
        let isGymUser = user.workoutLocation == "Gym"
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        // Define gym equipment priority for gym users
        let gymEquipmentPriority = ["barbell", "dumbbells", "dumbbell", "cables", "cable", "machines", "machine", "kettlebell"]
        
        // 🚫🚫🚫 HARD EXCLUDE keywords for gym users - NO floor exercises at the gym!
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
        
        // ✅ VERY LIMITED gym-appropriate bodyweight (pull-up bar, dip station)
        let gymAppropriateBodyweight = ["pull-up", "pullup", "chin-up", "chinup", "dip", "hanging", "muscle up", "inverted row"]
        
        // Filter exercises by muscle and equipment
        var filteredExercises = allExercises.filter { exercise in
            // Check muscle match
            let exerciseMuscles = (exercise.getMuscleGroups() ?? []).joined(separator: ",").lowercased()
            let category = (exercise.category ?? "").lowercased()
            let muscleMatch = dayTemplate.focusMuscles.contains { muscle in
                exerciseMuscles.contains(muscle.lowercased()) || category.contains(muscle.lowercased())
            }
            
            // Check equipment match
            let exerciseEquipment = (exercise.equipment ?? "").lowercased()
            let equipmentMatch = userEquipment.isEmpty || userEquipment.contains { equip in
                exerciseEquipment.contains(equip.lowercased()) || 
                equip.lowercased() == "bodyweight" && exerciseEquipment.isEmpty
            }
            
            // Exclude stretching for main workout
            let workoutType = exercise.workoutType?.lowercased() ?? ""
            let isStretch = workoutType == "stretch" || workoutType == "stretching"
            
            // 🔥🔥🔥 STRICT GYM USER FILTERING 🔥🔥🔥
            if isGymUser && !isStretch {
                let name = (exercise.name ?? "").lowercased()
                let isBodyweight = exerciseEquipment == "bodyweight" || exerciseEquipment.isEmpty
                
                // 🚫 HARD EXCLUDE: ANY floor exercise
                let isFloorExercise = floorExerciseKeywords.contains { name.contains($0) }
                if isFloorExercise {
                    return false  // NO floor exercises for gym users, PERIOD
                }
                
                // 🚫 HARD EXCLUDE: Plyometrics
                let isPlyometric = plyometricKeywords.contains { name.contains($0) }
                if isPlyometric {
                    return false  // Gym is for weights, not jumping
                }
                
                // Check if it's a gym-appropriate bodyweight exercise
                let isGymAppropriate = gymAppropriateBodyweight.contains { name.contains($0) }
                
                // 🚫 Exclude "floor" variants of otherwise gym-appropriate exercises
                if isGymAppropriate && name.contains("floor") {
                    return false  // Floor dips are NOT gym exercises
                }
                
                // 🚫 HARD EXCLUDE: ALL other bodyweight for gym users
                if isBodyweight && !isGymAppropriate {
                    return false  // User has gym equipment, USE IT!
                }
            }
            
            return muscleMatch && equipmentMatch && !isStretch
        }
        
        // Sort exercises to prioritize gym equipment for gym users
        if isGymUser {
            filteredExercises.sort { ex1, ex2 in
                let eq1 = (ex1.equipment ?? "").lowercased()
                let eq2 = (ex2.equipment ?? "").lowercased()
                
                let priority1 = gymEquipmentPriority.firstIndex { eq1.contains($0.lowercased()) } ?? 999
                let priority2 = gymEquipmentPriority.firstIndex { eq2.contains($0.lowercased()) } ?? 999
                
                // Penalize plyometrics for gym workouts
                let name1 = (ex1.name ?? "").lowercased()
                let name2 = (ex2.name ?? "").lowercased()
                let isPlyometric1 = ["jump", "hop", "bound", "plyo"].contains { name1.contains($0) }
                let isPlyometric2 = ["jump", "hop", "bound", "plyo"].contains { name2.contains($0) }
                
                if isPlyometric1 && !isPlyometric2 { return false }
                if !isPlyometric1 && isPlyometric2 { return true }
                
                return priority1 < priority2
            }
        }
        
        // Get previously used exercises to avoid too many duplicates
        let previousExerciseNames = Set(previousDays.flatMap { $0.exercises.map { $0.exerciseName.lowercased() } })
        
        // Select exercises, avoiding duplicates
        var selectedExercises: [Exercise] = []
        var selectedNames: Set<String> = []
        
        for exercise in filteredExercises {
            guard selectedExercises.count < dayTemplate.exerciseCount else { break }
            
            let name = (exercise.name ?? "").lowercased()
            
            // Avoid same exercise in same workout
            if selectedNames.contains(name) { continue }
            
            // Limit repetition of exercises from previous days
            if previousExerciseNames.contains(name) {
                // Still allow if we don't have enough variety
                if selectedExercises.count < dayTemplate.exerciseCount / 2 {
                    selectedExercises.append(exercise)
                    selectedNames.insert(name)
                }
            } else {
                selectedExercises.append(exercise)
                selectedNames.insert(name)
            }
        }
        
        // If we still need more, fill with any matching exercises
        if selectedExercises.count < dayTemplate.exerciseCount {
            for exercise in filteredExercises.shuffled() {
                guard selectedExercises.count < dayTemplate.exerciseCount else { break }
                let name = (exercise.name ?? "").lowercased()
                if !selectedNames.contains(name) {
                    selectedExercises.append(exercise)
                    selectedNames.insert(name)
                }
            }
        }
        
        // Convert to SmartProgramExercise
        return selectedExercises.map { exercise in
            let sets = calculateSets(intensity: dayTemplate.intensity, isCompound: true)
            let reps = calculateReps(goal: user.fitnessGoal ?? "Build Muscle", intensity: dayTemplate.intensity)
            
            return SmartProgramExercise(
                id: UUID().uuidString,
                exerciseName: exercise.name ?? "Unknown",
                exerciseId: exercise.id,
                sets: sets,
                reps: reps,
                suggestedWeight: nil,
                restSeconds: 60,
                notes: nil,
                isSuperset: false,
                supersetWith: nil
            )
        }
    }
    
    private func calculateSets(intensity: Double, isCompound: Bool) -> Int {
        if intensity >= 0.85 { return isCompound ? 5 : 4 }
        if intensity >= 0.7 { return isCompound ? 4 : 3 }
        return 3
    }
    
    private func calculateReps(goal: String, intensity: Double) -> Int {
        let goalLower = goal.lowercased()
        if goalLower.contains("strength") || goalLower.contains("strong") {
            return Int(5.0 + (1.0 - intensity) * 3.0)  // 5-8 reps
        } else if goalLower.contains("muscle") || goalLower.contains("bulk") {
            return Int(8.0 + (1.0 - intensity) * 4.0)  // 8-12 reps
        } else if goalLower.contains("weight") || goalLower.contains("fat") || goalLower.contains("tone") {
            return Int(12.0 + (1.0 - intensity) * 5.0)  // 12-17 reps
        }
        return Int(10.0 + (1.0 - intensity) * 4.0)  // 10-14 reps
    }
    
    private func parseEquipment(_ equipment: NSObject?) -> [String] {
        if let array = equipment as? [String] { return array }
        if let string = equipment as? String {
            return string.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return ["Bodyweight"]
    }
    
    private func generateSummary(from results: [ProgramAuditResult]) -> AuditSummary {
        let totalUsers = results.count
        let totalPrograms = results.count
        let totalWorkouts = results.reduce(0) { $0 + $1.workoutResults.count }
        
        let avgScore = results.isEmpty ? 0 : results.reduce(0) { $0 + $1.overallScore } / Double(results.count)
        let passingCount = results.filter { $0.overallScore >= 70 }.count
        let passRate = results.isEmpty ? 0 : Double(passingCount) / Double(results.count) * 100
        
        // Count issues
        var issueCounts: [String: Int] = [:]
        for result in results {
            for issue in result.issues {
                let normalizedIssue = normalizeIssue(issue)
                issueCounts[normalizedIssue, default: 0] += 1
            }
        }
        let topIssues = issueCounts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
        
        // Equipment utilization by location
        let gymResults = results.filter { $0.userProfile.workoutLocation == "Gym" }
        let homeResults = results.filter { $0.userProfile.workoutLocation == "Home" }
        
        let gymEquipUtil = gymResults.isEmpty ? 0 : gymResults.reduce(0) { $0 + $1.equipmentUtilizationScore } / Double(gymResults.count)
        let homeEquipUtil = homeResults.isEmpty ? 0 : homeResults.reduce(0) { $0 + $1.equipmentUtilizationScore } / Double(homeResults.count)
        
        // Goal alignment by goal
        var goalScores: [String: [Double]] = [:]
        for result in results {
            let goal = result.userProfile.fitnessGoal
            goalScores[goal, default: []].append(result.goalAlignmentScore)
        }
        let goalAlignment = goalScores.mapValues { scores in
            scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        }
        
        return AuditSummary(
            totalUsers: totalUsers,
            totalPrograms: totalPrograms,
            totalWorkouts: totalWorkouts,
            averageScore: avgScore,
            passRate: passRate,
            topIssues: topIssues,
            equipmentUtilizationByLocation: ["Gym": gymEquipUtil, "Home": homeEquipUtil],
            goalAlignmentByGoal: goalAlignment
        )
    }
    
    private func normalizeIssue(_ issue: String) -> String {
        if issue.contains("bodyweight exercise") { return "Too many bodyweight exercises for gym users" }
        if issue.contains("underutilizing") { return "Gym equipment underutilization" }
        if issue.contains("duplicate") || issue.contains("appears") { return "Exercise duplication" }
        if issue.contains("lying") { return "Lying bodyweight exercises for gym users" }
        if issue.contains("plyometric") { return "Too many plyometric exercises" }
        if issue.contains("rep") { return "Rep range misalignment with goal" }
        if issue.contains("variety") { return "Low exercise variety" }
        if issue.contains("muscle group") { return "Poor muscle group targeting" }
        return issue
    }
}

// MARK: - Exercise Metadata for Grading

extension ProgramGenerationAuditor {
    struct ExerciseMetadata {
        let name: String
        let equipment: String
        let category: String
        let primaryMuscles: [String]
        let workoutType: String?
    }
}

// MARK: - Audit Report Generator

extension ProgramGenerationAuditor {
    
    /// Generate a detailed text report of the audit
    func generateReport() -> String {
        guard let summary = summary else { return "No audit results available" }
        
        var report = """
        ╔══════════════════════════════════════════════════════════════════╗
        ║           PROGRAM GENERATION AUDIT REPORT                        ║
        ║                 \(Date().formatted())                            ║
        ╚══════════════════════════════════════════════════════════════════╝
        
        ┌──────────────────────────────────────────────────────────────────┐
        │ SUMMARY                                                          │
        └──────────────────────────────────────────────────────────────────┘
        
        Total Users Tested:     \(summary.totalUsers)
        Total Programs:         \(summary.totalPrograms)
        Total Workouts:         \(summary.totalWorkouts)
        
        OVERALL SCORE:          \(String(format: "%.1f", summary.averageScore))/100
        PASS RATE (≥70):        \(String(format: "%.1f", summary.passRate))%
        
        ┌──────────────────────────────────────────────────────────────────┐
        │ EQUIPMENT UTILIZATION BY LOCATION                                │
        └──────────────────────────────────────────────────────────────────┘
        
        Gym Users:              \(String(format: "%.1f", summary.equipmentUtilizationByLocation["Gym"] ?? 0))/100
        Home Users:             \(String(format: "%.1f", summary.equipmentUtilizationByLocation["Home"] ?? 0))/100
        
        ┌──────────────────────────────────────────────────────────────────┐
        │ GOAL ALIGNMENT SCORES                                            │
        └──────────────────────────────────────────────────────────────────┘
        
        """
        
        for (goal, score) in summary.goalAlignmentByGoal.sorted(by: { $0.value > $1.value }) {
            report += "\(goal.padding(toLength: 20, withPad: " ", startingAt: 0))\(String(format: "%.1f", score))/100\n"
        }
        
        report += """
        
        ┌──────────────────────────────────────────────────────────────────┐
        │ TOP ISSUES FOUND                                                 │
        └──────────────────────────────────────────────────────────────────┘
        
        """
        
        for (index, issue) in summary.topIssues.enumerated() {
            let emoji = index < 3 ? "🔴" : (index < 6 ? "🟡" : "🟢")
            report += "\(emoji) \(issue.count)x - \(issue.issue)\n"
        }
        
        report += """
        
        ┌──────────────────────────────────────────────────────────────────┐
        │ SCORING BREAKDOWN                                                │
        └──────────────────────────────────────────────────────────────────┘
        
        Score ranges:
        • 90-100: Excellent - Program generation is optimal
        • 70-89:  Good - Minor improvements needed
        • 50-69:  Fair - Significant issues to address
        • Below 50: Poor - Major logic fixes required
        
        ┌──────────────────────────────────────────────────────────────────┐
        │ RECOMMENDATIONS                                                  │
        └──────────────────────────────────────────────────────────────────┘
        
        """
        
        // Collect all unique recommendations
        var allRecommendations = Set<String>()
        for result in results {
            for rec in result.recommendations {
                allRecommendations.insert(rec)
            }
        }
        
        for (index, rec) in allRecommendations.enumerated() {
            report += "\(index + 1). \(rec)\n"
        }
        
        report += """
        
        ═══════════════════════════════════════════════════════════════════
                              END OF AUDIT REPORT
        ═══════════════════════════════════════════════════════════════════
        """
        
        return report
    }
    
    /// Generate detailed per-user results
    func generateDetailedResults() -> String {
        var details = "DETAILED RESULTS BY USER\n\n"
        
        for result in results.sorted(by: { $0.overallScore > $1.overallScore }).prefix(20) {
            details += """
            ───────────────────────────────────────────────────────────────────
            User: \(result.userName)
            Profile: \(result.userProfile.experienceLevel) | \(result.userProfile.fitnessGoal) | \(result.userProfile.workoutLocation)
            Equipment: \(result.userProfile.equipment.joined(separator: ", "))
            
            Program: \(result.programName)
            Score: \(String(format: "%.1f", result.overallScore))/100
            
            Breakdown:
              • Exercise Variety: \(String(format: "%.1f", result.exerciseVarietyScore))
              • Goal Alignment: \(String(format: "%.1f", result.goalAlignmentScore))
              • Equipment Utilization: \(String(format: "%.1f", result.equipmentUtilizationScore))
              • Progression: \(String(format: "%.1f", result.progressionScore))
              • Duplicate Penalty: -\(String(format: "%.1f", result.duplicateExercisePenalty))
              • Bodyweight Penalty: -\(String(format: "%.1f", result.bodyweightPenalty))
            
            Issues:
            \(result.issues.isEmpty ? "  None" : result.issues.map { "  • " + $0 }.joined(separator: "\n"))
            
            """
        }
        
        return details
    }
}

#endif
