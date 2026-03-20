import Foundation
import CoreData
import SwiftUI

// MARK: - Smart Program Recommender
// Recommends training programs based on:
// - User's equipment availability
// - Fitness goals
// - Experience level
// - Available training days
// - Community success data
// - Body type and preferences

/// Canonical program recommendation engine. Other recommendation entry points
/// (ProgramLibraryService.getRecommendedPrograms, CollaborativeLearningEngine.getRecommendedPrograms,
/// CommunityIntelligenceService.getRecommendedPrograms) should eventually delegate here.
class SmartProgramRecommender {
    static let shared = SmartProgramRecommender()
    
    private init() {}
    
    // MARK: - Main Recommendation Method
    
    func getTopRecommendedPrograms(
        for user: User,
        limit: Int = 5
    ) -> [ProgramRecommendation] {
        
        let allPrograms = WorkoutProgramEngine.shared.getAllPrograms()
        let profile = SmartRecommendationEngine.shared.userProfileAnalyzer.analyzeUser(user)
        
        print("🎯 Smart Program Recommender analyzing \(allPrograms.count) programs for user...")
        print("   User Profile: \(profile.experienceLevel.rawValue), \(profile.fitnessGoal.rawValue)")
        print("   Equipment: \(profile.prioritizedEquipment)")
        print("   Available Days: \(profile.availableDays)")
        
        // Score each program
        let scoredPrograms = allPrograms.map { program -> ProgramRecommendation in
            let score = calculateProgramScore(program: program, profile: profile)
            let reasons = getRecommendationReasons(program: program, profile: profile)
            let compatibility = calculateEquipmentCompatibility(program: program, equipment: profile.prioritizedEquipment)
            
            return ProgramRecommendation(
                program: program,
                matchScore: score,
                reasons: reasons,
                equipmentCompatibility: compatibility,
                difficultyMatch: getDifficultyMatch(program: program, profile: profile)
            )
        }
        .sorted { $0.matchScore > $1.matchScore }
        
        let top = Array(scoredPrograms.prefix(limit))
        
        print("✅ Top \(top.count) programs recommended:")
        for (index, rec) in top.enumerated() {
            print("   \(index + 1). \(rec.program.name) - Score: \(Int(rec.matchScore)) (\(rec.reasons.first ?? ""))")
        }
        
        return top
    }
    
    // MARK: - Single Best Recommendation
    
    func getBestProgram(for user: User) -> ProgramRecommendation {
        return getTopRecommendedPrograms(for: user, limit: 1).first ?? getDefaultProgram()
    }
    
    // MARK: - Program Scoring
    
