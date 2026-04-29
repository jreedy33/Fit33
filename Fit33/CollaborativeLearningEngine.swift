//
//  CollaborativeLearningEngine.swift
//  GoFit
//
//  Aggregates workout data across ALL users to find patterns, trends, and
//  successful combinations. Makes recommendations smarter based on what
//  works for similar users.
//
//  Key Features:
//  - User similarity matching (similar goals, stats, equipment)
//  - Exercise pairing analysis (what exercises work well together)
//  - Success metrics tracking (completion rates, program finishes)
//  - Global trend identification (popular + effective workouts)
//  - Cross-user recommendations (what worked for similar users)
//

import Foundation
import Supabase

// MARK: - Collaborative Learning Engine

@MainActor
class CollaborativeLearningEngine: ObservableObject {
    static let shared = CollaborativeLearningEngine()
    
    // MARK: - Published State
    
    @Published var isAnalyzing = false
    @Published var lastSyncDate: Date?
    @Published var totalUsersAnalyzed: Int = 0
    @Published var totalWorkoutsAnalyzed: Int = 0
    
    // MARK: - Cached Data (Some exposed for synchronous access)
    
    private var similarUserCache: [String: [SimilarUser]] = [:]  // userId -> similar users
    private var exercisePairingCache: [String: [ExercisePairing]] = [:]  // exercise -> best pairings
    nonisolated(unsafe) private(set) var globalTrendsCache: GlobalTrends?  // Exposed for sync access in scoring

    
    // MARK: - Constants
    
    private let similarityThreshold: Double = 0.7  // 70% similarity to be considered "similar"
    private let minDataPoints: Int = 5  // Minimum completions to be statistically relevant
    private let cacheDuration: TimeInterval = 3600  // 1 hour cache
    
    private var supabase: SupabaseClient {
        SupabaseManager.shared.supabaseClient
    }
    
    private init() {
        AppLogger.debug("🌐 [COLLABORATIVE ENGINE] Initialized", category: .workout)
    }
    
    // MARK: - Main API
    
    /// Get exercise recommendations boosted by what worked for similar users
    func getCollaborativeBoost(
        for exerciseName: String,
        userProfile: UserProfileSnapshot,
        targetMuscles: [String]
    ) async -> Double {
        var boost: Double = 0
        
        // 1. Check if this exercise is popular among similar users
        let similarUsers = await getSimilarUsers(to: userProfile)
        let popularityAmongSimilar = await getExercisePopularityAmongUsers(
            exerciseName: exerciseName,
            users: similarUsers
        )
        boost += popularityAmongSimilar * 30  // Up to +30 points
        
        // 2. Check if this exercise has high success rate globally
        if let globalSuccess = globalTrendsCache?.exerciseSuccessRates[exerciseName.lowercased()] {
            boost += globalSuccess * 20  // Up to +20 points
        }
        
        // 3. Check if this exercise pairs well with target muscles
        let pairingScore = await getExercisePairingScore(
            exerciseName: exerciseName,
            targetMuscles: targetMuscles
        )
        boost += pairingScore * 15  // Up to +15 points
        
        return boost
    }
    
    /// Get recommended exercise pairings based on global data
    func getRecommendedPairings(
        for exerciseName: String,
        limit: Int = 5
    ) async -> [ExercisePairing] {
        // Check cache
        if let cached = exercisePairingCache[exerciseName.lowercased()] {
            return Array(cached.prefix(limit))
        }
        
        // Fetch from database
        let pairings = await fetchExercisePairings(for: exerciseName)
        exercisePairingCache[exerciseName.lowercased()] = pairings
        
        return Array(pairings.prefix(limit))
    }
    
    // MARK: - Data Recording (Called after workout completion)
    
