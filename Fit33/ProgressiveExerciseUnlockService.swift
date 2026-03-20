//
//  ProgressiveExerciseUnlockService.swift
//  GoFit
//
//  A service that tracks user experience and progressively unlocks more exercise variety.
//  New users start with foundational, well-known exercises and gradually get exposed to
//  more variety as they demonstrate proficiency through:
//  - Completing workouts
//  - Completing full sets
//  - Favoriting exercises (shows engagement)
//  - NOT swapping exercises frequently (shows satisfaction)
//
//  This prevents new users from getting weird exercises like "Behind Back Cable Tricep Extension"
//  on their first workout.
//

import Foundation
import CoreData

// MARK: - Thread-safe cache for synchronous access from non-MainActor contexts
final class ProgressiveUnlockCache: @unchecked Sendable {
    static let shared = ProgressiveUnlockCache()
    
    var workoutCount: Int = 0
    var currentTier: FoundationTier = .essential
    var shouldRestrictToFoundational: Bool = true
    var varietyPercentage: Double = 0.0
    
    private init() {}
    
    func update(from profile: UserExerciseMaturityProfile?) {
        workoutCount = profile?.totalWorkoutsCompleted ?? 0
        currentTier = profile?.currentUnlockTier ?? .essential
        shouldRestrictToFoundational = profile?.shouldRestrictToFoundational ?? true
        varietyPercentage = profile?.varietyPercentage ?? 0.0
    }
}

// MARK: - User Exercise Maturity Profile

struct UserExerciseMaturityProfile: Codable {
    /// Total workouts completed
    var totalWorkoutsCompleted: Int = 0
    
    /// Total exercises completed with at least 2 sets
    var totalExercisesCompletedFull: Int = 0
    
    /// Total unique exercises the user has done
    var uniqueExercisesDone: Set<String> = []
    
    /// Exercises the user has favorited (shows engagement)
    var favoritedExercises: Set<String> = []
    
    /// Exercises the user frequently swaps out (negative signal)
    var frequentlySwappedExercises: Set<String> = []
    
    /// Equipment types the user has used at least 3 times
    var masteredEquipmentTypes: Set<String> = []
    
    /// Muscle groups the user has trained at least 5 times
    var masteredMuscleGroups: Set<String> = []
    
    /// Days since first workout (account age indicator)
    var daysSinceFirstWorkout: Int = 0
    
    /// Last analysis date
    var lastAnalyzed: Date = Date()
    
    /// The current unlock tier for this user
    var currentUnlockTier: FoundationTier {
        // Calculate based on multiple factors
        let workoutScore = min(totalWorkoutsCompleted, 20)  // Cap at 20
        let exerciseScore = min(totalExercisesCompletedFull / 5, 10)  // Cap at 10
        let uniqueScore = min(uniqueExercisesDone.count / 10, 10)  // Cap at 10
        let favoriteScore = min(favoritedExercises.count * 2, 10)  // Favorites are strong signal
        let equipmentScore = min(masteredEquipmentTypes.count * 2, 10)
        let ageScore = min(daysSinceFirstWorkout / 7, 10)  // Cap at 10 weeks
        
        let totalScore = workoutScore + exerciseScore + uniqueScore + 
                        favoriteScore + equipmentScore + ageScore
        
        if totalScore < 5 {
            return .essential
        } else if totalScore < 15 {
            return .fundamental
        } else if totalScore < 30 {
            return .standard
        } else {
            return .variety
        }
    }
    
    /// Whether user should see only foundational exercises
    var shouldRestrictToFoundational: Bool {
        // Restrict if:
        // 1. Less than 3 workouts completed
        // 2. Less than 10 unique exercises done
        // 3. No favorites yet (low engagement)
        
        if totalWorkoutsCompleted < 3 {
            return true
        }
        if totalWorkoutsCompleted < 10 && uniqueExercisesDone.count < 15 {
            return true
        }
        return false
    }
    
