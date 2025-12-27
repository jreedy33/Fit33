//
//  SmartExerciseSearchService.swift
//  GoFit
//
//  Intelligent exercise search with fuzzy matching, personalization, and common exercise prioritization
//  The more the user works out, the smarter the search becomes.
//

import Foundation
import CoreData

/// Smart exercise search service that learns from user behavior and provides intelligent fuzzy matching
@MainActor
final class SmartExerciseSearchService: ObservableObject {
    static let shared = SmartExerciseSearchService()
    
    // MARK: - Constants for Scoring
    
    // Name matching scores (highest priority)
    private let EXACT_MATCH_SCORE: Double = 1000
    private let STARTS_WITH_SCORE: Double = 500
    private let CONTAINS_SCORE: Double = 200
    private let POSITION_BONUS_MAX: Double = 50
    private let WORD_BOUNDARY_SCORE: Double = 100
    
    // Fuzzy matching scores
    private let FUZZY_MATCH_BONUS: Double = 150  // Bonus for partial word matches
    private let PARTIAL_WORD_MATCH_SCORE: Double = 75  // "bench" matches "benchpress"
    
    // User behavior scores (personalization)
    private let FAVORITE_BOOST: Double = 800  // User's favorites (highest user preference)
    private let HIGH_FREQUENCY_BOOST: Double = 400  // Exercises done 10+ times
    private let MEDIUM_FREQUENCY_BOOST: Double = 200  // Exercises done 5-9 times
    private let LOW_FREQUENCY_BOOST: Double = 100  // Exercises done 1-4 times
    private let EXPLICIT_SELECTION_BOOST: Double = 300  // User explicitly chose this
    
    // Popularity scores (for new users or discovery)
    private let COMMUNITY_POPULARITY_MULTIPLIER: Double = 2.0  // Database popularity score * 2
    private let COMMON_EXERCISE_BOOST: Double = 150  // Boost universally common exercises
    
    // Recency and variety
    private let RECENT_PENALTY: Double = -50  // Small penalty for recently done (encourage variety)
    private let FRESHNESS_BONUS: Double = 30  // Bonus for exercises not done recently
    
    // Equipment and category matches
    private let CATEGORY_MATCH_SCORE: Double = 50
    private let MUSCLE_MATCH_SCORE: Double = 40
    private let EQUIPMENT_MATCH_SCORE: Double = 30
    
    // Swap penalty
    private let SWAP_PENALTY_MAX: Double = -80  // Reduce score if user frequently swaps this
    
    // MARK: - Common Exercises (High Priority for Everyone)
    
