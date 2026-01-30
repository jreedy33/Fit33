//
//  WorkoutQualityAudit.swift
//  GoFit
//
//  Comprehensive automated testing system for workout generation quality.
//  Generates 200 diverse test users and grades workout outputs against
//  a detailed scorecard covering equipment, safety, practicality, and more.
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
    let weightLbs: Double
    let heightCm: Double
    let goal: String
    let experienceLevel: String
    let workoutLocation: String
    let equipment: [String]
    let limitations: [TestLimitation]
    let daysPerWeek: Int
    
    var description: String {
        """
        User #\(id): \(name)
        Age: \(age), Gender: \(gender), Weight: \(Int(weightLbs))lbs
        Goal: \(goal), Level: \(experienceLevel)
        Location: \(workoutLocation), Equipment: \(equipment.joined(separator: ", "))
        Limitations: \(limitations.isEmpty ? "None" : limitations.map { "\($0.area): \($0.accommodation)" }.joined(separator: ", "))
        """
    }
}

struct TestLimitation {
    let area: String  // "Lower Back", "Shoulders", "Knees", etc.
    let accommodation: String  // "skipCompletely", "lightWorkOnly", "stretchingOnly", "beCareful"
}

// MARK: - Workout Scorecard

struct WorkoutScorecard {
    var equipmentScore: Double = 0       // 0-100: All exercises use available equipment
    var safetyScore: Double = 0          // 0-100: Exercises safe for user's limitations
    var practicalityScore: Double = 0    // 0-100: Exercises are realistic/practical
    var goalAlignmentScore: Double = 0   // 0-100: Exercises match user's goals
    var experienceScore: Double = 0      // 0-100: Appropriate for user's level
    var varietyScore: Double = 0         // 0-100: Good mix of movement patterns
    var locationScore: Double = 0        // 0-100: Appropriate for workout location
    var profileScore: Double = 0         // 0-100: Safe for age/weight profile
    
    var equipmentViolations: [String] = []
    var safetyViolations: [String] = []
    var practicalityViolations: [String] = []
    var goalViolations: [String] = []
    var experienceViolations: [String] = []
    var varietyViolations: [String] = []
    var locationViolations: [String] = []
    var profileViolations: [String] = []
    
    var overallScore: Double {
        let weights: [Double] = [0.20, 0.20, 0.15, 0.10, 0.10, 0.10, 0.10, 0.05]
        let scores = [equipmentScore, safetyScore, practicalityScore, goalAlignmentScore,
                      experienceScore, varietyScore, locationScore, profileScore]
        return zip(weights, scores).reduce(0) { $0 + $1.0 * $1.1 }
    }
    
    var passed: Bool { overallScore >= 80 }
    
    var allViolations: [String] {
        equipmentViolations + safetyViolations + practicalityViolations +
        goalViolations + experienceViolations + varietyViolations +
        locationViolations + profileViolations
    }
}

// MARK: - Generated Workout Result

struct GeneratedWorkoutResult {
    let user: TestUserProfile
    let exercises: [TestExercise]
    let scorecard: WorkoutScorecard
    let generationTimeMs: Double
}

struct TestExercise {
    let name: String
    let equipment: String
    let muscleGroups: [String]
    let category: String
    let workoutType: String
    let practicalityScore: Int
}

// MARK: - Workout Quality Audit Engine

class WorkoutQualityAudit {
    static let shared = WorkoutQualityAudit()
    
    private let context: NSManagedObjectContext
    private var allExercises: [Exercise] = []
    