    private func calculateProgramScore(
        program: WorkoutProgram,
        profile: UserProfileAnalysis
    ) -> Double {
        
        var score: Double = 100
        
        // ==========================================
        // EXPERIENCE LEVEL MATCH (0-80 points)
        // ==========================================
        let programDifficulty = convertDifficulty(program.difficulty)
        
        switch (profile.experienceLevel, programDifficulty) {
        case (.beginner, .beginner):
            score += 80
        case (.beginner, .intermediate):
            score += 30 // Slight stretch is okay
        case (.beginner, .advanced):
            score -= 40 // Too advanced for beginner
            
        case (.intermediate, .beginner):
            score += 40 // Can do beginner, but might be easy
        case (.intermediate, .intermediate):
            score += 80
        case (.intermediate, .advanced):
            score += 50 // Good stretch
            
        case (.advanced, .beginner):
            score += 10 // Probably too easy
        case (.advanced, .intermediate):
            score += 50
        case (.advanced, .advanced):
            score += 80
        }
        
        // ==========================================
        // GOAL ALIGNMENT (0-100 points)
        // ==========================================
        let goalScore = calculateGoalAlignment(
            programFocus: program.focus,
            userGoal: profile.fitnessGoal
        )
        score += goalScore
        
        // ==========================================
        // EQUIPMENT COMPATIBILITY (0-60 points)
        // ==========================================
        let equipmentScore = calculateEquipmentScore(program: program, equipment: profile.prioritizedEquipment)
        score += equipmentScore
        
        // ==========================================
        // AVAILABLE DAYS MATCH (0-40 points)
        // ==========================================
        let daysPerWeek = program.workoutsPerWeek
        let daysDifference = abs(daysPerWeek - profile.availableDays)
        
        if daysDifference == 0 {
            score += 40 // Perfect match
        } else if daysDifference == 1 {
            score += 25 // Close enough
        } else if daysDifference == 2 {
            score += 10 // Might work
        } else {
            score -= 20 // Poor fit
        }
        
        // ==========================================
        // PROGRAM DURATION PREFERENCE (0-20 points)
        // ==========================================
        // Beginners often prefer shorter programs
        // Advanced users can handle longer commitments
        switch (profile.experienceLevel, program.duration) {
        case (.beginner, 7...14):
            score += 20 // Short programs good for beginners
        case (.beginner, 15...30):
            score += 10
        case (.beginner, _):
            score += 0 // Long programs might be overwhelming
            
        case (.intermediate, 14...30):
            score += 20 // Medium programs good for intermediate
        case (.intermediate, 7...13):
            score += 10
        case (.intermediate, _):
            score += 5
            
        case (.advanced, 30...):
            score += 20 // Advanced can handle long programs
        case (.advanced, _):
            score += 10
        }
        
        // ==========================================
        // AGE CONSIDERATIONS (0-25 points)
        // ==========================================
        if profile.age > 50 {
            if daysPerWeek <= 4 {
                score += 15
            }
            if programDifficulty == .beginner || programDifficulty == .intermediate {
                score += 10
            }
        } else if profile.age > 40 {
            if daysPerWeek <= 5 {
                score += 10
            }
            if programDifficulty != .advanced {
                score += 5
            }
        } else if profile.age < 30 {
            if programDifficulty == .intermediate || programDifficulty == .advanced {
                score += 10
            }
            if daysPerWeek >= 4 {
                score += 5
            }
        }
        
        // ==========================================
        // TRAINING AGE ADJUSTMENT
        // ==========================================
        switch profile.trainingAge {
        case .novice:
            // Strong preference for beginner programs
            if programDifficulty == .beginner {
                score += 30
            }
        case .beginner:
            if programDifficulty == .beginner || programDifficulty == .intermediate {
                score += 15
            }
        case .intermediate, .advanced, .elite:
            // More flexibility
            break
        }
        
        return max(0, score)
    }
    
    // MARK: - Goal Alignment
    
    private func calculateGoalAlignment(
        programFocus: ProgramFocus,
        userGoal: FitnessGoal
    ) -> Double {
        
        switch userGoal {
        case .gainStrength, .powerlifting:
            switch programFocus {
            case .strength, .powerbuilding:
                return 100
            case .hypertrophy:
                return 50
            default:
                return 20
            }
            
        case .buildMuscle, .bodybuilding:
            switch programFocus {
            case .hypertrophy:
                return 100
            case .powerbuilding, .strength:
                return 60
            case .fullBody:
                return 40
            default:
                return 20
            }
            
        case .loseWeight:
            switch programFocus {
            case .endurance, .fullBody:
                return 80
            case .bodyweight:
                return 70
            case .hypertrophy:
                return 60
            case .strength, .powerbuilding:
                return 50
            default:
                return 30
            }
            
        case .toneUp:
            switch programFocus {
            case .hypertrophy, .fullBody:
                return 80
            case .bodyweight:
                return 70
            default:
                return 40
            }
            
        case .improveEndurance, .athletic:
            switch programFocus {
            case .endurance:
                return 100
            case .bodyweight, .fullBody:
                return 60
            default:
                return 20
            }
            
        case .generalFitness, .flexibility:
            switch programFocus {
            case .fullBody:
                return 100
            case .bodyweight:
                return 80
            default:
                return 60
            }
        }
    }
    
    // MARK: - Equipment Compatibility
    
