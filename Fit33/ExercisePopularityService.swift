import Foundation
import CoreData

// MARK: - Exercise Popularity Service
// Tracks and provides exercise popularity data for workout prioritization
// Uses both static seeded data and dynamic user behavior data

final class ExercisePopularityService {
    static let shared = ExercisePopularityService()
    
    // MARK: - Popularity Data
    
    // In-memory cache of popularity scores
    private var popularityCache: [String: Int] = [:]
    private var favoritedCache: Set<String> = []
    private var trendingCache: [String: Double] = [:]
    private var lastRefresh: Date?
    private let cacheTimeout: TimeInterval = 3600 // 1 hour
    
    // Top 100 most universally recognized exercises (static baseline)
    // These are used when no dynamic data is available
    private let baselinePopularity: [String: Int] = [
        // TOP TIER (90-100): Universal classics
        "barbell bench press": 100,
        "flat bench press": 100,
        "bench press": 99,
        "barbell squat": 98,
        "back squat": 98,
        "squat": 97,
        "deadlift": 97,
        "conventional deadlift": 97,
        "pull up": 95,
        "pull-up": 95,
        "pullup": 95,
        "push up": 94,
        "push-up": 94,
        "pushup": 94,
        "shoulder press": 93,
        "overhead press": 93,
        "military press": 93,
        "dumbbell curl": 92,
        "bicep curl": 92,
        "lat pulldown": 91,
        "plank": 90,
        
        // HIGH TIER (80-89): Very popular
        "leg press": 89,
        "incline bench press": 88,
        "incline dumbbell press": 88,
        "romanian deadlift": 87,
        "rdl": 87,
        "barbell row": 86,
        "bent over row": 86,
        "cable row": 85,
        "seated row": 85,
        "tricep pushdown": 84,
        "triceps pushdown": 84,
        "cable pushdown": 84,
        "leg extension": 83,
        "leg curl": 82,
        "hamstring curl": 82,
        "lateral raise": 81,
        "side lateral raise": 81,
        "crunch": 80,
        "crunches": 80,
        
        // MEDIUM-HIGH TIER (70-79): Well-known
        "dumbbell chest press": 79,
        "dumbbell bench press": 79,
        "skull crusher": 78,
        "lying tricep extension": 78,
        "hammer curl": 77,
        "face pull": 76,
        "cable face pull": 76,
        "lunge": 75,
        "lunges": 75,
        "walking lunge": 75,
        "dip": 74,
        "dips": 74,
        "tricep dip": 74,
        "calf raise": 73,
        "standing calf raise": 73,
        "shrug": 72,
        "dumbbell shrug": 72,
        "fly": 71,
        "chest fly": 71,
        "dumbbell fly": 71,
        "preacher curl": 70,
        
        // MEDIUM TIER (60-69): Known exercises
        "cable curl": 69,
        "cable bicep curl": 69,
        "front squat": 68,
        "hip thrust": 67,
        "barbell hip thrust": 67,
        "good morning": 66,
        "reverse fly": 65,
        "rear delt fly": 65,
        "cable crossover": 64,
        "upright row": 63,
        "goblet squat": 62,
        "chin up": 61,
        "chin-up": 61,
        "chinup": 61,
        "decline bench press": 60,
        
        // MEDIUM-LOW TIER (50-59): Moderately known
        "concentration curl": 59,
        "incline curl": 58,
        "incline dumbbell curl": 58,
        "close grip bench press": 57,
        "sumo deadlift": 56,
        "bulgarian split squat": 55,
        "step up": 54,
        "step ups": 54,
        "arnold press": 53,
        "ez bar curl": 52,
        "cable fly": 51,
        "machine chest press": 50,
    ]
    
    private init() {
        // Initialize with baseline data
        popularityCache = baselinePopularity
    }
    
    // MARK: - Public API
    
    /// Get the popularity score for an exercise (0-100)
    func getPopularityScore(for exerciseName: String) -> Int {
        let key = exerciseName.lowercased()
        
        // Check exact match first
        if let score = popularityCache[key] {
            return score
        }
        
        // Check partial matches for variations
        for (name, score) in popularityCache {
            if key.contains(name) || name.contains(key) {
                return score
            }
        }
        
        // Default score for unknown exercises
        return 50
    }
    
    /// Check if an exercise is in the top tier (90+)
    func isTopTierExercise(_ exerciseName: String) -> Bool {
        return getPopularityScore(for: exerciseName) >= 90
    }
    
    /// Check if an exercise is popular (70+)
    func isPopularExercise(_ exerciseName: String) -> Bool {
        return getPopularityScore(for: exerciseName) >= 70
    }
    
    /// Check if an exercise is trending (based on recent usage)
    func isTrendingExercise(_ exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        return (trendingCache[key] ?? 0) > 10
    }
    
    /// Check if an exercise is frequently favorited by users
    func isCommunityFavorite(_ exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        return favoritedCache.contains(key)
    }
    