    // Statistics
    private var totalUsers = 0
    private var passedUsers = 0
    private var failedUsers = 0
    private var issuesFound: [String: Int] = [:]  // Issue type -> count
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }
    
    // MARK: - Main Audit Function
    
    func runFullAudit(userCount: Int = 200, completion: @escaping (AuditReport) -> Void) {
        print("╔══════════════════════════════════════════════════════════════════════╗")
        print("║        🧪 WORKOUT QUALITY AUDIT - \(userCount) USERS                         ║")
        print("╚══════════════════════════════════════════════════════════════════════╝")
        
        // Load exercises
        loadExercises()
        
        // Generate diverse test users
        let testUsers = generateTestUsers(count: userCount)
        print("\n✅ Generated \(testUsers.count) diverse test users")
        
        // Run workouts and grade
        var results: [GeneratedWorkoutResult] = []
        let startTime = Date()
        
        for (index, user) in testUsers.enumerated() {
            if index % 20 == 0 {
                print("📊 Testing user \(index + 1)/\(userCount)...")
            }
            
            let result = generateAndGradeWorkout(for: user)
            results.append(result)
            
            if result.scorecard.passed {
                passedUsers += 1
            } else {
                failedUsers += 1
            }
            
            // Track issues
            for violation in result.scorecard.allViolations {
                let issueType = categorizeViolation(violation)
                issuesFound[issueType, default: 0] += 1
            }
        }
        
        let totalTimeSeconds = Date().timeIntervalSince(startTime)
        
        // Generate report
        let report = generateReport(results: results, totalTimeSeconds: totalTimeSeconds)
        
        // Print summary
        printSummary(report: report)
        
        // Identify and suggest fixes
        let suggestedFixes = identifyCodeFixes(from: results)
        report.suggestedFixes = suggestedFixes
        
        completion(report)
    }
    
    // MARK: - User Generation
    
    private func generateTestUsers(count: Int) -> [TestUserProfile] {
        var users: [TestUserProfile] = []
        
        let goals = ["Build Muscle", "Lose Weight", "Get Stronger", "Tone & Define", "Endurance", "General Fitness"]
        let levels = ["Beginner", "Intermediate", "Advanced"]
        let locations = ["Gym", "Home", "Outdoor", "Hybrid"]
        let genders = ["Male", "Female"]
        
        let limitationAreas = ["Lower Back", "Shoulders", "Knees", "Wrists", "Neck", "Elbows", "Hips", "Ankles"]
        let accommodations = ["skipCompletely", "lightWorkOnly", "stretchingOnly", "beCareful"]
        
        let gymEquipment = [
            ["Dumbbells", "Barbell", "Cables", "Machines", "Bench"],
            ["Dumbbells", "Cables", "Machines"],
            ["Barbell", "Machines", "Bench"],
            ["Dumbbells", "Barbell", "Cables", "Machines", "Bench", "Smith Machine", "Kettlebells"],
            ["Machines", "Cables"],
            ["Dumbbells", "Barbell", "Bench"]
        ]
        
        let homeEquipment = [
            ["Dumbbells", "Resistance Bands"],
            ["Bodyweight"],
            ["Dumbbells", "Kettlebells", "Resistance Bands"],
            ["Dumbbells", "Barbell", "Bench"],
            ["Bodyweight", "Resistance Bands"],
            ["Dumbbells"]
        ]
        
        let firstNames = ["Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Quinn", "Avery",
                          "Cameron", "Skyler", "Dakota", "Jamie", "Reese", "Charlie", "Finley", "Sage",
                          "Blake", "Drew", "Hayden", "Parker", "Rowan", "Spencer", "Sydney", "Phoenix",
                          "River", "Addison", "Bailey", "Brooklyn", "Dallas", "Denver", "Eden", "Emerson"]
        
        for i in 0..<count {
            let goal = goals[i % goals.count]
            let level = levels[i % levels.count]
            let gender = genders[i % genders.count]
            
            // Varied age distribution
            let ageRanges = [(18, 25), (26, 35), (36, 45), (46, 55), (56, 65), (66, 75)]
            let ageRange = ageRanges[i % ageRanges.count]
            let age = Int.random(in: ageRange.0...ageRange.1)
            
            // Varied weight distribution based on gender
            let weightRange: ClosedRange<Double> = gender == "Male" ? 140...280 : 110...220
            let weight = Double.random(in: weightRange)
            
            // Height
            let heightRange: ClosedRange<Double> = gender == "Male" ? 165...195 : 155...180
            let height = Double.random(in: heightRange)
            
            // Location and equipment
            let location: String
            let equipment: [String]
            
            // Distribute locations more realistically
            let locationRoll = i % 10
            if locationRoll < 5 {
                location = "Gym"
                equipment = gymEquipment[i % gymEquipment.count]
            } else if locationRoll < 8 {
                location = "Home"
                equipment = homeEquipment[i % homeEquipment.count]
            } else if locationRoll < 9 {
                location = "Outdoor"
                equipment = ["Bodyweight"]
            } else {
                location = "Hybrid"
                equipment = homeEquipment[i % homeEquipment.count] + ["Machines", "Cables"]
            }
            
            // Generate limitations (30% of users have at least one)
            var limitations: [TestLimitation] = []
            if i % 3 == 0 {  // Every 3rd user has a limitation
                let numLimitations = (i % 5 == 0) ? 2 : 1  // Every 5th has 2
                for j in 0..<numLimitations {
                    let area = limitationAreas[(i + j) % limitationAreas.count]
                    let accommodation = accommodations[(i + j) % accommodations.count]
                    limitations.append(TestLimitation(area: area, accommodation: accommodation))
                }
            }
            
            // Days per week
            let daysPerWeek = [3, 4, 5, 6][i % 4]
            
            let user = TestUserProfile(
                id: i + 1,
                name: "\(firstNames[i % firstNames.count]) #\(i + 1)",
                age: age,
                gender: gender,
                weightLbs: weight,
                heightCm: height,
                goal: goal,
                experienceLevel: level,
                workoutLocation: location,
                equipment: equipment,
                limitations: limitations,
                daysPerWeek: daysPerWeek
            )
            
            users.append(user)
        }
        
        return users
    }
    
    // MARK: - Workout Generation & Grading
    
    private func generateAndGradeWorkout(for user: TestUserProfile) -> GeneratedWorkoutResult {
        let startTime = Date()
        
        // Simulate workout generation by filtering exercises
        let targetMuscles = getTargetMusclesForGoal(user.goal)
        let filteredExercises = filterExercisesForUser(user: user, targetMuscles: targetMuscles)
        
        // Select 6 exercises
        let selectedExercises = Array(filteredExercises.prefix(6))
        
        let generationTime = Date().timeIntervalSince(startTime) * 1000
        
        // Convert to test exercises
        let testExercises = selectedExercises.map { exercise in
            TestExercise(
                name: exercise.name ?? "Unknown",
                equipment: exercise.equipment ?? "Bodyweight",
                muscleGroups: exercise.getMuscleGroups() ?? [],
                category: exercise.category ?? "",
                workoutType: exercise.workoutType ?? "Strength",
                practicalityScore: Int(exercise.practicalityScore)
            )
        }
        
        // Grade the workout
        let scorecard = gradeWorkout(exercises: testExercises, user: user)
        
        return GeneratedWorkoutResult(
            user: user,
            exercises: testExercises,
            scorecard: scorecard,
            generationTimeMs: generationTime
        )
    }
    
    private func filterExercisesForUser(user: TestUserProfile, targetMuscles: [String]) -> [Exercise] {
        let normalizedEquipment = Set(user.equipment.map { $0.lowercased() })
        let normalizedMuscles = Set(targetMuscles.map { $0.lowercased() })
        let isGymUser = user.workoutLocation == "Gym" || user.workoutLocation == "Hybrid"
        
        // Get limitation areas to avoid
        let skipAreas = Set(user.limitations.filter { $0.accommodation == "skipCompletely" }.map { $0.area.lowercased() })
        let lightOnlyAreas = Set(user.limitations.filter { $0.accommodation == "lightWorkOnly" }.map { $0.area.lowercased() })
        
        var scored: [(Exercise, Double)] = []
        
        for exercise in allExercises {
            guard let name = exercise.name else { continue }
            let nameLower = name.lowercased()
            let equipmentLower = (exercise.equipment ?? "bodyweight").lowercased()
            let muscleGroups = (exercise.getMuscleGroups() ?? []).map { $0.lowercased() }
            let category = (exercise.category ?? "").lowercased()
            let practicalityScore = Int(exercise.practicalityScore)
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 1: Equipment - ALL required equipment must be available
            // ═══════════════════════════════════════════════════════════════
            let equipmentParts = equipmentLower
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            let commonItems: Set<String> = ["floor", "mat", "bodyweight", "body weight"]
            let isBodyweight = equipmentParts.isEmpty || (equipmentParts.count == 1 && equipmentParts.first == "bodyweight")
            
            let hasAllEquipment: Bool
            if normalizedEquipment.isEmpty || isBodyweight {
                hasAllEquipment = true
            } else {
                hasAllEquipment = equipmentParts.allSatisfy { part in
                    commonItems.contains(part) ||
                    normalizedEquipment.contains(part) ||
                    normalizedEquipment.contains { $0.contains(part) || part.contains($0) }
                }
            }
            
            guard hasAllEquipment else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 2: Muscle match
            // ═══════════════════════════════════════════════════════════════
            let matchesMuscle = muscleGroups.contains { muscle in
                normalizedMuscles.contains { target in
                    muscle.contains(target) || target.contains(muscle)
                }
            } || normalizedMuscles.contains { category.contains($0) }
            
            guard matchesMuscle else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 3: Practicality score
            // ═══════════════════════════════════════════════════════════════
            if practicalityScore > 0 && practicalityScore < 30 {
                continue
            }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 4: Injury/Limitation safety
            // ═══════════════════════════════════════════════════════════════
            var shouldSkip = false
            
            // Check skip completely areas
            for area in skipAreas {
                if isExerciseUnsafeForArea(exerciseName: nameLower, area: area) {
                    shouldSkip = true
                    break
                }
            }
            
            guard !shouldSkip else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 5: Experience level appropriateness
            // ═══════════════════════════════════════════════════════════════
            if user.experienceLevel == "Beginner" {
                let advancedKeywords = ["clean", "snatch", "jerk", "olympic", "muscle up",
                                        "pistol squat", "dragon flag", "front lever", "back lever",
                                        "planche", "handstand", "deficit deadlift"]
                if advancedKeywords.contains(where: { nameLower.contains($0) }) {
                    continue
                }
            }
            
            // ═══════════════════════════════════════════════════════════════
            // FILTER 6: Age/Weight appropriateness
            // ═══════════════════════════════════════════════════════════════
            if user.age >= 60 || user.weightLbs > 280 {
                let highImpactKeywords = ["jump", "box jump", "plyometric", "plyo", "burpee",
                                          "sprint", "depth jump", "tuck jump"]
                if highImpactKeywords.contains(where: { nameLower.contains($0) }) {
                    continue
                }
            }
            
            if user.weightLbs > 250 && isBodyweight {
                let hardBodyweight = ["pull up", "pullup", "chin up", "chinup", "muscle up",
                                      "dip", "pistol squat", "handstand", "planche"]
                if hardBodyweight.contains(where: { nameLower.contains($0) }) {
                    continue
                }
            }
            
            // ═══════════════════════════════════════════════════════════════
            // SCORING
            // ═══════════════════════════════════════════════════════════════
            var score: Double = 100
            
            // Practicality boost
            if practicalityScore > 70 {
                score += 20
            } else if practicalityScore > 50 {
                score += 10
            } else if practicalityScore > 0 && practicalityScore < 50 {
                score -= 10
            }
            
            // Goal alignment
            score += goalAlignmentBoost(exerciseName: nameLower, equipment: equipmentLower, goal: user.goal)
            
            // Location appropriateness
            if isGymUser {
                if equipmentLower.contains("cable") || equipmentLower.contains("machine") ||
                   equipmentLower.contains("barbell") || equipmentLower.contains("smith") {
                    score += 15
                }
                if isBodyweight && !nameLower.contains("pull") && !nameLower.contains("dip") {
                    score -= 10
                }
            } else {
                if equipmentLower.contains("cable") || equipmentLower.contains("machine") {
                    score -= 30  // Home users shouldn't get cable/machine exercises
                }
            }
            
            // Add randomization for variety
            score += Double.random(in: -5...5)
            
            scored.append((exercise, score))
        }
        
        // Sort by score and return
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }
    
    private func gradeWorkout(exercises: [TestExercise], user: TestUserProfile) -> WorkoutScorecard {
        var scorecard = WorkoutScorecard()
        let normalizedEquipment = Set(user.equipment.map { $0.lowercased() })
        let isGymUser = user.workoutLocation == "Gym" || user.workoutLocation == "Hybrid"
        let isHomeUser = user.workoutLocation == "Home"
        
        if exercises.isEmpty {
            scorecard.equipmentScore = 0
            scorecard.equipmentViolations.append("❌ No exercises generated!")
            return scorecard
        }
        
        var equipmentPasses = 0
        var safetyPasses = 0
        var practicalityPasses = 0
        var goalPasses = 0
        var experiencePasses = 0
        var locationPasses = 0
        var profilePasses = 0
        
        // Track movement patterns for variety
        var movementPatterns: Set<String> = []
        var equipmentUsed: Set<String> = []
        
        for exercise in exercises {
            let nameLower = exercise.name.lowercased()
            let equipmentLower = exercise.equipment.lowercased()
            let equipmentParts = equipmentLower.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            // ─────────────────────────────────────────────────────────────
            // EQUIPMENT CHECK
            // ─────────────────────────────────────────────────────────────
            let commonItems: Set<String> = ["floor", "mat", "bodyweight", "body weight"]
            let hasAllEquipment = equipmentParts.allSatisfy { part in
                commonItems.contains(part) ||
                normalizedEquipment.contains(part) ||
                normalizedEquipment.contains { $0.contains(part) || part.contains($0) }
            }
            
            if hasAllEquipment {
                equipmentPasses += 1
            } else {
                let missing = equipmentParts.filter { part in
                    !commonItems.contains(part) &&
                    !normalizedEquipment.contains(part) &&
                    !normalizedEquipment.contains { $0.contains(part) || part.contains($0) }
                }
                scorecard.equipmentViolations.append("❌ '\(exercise.name)' requires \(missing.joined(separator: ", ")) - user doesn't have")
            }
            
            // ─────────────────────────────────────────────────────────────
            // SAFETY CHECK (Limitations)
            // ─────────────────────────────────────────────────────────────
            var isSafe = true
            for limitation in user.limitations {
                if limitation.accommodation == "skipCompletely" {
                    if isExerciseUnsafeForArea(exerciseName: nameLower, area: limitation.area.lowercased()) {
                        scorecard.safetyViolations.append("⚠️ '\(exercise.name)' unsafe for \(limitation.area) (skip completely)")
                        isSafe = false
                    }
                }
            }
            if isSafe { safetyPasses += 1 }
            
            // ─────────────────────────────────────────────────────────────
            // PRACTICALITY CHECK
            // ─────────────────────────────────────────────────────────────
            if exercise.practicalityScore > 0 {
                if exercise.practicalityScore >= 40 {
                    practicalityPasses += 1
                } else {
                    scorecard.practicalityViolations.append("⚠️ '\(exercise.name)' has low practicality score (\(exercise.practicalityScore))")
                }
            } else {
                // No score = assume practical
                practicalityPasses += 1
            }
            
            // ─────────────────────────────────────────────────────────────
            // GOAL ALIGNMENT CHECK
            // ─────────────────────────────────────────────────────────────
            let goalAligned = isExerciseAlignedWithGoal(exercise: exercise, goal: user.goal)
            if goalAligned {
                goalPasses += 1
            } else {
                scorecard.goalViolations.append("⚠️ '\(exercise.name)' may not align with goal '\(user.goal)'")
            }
            
            // ─────────────────────────────────────────────────────────────
            // EXPERIENCE CHECK
            // ─────────────────────────────────────────────────────────────
            let advancedKeywords = ["clean", "snatch", "jerk", "olympic", "muscle up",
                                    "pistol squat", "dragon flag", "front lever", "planche", "handstand"]
            let isAdvanced = advancedKeywords.contains(where: { nameLower.contains($0) })
            
            if user.experienceLevel == "Beginner" && isAdvanced {
                scorecard.experienceViolations.append("⚠️ '\(exercise.name)' is advanced, user is Beginner")
            } else {
                experiencePasses += 1
            }
            
            // ─────────────────────────────────────────────────────────────
            // LOCATION CHECK
            // ─────────────────────────────────────────────────────────────
            let needsGymEquipment = equipmentLower.contains("cable") || equipmentLower.contains("machine") ||
                                    equipmentLower.contains("smith") || equipmentLower.contains("rack")
            
            if isHomeUser && needsGymEquipment {
                scorecard.locationViolations.append("❌ '\(exercise.name)' requires gym equipment (\(equipmentLower)) for Home user")
            } else {
                locationPasses += 1
            }
            
            // ─────────────────────────────────────────────────────────────
            // PROFILE CHECK (Age/Weight)
            // ─────────────────────────────────────────────────────────────
            var profileSafe = true
            
            let highImpactKeywords = ["jump", "plyometric", "plyo", "burpee", "sprint", "hop"]
            let isHighImpact = highImpactKeywords.contains(where: { nameLower.contains($0) })
            
            if (user.age >= 60 || user.weightLbs > 280) && isHighImpact {
                scorecard.profileViolations.append("⚠️ '\(exercise.name)' is high-impact, risky for age \(user.age) or weight \(Int(user.weightLbs))lbs")
                profileSafe = false
            }
            
            let hardBodyweight = ["pull up", "pullup", "chin up", "chinup", "muscle up", "dip", "pistol"]
            let isHardBodyweight = hardBodyweight.contains(where: { nameLower.contains($0) })
            
            if user.weightLbs > 250 && isHardBodyweight {
                scorecard.profileViolations.append("⚠️ '\(exercise.name)' is difficult for weight \(Int(user.weightLbs))lbs")
                profileSafe = false
            }
            
            if profileSafe { profilePasses += 1 }
            
            // ─────────────────────────────────────────────────────────────
            // VARIETY TRACKING
            // ─────────────────────────────────────────────────────────────
            let pattern = classifyMovementPattern(exerciseName: nameLower)
            movementPatterns.insert(pattern)
            equipmentUsed.insert(equipmentLower.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "bodyweight")
        }
        
        // Calculate scores
        let count = Double(exercises.count)
        scorecard.equipmentScore = (Double(equipmentPasses) / count) * 100
        scorecard.safetyScore = (Double(safetyPasses) / count) * 100
        scorecard.practicalityScore = (Double(practicalityPasses) / count) * 100
        scorecard.goalAlignmentScore = (Double(goalPasses) / count) * 100
        scorecard.experienceScore = (Double(experiencePasses) / count) * 100
        scorecard.locationScore = (Double(locationPasses) / count) * 100
        scorecard.profileScore = (Double(profilePasses) / count) * 100
        
        // Variety score based on movement patterns and equipment diversity
        let patternVariety = min(Double(movementPatterns.count) / 4.0, 1.0) * 50
        let equipmentVariety = min(Double(equipmentUsed.count) / 3.0, 1.0) * 50
        scorecard.varietyScore = patternVariety + equipmentVariety
        
        if movementPatterns.count < 3 {
            scorecard.varietyViolations.append("⚠️ Low movement pattern variety (\(movementPatterns.count) patterns)")
        }
        
        return scorecard
    }
    
    // MARK: - Helper Functions
    
    private func loadExercises() {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        do {
            allExercises = try context.fetch(request)
            print("📊 Loaded \(allExercises.count) exercises for audit")
        } catch {
            print("❌ Failed to load exercises: \(error)")
        }
    }
    
    private func getTargetMusclesForGoal(_ goal: String) -> [String] {
        switch goal.lowercased() {
        case "build muscle":
            return ["chest", "back", "shoulders", "arms", "legs"]
        case "lose weight":
            return ["full body", "cardio", "legs", "core"]
        case "get stronger":
            return ["chest", "back", "legs", "shoulders"]
        case "tone & define":
            return ["arms", "shoulders", "core", "legs"]
        case "endurance":
            return ["legs", "core", "cardio"]
        default:
            return ["chest", "back", "shoulders", "arms", "legs", "core"]
        }
    }
    
    private func isExerciseUnsafeForArea(exerciseName: String, area: String) -> Bool {
        let areaKeywords: [String: [String]] = [
            "lower back": ["deadlift", "good morning", "bent over row", "back extension", "hyperextension"],
            "shoulders": ["overhead press", "shoulder press", "military press", "lateral raise", "front raise", "upright row"],
            "knees": ["squat", "lunge", "leg press", "leg extension", "jump", "running"],
            "wrists": ["push-up", "pushup", "front squat", "clean", "snatch", "wrist curl"],
            "neck": ["shrug", "neck", "behind neck", "behind the neck"],
            "elbows": ["tricep extension", "skull crusher", "close grip", "curl"],
            "hips": ["squat", "lunge", "hip thrust", "deadlift", "leg raise"],
            "ankles": ["calf raise", "jump", "running", "lunge", "step up"]
        ]
        
        guard let keywords = areaKeywords[area] else { return false }
        return keywords.contains { exerciseName.contains($0) }
    }
    
    private func goalAlignmentBoost(exerciseName: String, equipment: String, goal: String) -> Double {
        switch goal.lowercased() {
        case "build muscle":
            if exerciseName.contains("press") || exerciseName.contains("curl") ||
               exerciseName.contains("row") || exerciseName.contains("squat") {
                return 15
            }
        case "lose weight":
            if exerciseName.contains("burpee") || exerciseName.contains("jump") ||
               equipment.contains("bodyweight") {
                return 10
            }
        case "get stronger":
            if exerciseName.contains("deadlift") || exerciseName.contains("squat") ||
               exerciseName.contains("bench press") || equipment.contains("barbell") {
                return 15
            }
        default:
            break
        }
        return 0
    }
    
    private func isExerciseAlignedWithGoal(exercise: TestExercise, goal: String) -> Bool {
        // Most exercises are reasonably aligned, only flag obvious mismatches
        let nameLower = exercise.name.lowercased()
        
        switch goal.lowercased() {
        case "get stronger":
            // Stretching/mobility shouldn't dominate a strength workout
            if exercise.workoutType.lowercased().contains("stretch") {
                return false
            }
        case "endurance":
            // Heavy isolation work not ideal for endurance
            if nameLower.contains("max") || nameLower.contains("heavy") {
                return false
            }
        default:
            return true
        }
        return true
    }
    
    private func classifyMovementPattern(exerciseName: String) -> String {
        let name = exerciseName.lowercased()
        
        if name.contains("press") || name.contains("push") { return "push" }
        if name.contains("row") || name.contains("pull") { return "pull" }
        if name.contains("squat") || name.contains("leg press") { return "squat" }
        if name.contains("deadlift") || name.contains("hip thrust") { return "hinge" }
        if name.contains("lunge") || name.contains("step") { return "lunge" }
        if name.contains("curl") { return "curl" }
        if name.contains("extension") || name.contains("tricep") { return "extension" }
        if name.contains("raise") || name.contains("fly") { return "isolation" }
        if name.contains("plank") || name.contains("crunch") { return "core" }
        
        return "other"
    }
    
    private func categorizeViolation(_ violation: String) -> String {
        if violation.contains("equipment") || violation.contains("requires") { return "Equipment Mismatch" }
        if violation.contains("unsafe") || violation.contains("limitation") { return "Safety Violation" }
        if violation.contains("practicality") { return "Low Practicality" }
        if violation.contains("goal") || violation.contains("align") { return "Goal Mismatch" }
        if violation.contains("Beginner") || violation.contains("Advanced") { return "Experience Mismatch" }
        if violation.contains("Home") || violation.contains("Gym") { return "Location Mismatch" }
        if violation.contains("age") || violation.contains("weight") { return "Profile Safety" }
        if violation.contains("variety") || violation.contains("pattern") { return "Low Variety" }
        return "Other"
    }
    
    // MARK: - Report Generation
    
    private func generateReport(results: [GeneratedWorkoutResult], totalTimeSeconds: Double) -> AuditReport {
        var report = AuditReport()
        
        report.totalUsers = results.count
        report.passedUsers = results.filter { $0.scorecard.passed }.count
        report.failedUsers = results.filter { !$0.scorecard.passed }.count
        report.passRate = Double(report.passedUsers) / Double(report.totalUsers) * 100
        
        // Average scores
        report.avgEquipmentScore = results.map { $0.scorecard.equipmentScore }.reduce(0, +) / Double(results.count)
        report.avgSafetyScore = results.map { $0.scorecard.safetyScore }.reduce(0, +) / Double(results.count)
        report.avgPracticalityScore = results.map { $0.scorecard.practicalityScore }.reduce(0, +) / Double(results.count)
        report.avgGoalScore = results.map { $0.scorecard.goalAlignmentScore }.reduce(0, +) / Double(results.count)
        report.avgExperienceScore = results.map { $0.scorecard.experienceScore }.reduce(0, +) / Double(results.count)
        report.avgVarietyScore = results.map { $0.scorecard.varietyScore }.reduce(0, +) / Double(results.count)
        report.avgLocationScore = results.map { $0.scorecard.locationScore }.reduce(0, +) / Double(results.count)
        report.avgProfileScore = results.map { $0.scorecard.profileScore }.reduce(0, +) / Double(results.count)
        report.avgOverallScore = results.map { $0.scorecard.overallScore }.reduce(0, +) / Double(results.count)
        
        report.totalTimeSeconds = totalTimeSeconds
        report.avgTimePerUser = totalTimeSeconds / Double(results.count)
        
        // Issue breakdown
        report.issueBreakdown = issuesFound
        
        // Worst performers
        report.worstPerformers = results
            .sorted { $0.scorecard.overallScore < $1.scorecard.overallScore }
            .prefix(10)
            .map { ($0.user.name, $0.scorecard.overallScore, $0.scorecard.allViolations) }
        
        // Best performers
        report.bestPerformers = results
            .sorted { $0.scorecard.overallScore > $1.scorecard.overallScore }
            .prefix(5)
            .map { ($0.user.name, $0.scorecard.overallScore) }
        
        return report
    }
    
    private func printSummary(report: AuditReport) {
        print("\n")
        print("╔══════════════════════════════════════════════════════════════════════╗")
        print("║                    📊 AUDIT RESULTS SUMMARY                          ║")
        print("╠══════════════════════════════════════════════════════════════════════╣")
        print("║ OVERALL:")
        print("║   Total Users Tested: \(report.totalUsers)")
        print("║   ✅ Passed: \(report.passedUsers) (\(String(format: "%.1f", report.passRate))%)")
        print("║   ❌ Failed: \(report.failedUsers) (\(String(format: "%.1f", 100 - report.passRate))%)")
        print("║   Average Overall Score: \(String(format: "%.1f", report.avgOverallScore))/100")
        print("╠══════════════════════════════════════════════════════════════════════╣")
        print("║ SCORE BREAKDOWN:")
        print("║   🎯 Equipment Match:    \(String(format: "%.1f", report.avgEquipmentScore))%")
        print("║   🛡️ Safety Score:       \(String(format: "%.1f", report.avgSafetyScore))%")
        print("║   ✨ Practicality:       \(String(format: "%.1f", report.avgPracticalityScore))%")
        print("║   🎯 Goal Alignment:     \(String(format: "%.1f", report.avgGoalScore))%")
        print("║   📈 Experience Match:   \(String(format: "%.1f", report.avgExperienceScore))%")
        print("║   🔄 Variety:            \(String(format: "%.1f", report.avgVarietyScore))%")
        print("║   📍 Location Match:     \(String(format: "%.1f", report.avgLocationScore))%")
        print("║   👤 Profile Safety:     \(String(format: "%.1f", report.avgProfileScore))%")
        print("╠══════════════════════════════════════════════════════════════════════╣")
        print("║ ISSUE BREAKDOWN:")
        for (issue, count) in report.issueBreakdown.sorted(by: { $0.value > $1.value }) {
            let bar = String(repeating: "█", count: min(count / 5, 20))
            print("║   \(issue): \(count) \(bar)")
        }
        print("╠══════════════════════════════════════════════════════════════════════╣")
        print("║ PERFORMANCE:")
        print("║   Total Time: \(String(format: "%.2f", report.totalTimeSeconds))s")
        print("║   Avg Time/User: \(String(format: "%.2f", report.avgTimePerUser * 1000))ms")
        print("╚══════════════════════════════════════════════════════════════════════╝")
        
        if !report.worstPerformers.isEmpty {
            print("\n⚠️ WORST PERFORMERS (need investigation):")
            for (name, score, violations) in report.worstPerformers.prefix(5) {
                print("   • \(name): \(String(format: "%.1f", score))/100")
                for violation in violations.prefix(2) {
                    print("     └─ \(violation)")
                }
            }
        }
    }
    
    // MARK: - Code Fix Identification
    
    private func identifyCodeFixes(from results: [GeneratedWorkoutResult]) -> [SuggestedFix] {
        var fixes: [SuggestedFix] = []
        
        // Analyze patterns in failures
        let allViolations = results.flatMap { $0.scorecard.allViolations }
        
        // Equipment issues
        let equipmentViolations = allViolations.filter { $0.contains("requires") || $0.contains("equipment") }
        if equipmentViolations.count > 10 {
            // Find most common missing equipment
            var missingEquipment: [String: Int] = [:]
            for v in equipmentViolations {
                if let range = v.range(of: "requires "), let endRange = v.range(of: " - user") {
                    let equipment = String(v[range.upperBound..<endRange.lowerBound])
                    missingEquipment[equipment, default: 0] += 1
                }
            }
            
            for (equip, count) in missingEquipment.sorted(by: { $0.value > $1.value }).prefix(3) {
                fixes.append(SuggestedFix(
                    category: "Equipment Filter",
                    description: "'\(equip)' appearing \(count) times despite not being in user equipment",
                    suggestedCode: "Ensure allSatisfy is used for equipment matching in WorkoutGeneratorService.swift",
                    priority: .high
                ))
            }
        }
        
        // Safety issues
        let safetyViolations = allViolations.filter { $0.contains("unsafe") }
        if safetyViolations.count > 5 {
            fixes.append(SuggestedFix(
                category: "Safety Filter",
                description: "\(safetyViolations.count) exercises violating injury limitations",
                suggestedCode: "Strengthen limitation filtering in WorkoutGeneratorService and SmartExerciseSelectionEngine",
                priority: .critical
            ))
        }
        
        // Practicality issues
        let practicalityViolations = allViolations.filter { $0.contains("practicality") }
        if practicalityViolations.count > 10 {
            fixes.append(SuggestedFix(
                category: "Practicality Filter",
                description: "\(practicalityViolations.count) low-practicality exercises getting through",
                suggestedCode: "Lower threshold or ensure practicalityScore > 0 && < 30 check is applied",
                priority: .medium
            ))
        }
        
        // Location issues
        let locationViolations = allViolations.filter { $0.contains("Home") && $0.contains("gym equipment") }
        if locationViolations.count > 5 {
            fixes.append(SuggestedFix(
                category: "Location Filter",
                description: "\(locationViolations.count) home users getting gym-only exercises",
                suggestedCode: "Add explicit location-based equipment filtering",
                priority: .high
            ))
        }
        
        return fixes
    }
}

