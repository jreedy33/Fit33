//
//  UserBehaviorLearningEngine.swift
//  BuiltSimple
//
//  A sophisticated machine learning-inspired engine that learns user preferences
//  from their workout behavior over time. The more the user works out, the smarter
//  the recommendations become.
//
//  Features:
//  - Persists to Supabase for cross-device sync
//  - Exercise similarity scoring (recommends similar variations)
//  - Equipment preference learning (dumbbell lover? more dumbbells!)
//  - Freshness factor (still includes variety and new exercises)
//  - Movement pattern tracking (push, pull, squat, hinge, etc.)
//

import Foundation
import CoreData
import QuartzCore
import Supabase

// MARK: - Thread-safe cache storage for scoring functions
// This allows nonisolated access from workout generators
final class LearningCacheStorage: @unchecked Sendable {
    static let shared = LearningCacheStorage()
    
    private let lock = NSLock()
    
    private var _userPreferences: UserBehaviorProfile?
    private var _exerciseAffinityCache: [String: Double] = [:]
    private var _equipmentAffinityCache: [String: Double] = [:]
    private var _muscleGroupAffinityCache: [String: Double] = [:]
    private var _categoryAffinityCache: [String: Double] = [:]
    private var _movementPatternCache: [String: Double] = [:]
    private var _exerciseVariationCache: [String: Set<String>] = [:]
    
    private init() {}
    
    var userPreferences: UserBehaviorProfile? {
        get { lock.withLock { _userPreferences } }
        set { lock.withLock { _userPreferences = newValue } }
    }
    var exerciseAffinityCache: [String: Double] {
        get { lock.withLock { _exerciseAffinityCache } }
        set { lock.withLock { _exerciseAffinityCache = newValue } }
    }
    var equipmentAffinityCache: [String: Double] {
        get { lock.withLock { _equipmentAffinityCache } }
        set { lock.withLock { _equipmentAffinityCache = newValue } }
    }
    var muscleGroupAffinityCache: [String: Double] {
        get { lock.withLock { _muscleGroupAffinityCache } }
        set { lock.withLock { _muscleGroupAffinityCache = newValue } }
    }
    var categoryAffinityCache: [String: Double] {
        get { lock.withLock { _categoryAffinityCache } }
        set { lock.withLock { _categoryAffinityCache = newValue } }
    }
    var movementPatternCache: [String: Double] {
        get { lock.withLock { _movementPatternCache } }
        set { lock.withLock { _movementPatternCache = newValue } }
    }
    var exerciseVariationCache: [String: Set<String>] {
        get { lock.withLock { _exerciseVariationCache } }
        set { lock.withLock { _exerciseVariationCache = newValue } }
    }
}

// MARK: - User Behavior Learning Engine

@MainActor
class UserBehaviorLearningEngine: ObservableObject {
    static let shared = UserBehaviorLearningEngine()
    
    // MARK: - Published Properties
    @Published private(set) var userPreferences: UserBehaviorProfile? {
        didSet { LearningCacheStorage.shared.userPreferences = userPreferences }
    }
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastAnalysisDate: Date?
    @Published private(set) var isSyncing = false
    
    // Reference to shared cache storage for convenience
    private var cacheStorage: LearningCacheStorage { LearningCacheStorage.shared }
    
    // MARK: - Constants
    private let recentWorkoutDays: Int = 90 // Consider last 90 days
    private let minSetsForFullCredit: Int = 3 // Exercises with 3+ sets get full credit
    private let recencyDecayFactor: Double = 0.95 // Recent workouts weighted more
    private let freshnessBonus: Double = 45.0 // Increased bonus for exercises user hasn't done recently (more variety)
    private let similarityBoostMax: Double = 100.0 // Max boost for similar exercises
    
    private var supabase: SupabaseClient {
        SupabaseManager.shared.supabaseClient
    }
    
    private init() {
        print("🧠 [LEARNING ENGINE] Initialized")
        
        // Load cached preferences from UserDefaults immediately
        loadCachedPreferences()
    }
    
    // MARK: - Local Cache Persistence (Immediate)
    
    private func loadCachedPreferences() {
        if let data = UserDefaults.standard.data(forKey: "userBehaviorProfile"),
           let profile = try? JSONDecoder().decode(UserBehaviorProfile.self, from: data) {
            self.userPreferences = profile
            updateCaches(from: profile)
            print("🧠 [LEARNING ENGINE] Loaded cached preferences (\(profile.totalWorkoutsAnalyzed) workouts)")
        }
    }
    