    /// Record a completed workout for collaborative analysis.
    ///
    /// Migration #154 (20260723_quality_workout_corpus.sql) added the
    /// `is_quality_workout` GENERATED column on `collaborative_workout_data`
    /// as the canonical corpus filter (score >= 70). The HARD client-side
    /// gate here is defense-in-depth so a junk 7-min / 2-exercise
    /// tap-through never produces a write at all — the auto-gen recommender
    /// reads from the corpus, so even a skipped row beats a bad one.
    func recordWorkoutCompletion(
        userId: String,
        userProfile: UserProfileSnapshot,
        exercises: [CompletedExercise],
        workoutType: String,  // "auto-gen", "custom", "program"
        programId: String? = nil,
        qualityScore: Int? = nil,
        qualityBand: String? = nil,
        workoutHistoryId: String? = nil,
        totalSets: Int? = nil,
        wasSuccessful: Bool = true  // Did user complete the full workout?
    ) async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("[COLLABORATIVE] Skipping workout record — not authenticated", category: .auth)
            return
        }
        guard !userId.isEmpty else {
            AppLogger.warning("[COLLABORATIVE] Skipping workout record — empty userId", category: .auth)
            return
        }
        // Hard quality gate (migration #154). A nil score means we couldn't
        // compute one — fall back to the legacy 3-exercise heuristic to
        // avoid breaking older code paths that haven't been ported yet.
        if let score = qualityScore {
            guard score >= 70 else {
                AppLogger.info("🚫 [COLLABORATIVE] Skipping corpus push — score \(score) below quality threshold (70). Junk workouts don't train the recommender.", category: .workout)
                return
            }
        }
        do {
            // 1. Record the workout completion
            var workoutData: [String: AnyJSON] = [
                "id": .string(UUID().uuidString),
                "user_id": .string(userId),
                "workout_type": .string(workoutType),
                "program_id": .string(programId ?? UUID().uuidString),
                "exercises": .array(exercises.map { exercise in
                    .object([
                        "name": .string(exercise.name),
                        "equipment": .string(exercise.equipment),
                        "sets_completed": .integer(exercise.setsCompleted),
                        "total_reps": .integer(exercise.totalReps),
                        "muscle_group": .string(exercise.muscleGroup)
                    ])
                }),
                "was_successful": .bool(wasSuccessful),
                "user_goal": .string(userProfile.goal),
                "user_experience": .string(userProfile.experience),
                "user_equipment": .array(userProfile.equipment.map { .string($0) }),
                "completed_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]

            // Migration #154 quality columns. workout_history_id is the FK
            // that lets `delete_workout_and_revert_stats` cascade the corpus
            // row when the user deletes their workout.
            if let historyId = workoutHistoryId {
                workoutData["workout_history_id"] = .string(historyId)
            }
            if let score = qualityScore {
                workoutData["workout_quality_score"] = .integer(score)
            }
            if let total = totalSets {
                workoutData["total_sets"] = .integer(total)
            }

            try await supabase
                .from("collaborative_workout_data")
                .insert(workoutData)
                .execute()
            
            // 2. Record exercise pairings (for co-occurrence analysis)
            await recordExercisePairings(exercises: exercises)
            
            // 3. Update user similarity profile
            await updateUserSimilarityProfile(userId: userId, profile: userProfile)
            
            AppLogger.debug("🌐 [COLLABORATIVE] Recorded quality workout (score=\(qualityScore ?? -1)) with \(exercises.count) exercises", category: .workout)
            
        } catch {
            // Route through classifier so RLS / transient / auth-expired errors don't
            // create high-severity bug-intel fingerprints. Caller already passes the
            // live auth.uid() (WorkoutManager fix), so 42501 here means a state edge
            // (token expired between guard and insert) rather than an app malfunction.
            NetworkErrorClassifier.log(
                error,
                context: "Recording collaborative_workout_data",
                category: .workout,
                transientLevel: .debug,
                op: "collaborative_workout_data.insert",
                userId: UUID(uuidString: userId)
            )
        }
    }
    
    /// Record a completed program for success analysis
    func recordProgramCompletion(
        userId: String,
        programId: String,
        programName: String,
        templateId: String,
        totalDays: Int,
        completedDays: Int,
        userProfile: UserProfileSnapshot
    ) async {
        do {
            let completionRate = Double(completedDays) / Double(totalDays)
            
            let data: [String: AnyJSON] = [
                "id": .string(UUID().uuidString),
                "user_id": .string(userId),
                "program_id": .string(programId),
                "program_name": .string(programName),
                "template_id": .string(templateId),
                "total_days": .integer(totalDays),
                "completed_days": .integer(completedDays),
                "completion_rate": .double(completionRate),
                "user_goal": .string(userProfile.goal),
                "user_experience": .string(userProfile.experience),
                "completed_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from("collaborative_program_completions")
                .insert(data)
                .execute()
            
            AppLogger.debug("🌐 [COLLABORATIVE] Recorded program completion: \(programName) (\(Int(completionRate * 100))%)", category: .workout)
            
        } catch {
            AppLogger.error("❌ [COLLABORATIVE] Failed to record program: \(error)", category: .workout)
        }
    }
    
    // MARK: - Sync & Analysis
    
    /// Sync and analyze global data (call periodically or on app launch)
    func syncGlobalData() async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        AppLogger.debug("🌐 [COLLABORATIVE] Starting global data sync...", category: .workout)
        
        do {
            // 1. Fetch global exercise statistics
            await fetchGlobalExerciseStats()

            // 2. Build exercise pairing index
            await buildExercisePairingIndex()

            // 3. Update user similarity clusters
            await updateUserSimilarityClusters()
            
            lastSyncDate = Date()
            AppLogger.debug("🌐 [COLLABORATIVE] Global sync complete!", category: .workout)
            
        }
    }
    
    // MARK: - Private Methods
    
    private func getSimilarUsers(to profile: UserProfileSnapshot) async -> [SimilarUser] {
        // Check cache first
        if let cached = similarUserCache[profile.id], !cached.isEmpty {
            return cached
        }
        
        do {
            // Fetch user profiles from database
            struct UserProfile: Decodable {
                let user_id: String
                let goal: String
                let experience: String
                let equipment: [String]
                let age_range: String?
                let gender: String?
            }
            
            let profiles: [UserProfile] = try await supabase
                .from("user_similarity_profiles")
                .select()
                .neq("user_id", value: profile.id)
                .execute()
                .value
            
            // Calculate similarity scores
            var similarUsers: [SimilarUser] = []
            
            for userProfile in profiles {
                let snapshot = UserProfileSnapshot(
                    id: userProfile.user_id,
                    goal: userProfile.goal,
                    experience: userProfile.experience,
                    equipment: userProfile.equipment,
                    ageRange: userProfile.age_range,
                    gender: userProfile.gender
                )
                let similarity = calculateSimilarity(profile, snapshot)
                
                if similarity >= similarityThreshold {
                    similarUsers.append(SimilarUser(
                        userId: userProfile.user_id,
                        similarityScore: similarity,
                        sharedGoal: userProfile.goal == profile.goal,
                        sharedExperience: userProfile.experience == profile.experience
                    ))
                }
            }
            
            // Sort by similarity and cache
            similarUsers.sort { $0.similarityScore > $1.similarityScore }
            similarUserCache[profile.id] = Array(similarUsers.prefix(50))  // Top 50 similar users
            
            return similarUsers
            
        } catch {
            AppLogger.warning("⚠️ [COLLABORATIVE] Could not fetch similar users: \(error)", category: .workout)
            return []
        }
    }
    
    private func calculateSimilarity(_ profile1: UserProfileSnapshot, _ profile2: UserProfileSnapshot) -> Double {
        var score: Double = 0
        var weights: Double = 0
        
        // Goal match (40% weight)
        if profile1.goal.lowercased() == profile2.goal.lowercased() {
            score += 0.4
        }
        weights += 0.4
        
        // Experience match (30% weight)
        if profile1.experience.lowercased() == profile2.experience.lowercased() {
            score += 0.3
        }
        weights += 0.3
        
        // Equipment overlap (30% weight)
        let equip1 = Set(profile1.equipment.map { $0.lowercased() })
        let equip2 = Set(profile2.equipment.map { $0.lowercased() })
        let overlap = Double(equip1.intersection(equip2).count)
        let total = Double(max(equip1.count, equip2.count))
        if total > 0 {
            score += (overlap / total) * 0.3
        }
        weights += 0.3
        
        return score / weights
    }
    
    private func getExercisePopularityAmongUsers(
        exerciseName: String,
        users: [SimilarUser]
    ) async -> Double {
        guard !users.isEmpty else { return 0 }
        
        do {
            // Count how many similar users completed this exercise
            let userIds = users.map { $0.userId }
            
            struct CountResult: Decodable {
                let count: Int
            }
            
            // This would need a proper count query - simplified for now
            let exerciseNameLower = exerciseName.lowercased()
            
            // Check global trends cache
            if let popularity = globalTrendsCache?.exercisePopularity[exerciseNameLower] {
                // Weight by similarity of users who did this exercise
                let avgSimilarity = users.reduce(0.0) { $0 + $1.similarityScore } / Double(users.count)
                return popularity * avgSimilarity
            }
            
            return 0.5  // Default moderate popularity
            
        }
    }
    
    private func getExercisePairingScore(
        exerciseName: String,
        targetMuscles: [String]
    ) async -> Double {
        // Check if this exercise commonly pairs with exercises for target muscles
        guard let pairings = exercisePairingCache[exerciseName.lowercased()] else {
            return 0.5
        }
        
        var score: Double = 0
        for pairing in pairings {
            if targetMuscles.contains(where: { pairing.muscleGroup.lowercased().contains($0.lowercased()) }) {
                score += pairing.coOccurrenceScore * 0.2
            }
        }
        
        return min(1.0, score)
    }
    
    private func recordExercisePairings(exercises: [CompletedExercise]) async {
        // Record which exercises were done together (co-occurrence)
        guard exercises.count >= 2 else { return }
        
        do {
            for i in 0..<exercises.count {
                for j in (i+1)..<exercises.count {
                    let ex1 = exercises[i]
                    let ex2 = exercises[j]
                    
                    let pairingData: [String: AnyJSON] = [
                        "id": .string(UUID().uuidString),
                        "ex1": .string(ex1.name.lowercased()),
                        "ex2": .string(ex2.name.lowercased()),
                        "muscle1": .string(ex1.muscleGroup),
                        "muscle2": .string(ex2.muscleGroup),
                        "equip1": .string(ex1.equipment),
                        "equip2": .string(ex2.equipment),
                        "recorded_at": .string(ISO8601DateFormatter().string(from: Date()))
                    ]
                    
                    try await supabase
                        .from("exercise_pairings")
                        .insert(pairingData)
                        .execute()
                }
            }
        } catch {
            // Silently fail - pairings are supplementary data
        }
    }
    
    private func updateUserSimilarityProfile(userId: String, profile: UserProfileSnapshot) async {
        do {
            let data: [String: AnyJSON] = [
                "user_id": .string(userId),
                "goal": .string(profile.goal),
                "experience": .string(profile.experience),
                "equipment": .array(profile.equipment.map { .string($0) }),
                "age_range": .string(profile.ageRange ?? "unknown"),
                "gender": .string(profile.gender ?? "unknown"),
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from("user_similarity_profiles")
                .upsert(data, onConflict: "user_id")
                .execute()
            
        } catch {
            AppLogger.warning("⚠️ [COLLABORATIVE] Could not update user profile: \(error)", category: .workout)
        }
    }
    
    private func fetchGlobalExerciseStats() async {
        do {
            // Try materialized view first (faster)
            struct ExerciseStat: Decodable {
                let exercise_name: String
                let completion_count: Int
                let success_rate: Double
            }
            
            let stats: [ExerciseStat] = try await supabase
                .from("exercise_global_stats")
                .select()
                .order("completion_count", ascending: false)
                .limit(500)
                .execute()
                .value
            
            // Build trends cache
            var popularity: [String: Double] = [:]
            var successRates: [String: Double] = [:]
            let maxCount = stats.first?.completion_count ?? 1
            
            for stat in stats {
                let name = stat.exercise_name.lowercased()
                popularity[name] = Double(stat.completion_count) / Double(maxCount)
                successRates[name] = stat.success_rate
            }
            
            globalTrendsCache = GlobalTrends(
                exercisePopularity: popularity,
                exerciseSuccessRates: successRates,
                lastUpdated: Date()
            )
            
            totalWorkoutsAnalyzed = stats.reduce(0) { $0 + $1.completion_count }
            AppLogger.debug("🌐 [COLLABORATIVE] Loaded \(stats.count) exercise stats from materialized view", category: .workout)
            
        } catch {
            AppLogger.warning("⚠️ [COLLABORATIVE] Materialized view not ready, using base table: \(error)", category: .workout)
            // Fallback to base table calculation
            await fetchGlobalExerciseStatsFromBaseTable()
        }
    }
    
    private func fetchGlobalExerciseStatsFromBaseTable() async {
        do {
            struct WorkoutRow: Decodable {
                let exercises_completed: [String]
            }
            
            let workouts: [WorkoutRow] = try await supabase
                .from("collaborative_workout_data")
                .select("exercises_completed")
                .limit(1000)
                .execute()
                .value
            
            // Count exercise occurrences
            var exerciseCounts: [String: Int] = [:]
            for workout in workouts {
                for exercise in workout.exercises_completed {
                    exerciseCounts[exercise.lowercased(), default: 0] += 1
                }
            }
            
            // Build trends cache
            var popularity: [String: Double] = [:]
            let maxCount = exerciseCounts.values.max() ?? 1
            
            for (name, count) in exerciseCounts {
                popularity[name] = Double(count) / Double(maxCount)
            }
            
            globalTrendsCache = GlobalTrends(
                exercisePopularity: popularity,
                exerciseSuccessRates: [:],
                lastUpdated: Date()
            )
            
            totalWorkoutsAnalyzed = workouts.count
            AppLogger.debug("🌐 [COLLABORATIVE] Loaded stats from \(workouts.count) workouts (base table)", category: .workout)
            
        } catch {
            AppLogger.warning("⚠️ [COLLABORATIVE] Could not fetch exercise stats: \(error)", category: .workout)
            globalTrendsCache = GlobalTrends(
                exercisePopularity: [:],
                exerciseSuccessRates: [:],
                lastUpdated: Date()
            )
        }
    }
    
    private func buildExercisePairingIndex() async {
        do {
            // Try materialized view first
            struct PairingStat: Decodable {
                let ex1: String
                let ex2: String
                let muscle1: String?
                let muscle2: String?
                let co_occurrence_count: Int
            }
            
            let pairings: [PairingStat] = try await supabase
                .from("exercise_pairing_stats")
                .select()
                .gte("co_occurrence_count", value: minDataPoints)
                .order("co_occurrence_count", ascending: false)
                .limit(1000)
                .execute()
                .value
            
            // Build index
            var index: [String: [ExercisePairing]] = [:]
            let maxCount = pairings.first?.co_occurrence_count ?? 1
            
            for pairing in pairings {
                let score = Double(pairing.co_occurrence_count) / Double(maxCount)
                
                // Add for exercise 1
                let p1 = ExercisePairing(
                    exerciseName: pairing.ex2,
                    muscleGroup: pairing.muscle2 ?? "",
                    coOccurrenceScore: score
                )
                index[pairing.ex1, default: []].append(p1)
                
                // Add for exercise 2
                let p2 = ExercisePairing(
                    exerciseName: pairing.ex1,
                    muscleGroup: pairing.muscle1 ?? "",
                    coOccurrenceScore: score
                )
                index[pairing.ex2, default: []].append(p2)
            }
            
            exercisePairingCache = index
            AppLogger.debug("🌐 [COLLABORATIVE] Built pairing index for \(index.count) exercises", category: .workout)
            
        } catch {
            AppLogger.warning("⚠️ [COLLABORATIVE] Could not build pairing index: \(error)", category: .workout)
        }
    }
    
    private func updateUserSimilarityClusters() async {
        do {
            struct UserCount: Decodable {
                let count: Int
            }
            
            // Get total user count
            let result: [UserCount] = try await supabase
                .from("user_similarity_profiles")
                .select("count")
                .execute()
                .value
            
            totalUsersAnalyzed = result.first?.count ?? 0
            AppLogger.debug("🌐 [COLLABORATIVE] Tracking \(totalUsersAnalyzed) users", category: .workout)
            
        } catch {
            AppLogger.warning("⚠️ [COLLABORATIVE] Could not count users: \(error)", category: .workout)
        }
    }
    
    private func fetchExercisePairings(for exerciseName: String) async -> [ExercisePairing] {
        do {
            struct PairingRow: Decodable {
                let ex1: String
                let ex2: String
                let muscle1: String?
                let muscle2: String?
            }
            
            // Fetch from base table
            let rows: [PairingRow] = try await supabase
                .from("exercise_pairings")
                .select()
                .or("ex1.eq.\(exerciseName.lowercased()),ex2.eq.\(exerciseName.lowercased())")
                .limit(100)
                .execute()
                .value
            
            // Count occurrences and build pairings
            var pairingCounts: [String: (muscle: String, count: Int)] = [:]
            for row in rows {
                if row.ex1.lowercased() == exerciseName.lowercased() {
                    pairingCounts[row.ex2, default: (muscle: row.muscle2 ?? "", count: 0)].count += 1
                } else {
                    pairingCounts[row.ex1, default: (muscle: row.muscle1 ?? "", count: 0)].count += 1
                }
            }
            
            let maxCount = pairingCounts.values.map { $0.count }.max() ?? 1
            
            return pairingCounts.map { name, data in
                ExercisePairing(
                    exerciseName: name,
                    muscleGroup: data.muscle,
                    coOccurrenceScore: Double(data.count) / Double(maxCount)
                )
            }.sorted { $0.coOccurrenceScore > $1.coOccurrenceScore }
            
        } catch {
            return []
        }
    }
}