    /// Percentage of variety exercises that should be included (0.0 - 1.0)
    var varietyPercentage: Double {
        switch currentUnlockTier {
        case .essential:
            return 0.0  // 0% variety - only essential exercises
        case .fundamental:
            return 0.1  // 10% variety allowed
        case .standard:
            return 0.3  // 30% variety allowed
        case .variety:
            return 1.0  // 100% - full access
        }
    }
    
    /// Get a human-readable description of user's experience level
    var experienceDescription: String {
        if totalWorkoutsCompleted < 5 {
            return "New to the app"
        } else if totalWorkoutsCompleted < 15 {
            return "Getting started"
        } else if totalWorkoutsCompleted < 30 {
            return "Building consistency"
        } else if totalWorkoutsCompleted < 50 {
            return "Regular user"
        } else {
            return "Experienced user"
        }
    }
}

// MARK: - Progressive Exercise Unlock Service

@MainActor
class ProgressiveExerciseUnlockService: ObservableObject {
    static let shared = ProgressiveExerciseUnlockService()
    
    @Published private(set) var userProfile: UserExerciseMaturityProfile? {
        didSet {
            // Update thread-safe cache whenever profile changes
            ProgressiveUnlockCache.shared.update(from: userProfile)
        }
    }
    @Published private(set) var isAnalyzing = false
    
    private let cacheKey = "userExerciseMaturityProfile"
    
    private init() {
        loadCachedProfile()
        print("📈 [PROGRESSIVE UNLOCK] Service initialized")
    }
    
    // MARK: - Cache Management
    