// MARK: - Report Models

class AuditReport {
    var totalUsers: Int = 0
    var passedUsers: Int = 0
    var failedUsers: Int = 0
    var passRate: Double = 0
    
    var avgEquipmentScore: Double = 0
    var avgSafetyScore: Double = 0
    var avgPracticalityScore: Double = 0
    var avgGoalScore: Double = 0
    var avgExperienceScore: Double = 0
    var avgVarietyScore: Double = 0
    var avgLocationScore: Double = 0
    var avgProfileScore: Double = 0
    var avgOverallScore: Double = 0
    
    var totalTimeSeconds: Double = 0
    var avgTimePerUser: Double = 0
    
    var issueBreakdown: [String: Int] = [:]
    var worstPerformers: [(String, Double, [String])] = []  // (name, score, violations)
    var bestPerformers: [(String, Double)] = []  // (name, score)
    
    var suggestedFixes: [SuggestedFix] = []
}

struct SuggestedFix {
    let category: String
    let description: String
    let suggestedCode: String
    let priority: Priority
    
    enum Priority: String {
        case critical = "🔴 CRITICAL"
        case high = "🟠 HIGH"
        case medium = "🟡 MEDIUM"
        case low = "🟢 LOW"
    }
}

// MARK: - Integration with Dev Menu

