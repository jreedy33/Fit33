import Foundation
import CoreData

// MARK: - Community Intelligence Service
// Connects to comprehensive aggregation system in Supabase
// Priority: User input > User history > Similar users > Community > Algorithm

class CommunityIntelligenceService {
    static let shared = CommunityIntelligenceService()
    
    private init() {}
    
    // MARK: - Smart Recommendation with Priority System
    
    /// Gets the smartest recommendation possible using priority hierarchy
    /// Priority 0: User's explicit input (always respected)
    /// Priority 1: User's own history
    /// Priority 2: Similar users (same age/gender/experience/strength)
    /// Priority 3: General community
    /// Priority 4: Algorithm fallback
    func getSmartRecommendation(
        userId: UUID,
        exerciseName: String,
        userInputWeight: Double? = nil,  // If user explicitly chose weight
        userInputReps: Int? = nil,       // If user explicitly chose reps
        userAge: Int,
        userGender: String,
        userExperience: String,
        userStrengthLevel: String?,
        userGoal: String,
        context: NSManagedObjectContext
    ) async -> SmartRecommendationResult {
        
        // PRIORITY 0: User's explicit choice ALWAYS wins
        if let weight = userInputWeight, let reps = userInputReps {
            return SmartRecommendationResult(
                weight: weight,
                reps: reps,
                sets: 3,
                priorityLevel: .userChoice,
                confidence: 1.0,
                note: "👤 Your choice (backed by smart data)",
                dataSource: "USER_INPUT"
            )
        }
        
        // PRIORITY 1: Check user's own history
        if let userHistory = await fetchUserHistory(
            userId: userId,
            exerciseName: exerciseName
        ) {
            return SmartRecommendationResult(
                weight: userHistory.avgWeight,
                reps: userHistory.avgReps,
                sets: 3,
                priorityLevel: .userHistory,
                confidence: 1.0,
                note: "✅ Based on YOUR last performance (\(userHistory.sampleSize) workouts)",
                dataSource: "USER_HISTORY"
            )
        }
        
        // PRIORITY 2: Check similar users
        if let similarUsers = await fetchSimilarUsersData(
            exerciseName: exerciseName,
            ageRange: getAgeRange(userAge),
            gender: userGender,
            experience: userExperience,
            strengthLevel: userStrengthLevel
        ) {
            let confidence = min(1.0, Double(similarUsers.sampleSize) / 10.0)
            return SmartRecommendationResult(
                weight: similarUsers.avgWeight,
                reps: similarUsers.avgReps,
                sets: 3,
                priorityLevel: .similarUsers,
                confidence: confidence,
                note: "📊 Based on \(similarUsers.sampleSize) similar users (age \(getAgeRange(userAge)), \(userGender), \(userExperience))",
                dataSource: "SIMILAR_USERS"
            )
        }
        
        // PRIORITY 3: Check general community
        if let community = await fetchCommunityData(
            exerciseName: exerciseName,
            ageRange: getAgeRange(userAge),
            gender: userGender
        ) {
            return SmartRecommendationResult(
                weight: community.avgWeight,
                reps: community.avgReps,
                sets: 3,
                priorityLevel: .community,
                confidence: 0.6,
                note: "🌍 Community average (\(community.sampleSize) users)",
                dataSource: "COMMUNITY"
            )
        }
        
        // PRIORITY 4: Fallback to algorithm
        let algorithmRec = StrengthProfileRecommendationEngine.shared.getRecommendation(
            for: exerciseName,
            user: getUserFromContext(userId: userId, context: context)!,
            setNumber: 1,
            context: context
        )
        
        return SmartRecommendationResult(
            weight: algorithmRec.weight,
            reps: algorithmRec.reps,
            sets: 3,
            priorityLevel: .algorithm,
            confidence: 0.5,
            note: "🧮 Smart calculation from your profile",
            dataSource: "ALGORITHM"
        )
    }
    
    // MARK: - Track Data for Community Learning
    
    /// Tracks a successful progression to help the community
    func trackProgression(
        userId: UUID,
        exerciseName: String,
        fromWeight: Double,
        toWeight: Double,
        reps: Int,
        userAge: Int,
        userGender: String,
        userExperience: String,
        userStrengthLevel: String?,
        success: Bool = true
    ) async throws {
        
        let progression = ExerciseProgressionDTO(
            userId: userId.uuidString,
            exerciseName: exerciseName,
            fromWeight: fromWeight,
            toWeight: toWeight,
            progressionAmount: toWeight - fromWeight,
            reps: reps,
            userAgeRange: getAgeRange(userAge),
            userGender: userGender,
            userExperience: userExperience,
            userStrengthLevel: userStrengthLevel,
            success: success,
            date: ISO8601DateFormatter().string(from: Date())
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("exercise_progressions")
                .insert(progression)
                .execute()
            
            print("📊 [COMMUNITY] Tracked progression: \(exerciseName) \(Int(fromWeight))→\(Int(toWeight))lbs")
        } catch {
            print("❌ [COMMUNITY] Failed to track progression: \(error)")
            throw error
        }
    }
    