    private func loadCachedProfile() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let profile = try? JSONDecoder().decode(UserExerciseMaturityProfile.self, from: data) {
            self.userProfile = profile
            // Update thread-safe cache for synchronous access
            ProgressiveUnlockCache.shared.update(from: profile)
            print("📈 [PROGRESSIVE UNLOCK] Loaded cached profile:")
            print("   • Workouts: \(profile.totalWorkoutsCompleted)")
            print("   • Unlock tier: \(profile.currentUnlockTier.displayName)")
            print("   • Restrict to foundational: \(profile.shouldRestrictToFoundational)")
        }
    }
    
    private func saveProfile() {
        guard let profile = userProfile else { return }
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    // MARK: - Profile Analysis
    
    /// Analyze user's workout history to build maturity profile
    func analyzeUserMaturity(context: NSManagedObjectContext) async -> UserExerciseMaturityProfile {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        print("📈 [PROGRESSIVE UNLOCK] Analyzing user maturity...")
        
        var profile = UserExerciseMaturityProfile()
        
        // Fetch completed workouts
        let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        workoutRequest.predicate = NSPredicate(format: "isCompleted == YES")
        workoutRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]
        
        let workouts: [Workout]
        do {
            workouts = try context.fetch(workoutRequest)
        } catch {
            print("❌ [PROGRESSIVE UNLOCK] Error fetching workouts: \(error)")
            return profile
        }
        
        profile.totalWorkoutsCompleted = workouts.count
        
        // Calculate days since first workout
        if let firstWorkout = workouts.first?.date {
            let days = Calendar.current.dateComponents([.day], from: firstWorkout, to: Date()).day ?? 0
            profile.daysSinceFirstWorkout = days
        }
        
        // Track equipment and muscle usage
        var equipmentCounts: [String: Int] = [:]
        var muscleCounts: [String: Int] = [:]
        
        // Process each workout
        for workout in workouts {
            guard let workoutExercises = workout.exercises as? Set<WorkoutExercise> else { continue }
            
            for workoutExercise in workoutExercises {
                guard let exercise = workoutExercise.exercise,
                      let name = exercise.name else { continue }
                
                let nameLower = name.lowercased()
                
                // Track unique exercises
                profile.uniqueExercisesDone.insert(nameLower)
                
                // Check if completed with at least 2 sets
                let sets = (workoutExercise.sets as? Set<WorkoutSet>) ?? []
                let completedSets = sets.filter { $0.isCompleted }.count
                if completedSets >= 2 {
                    profile.totalExercisesCompletedFull += 1
                }
                
                // Track equipment usage
                if let equipment = exercise.equipment?.lowercased() {
                    let normalizedEquip = normalizeEquipment(equipment)
                    equipmentCounts[normalizedEquip, default: 0] += 1
                }
                
                // Track muscle usage
                if let muscles = exercise.muscleGroups as? [String] {
                    for muscle in muscles {
                        let muscleLower = muscle.lowercased()
                        muscleCounts[muscleLower, default: 0] += 1
                    }
                }
            }
        }
        
        // Determine mastered equipment (used 3+ times)
        profile.masteredEquipmentTypes = Set(equipmentCounts.filter { $0.value >= 3 }.keys)
        
        // Determine mastered muscles (trained 5+ times)
        profile.masteredMuscleGroups = Set(muscleCounts.filter { $0.value >= 5 }.keys)
        
        // Fetch favorites
        let favoriteRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        favoriteRequest.predicate = NSPredicate(format: "isFavorite == YES")
        
        if let favorites = try? context.fetch(favoriteRequest) {
            profile.favoritedExercises = Set(favorites.compactMap { $0.name?.lowercased() })
        }
        
        // Get swap history from learning engine
        if let learningProfile = UserBehaviorLearningEngine.shared.userPreferences {
            let frequentSwaps = learningProfile.swapHistory.filter { $0.value.swapCount >= 3 }
            profile.frequentlySwappedExercises = Set(frequentSwaps.keys)
        }
        
        profile.lastAnalyzed = Date()
        
        self.userProfile = profile
        saveProfile()
        
        print("📈 [PROGRESSIVE UNLOCK] Analysis complete:")
        print("   • Total workouts: \(profile.totalWorkoutsCompleted)")
        print("   • Unique exercises: \(profile.uniqueExercisesDone.count)")
        print("   • Full-set exercises: \(profile.totalExercisesCompletedFull)")
        print("   • Favorites: \(profile.favoritedExercises.count)")
        print("   • Mastered equipment: \(profile.masteredEquipmentTypes)")
        print("   • Days active: \(profile.daysSinceFirstWorkout)")
        print("   • Current tier: \(profile.currentUnlockTier.displayName)")
        print("   • Restrict to foundational: \(profile.shouldRestrictToFoundational)")
        print("   • Variety percentage: \(Int(profile.varietyPercentage * 100))%")
        
        return profile
    }
    
    /// Quick refresh after a workout completes
    func recordWorkoutCompletion(exerciseNames: [String]) {
        guard var profile = userProfile else { return }
        
        profile.totalWorkoutsCompleted += 1
        profile.totalExercisesCompletedFull += exerciseNames.count
        
        for name in exerciseNames {
            profile.uniqueExercisesDone.insert(name.lowercased())
        }
        
        profile.lastAnalyzed = Date()
        
        self.userProfile = profile
        saveProfile()
        
        print("📈 [PROGRESSIVE UNLOCK] Recorded workout completion:")
        print("   • Total workouts now: \(profile.totalWorkoutsCompleted)")
        print("   • Tier: \(profile.currentUnlockTier.displayName)")
    }
    
    /// Record when user favorites an exercise
    func recordFavorite(exerciseName: String) {
        guard var profile = userProfile else { return }
        
        profile.favoritedExercises.insert(exerciseName.lowercased())
        self.userProfile = profile
        saveProfile()
        
        print("📈 [PROGRESSIVE UNLOCK] Recorded favorite: \(exerciseName)")
    }
    
    /// Record when user swaps an exercise
    func recordSwap(exerciseName: String) {
        guard var profile = userProfile else { return }
        
        let nameLower = exerciseName.lowercased()
        
        // Check if this is now a frequently swapped exercise (3+ times)
        if let learningProfile = UserBehaviorLearningEngine.shared.userPreferences,
           let swapData = learningProfile.swapHistory[nameLower],
           swapData.swapCount >= 3 {
            profile.frequentlySwappedExercises.insert(nameLower)
            self.userProfile = profile
            saveProfile()
            
            print("📈 [PROGRESSIVE UNLOCK] '\(exerciseName)' marked as frequently swapped")
        }
    }
    
    // MARK: - Scoring Methods
    
    /// Get the foundational boost score for an exercise based on user's maturity
    func getFoundationalBoostScore(for exerciseName: String) -> Double {
        let profile = userProfile ?? UserExerciseMaturityProfile()
        
        return FoundationalExerciseDatabase.shared.getFoundationalBoostScore(
            exerciseName: exerciseName,
            userWorkoutCount: profile.totalWorkoutsCompleted,
            userTotalCompletedExercises: profile.totalExercisesCompletedFull
        )
    }
    
    /// Check if an exercise should be included based on user's tier
    func shouldIncludeExercise(exerciseName: String) -> Bool {
        let profile = userProfile ?? UserExerciseMaturityProfile()
        
        // If user is restricted to foundational, check if exercise is foundational
        if profile.shouldRestrictToFoundational {
            return FoundationalExerciseDatabase.shared.isFoundationalExercise(exerciseName)
        }
        
        // Check if exercise is within user's tier
        if let tier = FoundationalExerciseDatabase.shared.getTier(for: exerciseName) {
            return tier <= profile.currentUnlockTier
        }
        
        // Non-foundational exercise - allow based on variety percentage (deterministic per day)
        let dateString = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        let seed = abs((exerciseName + dateString).hashValue) % 1000
        let value = Double(seed) / 1000.0
        return value < profile.varietyPercentage
    }
    
    /// Get penalty for frequently swapped exercises
    func getSwapPenalty(for exerciseName: String) -> Double {
        guard let profile = userProfile else { return 0 }
        
        if profile.frequentlySwappedExercises.contains(exerciseName.lowercased()) {
            return -50  // Penalize exercises user doesn't like
        }
        return 0
    }
    
    /// Get the user's current workout count
    var workoutCount: Int {
        return userProfile?.totalWorkoutsCompleted ?? 0
    }
    
    /// Get the user's current unlock tier
    var currentTier: FoundationTier {
        return userProfile?.currentUnlockTier ?? .essential
    }
    
    /// Whether user should be restricted to foundational exercises
    var shouldRestrictToFoundational: Bool {
        return userProfile?.shouldRestrictToFoundational ?? true
    }
    
    /// Get variety percentage (0.0 - 1.0)
    var varietyPercentage: Double {
        return userProfile?.varietyPercentage ?? 0.0
    }
    
    // MARK: - Helper Methods
    
    private func normalizeEquipment(_ equipment: String) -> String {
        ExerciseFilterService.normalizeEquipment(equipment)
    }
    
    // MARK: - Debug Methods
    
    /// Reset user profile (for testing)
    func resetProfile() {
        userProfile = UserExerciseMaturityProfile()
        saveProfile()
        print("📈 [PROGRESSIVE UNLOCK] Profile reset")
    }
    
    /// Get detailed debug info
    func getDebugInfo() -> String {
        guard let profile = userProfile else { return "No profile loaded" }
        
        return """
        Progressive Unlock Profile:
        ─────────────────────────────
        Workouts Completed: \(profile.totalWorkoutsCompleted)
        Unique Exercises: \(profile.uniqueExercisesDone.count)
        Full-Set Exercises: \(profile.totalExercisesCompletedFull)
        Favorites: \(profile.favoritedExercises.count)
        Frequently Swapped: \(profile.frequentlySwappedExercises.count)
        Mastered Equipment: \(profile.masteredEquipmentTypes.joined(separator: ", "))
        Days Active: \(profile.daysSinceFirstWorkout)
        ─────────────────────────────
        Current Tier: \(profile.currentUnlockTier.displayName)
        Restrict to Foundational: \(profile.shouldRestrictToFoundational)
        Variety Percentage: \(Int(profile.varietyPercentage * 100))%
        Experience: \(profile.experienceDescription)
        """
    }
}