    private func saveCachedPreferences() {
        guard let profile = userPreferences else { return }
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "userBehaviorProfile")
            print("🧠 [LEARNING ENGINE] Saved preferences to local cache")
        }
    }
    
    // MARK: - 🆕 Smart Swap & Selection Recording
    
    /// Record when a user swaps out an exercise
    /// Call this when user replaces/swaps an exercise in a workout
    func recordExerciseSwap(from originalExercise: String, to newExercise: String) {
        let nameLower = originalExercise.lowercased()
        let newNameLower = newExercise.lowercased()
        
        guard var profile = userPreferences else {
            print("⚠️ [LEARNING] No profile to record swap")
            return
        }
        
        // Update or create swap data
        var swapData = profile.swapHistory[nameLower] ?? ExerciseSwapData()
        swapData.swapCount += 1
        swapData.lastSwappedDate = Date()
        swapData.swappedTo[newNameLower] = (swapData.swappedTo[newNameLower] ?? 0) + 1
        
        profile.swapHistory[nameLower] = swapData
        profile.lastUpdated = Date()
        
        // Also track what they swapped TO as an explicit selection
        profile.explicitlySelectedExercises.insert(newNameLower)
        
        self.userPreferences = profile
        saveCachedPreferences()
        
        // 🌟 Update progressive unlock service about the swap
        Task { @MainActor in
            ProgressiveExerciseUnlockService.shared.recordSwap(exerciseName: originalExercise)
        }
        
        #if DEBUG
        print("🔄 [LEARNING] Recorded swap: '\(originalExercise)' → '\(newExercise)' (total swaps: \(swapData.swapCount))")
        if swapData.swapCount >= 3 {
            print("   ⚠️ Exercise '\(originalExercise)' has been swapped \(swapData.swapCount)x - reducing recommendations")
        }
        #endif
    }
    
    /// Record when user adds an exercise to a custom workout
    /// This signals they explicitly want exercises like this
    func recordCustomWorkoutAddition(exerciseName: String) {
        let nameLower = exerciseName.lowercased()
        
        guard var profile = userPreferences else { return }
        
        // Add to custom additions (keep last 20)
        var additions = profile.customWorkoutAdditions
        additions.insert(nameLower, at: 0)
        if additions.count > 20 {
            additions = Array(additions.prefix(20))
        }
        profile.customWorkoutAdditions = additions
        
        // Also mark as explicitly selected
        profile.explicitlySelectedExercises.insert(nameLower)
        profile.lastUpdated = Date()
        
        self.userPreferences = profile
        saveCachedPreferences()
        
        #if DEBUG
        print("➕ [LEARNING] Recorded custom workout addition: '\(exerciseName)' - will recommend similar exercises")
        #endif
    }
    
    /// Record when user explicitly selects/chooses an exercise (from library, search, etc.)
    func recordExplicitSelection(exerciseName: String) {
        let nameLower = exerciseName.lowercased()
        
        guard var profile = userPreferences else { return }
        
        profile.explicitlySelectedExercises.insert(nameLower)
        profile.lastUpdated = Date()
        
        self.userPreferences = profile
        saveCachedPreferences()
        
        #if DEBUG
        print("✅ [LEARNING] Recorded explicit selection: '\(exerciseName)'")
        #endif
    }
    
    /// Get suggested replacements when user wants to swap (based on what they've swapped TO before)
    func getSuggestedReplacements(for exerciseName: String) -> [String] {
        guard let swapData = userPreferences?.swapHistory[exerciseName.lowercased()] else { return [] }
        
        // Return exercises they've swapped to before, sorted by frequency
        return swapData.swappedTo
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
    
    // MARK: - Main Analysis Entry Point
    
    /// 🔒 Track in-flight analysis to prevent duplicates
    private static var analysisTask: Task<UserBehaviorProfile, Never>?
    private static var lastAnalysisStart: Date?
    private static let minAnalysisInterval: TimeInterval = 60 // Min 60 seconds between full analyses
    
    /// Analyze user's complete workout history to build preference profile
    /// ⚡️ PERFORMANCE: Now runs heavy work on background thread with deduplication and CPU protection
    func analyzeUserBehavior(context: NSManagedObjectContext) async -> UserBehaviorProfile {
        // 🛡️ Return cached if we have recent analysis
        if let existing = userPreferences,
           let lastStart = UserBehaviorLearningEngine.lastAnalysisStart,
           Date().timeIntervalSince(lastStart) < UserBehaviorLearningEngine.minAnalysisInterval {
            print("⚡️ [LEARNING ENGINE] Using cached profile (analyzed \(Int(Date().timeIntervalSince(lastStart)))s ago)")
            return existing
        }
        
        // 🛡️ Skip if CPU is critical (> 200%)
        if CPUProtection.shared.isCPUCritical() {
            print("⚠️ [LEARNING ENGINE] Skipping analysis - CPU critical")
            return userPreferences ?? UserBehaviorProfile.empty
        }
        
        // 🛡️ Reuse in-flight analysis
        if let existingTask = UserBehaviorLearningEngine.analysisTask {
            print("⚡️ [LEARNING ENGINE] Reusing in-flight analysis")
            return await existingTask.value
        }
        
        // 🔴 Wait for CPU to settle before heavy analysis
        await CPUProtection.shared.waitForCPUSettled(maxWait: 3.0)
        
        UserBehaviorLearningEngine.lastAnalysisStart = Date()
        
        // Create analysis task
        let task = Task<UserBehaviorProfile, Never> { [weak self] in
            guard let self = self else {
                return UserBehaviorProfile.empty
            }
            
            await MainActor.run { self.isAnalyzing = true }
            defer { 
                Task { @MainActor in 
                    self.isAnalyzing = false 
                    UserBehaviorLearningEngine.analysisTask = nil
                }
            }
            
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🧠 [LEARNING ENGINE] Starting comprehensive behavior analysis...")
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Try to load from cloud first (for cross-device sync)
            if let cloudProfile = await self.loadFromCloud() {
                print("🧠 [LEARNING ENGINE] Loaded profile from cloud (\(cloudProfile.totalWorkoutsAnalyzed) workouts)")
                await MainActor.run {
                    self.userPreferences = cloudProfile
                }
                self.updateCaches(from: cloudProfile)
                self.saveCachedPreferences()
            }
            
            // ⚡️ PERFORMANCE: Yield to let UI breathe
            await Task.yield()
            
            // Fetch completed workouts
            let workouts = await self.fetchCompletedWorkouts(context: context)
            print("🧠 [LEARNING ENGINE] Analyzing \(workouts.count) completed workouts")
            
            // ⚡️ PERFORMANCE: Yield between heavy operations
            await Task.yield()
            
            // Fetch favorited exercises
            let favoritedExercises = await self.fetchFavoritedExercises(context: context)
            print("🧠 [LEARNING ENGINE] Found \(favoritedExercises.count) favorited exercises")
            
            // Fetch favorited workouts
            let favoritedWorkouts = await self.fetchFavoritedWorkouts(context: context)
            print("🧠 [LEARNING ENGINE] Found \(favoritedWorkouts.count) favorited workout routines")
            
            // Fetch program day completions from cloud (for comprehensive learning)
            let programCompletions = await self.fetchProgramCompletions()
            print("🧠 [LEARNING ENGINE] Found \(programCompletions.count) program day completions")
            
            // ⚡️ PERFORMANCE: Yield before heavy profile building
            await Task.yield()
            
            // Build comprehensive profile
            let profile = await self.buildUserProfile(
                workouts: workouts,
                favoritedExercises: favoritedExercises,
                favoritedWorkouts: favoritedWorkouts,
                programCompletions: programCompletions,
                context: context
            )
            
            // Update caches
            self.updateCaches(from: profile)
            
            // ⚡️ PERFORMANCE: Defer similarity map to background
            // Pre-extract exercise data on main thread (Core Data objects aren't thread-safe)
            let exerciseData: [(name: String, muscles: String, equipment: String)] = ExerciseLibraryService.shared.getAllExercises().compactMap { exercise in
                guard let name = exercise.name?.lowercased() else { return nil }
                let muscles = (exercise.muscleGroups as? [String])?.first?.lowercased() ?? ""
                let equipment = exercise.equipment ?? ""
                return (name: name, muscles: muscles, equipment: equipment)
            }
            
            // Use Task.detached to truly run off @MainActor
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                self.buildExerciseSimilarityMapBackground(exerciseData)
            }
            
            await MainActor.run {
                self.userPreferences = profile
                self.lastAnalysisDate = Date()
            }
            
            // Save to local cache
            self.saveCachedPreferences()
            
            // Sync to cloud in background (low priority)
            Task(priority: .background) {
                await self.saveToCloud(profile)
            }
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("🧠 [LEARNING ENGINE] Analysis complete in \(String(format: "%.0f", elapsed))ms")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            // 🌟 Also trigger progressive unlock service analysis (deferred)
            Task(priority: .utility) { @MainActor in
                _ = await ProgressiveExerciseUnlockService.shared.analyzeUserMaturity(context: context)
            }
            
            return profile
        }
        
        UserBehaviorLearningEngine.analysisTask = task
        return await task.value
    }
    
    // MARK: - Cloud Persistence
    
    private func loadFromCloud() async -> UserBehaviorProfile? {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return nil }
        
        do {
            struct CloudProfile: Decodable {
                let user_id: String
                let exercise_affinities: [String: Double]
                let equipment_preferences: [String: Double]
                let muscle_preferences: [String: Double]
                let category_preferences: [String: Double]
                let movement_patterns: [String: Double]
                let exercise_completion_counts: [String: Int]
                let full_set_exercises: [String]
                let favorited_exercises: [String]
                let preferred_duration: Int
                let preferred_time: String
                let total_workouts: Int
                let last_updated: String
            }
            
            let response: [CloudProfile] = try await supabase
                .from("user_learning_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            
            guard let cloud = response.first else { return nil }
            
            return UserBehaviorProfile(
                exerciseAffinityScores: cloud.exercise_affinities,
                equipmentPreferences: cloud.equipment_preferences,
                muscleGroupPreferences: cloud.muscle_preferences,
                categoryPreferences: cloud.category_preferences,
                movementPatternPreferences: cloud.movement_patterns,
                exerciseCompletionCounts: cloud.exercise_completion_counts,
                fullSetExercises: Set(cloud.full_set_exercises),
                favoritedExerciseNames: Set(cloud.favorited_exercises),
                recentlyDoneExercises: [],
                preferredWorkoutDuration: cloud.preferred_duration,
                preferredTimeOfDay: cloud.preferred_time,
                totalWorkoutsAnalyzed: cloud.total_workouts,
                insights: [],
                lastUpdated: ISO8601DateFormatter().date(from: cloud.last_updated) ?? Date(),
                swapHistory: [:],  // Will be loaded separately or merged
                customWorkoutAdditions: [],
                explicitlySelectedExercises: []
            )
        } catch {
            print("⚠️ [LEARNING ENGINE] Could not load from cloud: \(error)")
            return nil
        }
    }
    
    /// Fetches program day completions to enhance learning
    private func fetchProgramCompletions() async -> [(exercises: [String], muscles: [String], date: Date)] {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return [] }
        
        do {
            struct ProgramDayCompletion: Decodable {
                let exercises_completed: [String]?
                let focus_muscles: [String]?
                let completed_at: String
            }
            
            let response: [ProgramDayCompletion] = try await supabase
                .from("program_day_completions")
                .select("exercises_completed, focus_muscles, completed_at")
                .eq("user_id", value: userId.uuidString)
                .order("completed_at", ascending: false)
                .limit(100)  // Last 100 program days
                .execute()
                .value
            
            print("🧠 [LEARNING ENGINE] Fetched \(response.count) program day completions from cloud")
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            
            return response.compactMap { completion in
                let date = formatter.date(from: completion.completed_at) 
                    ?? fallbackFormatter.date(from: completion.completed_at)
                    ?? Date()
                return (
                    exercises: completion.exercises_completed ?? [],
                    muscles: completion.focus_muscles ?? [],
                    date: date
                )
            }
        } catch {
            print("⚠️ [LEARNING ENGINE] Could not fetch program completions: \(error)")
            return []
        }
    }
    
    private func saveToCloud(_ profile: UserBehaviorProfile) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [LEARNING ENGINE] Not authenticated, skipping cloud save")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let data: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "exercise_affinities": .object(profile.exerciseAffinityScores.mapValues { .double($0) }),
                "equipment_preferences": .object(profile.equipmentPreferences.mapValues { .double($0) }),
                "muscle_preferences": .object(profile.muscleGroupPreferences.mapValues { .double($0) }),
                "category_preferences": .object(profile.categoryPreferences.mapValues { .double($0) }),
                "movement_patterns": .object(profile.movementPatternPreferences.mapValues { .double($0) }),
                "exercise_completion_counts": .object(profile.exerciseCompletionCounts.mapValues { .integer($0) }),
                "full_set_exercises": .array(Array(profile.fullSetExercises).map { .string($0) }),
                "favorited_exercises": .array(Array(profile.favoritedExerciseNames).map { .string($0) }),
                "preferred_duration": .integer(profile.preferredWorkoutDuration),
                "preferred_time": .string(profile.preferredTimeOfDay),
                "total_workouts": .integer(profile.totalWorkoutsAnalyzed),
                "last_updated": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from("user_learning_profiles")
                .upsert(data, onConflict: "user_id")
                .execute()
            
            print("☁️ [LEARNING ENGINE] Profile saved to cloud successfully")
        } catch {
            print("❌ [LEARNING ENGINE] Failed to save to cloud: \(error)")
        }
    }
    
    // MARK: - Exercise Similarity Map
    
    /// Builds similarity map on a BACKGROUND thread using pre-extracted data.
    /// This was previously blocking the main thread for ~6 seconds with 5500+ exercises.
    nonisolated private func buildExerciseSimilarityMapBackground(_ exerciseData: [(name: String, muscles: String, equipment: String)]) {
        let startTime = CACurrentMediaTime()
        
        // Group exercises by movement pattern and muscle+equipment
        var byPattern: [String: [String]] = [:]
        var byMuscleEquipment: [String: [String]] = [:]
        
        for data in exerciseData {
            let pattern = getMovementPattern(data.name)
            let normalizedEquip = normalizeEquipmentSync(data.equipment)
            
            byPattern[pattern, default: []].append(data.name)
            
            let muscleKey = "\(data.muscles)_\(getEquipmentCategory(normalizedEquip))"
            byMuscleEquipment[muscleKey, default: []].append(data.name)
        }
        
        // Build similarity sets — optimized: create group Set once, then subtract
        var variationCache: [String: Set<String>] = [:]
        variationCache.reserveCapacity(exerciseData.count)
        
        for (_, exercises) in byPattern {
            guard exercises.count > 1, exercises.count < 500 else { continue } // Skip huge/trivial groups
            let groupSet = Set(exercises)
            for exercise in exercises {
                var similar = groupSet
                similar.remove(exercise)
                variationCache[exercise, default: []].formUnion(similar)
            }
        }
        
        for (_, exercises) in byMuscleEquipment {
            guard exercises.count > 1, exercises.count < 500 else { continue } // Skip huge/trivial groups
            let groupSet = Set(exercises)
            for exercise in exercises {
                var similar = groupSet
                similar.remove(exercise)
                variationCache[exercise, default: []].formUnion(similar)
            }
        }
        
        // Assign to shared cache atomically
        LearningCacheStorage.shared.exerciseVariationCache = variationCache
        
        let elapsedMs = (CACurrentMediaTime() - startTime) * 1000
        print("🧠 [LEARNING ENGINE] Built similarity map for \(variationCache.count) exercises in \(String(format: "%.0f", elapsedMs))ms (background thread)")
    }
    
    /// Get similar exercises based on movement pattern and muscle group
    nonisolated func getSimilarExercises(to exerciseName: String) -> Set<String> {
        return LearningCacheStorage.shared.exerciseVariationCache[exerciseName.lowercased()] ?? []
    }
    
    /// Quick refresh after a workout completes (incremental update)
    func refreshAfterWorkout(_ workout: Workout, context: NSManagedObjectContext) async {
        print("🧠 [LEARNING ENGINE] Quick refresh after workout: \(workout.name ?? "Unknown")")
        
        // 🌟 Also update progressive unlock service
        let exerciseNames = extractExerciseData(from: workout).map { $0.name }
        await ProgressiveExerciseUnlockService.shared.recordWorkoutCompletion(exerciseNames: exerciseNames)
        
        guard var profile = userPreferences else {
            // No existing profile, do full analysis
            _ = await analyzeUserBehavior(context: context)
            return
        }
        
        // Incrementally update based on this workout
        let exerciseData = extractExerciseData(from: workout)
        
        for data in exerciseData {
            // Update exercise affinity
            let existingAffinity = profile.exerciseAffinityScores[data.name.lowercased()] ?? 0
            let newAffinity = min(1.0, existingAffinity + (data.completedSets >= 3 ? 0.1 : 0.05))
            profile.exerciseAffinityScores[data.name.lowercased()] = newAffinity
            
            // Update equipment affinity
            let equipNormalized = data.equipment.lowercased()
            let existingEquipAffinity = profile.equipmentPreferences[equipNormalized] ?? 0
            profile.equipmentPreferences[equipNormalized] = min(1.0, existingEquipAffinity + 0.05)
            
            // Update muscle group affinity
            for muscle in data.muscleGroups {
                let muscleNormalized = muscle.lowercased()
                let existingMuscleAffinity = profile.muscleGroupPreferences[muscleNormalized] ?? 0
                profile.muscleGroupPreferences[muscleNormalized] = min(1.0, existingMuscleAffinity + 0.05)
            }
        }
        
        // Update workout count
        profile.totalWorkoutsAnalyzed += 1
        profile.lastUpdated = Date()
        
        self.userPreferences = profile
        updateCaches(from: profile)
        
        print("🧠 [LEARNING ENGINE] Profile updated incrementally")
    }
    
    // MARK: - Scoring Functions for Workout Generation
    // These are nonisolated so they can be called from any context (sync or async)
    // They access the shared LearningCacheStorage which is thread-safe
    
    /// Get the learned affinity score for a specific exercise (0.0 - 1.0)
    nonisolated func getExerciseAffinity(_ exerciseName: String) -> Double {
        return LearningCacheStorage.shared.exerciseAffinityCache[exerciseName.lowercased()] ?? 0.0
    }
    
    /// Get the learned affinity score for equipment type (0.0 - 1.0)
    nonisolated func getEquipmentAffinity(_ equipment: String) -> Double {
        let normalized = normalizeEquipmentSync(equipment)
        return LearningCacheStorage.shared.equipmentAffinityCache[normalized] ?? 0.0
    }
    
    /// Get the learned affinity score for a muscle group (0.0 - 1.0)
    nonisolated func getMuscleGroupAffinity(_ muscleGroup: String) -> Double {
        return LearningCacheStorage.shared.muscleGroupAffinityCache[muscleGroup.lowercased()] ?? 0.0
    }
    
    /// Get the learned affinity score for an exercise category (0.0 - 1.0)
    nonisolated func getCategoryAffinity(_ category: String) -> Double {
        return LearningCacheStorage.shared.categoryAffinityCache[category.lowercased()] ?? 0.0
    }
    
    /// Get the learned affinity for a movement pattern (0.0 - 1.0)
    nonisolated func getMovementPatternAffinity(_ pattern: String) -> Double {
        return LearningCacheStorage.shared.movementPatternCache[pattern.lowercased()] ?? 0.0
    }
    
    /// Calculate comprehensive boost score for an exercise based on all learned preferences
    /// This is the main scoring function used by workout generators
    nonisolated func calculateLearnedBoostScore(
        exerciseName: String,
        equipment: String,
        muscleGroups: [String],
        category: String
    ) -> Double {
        let nameLower = exerciseName.lowercased()
        var boost: Double = 0
        
        // ═══════════════════════════════════════════════════════════════
        // DIRECT EXERCISE AFFINITY (user has done this exact exercise)
        // ═══════════════════════════════════════════════════════════════
        let exerciseAffinity = getExerciseAffinity(nameLower)
        boost += exerciseAffinity * 120 // Up to 120 points for exercises user has done
        
        // ═══════════════════════════════════════════════════════════════
        // SIMILAR EXERCISE BOOST (user did incline dumbbell → boost decline dumbbell)
        // This is key for smart recommendations!
        // ═══════════════════════════════════════════════════════════════
        let similarExercises = getSimilarExercises(to: nameLower)
        var maxSimilarityBoost: Double = 0
        
        for similar in similarExercises {
            let similarAffinity = getExerciseAffinity(similar)
            if similarAffinity > 0 {
                // Calculate similarity score based on shared characteristics
                let similarityScore = calculateSimilarityScore(nameLower, to: similar, equipment: equipment)
                let potentialBoost = similarAffinity * similarityScore * similarityBoostMax
                maxSimilarityBoost = max(maxSimilarityBoost, potentialBoost)
            }
        }
        boost += maxSimilarityBoost
        
        #if DEBUG
        if maxSimilarityBoost > 30 {
            print("   🔗 Similar exercise boost: \(exerciseName) (+\(Int(maxSimilarityBoost)))")
        }
        #endif
        
        // ═══════════════════════════════════════════════════════════════
        // EQUIPMENT PREFERENCE (user prefers dumbbells → boost dumbbell exercises)
        // ═══════════════════════════════════════════════════════════════
        let equipmentAffinity = getEquipmentAffinity(equipment)
        boost += equipmentAffinity * 80 // Up to 80 points
        
        // Extra boost for matching equipment category (free weights vs machines)
        let equipmentCategory = getEquipmentCategory(normalizeEquipmentSync(equipment))
        let categoryBoost = getEquipmentCategoryAffinity(equipmentCategory) * 40
        boost += categoryBoost
        
        // ═══════════════════════════════════════════════════════════════
        // MOVEMENT PATTERN PREFERENCE (user likes pressing → boost presses)
        // ═══════════════════════════════════════════════════════════════
        let pattern = getMovementPattern(nameLower)
        let patternAffinity = getMovementPatternAffinity(pattern)
        boost += patternAffinity * 50 // Up to 50 points
        
        // ═══════════════════════════════════════════════════════════════
        // MUSCLE GROUP AFFINITY
        // ═══════════════════════════════════════════════════════════════
        let muscleAffinities = muscleGroups.map { getMuscleGroupAffinity($0) }
        let avgMuscleAffinity = muscleAffinities.isEmpty ? 0 : muscleAffinities.reduce(0, +) / Double(muscleAffinities.count)
        boost += avgMuscleAffinity * 50 // Up to 50 points
        
        // ═══════════════════════════════════════════════════════════════
        // FRESHNESS & VARIETY (encourage trying new things, penalize repetition)
        // ═══════════════════════════════════════════════════════════════
        let isRecentlyDone = LearningCacheStorage.shared.userPreferences?.recentlyDoneExercises.contains(nameLower) ?? false
        
        if isRecentlyDone {
            // PENALTY for exercises done in recent workouts - encourages variety
            boost -= 35  // Stronger penalty to encourage trying different exercises
        } else if exerciseAffinity < 0.1 {
            // BONUS for exercises user hasn't done much - adds freshness
            boost += freshnessBonus
            
            // Extra bonus if it's a fresh exercise using preferred equipment
            if equipmentAffinity > 0.5 {
                boost += 25 // "Try this new exercise with your favorite equipment!"
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // RANDOM DISCOVERY FACTOR (occasionally boost completely new exercises)
        // ═══════════════════════════════════════════════════════════════
        if exerciseAffinity == 0 && Double.random(in: 0...1) < 0.15 {
            boost += 25 // 15% chance to boost a completely new exercise
        }
        
        // ═══════════════════════════════════════════════════════════════
        // 🆕 SWAP HISTORY PENALTY (reduce score if user frequently swaps this out)
        // ═══════════════════════════════════════════════════════════════
        let swapPenalty = getSwapPenalty(for: nameLower)
        boost -= swapPenalty
        
        // ═══════════════════════════════════════════════════════════════
        // 🆕 CUSTOM WORKOUT BOOST (if user added similar exercises to custom workouts)
        // ═══════════════════════════════════════════════════════════════
        let customBoost = getCustomWorkoutBoost(for: nameLower, muscleGroups: muscleGroups, equipment: equipment)
        boost += customBoost
        
        // ═══════════════════════════════════════════════════════════════
        // 🆕 EXPLICIT SELECTION BOOST (user chose this exercise before)
        // ═══════════════════════════════════════════════════════════════
        if LearningCacheStorage.shared.userPreferences?.explicitlySelectedExercises.contains(nameLower) == true {
            boost += 40 // Strong boost for exercises user explicitly picked
        }
        
        return boost
    }
    
    // MARK: - 🆕 Smart Swap & Selection Tracking (nonisolated)
    
    /// Get penalty for exercises that are frequently swapped (0 = no penalty, up to 60 for heavily swapped)
    /// Accessible from any isolation context via LearningCacheStorage (thread-safe)
    nonisolated static func swapPenalty(for exerciseName: String) -> Double {
        return _computeSwapPenalty(for: exerciseName.lowercased())
    }
    
    nonisolated private func getSwapPenalty(for exerciseName: String) -> Double {
        return Self._computeSwapPenalty(for: exerciseName)
    }
    
    nonisolated private static func _computeSwapPenalty(for exerciseName: String) -> Double {
        guard let swapData = LearningCacheStorage.shared.userPreferences?.swapHistory[exerciseName] else { return 0 }
        
        // No penalty for 1-2 swaps (maybe equipment was busy)
        if swapData.swapCount <= 2 { return 0 }
        
        // Gradual penalty: 3 swaps = -15, 4 = -30, 5+ = -45 to -60
        let penalty: Double
        switch swapData.swapCount {
        case 3: penalty = 15
        case 4: penalty = 30
        case 5: penalty = 45
        default: penalty = min(60, Double(swapData.swapCount) * 10) // Cap at 60
        }
        
        // Decay penalty over time (if they haven't swapped recently, reduce penalty)
        let daysSinceSwap = Calendar.current.dateComponents([.day], from: swapData.lastSwappedDate, to: Date()).day ?? 0
        let decayFactor = max(0.3, 1.0 - Double(daysSinceSwap) / 60.0) // Decays over 60 days
        
        return penalty * decayFactor
    }
    
    /// Get boost for exercises similar to what user added to custom workouts
    nonisolated private func getCustomWorkoutBoost(for exerciseName: String, muscleGroups: [String], equipment: String) -> Double {
        guard let customAdditions = LearningCacheStorage.shared.userPreferences?.customWorkoutAdditions, !customAdditions.isEmpty else { return 0 }
        
        // If this exact exercise was added, big boost
        if customAdditions.contains(exerciseName.lowercased()) {
            return 50
        }
        
        // Check similarity to custom-added exercises
        var similarityBoost: Double = 0
        for addedExercise in customAdditions.prefix(10) { // Limit to recent 10
            let similarity = calculateSimilarityScore(exerciseName, to: addedExercise, equipment: equipment)
            if similarity > 0.5 {
                similarityBoost += 15 * similarity // Up to +15 per similar exercise
            }
        }
        
        return min(35, similarityBoost) // Cap total boost at 35
    }
    
    // MARK: - Similarity Scoring (nonisolated for sync access)
    
    /// Calculate how similar two exercises are (0.0 - 1.0)
    /// Enhanced scoring based on movement pattern, equipment, and exercise type
    nonisolated private func calculateSimilarityScore(_ exercise1: String, to exercise2: String, equipment: String) -> Double {
        var score: Double = 0.2 // Base similarity for being in same group
        
        let name1 = exercise1.lowercased()
        let name2 = exercise2.lowercased()
        
        // ═══════════════════════════════════════════════════════════════
        // MOVEMENT PATTERN MATCH (Very Important - +0.3)
        // ═══════════════════════════════════════════════════════════════
        let pattern1 = getMovementPattern(exercise1)
        let pattern2 = getMovementPattern(exercise2)
        if pattern1 == pattern2 && pattern1 != "other" {
            score += 0.3
        }
        
        // ═══════════════════════════════════════════════════════════════
        // EQUIPMENT CATEGORY MATCH (+0.2)
        // ═══════════════════════════════════════════════════════════════
        let equip1 = normalizeEquipmentSync(equipment)
        let category1 = getEquipmentCategory(equip1)
        
        // Infer equipment from exercise name and check category match
        let inferredCategory2: String
        if name2.contains("dumbbell") {
            inferredCategory2 = "freeweights"
        } else if name2.contains("barbell") || name2.contains("ez bar") {
            inferredCategory2 = "freeweights"
        } else if name2.contains("cable") {
            inferredCategory2 = "cables"
        } else if name2.contains("machine") || name2.contains("lever") || name2.contains("smith") {
            inferredCategory2 = "machines"
        } else if name2.contains("band") {
            inferredCategory2 = "bands"
        } else {
            inferredCategory2 = "bodyweight"
        }
        
        if category1 == inferredCategory2 {
            score += 0.2
        } else if (category1 == "freeweights" && inferredCategory2 == "freeweights") {
            // Same free weights category gets full bonus
            score += 0.2
        }
        
        // ═══════════════════════════════════════════════════════════════
        // MOVEMENT KEYWORD MATCH (+0.2)
        // ═══════════════════════════════════════════════════════════════
        let movements = ["press", "row", "curl", "fly", "raise", "extension", "squat", "deadlift", "lunge", "pulldown", "pushdown", "dip", "shrug"]
        for movement in movements {
            if name1.contains(movement) && name2.contains(movement) {
                score += 0.2
                break
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // BODY POSITION MATCH (+0.1)
        // ═══════════════════════════════════════════════════════════════
        let positions = ["incline", "decline", "seated", "standing", "lying", "bent over", "kneeling"]
        for position in positions {
            if name1.contains(position) && name2.contains(position) {
                score += 0.1
                break
            }
        }
        
        return min(1.0, score)
    }
    
    /// Get equipment category for grouping similar equipment types
    nonisolated private func getEquipmentCategory(_ equipment: String) -> String {
        let lowered = equipment.lowercased()
        if lowered.contains("dumbbell") || lowered.contains("barbell") || lowered.contains("kettlebell") {
            return "freeweights"
        }
        if lowered.contains("cable") {
            return "cables"
        }
        if lowered.contains("machine") || lowered.contains("smith") {
            return "machines"
        }
        if lowered.contains("band") || lowered.contains("resistance") {
            return "bands"
        }
        if lowered.contains("body") || lowered == "none" {
            return "bodyweight"
        }
        return "other"
    }
    
    /// Get equipment category affinity based on user's preferences
    nonisolated private func getEquipmentCategoryAffinity(_ category: String) -> Double {
        guard let profile = LearningCacheStorage.shared.userPreferences else { return 0 }
        
        // Calculate category affinity from all equipment in that category
        var totalAffinity: Double = 0
        var count: Double = 0
        
        for (equipment, affinity) in profile.equipmentPreferences {
            if getEquipmentCategory(equipment) == category {
                totalAffinity += affinity
                count += 1
            }
        }
        
        return count > 0 ? totalAffinity / count : 0
    }
    
    /// Get movement pattern from exercise name
    nonisolated private func getMovementPattern(_ exerciseName: String) -> String {
        let name = exerciseName.lowercased()
        
        if name.contains("press") || name.contains("push") { return "press" }
        if name.contains("row") || name.contains("pull") { return "row" }
        if name.contains("curl") { return "curl" }
        if name.contains("fly") || name.contains("flye") { return "fly" }
        if name.contains("raise") { return "raise" }
        if name.contains("extension") || name.contains("pushdown") { return "extension" }
        if name.contains("squat") { return "squat" }
        if name.contains("deadlift") || name.contains("rdl") || name.contains("hip hinge") { return "hinge" }
        if name.contains("lunge") || name.contains("split") { return "lunge" }
        if name.contains("crunch") || name.contains("sit-up") || name.contains("plank") { return "core" }
        
        return "other"
    }
    
    /// Sync version of normalizeEquipment for nonisolated functions
    /// Normalize equipment for learning engine (sync version for nonisolated context)
    /// Handles new database format (Cable Machine, Lever Machine, etc.)
    nonisolated private func normalizeEquipmentSync(_ equipment: String) -> String {
        ExerciseFilterService.normalizeEquipment(equipment)
    }
    
    /// Get exercises similar to user's favorites for substitution/alternatives
    func getSimilarToFavorites(from exercises: [Exercise]) -> [Exercise] {
        guard let profile = userPreferences else { return [] }
        
        // Get characteristics of favorite exercises
        let favoriteEquipment = Set(profile.equipmentPreferences.filter { $0.value > 0.5 }.keys)
        let favoriteMuscles = Set(profile.muscleGroupPreferences.filter { $0.value > 0.5 }.keys)
        
        return exercises.filter { exercise in
            let equipNormalized = normalizeEquipment(exercise.equipment ?? "")
            let muscles = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
            
            let equipMatch = favoriteEquipment.contains(equipNormalized)
            let muscleMatch = !Set(muscles).intersection(favoriteMuscles).isEmpty
            
            return equipMatch || muscleMatch
        }
    }
    
    // MARK: - Private Analysis Functions
    
    private func fetchCompletedWorkouts(context: NSManagedObjectContext) async -> [Workout] {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -recentWorkoutDays, to: Date())!
        request.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@", cutoffDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ [LEARNING ENGINE] Error fetching workouts: \(error)")
            return []
        }
    }
    
    private func fetchFavoritedExercises(context: NSManagedObjectContext) async -> [Exercise] {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ [LEARNING ENGINE] Error fetching favorited exercises: \(error)")
            return []
        }
    }
    
    private func fetchFavoritedWorkouts(context: NSManagedObjectContext) async -> [Workout] {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ [LEARNING ENGINE] Error fetching favorited workouts: \(error)")
            return []
        }
    }
    
    private func buildUserProfile(
        workouts: [Workout],
        favoritedExercises: [Exercise],
        favoritedWorkouts: [Workout],
        programCompletions: [(exercises: [String], muscles: [String], date: Date)] = [],
        context: NSManagedObjectContext
    ) async -> UserBehaviorProfile {
        
        var exerciseScores: [String: Double] = [:]
        var equipmentScores: [String: Double] = [:]
        var muscleScores: [String: Double] = [:]
        var categoryScores: [String: Double] = [:]
        var movementPatternScores: [String: Double] = [:]
        var timeOfDayScores: [String: Int] = [:]
        var workoutDurations: [Int] = []
        var exerciseCompletionCounts: [String: Int] = [:]
        var fullSetExercises: Set<String> = [] // Exercises done with 3+ sets
        var recentExercises: Set<String> = [] // Exercises done in last 14 days (expanded)
        
        // Process each workout with recency weighting
        // ⚡️ PERFORMANCE: Yield every 10 workouts to prevent blocking
        for (index, workout) in workouts.enumerated() {
            if index > 0 && index % 10 == 0 {
                await Task.yield()
            }
            let recencyWeight = pow(recencyDecayFactor, Double(index))
            
            // Track workout duration
            if workout.duration > 0 {
                workoutDurations.append(Int(workout.duration / 60)) // in minutes
            }
            
            // Track time of day preference
            if let date = workout.date {
                let hour = Calendar.current.component(.hour, from: date)
                let timeCategory = categorizeTimeOfDay(hour: hour)
                timeOfDayScores[timeCategory, default: 0] += 1
            }
            
            // Process exercises in workout
            let exerciseData = extractExerciseData(from: workout)
            
            for data in exerciseData {
                let nameLower = data.name.lowercased()
                
                // Track completion count
                exerciseCompletionCounts[nameLower, default: 0] += 1
                
                // Calculate exercise score based on sets completed
                var exerciseWeight = recencyWeight
                if data.completedSets >= minSetsForFullCredit {
                    exerciseWeight *= 1.5 // Bonus for completing 3+ sets
                    fullSetExercises.insert(nameLower)
                } else if data.completedSets >= 2 {
                    exerciseWeight *= 1.2
                }
                
                // Update exercise affinity
                exerciseScores[nameLower, default: 0] += exerciseWeight
                
                // Update equipment affinity
                let equipNormalized = normalizeEquipment(data.equipment)
                equipmentScores[equipNormalized, default: 0] += exerciseWeight
                
                // Update muscle group affinity
                for muscle in data.muscleGroups {
                    muscleScores[muscle.lowercased(), default: 0] += exerciseWeight
                }
                
                // Update category affinity
                categoryScores[data.category.lowercased(), default: 0] += exerciseWeight
                
                // Update movement pattern affinity
                let pattern = getMovementPattern(nameLower)
                movementPatternScores[pattern, default: 0] += exerciseWeight
                
                // Track recently done exercises (last 14 workouts for better variety)
                if index < 14 { // First 14 workouts are "recent" - expanded for more variety
                    recentExercises.insert(nameLower)
                }
            }
        }
        
        // ⚡️ Yield after workout processing
        await Task.yield()
        
        // Process favorited exercises (major boost)
        for exercise in favoritedExercises {
            let nameLower = (exercise.name ?? "").lowercased()
            exerciseScores[nameLower, default: 0] += 5.0 // Big boost for favorites
            
            let equipNormalized = normalizeEquipment(exercise.equipment ?? "")
            equipmentScores[equipNormalized, default: 0] += 2.0
            
            if let muscles = exercise.muscleGroups as? [String] {
                for muscle in muscles {
                    muscleScores[muscle.lowercased(), default: 0] += 2.0
                }
            }
            
            categoryScores[(exercise.category ?? "").lowercased(), default: 0] += 2.0
        }
        
        // Process favorited workouts
        for workout in favoritedWorkouts {
            let exerciseData = extractExerciseData(from: workout)
            for data in exerciseData {
                // Boost exercises from favorited workout routines
                exerciseScores[data.name.lowercased(), default: 0] += 3.0
                
                let equipNormalized = normalizeEquipment(data.equipment)
                equipmentScores[equipNormalized, default: 0] += 1.5
            }
        }
        
        // Process program day completions (from cloud)
        // This ensures cross-device learning and program-specific preferences
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        for (index, completion) in programCompletions.enumerated() {
            let recencyWeight = pow(recencyDecayFactor, Double(index))
            
            // Track muscle preferences from program
            for muscle in completion.muscles {
                muscleScores[muscle.lowercased(), default: 0] += recencyWeight * 1.5
            }
            
            // Track exercises completed in programs
            for exerciseName in completion.exercises {
                let nameLower = exerciseName.lowercased()
                exerciseScores[nameLower, default: 0] += recencyWeight * 1.2
                exerciseCompletionCounts[nameLower, default: 0] += 1
                
                // Track as recent if within last 14 days
                if completion.date > fourteenDaysAgo {
                    recentExercises.insert(nameLower)
                }
                
                // Infer movement pattern from name
                let pattern = getMovementPattern(nameLower)
                movementPatternScores[pattern, default: 0] += recencyWeight
            }
        }
        print("🧠 [LEARNING ENGINE] Incorporated \(programCompletions.count) program completions into profile")
        
        // Normalize scores to 0.0 - 1.0 range
        let normalizedExercises = normalizeScores(exerciseScores)
        let normalizedEquipment = normalizeScores(equipmentScores)
        let normalizedMuscles = normalizeScores(muscleScores)
        let normalizedCategories = normalizeScores(categoryScores)
        let normalizedPatterns = normalizeScores(movementPatternScores)
        
        // Calculate preferred workout duration
        let avgDuration = workoutDurations.isEmpty ? 45 : workoutDurations.reduce(0, +) / workoutDurations.count
        
        // Determine preferred time of day
        let preferredTime = timeOfDayScores.max(by: { $0.value < $1.value })?.key ?? "any"
        
        // Build insights
        var insights: [String] = []
        
        if let topEquipment = normalizedEquipment.max(by: { $0.value < $1.value })?.key {
            insights.append("You prefer \(topEquipment.capitalized) exercises")
        }
        
        if let topMuscle = normalizedMuscles.max(by: { $0.value < $1.value })?.key {
            insights.append("You train \(topMuscle.capitalized) most frequently")
        }
        
        if let topPattern = normalizedPatterns.max(by: { $0.value < $1.value })?.key {
            insights.append("You love \(topPattern) movements")
        }
        
        if fullSetExercises.count > 10 {
            insights.append("You've mastered \(fullSetExercises.count) exercises (3+ sets)")
        }
        
        print("🧠 [LEARNING ENGINE] Profile built:")
        print("   - Exercise affinities: \(normalizedExercises.count)")
        print("   - Equipment affinities: \(normalizedEquipment.count)")
        print("   - Muscle affinities: \(normalizedMuscles.count)")
        print("   - Movement patterns: \(normalizedPatterns.count)")
        print("   - Full-set exercises: \(fullSetExercises.count)")
        print("   - Recent exercises: \(recentExercises.count)")
        print("   - Preferred duration: \(avgDuration) min")
        print("   - Preferred time: \(preferredTime)")
        
        // Preserve existing swap history and custom additions
        let existingSwapHistory = userPreferences?.swapHistory ?? [:]
        let existingCustomAdditions = userPreferences?.customWorkoutAdditions ?? []
        let existingSelectedExercises = userPreferences?.explicitlySelectedExercises ?? []
        
        return UserBehaviorProfile(
            exerciseAffinityScores: normalizedExercises,
            equipmentPreferences: normalizedEquipment,
            muscleGroupPreferences: normalizedMuscles,
            categoryPreferences: normalizedCategories,
            movementPatternPreferences: normalizedPatterns,
            exerciseCompletionCounts: exerciseCompletionCounts,
            fullSetExercises: fullSetExercises,
            favoritedExerciseNames: Set(favoritedExercises.compactMap { $0.name?.lowercased() }),
            recentlyDoneExercises: recentExercises,
            preferredWorkoutDuration: avgDuration,
            preferredTimeOfDay: preferredTime,
            totalWorkoutsAnalyzed: workouts.count,
            insights: insights,
            lastUpdated: Date(),
            swapHistory: existingSwapHistory,
            customWorkoutAdditions: existingCustomAdditions,
            explicitlySelectedExercises: existingSelectedExercises
        )
    }
    
    private func extractExerciseData(from workout: Workout) -> [ExerciseAnalysisData] {
        guard let workoutExercises = workout.exercises as? Set<WorkoutExercise> else {
            return []
        }
        
        return workoutExercises.compactMap { workoutExercise -> ExerciseAnalysisData? in
            guard let exercise = workoutExercise.exercise,
                  let name = exercise.name else { return nil }
            
            let sets = (workoutExercise.sets as? Set<WorkoutSet>) ?? []
            let completedSets = sets.filter { $0.isCompleted }.count
            let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
            
            return ExerciseAnalysisData(
                name: name,
                equipment: exercise.equipment ?? "Bodyweight",
                category: exercise.category ?? "Unknown",
                muscleGroups: muscleGroups,
                completedSets: completedSets,
                totalVolume: sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            )
        }
    }
    
    private func normalizeScores(_ scores: [String: Double]) -> [String: Double] {
        guard let maxScore = scores.values.max(), maxScore > 0 else {
            return scores
        }
        
        return scores.mapValues { $0 / maxScore }
    }
    
    /// Normalize equipment for learning engine (async context version)
    /// Handles new database format (Cable Machine, Lever Machine, etc.)
    private func normalizeEquipment(_ equipment: String) -> String {
        ExerciseFilterService.normalizeEquipment(equipment)
    }
    
    private func categorizeTimeOfDay(hour: Int) -> String {
        switch hour {
        case 5..<9: return "early_morning"
        case 9..<12: return "morning"
        case 12..<14: return "midday"
        case 14..<17: return "afternoon"
        case 17..<20: return "evening"
        case 20..<24: return "night"
        default: return "any"
        }
    }
    
    private func updateCaches(from profile: UserBehaviorProfile) {
        LearningCacheStorage.shared.exerciseAffinityCache = profile.exerciseAffinityScores
        LearningCacheStorage.shared.equipmentAffinityCache = profile.equipmentPreferences
        LearningCacheStorage.shared.muscleGroupAffinityCache = profile.muscleGroupPreferences
        LearningCacheStorage.shared.categoryAffinityCache = profile.categoryPreferences
        LearningCacheStorage.shared.movementPatternCache = profile.movementPatternPreferences
    }
}