    /// Tracks program completion for community insights
    func trackProgramCompletion(
        userId: UUID,
        programName: String,
        programType: String,
        totalDays: Int,
        daysCompleted: Int,
        completedSuccessfully: Bool,
        userAge: Int,
        userGender: String,
        userExperience: String,
        userGoal: String,
        startedAt: Date,
        completedAt: Date?,
        userRating: Int? = nil
    ) async throws {
        
        let completionRate = Double(daysCompleted) / Double(totalDays)
        
        let analytics = ProgramCompletionDTO(
            userId: userId.uuidString,
            programName: programName,
            programType: programType,
            totalDays: totalDays,
            daysCompleted: daysCompleted,
            completionRate: completionRate,
            userAgeRange: getAgeRange(userAge),
            userGender: userGender,
            userExperience: userExperience,
            userGoal: userGoal,
            completedSuccessfully: completedSuccessfully,
            userRating: userRating,
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            completedAt: completedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("program_completion_analytics")
                .insert(analytics)
                .execute()
            
            print("📊 [COMMUNITY] Tracked program completion: \(programName)")
        } catch {
            print("❌ [COMMUNITY] Failed to track program: \(error)")
            throw error
        }
    }
    
    /// Updates exercise effectiveness based on performance
    func trackExerciseEffectiveness(
        userId: UUID,
        exerciseName: String,
        setsCompleted: Int,
        avgReps: Double,
        avgWeight: Double,
        consistencyScore: Double,
        userAge: Int,
        userGender: String,
        userExperience: String,
        equipment: [String],
        isFavorited: Bool,
        completionRate: Double
    ) async throws {
        
        let effectiveness = ExerciseEffectivenessDTO(
            userId: userId.uuidString,
            exerciseName: exerciseName,
            timesPerformed: 1,
            avgSetsCompleted: Double(setsCompleted),
            avgRepsCompleted: avgReps,
            avgWeightUsed: avgWeight,
            consistencyScore: consistencyScore,
            userAgeRange: getAgeRange(userAge),
            userGender: userGender,
            userExperience: userExperience,
            userEquipment: equipment,
            isFavorited: isFavorited,
            completionRate: completionRate
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("exercise_effectiveness")
                .upsert(effectiveness)
                .execute()
            
            print("📊 [COMMUNITY] Tracked effectiveness: \(exerciseName)")
        } catch {
            print("❌ [COMMUNITY] Failed to track effectiveness: \(error)")
            throw error
        }
    }
    
    // MARK: - Get Community Insights
    
    /// Gets recommended programs based on community success rates
    func getRecommendedPrograms(
        userAge: Int,
        userGender: String,
        userGoal: String,
        userExperience: String
    ) async -> [CommunityProgramRecommendation] {
        
        do {
            let response: [ProgramRecommendationDTO] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_recommended_programs_for_profile", params: [
                    "p_age_range": getAgeRange(userAge),
                    "p_gender": userGender,
                    "p_goal": userGoal,
                    "p_experience": userExperience
                ])
                .execute()
                .value
            