    // Top common exercises organized by category and equipment
    // Used to prioritize for new users or when filters are applied
    private let commonExercisesByCategory: [String: [String: [String]]] = [
        "chest": [
            "barbell": ["bench press", "incline bench press", "decline bench press", "close grip bench press", "press"],
            "dumbbell": ["dumbbell bench press", "incline dumbbell press", "dumbbell fly", "decline dumbbell press", "dumbbell press", "fly"],
            "cable": ["cable fly", "cable crossover", "low cable fly", "high cable fly", "cable press", "fly"],
            "machine": ["machine chest press", "pec deck", "chest press machine", "machine fly", "press"],
            "bodyweight": ["push up", "dips", "decline push up", "diamond push up", "push"]
        ],
        "back": [
            "barbell": ["barbell row", "deadlift", "t-bar row", "rack pull", "row", "pull"],
            "dumbbell": ["dumbbell row", "single arm row", "dumbbell pullover", "row"],
            "cable": ["cable row", "seated cable row", "straight arm pulldown", "face pull", "lat pulldown", "row", "pulldown"],
            "machine": ["lat pulldown", "machine row", "assisted pull up", "pulldown", "row"],
            "bodyweight": ["pull up", "chin up", "inverted row", "pull"]
        ],
        "shoulders": [
            "barbell": ["overhead press", "military press", "behind neck press", "shoulder press", "press"],
            "dumbbell": ["dumbbell shoulder press", "lateral raise", "front raise", "arnold press", "rear delt fly", "shoulder press", "press", "raise"],
            "cable": ["cable lateral raise", "cable front raise", "cable rear delt fly", "face pull", "raise"],
            "machine": ["machine shoulder press", "machine lateral raise", "press", "raise"],
            "bodyweight": ["pike push up", "handstand push up", "push"]
        ],
        "arms": [
            "barbell": ["barbell curl", "ez bar curl", "close grip bench press", "skull crusher", "curl", "standing barbell curl"],
            "dumbbell": ["dumbbell curl", "bicep curl", "hammer curl", "tricep extension", "concentration curl", "tricep kickback", "standing curl", "curl"],
            "cable": ["cable curl", "bicep curl", "tricep pushdown", "rope pushdown", "overhead cable extension", "pushdown"],
            "machine": ["preacher curl machine", "tricep extension machine", "curl machine"],
            "bodyweight": ["dips", "close grip push up", "chin up"]
        ],
        "legs": [
            "barbell": ["squat", "front squat", "romanian deadlift", "deadlift", "good morning", "lunge"],
            "dumbbell": ["dumbbell lunge", "goblet squat", "bulgarian split squat", "dumbbell romanian deadlift", "lunge", "squat"],
            "cable": ["cable kickback", "cable pull through", "kickback"],
            "machine": ["leg press", "leg extension", "leg curl", "hack squat", "press", "extension", "curl"],
            "bodyweight": ["squat", "lunge", "bulgarian split squat", "pistol squat", "calf raise", "hip thrust", "glute bridge"]
        ],
        "core": [
            "bodyweight": ["plank", "crunch", "sit up", "leg raise", "mountain climber", "russian twist"],
            "cable": ["cable crunch", "wood chop", "pallof press"],
            "machine": ["ab machine", "ab crunch machine"]
        ]
    ]
    
    // Universal common exercises (for when no category filter applied)
    private let universalCommonExercises: Set<String> = [
        // The absolute essentials everyone should know
        "bench press", "squat", "deadlift", "pull up", "overhead press",
        "barbell row", "dumbbell press", "leg press", "lat pulldown",
        "shoulder press", "bicep curl", "tricep pushdown", "lunge", "plank"
    ]
    
    private init() {
        print("🔍 [SMART SEARCH] Initialized")
    }
    
    // MARK: - Main Search API
    
    /// Search exercises with intelligent fuzzy matching and personalized ranking
    /// - Parameters:
    ///   - query: Search query string
    ///   - exercises: Pool of exercises to search through
    ///   - userBehavior: Optional user behavior profile for personalization
    ///   - categoryFilter: Optional category filter (e.g., "Chest", "Back")
    ///   - equipmentFilter: Optional equipment filter (e.g., "Dumbbell", "Barbell")
    /// - Returns: Ranked list of exercises
    func searchExercises(
        query: String,
        in exercises: [Exercise],
        userBehavior: UserBehaviorProfile? = nil,
        categoryFilter: String? = nil,
        equipmentFilter: String? = nil
    ) -> [Exercise] {
        guard !query.isEmpty else {
            // No search query - just rank by common exercises for filters
            return rankByCommonExercises(
                exercises,
                userBehavior: userBehavior,
                categoryFilter: categoryFilter,
                equipmentFilter: equipmentFilter
            )
        }
        
        let searchLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        let searchWords = searchLower.split(separator: " ").map { String($0) }
        
        // Score all exercises
        var scoredResults: [(exercise: Exercise, score: Double)] = []
        
        for exercise in exercises {
            if let score = scoreExercise(
                exercise,
                searchQuery: searchLower,
                searchWords: searchWords,
                userBehavior: userBehavior,
                categoryFilter: categoryFilter,
                equipmentFilter: equipmentFilter
            ) {
                scoredResults.append((exercise, score))
            }
        }
        
        // Sort by score (highest first)
        scoredResults.sort { $0.score > $1.score }
        
        // Debug: Log top 5 results
        #if DEBUG
        if !scoredResults.isEmpty {
            print("🔍 [SMART SEARCH] Top results for '\(query)':")
            for (index, result) in scoredResults.prefix(5).enumerated() {
                print("   \(index + 1). \(result.exercise.name ?? "Unknown") (score: \(Int(result.score)))")
            }
        }
        #endif
        
        return scoredResults.map { $0.exercise }
    }
    