// MARK: - Data Types

/// Tracks swap behavior for an exercise
struct ExerciseSwapData: Codable {
    var swapCount: Int
    var lastSwappedDate: Date
    var swappedTo: [String: Int]  // What exercises they swapped TO (and how many times)
    
    init(swapCount: Int = 1, lastSwappedDate: Date = Date(), swappedTo: [String: Int] = [:]) {
        self.swapCount = swapCount
        self.lastSwappedDate = lastSwappedDate
        self.swappedTo = swappedTo
    }
}

struct UserBehaviorProfile: Codable {
    
    /// ⚡️ PERFORMANCE: Empty profile for fallback
    static let empty = UserBehaviorProfile(
        exerciseAffinityScores: [:],
        equipmentPreferences: [:],
        muscleGroupPreferences: [:],
        categoryPreferences: [:],
        movementPatternPreferences: [:],
        exerciseCompletionCounts: [:],
        fullSetExercises: [],
        favoritedExerciseNames: [],
        recentlyDoneExercises: [],
        preferredWorkoutDuration: 45,
        preferredTimeOfDay: "morning",
        totalWorkoutsAnalyzed: 0,
        insights: [],
        lastUpdated: Date(),
        swapHistory: [:],
        customWorkoutAdditions: [],
        explicitlySelectedExercises: []
    )
    