            return response.map { dto in
                CommunityProgramRecommendation(
                    programName: dto.programName,
                    successRate: dto.successRate,
                    avgCompletionRate: dto.avgCompletionRate,
                    userCount: dto.userCount
                )
            }
        } catch {
            print("❌ [COMMUNITY] Failed to fetch program recommendations: \(error)")
            return []
        }
    }
    
    /// Gets top exercises for a muscle group based on community data
    func getTopExercisesForMuscleGroup(
        muscleGroup: String,
        userAge: Int,
        userGender: String,
        userExperience: String,
        limit: Int = 10
    ) async -> [ExerciseRecommendation] {
        
        do {
            let response: [ExerciseRecommendationDTO] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_top_exercises_for_profile", params: [
                    "p_muscle_group": muscleGroup,
                    "p_age_range": getAgeRange(userAge),
                    "p_gender": userGender,
                    "p_experience": userExperience,
                    "p_limit": String(limit)
                ])
                .execute()
                .value
            
            return response.map { dto in
                ExerciseRecommendation(
                    exerciseName: dto.exerciseName,
                    avgPerformance: dto.avgPerformance,
                    timesPerformed: dto.timesPerformed,
                    favoritedCount: dto.favoritedCount,
                    completionRate: dto.completionRate
                )
            }
        } catch {
            print("❌ [COMMUNITY] Failed to fetch exercise recommendations: \(error)")
            return []
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func fetchUserHistory(
        userId: UUID,
        exerciseName: String
    ) async -> UserHistoryData? {
        
        do {
            struct HistoryResult: Codable {
                let avgWeight: Double
                let avgReps: Double
                let sampleSize: Int
                
                enum CodingKeys: String, CodingKey {
                    case avgWeight = "avg_weight"
                    case avgReps = "avg_reps"
                    case sampleSize = "sample_size"
                }
            }
            
            let response: [HistoryResult] = try await SupabaseManager.shared.supabaseClient
                .from("exercise_progressions")
                .select("to_weight, reps")
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .eq("success", value: true)
                .order("date", ascending: false)
                .limit(5)
                .execute()
                .value
            
            guard !response.isEmpty else { return nil }
            
            let avgWeight = response.map { $0.avgWeight }.reduce(0, +) / Double(response.count)
            let avgReps = response.map { $0.avgReps }.reduce(0, +) / Double(response.count)
            
            return UserHistoryData(
                avgWeight: avgWeight,
                avgReps: Int(avgReps),
                sampleSize: response.count
            )
        } catch {
            print("❌ Failed to fetch user history: \(error)")
            return nil
        }
    }
    
    private func fetchSimilarUsersData(
        exerciseName: String,
        ageRange: String,
        gender: String,
        experience: String,
        strengthLevel: String?
    ) async -> SimilarUsersData? {
        
        do {
            struct SimilarResult: Codable {
                let avgProgression: Double
                let sampleCount: Int
                let confidence: Double
                
                enum CodingKeys: String, CodingKey {
                    case avgProgression = "avg_progression"
                    case sampleCount = "sample_count"
                    case confidence
                }
            }
            
            let response: [SimilarResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_progression_for_similar_users", params: [
                    "p_exercise_name": exerciseName,
                    "p_age_range": ageRange,
                    "p_gender": gender,
                    "p_strength_level": strengthLevel ?? ""
                ])
                .execute()
                .value
            
            guard let result = response.first, result.sampleCount >= 3 else { return nil }
            
            return SimilarUsersData(
                avgWeight: result.avgProgression,
                avgReps: 10, // Default, can be refined
                sampleSize: result.sampleCount
            )
        } catch {
            print("❌ Failed to fetch similar users data: \(error)")
            return nil
        }
    }
    
    private func fetchCommunityData(
        exerciseName: String,
        ageRange: String,
        gender: String
    ) async -> CommunityData? {
        
        do {
            struct CommunityResult: Codable {
                let recommendedWeight: Double
                let recommendedReps: Double
                let userCount: Int
                
                enum CodingKeys: String, CodingKey {
                    case recommendedWeight = "recommended_weight"
                    case recommendedReps = "recommended_reps"
                    case userCount = "user_count"
                }
            }
            
            let response: [CommunityResult] = try await SupabaseManager.shared.supabaseClient
                .from("community_exercise_insights")
                .select()
                .eq("exercise_name", value: exerciseName)
                .eq("user_age_range", value: ageRange)
                .eq("user_gender", value: gender)
                .limit(1)
                .execute()
                .value
            
            guard let result = response.first, result.userCount >= 5 else { return nil }
            
            return CommunityData(
                avgWeight: result.recommendedWeight,
                avgReps: Int(result.recommendedReps),
                sampleSize: result.userCount
            )
        } catch {
            print("❌ Failed to fetch community data: \(error)")
            return nil
        }
    }
    
    private func getAgeRange(_ age: Int) -> String {
        let decade = (age / 10) * 10
        return "\(decade)-\(decade + 9)"
    }
    
    private func getUserFromContext(userId: UUID, context: NSManagedObjectContext) -> User? {
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", userId as CVarArg)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("❌ Failed to fetch user: \(error)")
            return nil
        }
    }
}

// MARK: - Data Models

struct SmartRecommendationResult {
    let weight: Double
    let reps: Int
    let sets: Int
    let priorityLevel: RecommendationPriority
    let confidence: Double
    let note: String
    let dataSource: String
}

enum RecommendationPriority: String {
    case userChoice = "USER_CHOICE"
    case userHistory = "USER_HISTORY"
    case similarUsers = "SIMILAR_USERS"
    case community = "COMMUNITY"
    case algorithm = "ALGORITHM"
    