    /// Get popularity boost for workout scoring (0-200 points)
    func getPopularityBoost(for exerciseName: String) -> Int {
        let baseScore = getPopularityScore(for: exerciseName)
        var boost = 0
        
        // Scale popularity to boost (50-100 -> 0-100 boost)
        if baseScore >= 50 {
            boost += (baseScore - 50) * 2
        }
        
        // Extra boost for trending
        if isTrendingExercise(exerciseName) {
            boost += 30
        }
        
        // Extra boost for community favorites
        if isCommunityFavorite(exerciseName) {
            boost += 50
        }
        
        return min(boost, 200)
    }
    
    /// Get top N most popular exercises
    func getTopExercises(count: Int = 50) -> [String] {
        return popularityCache
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { $0.key }
    }
    
    /// Get top exercises for a specific category/muscle group
    func getTopExercises(for category: String, count: Int = 10) -> [String] {
        // This would filter by category - for now return overall top
        return getTopExercises(count: count)
    }
    
    // MARK: - Data Refresh
    
    /// Refresh popularity data from the server
    func refreshFromServer() async {
        // Only refresh if cache is stale
        if let lastRefresh = lastRefresh,
           Date().timeIntervalSince(lastRefresh) < cacheTimeout {
            return
        }
        
        do {
            // Fetch from Supabase
            let popular = try await SupabaseManager.shared.fetchPopularExercises(limit: 100)
            let trending = try await SupabaseManager.shared.fetchTrendingExercises(limit: 50)
            let favorited = try await SupabaseManager.shared.fetchMostFavoritedExercises(limit: 50)
            
            await MainActor.run {
                // Update popularity cache
                for exercise in popular {
                    let key = exercise.exerciseName.lowercased()
                    let dynamicScore = Int(exercise.popularityScore)
                    let baselineScore = baselinePopularity[key] ?? 50
                    // Blend dynamic and baseline scores
                    popularityCache[key] = max(dynamicScore, baselineScore)
                }
                
                // Update trending cache
                trendingCache.removeAll()
                for exercise in trending {
                    trendingCache[exercise.exerciseName.lowercased()] = exercise.trendingScore
                }
                
                // Update favorited cache
                favoritedCache = Set(favorited.map { $0.exerciseName.lowercased() })
                
                lastRefresh = Date()
                
                #if DEBUG
                print("📊 [POPULARITY] Refreshed: \(popular.count) popular, \(trending.count) trending, \(favorited.count) favorited")
                #endif
            }
            
        } catch {
            #if DEBUG
            print("⚠️ [POPULARITY] Failed to refresh: \(error)")
            #endif
        }
    }
    
    // MARK: - Usage Tracking
    
    /// Log that an exercise was used in a workout (updates local cache)
    /// Note: Full usage logging is handled by ActiveWorkoutView.logExerciseUsageToCloud()
    func logExerciseUsageLocally(exerciseName: String, setsCompleted: Int) {
        // Increment local cache optimistically
        Task { @MainActor in
            let key = exerciseName.lowercased()
            let currentScore = popularityCache[key] ?? 50
            popularityCache[key] = min(currentScore + 1, 100)
            
            #if DEBUG
            print("📊 [POPULARITY] Local cache updated: \(exerciseName) -> \(popularityCache[key] ?? 50)")
            #endif
        }
    }
    
    /// Log that a user favorited an exercise
    func logExerciseFavorited(exerciseName: String) {
        Task {
            // The favorite is already synced elsewhere, just update local cache
            await MainActor.run {
                favoritedCache.insert(exerciseName.lowercased())
            }
        }
    }
}

// MARK: - Integration with Workout Generation

extension IntelligentWorkoutGenerator {
    
    /// Score exercises with popularity boost integrated
    func scoreExerciseWithPopularity(_ exercise: Exercise, userFavorites: Set<String>) -> Double {
        var score: Double = 100
        
        let name = (exercise.name ?? "").lowercased()
        
        // Base popularity boost (0-200 points)
        let popularityBoost = ExercisePopularityService.shared.getPopularityBoost(for: name)
        score += Double(popularityBoost)
        
        // User's personal favorites get massive boost
        if userFavorites.contains(name) {
            score += 500
        }
        
        // Community favorites get additional boost
        if ExercisePopularityService.shared.isCommunityFavorite(name) {
            score += 100
        }
        
        // Trending exercises get temporary boost
        if ExercisePopularityService.shared.isTrendingExercise(name) {
            score += 75
        }
        
        // Top tier exercises (bench, squat, deadlift) always score high
        if ExercisePopularityService.shared.isTopTierExercise(name) {
            score += 150
        }
        
        return score
    }
}

// MARK: - Preview/Debug

#if DEBUG
extension ExercisePopularityService {
    func printTopExercises() {
        print("📊 TOP 20 EXERCISES BY POPULARITY:")
        for (index, name) in getTopExercises(count: 20).enumerated() {
            let score = getPopularityScore(for: name)
            let trending = isTrendingExercise(name) ? "📈" : ""
            let favorite = isCommunityFavorite(name) ? "⭐" : ""
            print("  \(index + 1). \(name.capitalized) - Score: \(score) \(trending)\(favorite)")
        }
    }
}
#endif