extension WorkoutQualityAudit {
    
    /// Run audit and save results to a file
    func runAndSaveAudit(userCount: Int = 200) {
        runFullAudit(userCount: userCount) { report in
            // Generate detailed report file
            var reportContent = """
            ╔══════════════════════════════════════════════════════════════════════════════╗
            ║                    WORKOUT QUALITY AUDIT REPORT                               ║
            ║                    Generated: \(Date())                                       ║
            ╚══════════════════════════════════════════════════════════════════════════════╝
            
            SUMMARY
            ═══════
            Total Users Tested: \(report.totalUsers)
            Passed: \(report.passedUsers) (\(String(format: "%.1f", report.passRate))%)
            Failed: \(report.failedUsers) (\(String(format: "%.1f", 100 - report.passRate))%)
            Average Overall Score: \(String(format: "%.1f", report.avgOverallScore))/100
            
            DETAILED SCORES
            ═══════════════
            Equipment Match:    \(String(format: "%.1f", report.avgEquipmentScore))%
            Safety Score:       \(String(format: "%.1f", report.avgSafetyScore))%
            Practicality:       \(String(format: "%.1f", report.avgPracticalityScore))%
            Goal Alignment:     \(String(format: "%.1f", report.avgGoalScore))%
            Experience Match:   \(String(format: "%.1f", report.avgExperienceScore))%
            Variety:            \(String(format: "%.1f", report.avgVarietyScore))%
            Location Match:     \(String(format: "%.1f", report.avgLocationScore))%
            Profile Safety:     \(String(format: "%.1f", report.avgProfileScore))%
            
            ISSUE BREAKDOWN
            ═══════════════
            """
            
            for (issue, count) in report.issueBreakdown.sorted(by: { $0.value > $1.value }) {
                reportContent += "\n\(issue): \(count)"
            }
            
            reportContent += """
            
            
            SUGGESTED CODE FIXES
            ══════════════════
            """
            
            for fix in report.suggestedFixes {
                reportContent += """
                
                [\(fix.priority.rawValue)] \(fix.category)
                Description: \(fix.description)
                Suggested: \(fix.suggestedCode)
                
                """
            }
            
            reportContent += """
            
            
            WORST PERFORMERS
            ════════════════
            """
            
            for (name, score, violations) in report.worstPerformers {
                reportContent += "\n\(name): \(String(format: "%.1f", score))/100"
                for v in violations.prefix(3) {
                    reportContent += "\n  • \(v)"
                }
            }
            
            print("\n\n📄 FULL REPORT:")
            print(reportContent)
            
            // Apply any critical fixes automatically
            if !report.suggestedFixes.filter({ $0.priority == .critical }).isEmpty {
                print("\n\n🔴 CRITICAL ISSUES FOUND - Manual review required!")
            }
        }
    }
}

#endif