    /// Rank exercises when no search query (just filters applied)
    /// Prioritizes common exercises for new users
    private func rankByCommonExercises(
        _ exercises: [Exercise],
        userBehavior: UserBehaviorProfile?,
        categoryFilter: String?,
        equipmentFilter: String?
    ) -> [Exercise] {
        // Check if user is new (less than 5 workouts or less than 3 favorites)
        let isNewUser = (userBehavior?.totalWorkoutsAnalyzed ?? 0) < 5 || 
                       (userBehavior?.favoritedExerciseNames.count ?? 0) < 3
        
        var scoredResults: [(exercise: Exercise, score: Double)] = []
        
        for exercise in exercises {
            var score: Double = 0
            let name = exercise.name?.lowercased() ?? ""
            
            // For new users, heavily prioritize common exercises
            let commonBoost = isNewUser ? 500.0 : 150.0
            
            if isCommonExerciseForFilters(
                name,
                category: categoryFilter,
                equipment: equipmentFilter
            ) {
                score += commonBoost
            }
            
            // Add user behavior scoring if available
            if let profile = userBehavior {
                if exercise.isFavorite {
                    score += FAVORITE_BOOST
                }
                
                let nameLower = name.lowercased()
                let completionCount = profile.completionCount(for: nameLower)
                if completionCount >= 10 {
                    score += HIGH_FREQUENCY_BOOST
                } else if completionCount >= 5 {
                    score += MEDIUM_FREQUENCY_BOOST
                } else if completionCount >= 1 {
                    score += LOW_FREQUENCY_BOOST
                }
            }
            
            // Add popularity score
            if exercise.popularityScore > 0 {
                score += Double(exercise.popularityScore) * COMMUNITY_POPULARITY_MULTIPLIER
            }
            
            scoredResults.append((exercise, score))
        }
        
        // Sort by score
        scoredResults.sort { $0.score > $1.score }
        
        return scoredResults.map { $0.exercise }
    }
    
    // MARK: - Exercise Scoring
    