    private func calculateEquipmentScore(program: WorkoutProgram, equipment: [String]) -> Double {
        // Check what equipment the program requires
        let requiredEquipment = Set(program.equipment.map { $0.lowercased() })
        let userEquipment = Set(equipment.map { $0.lowercased() })
        
        if requiredEquipment.isEmpty {
            return 60 // No specific requirements = compatible
        }
        
        // Calculate how much user equipment matches
        let matchedEquipment = requiredEquipment.filter { req in
            userEquipment.contains(where: { user in
                user.contains(req) || req.contains(user)
            })
        }
        
        let matchRatio = Double(matchedEquipment.count) / Double(max(1, requiredEquipment.count))
        return matchRatio * 60 // Max 60 points
    }
    
    private func calculateEquipmentCompatibility(program: WorkoutProgram, equipment: [String]) -> EquipmentCompatibility {
        let score = calculateEquipmentScore(program: program, equipment: equipment)
        let ratio = score / 60
        
        if ratio >= 0.9 {
            return .perfect
        } else if ratio >= 0.7 {
            return .good
        } else if ratio >= 0.5 {
            return .partial
        } else {
            return .poor
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertDifficulty(_ difficulty: ProgramDifficulty) -> ExperienceLevel {
        switch difficulty {
        case .beginner:
            return .beginner
        case .intermediate:
            return .intermediate
        case .advanced:
            return .advanced
        }
    }
    
    private func getDifficultyMatch(program: WorkoutProgram, profile: UserProfileAnalysis) -> DifficultyMatch {
        let programDifficulty = convertDifficulty(program.difficulty)
        
        switch (profile.experienceLevel, programDifficulty) {
        case (.beginner, .beginner),
             (.intermediate, .intermediate),
             (.advanced, .advanced):
            return .perfect
            
        case (.beginner, .intermediate),
             (.intermediate, .advanced):
            return .challenging
            
        case (.intermediate, .beginner),
             (.advanced, .intermediate):
            return .comfortable
            
        case (.beginner, .advanced):
            return .tooHard
            
        case (.advanced, .beginner):
            return .tooEasy
        }
    }
    
    private func getRecommendationReasons(program: WorkoutProgram, profile: UserProfileAnalysis) -> [String] {
        var reasons: [String] = []
        
        // Goal alignment
        switch (profile.fitnessGoal, program.focus) {
        case (.gainStrength, .strength), (.gainStrength, .powerbuilding), (.powerlifting, .strength):
            reasons.append("Perfect for your strength goals 💪")
        case (.buildMuscle, .hypertrophy), (.bodybuilding, .hypertrophy):
            reasons.append("Optimized for muscle building 📈")
        case (.loseWeight, .endurance), (.loseWeight, .fullBody):
            reasons.append("Designed for fat loss 🔥")
        case (.toneUp, .hypertrophy), (.toneUp, .fullBody):
            reasons.append("Great for toning and definition ✨")
        case (.improveEndurance, .endurance), (.athletic, .endurance):
            reasons.append("Perfect for building endurance 🏃")
        case (.generalFitness, .fullBody):
            reasons.append("Well-rounded for general fitness 🌟")
        default:
            break
        }
        
        // Experience match
        let difficulty = convertDifficulty(program.difficulty)
        if difficulty == profile.experienceLevel {
            reasons.append("Matches your \(profile.experienceLevel.rawValue) level")
        } else if difficulty == .beginner && profile.experienceLevel == .intermediate {
            reasons.append("Solid foundation program")
        }
        
        // Equipment compatibility
        if calculateEquipmentScore(program: program, equipment: profile.prioritizedEquipment) > 50 {
            reasons.append("Works with your equipment ✓")
        }
        
        // Days per week
        let days = program.workoutsPerWeek
        if days == profile.availableDays {
            reasons.append("Fits your \(days)-day schedule")
        }
        
        // Duration
        if program.duration <= 14 {
            reasons.append("Quick \(program.duration)-day program")
        } else if program.duration >= 60 {
            reasons.append("Comprehensive \(program.duration)-day transformation")
        }
        
        return reasons
    }
    
    private func getDefaultProgram() -> ProgramRecommendation {
        guard let defaultProgram = WorkoutProgramEngine.shared.getAllPrograms().first else {
            // Return a safe fallback instead of crashing
            print("⚠️ [RECOMMENDER] No programs available — returning empty recommendation")
            let fallbackProgram = WorkoutProgram(
                id: "fallback",
                name: "Custom Workout",
                description: "Build your own workout",
                duration: 7,
                difficulty: .beginner,
                focus: .fullBody,
                schedule: [:],
                restDays: [4, 7],
                icon: "figure.strengthtraining.traditional",
                color: "blue",
                workoutsPerWeek: 3,
                estimatedTimePerWorkout: 45,
                equipment: [],
                benefits: ["General fitness"],
                preview: "A flexible workout plan"
            )
            return ProgramRecommendation(
                program: fallbackProgram,
                matchScore: 0,
                reasons: ["No programs loaded — try restarting the app"],
                equipmentCompatibility: .good,
                difficultyMatch: .comfortable
            )
        }
        return ProgramRecommendation(
            program: defaultProgram,
            matchScore: 50,
            reasons: ["Great starter program"],
            equipmentCompatibility: .good,
            difficultyMatch: .comfortable
        )
    }
}

// MARK: - Data Types (renamed to avoid conflicts)

struct ProgramRecommendation {
    let program: WorkoutProgram
    let matchScore: Double
    let reasons: [String]
    let equipmentCompatibility: EquipmentCompatibility
    let difficultyMatch: DifficultyMatch
}

enum EquipmentCompatibility: String {
    case perfect = "All equipment matches"
    case good = "Most equipment available"
    case partial = "Some substitutions needed"
    case poor = "May need alternatives"
}

enum DifficultyMatch: String {
    case tooEasy = "Below your level"
    case comfortable = "Comfortable"
    case perfect = "Perfect match"
    case challenging = "Good challenge"
    case tooHard = "May be too advanced"
}

// MARK: - Enhanced Program Suggestion Card Data

extension SmartProgramRecommender {
    
    /// Get a suggested program in the format expected by ProgramSuggestionCard
    func getSuggestedProgram(for user: User) -> SuggestedProgram {
        let recommended = getBestProgram(for: user)
        let program = recommended.program
        let profile = SmartRecommendationEngine.shared.userProfileAnalyzer.analyzeUser(user)
        
        // Map program to suggested program format
        return SuggestedProgram(
            title: program.name,
            description: buildDescription(for: recommended, profile: profile),
            duration: "\(program.duration / 7) weeks",
            workoutsPerWeek: "\(program.workoutsPerWeek) days/week",
            focusAreas: program.benefits.prefix(3).map { String($0) },
            difficulty: program.difficulty.rawValue,
            primaryColor: colorForGoal(profile.fitnessGoal),
            secondaryColor: colorForGoal(profile.fitnessGoal).opacity(0.7),
            icon: iconForGoal(profile.fitnessGoal),
            callToAction: "Start \(program.duration)-Day Program"
        )
    }
    
    private func buildDescription(for recommended: ProgramRecommendation, profile: UserProfileAnalysis) -> String {
        let primary = recommended.reasons.first ?? "Recommended for you"
        let equipment = recommended.equipmentCompatibility == .perfect || recommended.equipmentCompatibility == .good
            ? " Uses your available equipment."
            : ""
        
        return "\(primary).\(equipment)"
    }
    
    private func colorForGoal(_ goal: FitnessGoal) -> Color {
        switch goal {
        case .gainStrength, .powerlifting: return Color.red
        case .buildMuscle, .bodybuilding: return Color.blue
        case .loseWeight: return Color.orange
        case .toneUp: return Color.purple
        case .improveEndurance, .athletic: return Color.green
        case .generalFitness, .flexibility: return Color.cyan
        }
    }
    
    private func iconForGoal(_ goal: FitnessGoal) -> String {
        switch goal {
        case .gainStrength, .powerlifting: return "figure.strengthtraining.traditional"
        case .buildMuscle, .bodybuilding: return "figure.arms.open"
        case .loseWeight: return "flame.fill"
        case .toneUp: return "sparkles"
        case .improveEndurance, .athletic: return "heart.fill"
        case .generalFitness, .flexibility: return "figure.run"
        }
    }
}