    var displayIcon: String {
        switch self {
        case .userChoice: return "👤"
        case .userHistory: return "✅"
        case .similarUsers: return "📊"
        case .community: return "🌍"
        case .algorithm: return "🧮"
        }
    }
}

struct UserHistoryData {
    let avgWeight: Double
    let avgReps: Int
    let sampleSize: Int
}

struct SimilarUsersData {
    let avgWeight: Double
    let avgReps: Int
    let sampleSize: Int
}

struct CommunityData {
    let avgWeight: Double
    let avgReps: Int
    let sampleSize: Int
}

struct CommunityProgramRecommendation {
    let programName: String
    let successRate: Double
    let avgCompletionRate: Double
    let userCount: Int
    
    var displayText: String {
        let successPercent = Int(successRate * 100)
        return "\(programName) - \(successPercent)% success rate (\(userCount) users)"
    }
}

struct ExerciseRecommendation {
    let exerciseName: String
    let avgPerformance: Double
    let timesPerformed: Int
    let favoritedCount: Int
    let completionRate: Double
    
    var popularityScore: Double {
        let favoritedWeight = Double(favoritedCount) * 10.0
        let performanceWeight = Double(timesPerformed)
        let completionWeight = completionRate * 100
        return favoritedWeight + performanceWeight + completionWeight
    }
}

// MARK: - DTOs

struct ExerciseProgressionDTO: Codable {
    let userId: String
    let exerciseName: String
    let fromWeight: Double
    let toWeight: Double
    let progressionAmount: Double
    let reps: Int
    let userAgeRange: String
    let userGender: String
    let userExperience: String
    let userStrengthLevel: String?
    let success: Bool
    let date: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case exerciseName = "exercise_name"
        case fromWeight = "from_weight"
        case toWeight = "to_weight"
        case progressionAmount = "progression_amount"
        case reps
        case userAgeRange = "user_age_range"
        case userGender = "user_gender"
        case userExperience = "user_experience"
        case userStrengthLevel = "user_strength_level"
        case success
        case date
    }
}

struct ProgramCompletionDTO: Codable {
    let userId: String
    let programName: String
    let programType: String
    let totalDays: Int
    let daysCompleted: Int
    let completionRate: Double
    let userAgeRange: String
    let userGender: String
    let userExperience: String
    let userGoal: String
    let completedSuccessfully: Bool
    let userRating: Int?
    let startedAt: String
    let completedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case programName = "program_name"
        case programType = "program_type"
        case totalDays = "total_days"
        case daysCompleted = "days_completed"
        case completionRate = "completion_rate"
        case userAgeRange = "user_age_range"
        case userGender = "user_gender"
        case userExperience = "user_experience"
        case userGoal = "user_goal"
        case completedSuccessfully = "completed_successfully"
        case userRating = "user_rating"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct ExerciseEffectivenessDTO: Codable {
    let userId: String
    let exerciseName: String
    let timesPerformed: Int
    let avgSetsCompleted: Double
    let avgRepsCompleted: Double
    let avgWeightUsed: Double
    let consistencyScore: Double
    let userAgeRange: String
    let userGender: String
    let userExperience: String
    let userEquipment: [String]
    let isFavorited: Bool
    let completionRate: Double
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case exerciseName = "exercise_name"
        case timesPerformed = "times_performed"
        case avgSetsCompleted = "avg_sets_completed"
        case avgRepsCompleted = "avg_reps_completed"
        case avgWeightUsed = "avg_weight_used"
        case consistencyScore = "consistency_score"
        case userAgeRange = "user_age_range"
        case userGender = "user_gender"
        case userExperience = "user_experience"
        case userEquipment = "user_equipment"
        case isFavorited = "is_favorited"
        case completionRate = "completion_rate"
    }
}

struct ProgramRecommendationDTO: Codable {
    let programName: String
    let successRate: Double
    let avgCompletionRate: Double
    let userCount: Int
    
    enum CodingKeys: String, CodingKey {
        case programName = "program_name"
        case successRate = "success_rate"
        case avgCompletionRate = "avg_completion_rate"
        case userCount = "user_count"
    }
}

struct ExerciseRecommendationDTO: Codable {
    let exerciseName: String
    let avgPerformance: Double
    let timesPerformed: Int
    let favoritedCount: Int
    let completionRate: Double
    
    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case avgPerformance = "avg_performance"
        case timesPerformed = "times_performed"
        case favoritedCount = "favorited_count"
        case completionRate = "completion_rate"
    }
}