    /// Affinity scores for specific exercises (0.0 - 1.0)
    var exerciseAffinityScores: [String: Double]
    
    /// Preference scores for equipment types (0.0 - 1.0)
    var equipmentPreferences: [String: Double]
    
    /// Preference scores for muscle groups (0.0 - 1.0)
    var muscleGroupPreferences: [String: Double]
    
    /// Preference scores for exercise categories (0.0 - 1.0)
    var categoryPreferences: [String: Double]
    
    /// Preference scores for movement patterns (press, row, squat, etc.)
    var movementPatternPreferences: [String: Double]
    
    /// How many times each exercise has been completed
    let exerciseCompletionCounts: [String: Int]
    
    /// Exercises the user has done with 3+ sets (mastered)
    let fullSetExercises: Set<String>
    
    /// Explicitly favorited exercise names
    let favoritedExerciseNames: Set<String>
    
    /// Exercises done in last 7 days (for freshness calculation)
    var recentlyDoneExercises: Set<String>
    
    /// Average workout duration in minutes
    let preferredWorkoutDuration: Int
    
    /// Preferred time of day for workouts
    let preferredTimeOfDay: String
    
    /// Total workouts analyzed
    var totalWorkoutsAnalyzed: Int
    
    /// AI-generated insights about user behavior
    let insights: [String]
    