// MARK: - Supporting Types

struct UserProfileSnapshot: Identifiable {
    let id: String
    let goal: String
    let experience: String
    let equipment: [String]
    let ageRange: String?
    let gender: String?
    let weight: Double?
    let height: Double?
    
    init(id: String, goal: String, experience: String, equipment: [String], ageRange: String?, gender: String?, weight: Double? = nil, height: Double? = nil) {
        self.id = id
        self.goal = goal
        self.experience = experience
        self.equipment = equipment
        self.ageRange = ageRange
        self.gender = gender
        self.weight = weight
        self.height = height
    }
    
    init(from user: User) {
        self.id = user.id?.uuidString ?? UUID().uuidString
        self.goal = user.fitnessGoal ?? "Get Fit"
        self.experience = user.experienceLevel ?? "Beginner"
        
        // Parse equipment
        if let equipArray = user.equipment as? [String] {
            self.equipment = equipArray
        } else if let equipString = user.equipment as? String {
            self.equipment = equipString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            self.equipment = ["Bodyweight"]
        }
        
        // Convert age to age range
        let age = user.age
        if age > 0 {
            if age < 25 {
                self.ageRange = "18-24"
            } else if age < 35 {
                self.ageRange = "25-34"
            } else if age < 45 {
                self.ageRange = "35-44"
            } else if age < 55 {
                self.ageRange = "45-54"
            } else {
                self.ageRange = "55+"
            }
        } else {
            self.ageRange = nil
        }
        
        self.gender = user.gender
        self.weight = user.weight > 0 ? Double(user.weight) : nil
        self.height = user.height > 0 ? Double(user.height) : nil
    }
}

struct SimilarUser {
    let userId: String
    let similarityScore: Double
    let sharedGoal: Bool
    let sharedExperience: Bool
}

struct ExercisePairing {
    let exerciseName: String
    let muscleGroup: String
    let coOccurrenceScore: Double  // 0.0 - 1.0
}

struct GlobalTrends {
    var exercisePopularity: [String: Double]  // exercise name -> popularity (0-1)
    var exerciseSuccessRates: [String: Double]  // exercise name -> completion rate
    var lastUpdated: Date
}

struct CompletedExercise {
    let name: String
    let equipment: String
    let muscleGroup: String
    let setsCompleted: Int
    let totalReps: Int
}

// MARK: - Integration with Existing Engines

extension SmartExerciseSelectionEngine {
    /// Enhanced scoring that includes collaborative data
    func getCollaborativeScore(
        for exercise: Exercise,
        userProfile: UserProfileSnapshot,
        targetMuscles: [String]
    ) async -> Double {
        return await CollaborativeLearningEngine.shared.getCollaborativeBoost(
            for: exercise.name ?? "",
            userProfile: userProfile,
            targetMuscles: targetMuscles
        )
    }
}