    /// Score an exercise based on search relevance and personalization
    /// Returns nil if exercise doesn't match at all
    private func scoreExercise(
        _ exercise: Exercise,
        searchQuery: String,
        searchWords: [String],
        userBehavior: UserBehaviorProfile?,
        categoryFilter: String?,
        equipmentFilter: String?
    ) -> Double? {
        let name = exercise.name?.lowercased() ?? ""
        let category = exercise.category?.lowercased() ?? ""
        let equipment = exercise.equipment?.lowercased() ?? ""
        let muscles = (exercise.muscleGroups as? [String])?.map { $0.lowercased() }.joined(separator: " ") ?? ""
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 1: Check if exercise matches search (fuzzy matching)
        // ═══════════════════════════════════════════════════════════════
        
        var hasMatch = false
        var baseScore: Double = 0
        
        // Exact name match (perfect match)
        if name == searchQuery {
            baseScore += EXACT_MATCH_SCORE
            hasMatch = true
        }
        // Name starts with query (very strong match)
        else if name.hasPrefix(searchQuery) {
            baseScore += STARTS_WITH_SCORE
            hasMatch = true
        }
        // Name contains query (strong match)
        else if name.contains(searchQuery) {
            baseScore += CONTAINS_SCORE
            hasMatch = true
            
            // Bonus for position (earlier in name = better)
            if let range = name.range(of: searchQuery) {
                let position = name.distance(from: name.startIndex, to: range.lowerBound)
                let positionBonus = max(0, POSITION_BONUS_MAX - Double(position))
                baseScore += positionBonus
            }
        }
        // Word boundary matching (e.g., "curl" matches "bicep curl")
        else if searchWords.count == 1 {
            let nameWords = name.split(separator: " ").map { String($0) }
            if nameWords.contains(searchQuery) {
                baseScore += WORD_BOUNDARY_SCORE
                hasMatch = true
            }
            // Partial word match (e.g., "press" matches "bench press")
            else if nameWords.contains(where: { $0.contains(searchQuery) }) {
                baseScore += PARTIAL_WORD_MATCH_SCORE
                hasMatch = true
            }
        }
        // Multi-word fuzzy matching (all words must appear)
        else if searchWords.count > 1 {
            let allWordsMatch = searchWords.allSatisfy { word in
                name.contains(word) || category.contains(word)
            }
            if allWordsMatch {
                baseScore += FUZZY_MATCH_BONUS
                hasMatch = true
                
                // Bonus if words are in order
                let wordsInOrder = searchWords.reduce((lastIndex: -1, inOrder: true)) { result, word in
                    if !result.inOrder { return result }
                    if let range = name.range(of: word) {
                        let index = name.distance(from: name.startIndex, to: range.lowerBound)
                        return (index, index > result.lastIndex)
                    }
                    return (result.lastIndex, false)
                }
                if wordsInOrder.inOrder {
                    baseScore += 50
                }
            }
        }
        
        // Check category/equipment/muscle matches (secondary matches)
        if !hasMatch {
            if category.contains(searchQuery) {
                baseScore += CATEGORY_MATCH_SCORE
                hasMatch = true
            } else if muscles.contains(searchQuery) {
                baseScore += MUSCLE_MATCH_SCORE
                hasMatch = true
            } else if equipment.contains(searchQuery) {
                baseScore += EQUIPMENT_MATCH_SCORE
                hasMatch = true
            }
        }
        
        // No match at all - filter out
        guard hasMatch else { return nil }
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 2: Apply user behavior personalization
        // ═══════════════════════════════════════════════════════════════
        
        if let profile = userBehavior {
            let nameLower = name.lowercased()
            
            // Favorites (highest user preference)
            if exercise.isFavorite {
                baseScore += FAVORITE_BOOST
            }
            
            // Completion frequency (the more they do it, the more they like it)
            let completionCount = profile.completionCount(for: nameLower)
            if completionCount >= 10 {
                baseScore += HIGH_FREQUENCY_BOOST
            } else if completionCount >= 5 {
                baseScore += MEDIUM_FREQUENCY_BOOST
            } else if completionCount >= 1 {
                baseScore += LOW_FREQUENCY_BOOST
            }
            
            // Explicit selection boost (user chose this before)
            if profile.explicitlySelectedExercises.contains(nameLower) {
                baseScore += EXPLICIT_SELECTION_BOOST
            }
            
            // Recency penalty/bonus (encourage variety)
            if profile.recentlyDoneExercises.contains(nameLower) {
                baseScore += RECENT_PENALTY  // Small penalty for recently done
            } else if completionCount > 0 {
                baseScore += FRESHNESS_BONUS  // Bonus for exercises they like but haven't done recently
            }
            
            // Swap penalty (if user frequently swaps this out, they don't like it)
            if let swapData = profile.swapHistory[nameLower], swapData.swapCount >= 3 {
                let swapPenalty = min(SWAP_PENALTY_MAX, -Double(swapData.swapCount) * 15)
                baseScore += swapPenalty
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 3: Apply community popularity and common exercise boost
        // ═══════════════════════════════════════════════════════════════
        
        // Community popularity from database
        if exercise.popularityScore > 0 {
            baseScore += Double(exercise.popularityScore) * COMMUNITY_POPULARITY_MULTIPLIER
        }
        
        // Common exercise boost - ENHANCED for filter context
        // Check if user is new (less than 5 workouts or less than 3 favorites)
        let isNewUser = (userBehavior?.totalWorkoutsAnalyzed ?? 0) < 5 || 
                       (userBehavior?.favoritedExerciseNames.count ?? 0) < 3
        
        // Check if this is a common exercise for the applied filters
        if isCommonExerciseForFilters(name, category: categoryFilter, equipment: equipmentFilter) {
            // New users get MASSIVE boost for common exercises
            // Experienced users still get boost, but user behavior matters more
            let commonBoost = isNewUser ? COMMON_EXERCISE_BOOST * 3.0 : COMMON_EXERCISE_BOOST
            baseScore += commonBoost
            
            #if DEBUG
            if isNewUser && commonBoost > 200 {
                print("   🌟 Common exercise boost (new user): \(exercise.name ?? "") (+\(Int(commonBoost)))")
            }
            #endif
        }
        
        return baseScore
    }
    
    // MARK: - Helper Methods
    
    /// Check if exercise is common for specific category/equipment filters
    /// This is the NEW filter-aware common exercise checking
    private func isCommonExerciseForFilters(
        _ exerciseName: String,
        category: String?,
        equipment: String?
    ) -> Bool {
        let name = exerciseName.lowercased()
        
        // First check universal common exercises (always prioritized)
        if universalCommonExercises.contains(name) {
            return true
        }
        
        // Check if name contains any universal common exercise
        for common in universalCommonExercises {
            if name.contains(common) {
                return true
            }
        }
        
        // If both category and equipment filters are applied, check specific combinations
        if let cat = category?.lowercased(), let equip = equipment?.lowercased() {
            // Normalize equipment name
            let normalizedEquip = normalizeEquipmentForCommonLookup(equip)
            
            // Check category-specific common exercises for this equipment
            if let categoryExercises = commonExercisesByCategory[cat],
               let equipmentExercises = categoryExercises[normalizedEquip] {
                // Check exact match
                if equipmentExercises.contains(name) {
                    return true
                }
                // Check if name contains any of these common exercises
                for common in equipmentExercises {
                    if name.contains(common) {
                        return true
                    }
                }
            }
            
            // ═══════════════════════════════════════════════════════════════
            // SMART CATEGORY MATCHING - Understands movement patterns
            // ═══════════════════════════════════════════════════════════════
            
            // ARMS: Any curl, extension, or pushdown
            if cat == "arms" {
                if name.contains("curl") || 
                   name.contains("extension") || 
                   name.contains("pushdown") ||
                   name.contains("push down") {
                    return true
                }
            }
            
            // CHEST: Any press, fly, or push movement
            if cat == "chest" {
                if name.contains("press") || 
                   name.contains("fly") ||
                   name.contains("flye") ||
                   name.contains("push") ||
                   name.contains("dip") {
                    return true
                }
            }
            
            // BACK: Any row, pull, or deadlift movement
            if cat == "back" {
                if name.contains("row") || 
                   name.contains("pull") ||
                   name.contains("pulldown") ||
                   name.contains("pull down") ||
                   name.contains("deadlift") ||
                   name.contains("chin") {
                    return true
                }
            }
            
            // SHOULDERS: Any press, raise, or fly movement
            if cat == "shoulders" {
                if name.contains("press") || 
                   name.contains("raise") ||
                   name.contains("fly") ||
                   name.contains("flye") ||
                   name.contains("shrug") {
                    return true
                }
            }
            
            // LEGS: Any squat, lunge, press, curl, extension, deadlift
            if cat == "legs" {
                if name.contains("squat") || 
                   name.contains("lunge") ||
                   name.contains("press") ||
                   name.contains("curl") ||
                   name.contains("extension") ||
                   name.contains("deadlift") ||
                   name.contains("raise") ||
                   name.contains("thrust") ||
                   name.contains("bridge") {
                    return true
                }
            }
            
            // CORE: Any crunch, plank, raise, twist, sit-up
            if cat == "core" {
                if name.contains("crunch") || 
                   name.contains("plank") ||
                   name.contains("raise") ||
                   name.contains("twist") ||
                   name.contains("sit up") ||
                   name.contains("situp") ||
                   name.contains("roll") {
                    return true
                }
            }
        }
        
        // If only category filter is applied, check across all equipment for that category
        if let cat = category?.lowercased() {
            if let categoryExercises = commonExercisesByCategory[cat] {
                for (_, exercises) in categoryExercises {
                    if exercises.contains(name) {
                        return true
                    }
                    for common in exercises {
                        if name.contains(common) {
                            return true
                        }
                    }
                }
            }
            
            // ═══════════════════════════════════════════════════════════════
            // SMART CATEGORY MATCHING - Understands movement patterns
            // ═══════════════════════════════════════════════════════════════
            
            // ARMS: Any curl, extension, or pushdown
            if cat == "arms" {
                if name.contains("curl") || 
                   name.contains("extension") || 
                   name.contains("pushdown") ||
                   name.contains("push down") {
                    return true
                }
            }
            
            // CHEST: Any press, fly, or push movement
            if cat == "chest" {
                if name.contains("press") || 
                   name.contains("fly") ||
                   name.contains("flye") ||
                   name.contains("push") ||
                   name.contains("dip") {
                    return true
                }
            }
            
            // BACK: Any row, pull, or deadlift movement
            if cat == "back" {
                if name.contains("row") || 
                   name.contains("pull") ||
                   name.contains("pulldown") ||
                   name.contains("pull down") ||
                   name.contains("deadlift") ||
                   name.contains("chin") {
                    return true
                }
            }
            
            // SHOULDERS: Any press, raise, or fly movement
            if cat == "shoulders" {
                if name.contains("press") || 
                   name.contains("raise") ||
                   name.contains("fly") ||
                   name.contains("flye") ||
                   name.contains("shrug") {
                    return true
                }
            }
            
            // LEGS: Any squat, lunge, press, curl, extension, deadlift
            if cat == "legs" {
                if name.contains("squat") || 
                   name.contains("lunge") ||
                   name.contains("press") ||
                   name.contains("curl") ||
                   name.contains("extension") ||
                   name.contains("deadlift") ||
                   name.contains("raise") ||
                   name.contains("thrust") ||
                   name.contains("bridge") {
                    return true
                }
            }
            
            // CORE: Any crunch, plank, raise, twist, sit-up
            if cat == "core" {
                if name.contains("crunch") || 
                   name.contains("plank") ||
                   name.contains("raise") ||
                   name.contains("twist") ||
                   name.contains("sit up") ||
                   name.contains("situp") ||
                   name.contains("roll") {
                    return true
                }
            }
        }
        
        // If only equipment filter is applied, check across all categories for that equipment
        if let equip = equipment?.lowercased() {
            let normalizedEquip = normalizeEquipmentForCommonLookup(equip)
            for (_, categoryExercises) in commonExercisesByCategory {
                if let equipmentExercises = categoryExercises[normalizedEquip] {
                    if equipmentExercises.contains(name) {
                        return true
                    }
                    for common in equipmentExercises {
                        if name.contains(common) {
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    /// Normalize equipment name for common exercise lookup
    private func normalizeEquipmentForCommonLookup(_ equipment: String) -> String {
        let lowered = equipment.lowercased()
        if lowered.contains("dumbbell") { return "dumbbell" }
        if lowered.contains("barbell") || lowered.contains("ez bar") { return "barbell" }
        if lowered.contains("cable") { return "cable" }
        if lowered.contains("machine") || lowered.contains("lever") { return "machine" }
        if lowered.contains("body") || lowered == "none" { return "bodyweight" }
        return lowered
    }
    
    /// Get similarity ratio between two strings (0.0 - 1.0)
    /// Uses Levenshtein-inspired algorithm for fuzzy matching
    private func calculateSimilarity(between str1: String, and str2: String) -> Double {
        let s1 = str1.lowercased()
        let s2 = str2.lowercased()
        
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }
        
        // Simple similarity: count matching characters
        let maxLength = max(s1.count, s2.count)
        var matches = 0
        
        let chars1 = Array(s1)
        let chars2 = Array(s2)
        
        for (index, char) in chars1.enumerated() {
            if index < chars2.count && chars2[index] == char {
                matches += 1
            }
        }
        
        return Double(matches) / Double(maxLength)
    }
}

// MARK: - Integration with User Behavior Learning

extension SmartExerciseSearchService {
    
    /// Log when user selects an exercise from search results
    /// This helps the learning engine understand user preferences
    func recordSearchSelection(exerciseName: String, searchQuery: String, resultPosition: Int) {
        // Log to learning engine
        UserBehaviorLearningEngine.shared.recordExplicitSelection(exerciseName: exerciseName)
        
        // Log to analytics
        SessionLogManager.shared.logExerciseSearch(
            query: searchQuery,
            resultCount: resultPosition,
            filters: nil
        )
        
        #if DEBUG
        print("🔍 [SMART SEARCH] User selected '\(exerciseName)' from search '\(searchQuery)' (position: \(resultPosition))")
        #endif
    }
}