    /// Last time profile was updated
    var lastUpdated: Date
    
    // 🆕 SMART SWAP TRACKING
    /// Track when exercises are swapped out (exerciseName -> swap data)
    var swapHistory: [String: ExerciseSwapData]
    
    /// Exercises user has added to custom workouts (boost similar exercises)
    var customWorkoutAdditions: [String]
    
    /// Exercises user has explicitly selected/chosen (strong preference signal)
    var explicitlySelectedExercises: Set<String>
    
    // MARK: - Convenience Properties
    
    /// Top 5 preferred equipment types
    var topEquipment: [String] {
        equipmentPreferences
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    /// Top 5 most trained muscle groups
    var topMuscleGroups: [String] {
        muscleGroupPreferences
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    /// Top 10 exercises the user does most
    var topExercises: [String] {
        exerciseAffinityScores
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }
    
    /// Top movement patterns (press, row, squat, etc.)
    var topMovementPatterns: [String] {
        movementPatternPreferences
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    /// Check if user has strong preference for an exercise
    func hasStrongPreferenceFor(exercise: String) -> Bool {
        let score = exerciseAffinityScores[exercise.lowercased()] ?? 0
        return score >= 0.7 || favoritedExerciseNames.contains(exercise.lowercased())
    }
    
    /// Check if user has completed exercise with full sets before
    func hasMastered(exercise: String) -> Bool {
        return fullSetExercises.contains(exercise.lowercased())
    }
    
    /// Get completion count for exercise
    func completionCount(for exercise: String) -> Int {
        return exerciseCompletionCounts[exercise.lowercased()] ?? 0
    }
}

struct ExerciseAnalysisData {
    let name: String
    let equipment: String
    let category: String
    let muscleGroups: [String]
    let completedSets: Int
    let totalVolume: Double
}

// MARK: - Extension for Workout Generator Integration

extension UserBehaviorLearningEngine {
    
    /// Apply learned preferences to exercise scoring in workout generation
    func applyLearnedPreferencesToScoring(
        exercises: [(exercise: Any, baseScore: Double)],
        getExerciseDetails: (Any) -> (name: String, equipment: String, muscles: [String], category: String)
    ) -> [(exercise: Any, finalScore: Double)] {
        
        return exercises.map { item in
            let details = getExerciseDetails(item.exercise)
            let learnedBoost = calculateLearnedBoostScore(
                exerciseName: details.name,
                equipment: details.equipment,
                muscleGroups: details.muscles,
                category: details.category
            )
            
            return (item.exercise, item.baseScore + learnedBoost)
        }
    }
    
    /// Get alternative exercises based on user preferences
    func getPreferredAlternatives(
        for exerciseName: String,
        from candidates: [Exercise]
    ) -> [Exercise] {
        guard let profile = userPreferences else { return candidates }
        
        // Score candidates based on similarity to user preferences
        let scored = candidates.compactMap { exercise -> (Exercise, Double)? in
            guard let name = exercise.name else { return nil }
            
            var score: Double = 0
            
            // Boost if user has done this exercise before
            score += (profile.exerciseAffinityScores[name.lowercased()] ?? 0) * 100
            
            // Boost for matching equipment preference
            let equip = normalizeEquipment(exercise.equipment ?? "")
            score += (profile.equipmentPreferences[equip] ?? 0) * 50
            
            // Boost for matching muscle groups
            if let muscles = exercise.muscleGroups as? [String] {
                let muscleScore = muscles.reduce(0.0) { $0 + (profile.muscleGroupPreferences[$1.lowercased()] ?? 0) }
                score += muscleScore * 30
            }
            
            return (exercise, score)
        }
        
        return scored
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
}

