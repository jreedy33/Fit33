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
    
    // MARK: - Prefix-Aware Search Cache
    private var lastSearchQuery: String = ""
    private var lastSearchResults: [Exercise] = []
    
    /// Clear the prefix cache (call when the pre-filtered exercise set changes)
    func invalidateCache() {
        lastSearchQuery = ""
        lastSearchResults = []
    }
    
    // MARK: - Constants for Scoring
    
    // ⚡️ SNAPPY SEARCH: Aggressive exact-match prioritization
    // Exact matches get MASSIVE scores to always appear first
    private let EXACT_MATCH_SCORE: Double = 10000      // Exact name = always first
    private let STARTS_WITH_SCORE: Double = 5000       // Name starts with query = top
    private let CONTAINS_SCORE: Double = 1000          // Name contains query
    private let POSITION_BONUS_MAX: Double = 200       // Earlier position = better
    private let WORD_BOUNDARY_SCORE: Double = 800      // Matches a complete word
    
    // Fuzzy matching scores (lower priority than exact)
    private let FUZZY_MATCH_BONUS: Double = 300       // Bonus for partial word matches
    private let PARTIAL_WORD_MATCH_SCORE: Double = 150 // "bench" matches "benchpress"
    private let TYPO_CORRECTED_SCORE: Double = 250    // Bonus when typo was corrected
    
    // MARK: - Common Typos Dictionary
    // Maps common misspellings to correct spellings for exercise-related terms
    private let typoCorrections: [String: String] = [
        // Equipment typos
        "dumbell": "dumbbell",
        "dumbel": "dumbbell",
        "dumble": "dumbbell",
        "dumbbel": "dumbbell",
        "dumbells": "dumbbell",
        "dumbels": "dumbbell",
        "barbel": "barbell",
        "barbells": "barbell",
        "kettleball": "kettlebell",
        "kettlebel": "kettlebell",
        "cabel": "cable",
        "cabels": "cable",
        "machien": "machine",
        "mashine": "machine",
        "bodyweigt": "bodyweight",
        "benchpress": "bench press",
        
        // Muscle group typos
        "bycep": "bicep",
        "byceps": "bicep",
        "bicept": "bicep",
        "bicepp": "bicep",
        "trycep": "tricep",
        "tryceps": "tricep",
        "tricept": "tricep",
        "tricepp": "tricep",
        "forarm": "forearm",
        "forarms": "forearm",
        "quadricep": "quads",
        "hammstring": "hamstrings",
        "hammstrings": "hamstrings",
        "hamstrigns": "hamstrings",
        "gluteus": "glutes",
        "calfs": "calves",
        "latissimus": "lats",
        "trapezius": "traps",
        "deltoid": "delts",
        "deltoids": "delts",
        "sholder": "shoulders",
        "sholders": "shoulders",
        "shouder": "shoulders",
        "abdominal": "abs",
        "abdominals": "abs",
        "pectoral": "chest",
        "pectorals": "chest",
        
        // Exercise type typos
        "flye": "fly",
        "flyes": "fly",
        "flies": "fly",
        "flie": "fly",
        "curle": "curl",
        "pres": "press",
        "presss": "press",
        "rwo": "row",
        "sqaut": "squat",
        "sqat": "squat",
        "squatt": "squat",
        "lange": "lunge",
        "deadlif": "deadlift",
        "dedlift": "deadlift",
        "pullup": "pull up",
        "pullups": "pull up",
        "chinup": "chin up",
        "chinups": "chin up",
        "pushup": "push up",
        "pushups": "push up",
        "extention": "extension",
        "extentions": "extension",
        "extenstion": "extension",
        "extnsion": "extension",
        "crunchs": "crunch",
        "rais": "raise",
        "shrg": "shrug",
        "dipp": "dip",
        "inclin": "incline",
        "inclien": "incline",
        "declin": "decline",
        "declien": "decline",
        "laterl": "lateral",
        "latral": "lateral",
        
        // Common word typos
        "excercise": "exercise",
        "exercize": "exercise",
        "excersize": "exercise",
        "exercis": "exercise",
        "overhed": "overhead",
        "overhad": "overhead",
        "millitary": "military",
        "militery": "military",
        "millitry": "military",
        "arnlod": "arnold",
        "hamer": "hammer",
        "hammar": "hammer",
        "precher": "preacher",
        "preecher": "preacher",
        "scull": "skull",
        "romanaian": "romanian",
        "romanain": "romanian",
        "bulgarin": "bulgarian",
        "bulgarain": "bulgarian",
        "revers": "reverse",
        "reverese": "reverse",
        "hyperextention": "hyperextension",
        "sitted": "seated",
        "seeted": "seated",
        "standng": "standing",
        "stading": "standing",
        "lieing": "lying",
        "lyeing": "lying",
        
        // Merged from view-level dictionaries
        "barble": "barbell",
        "quatricep": "quadricep",
        "bensh": "bench",
        "banch": "bench",
        "benc": "bench"
        // NOTE: "glute" → "glutes" intentionally EXCLUDED — breaks singular name matching
        // NOTE: "hamstring" → "hamstrings" intentionally EXCLUDED — breaks singular name matching
    ]
    
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
    
    // MARK: - Typo Correction
    
    /// Correct common typos in the search query
    /// Returns both the corrected query and whether any corrections were made
    func correctTypos(in query: String) -> (corrected: String, wasModified: Bool) {
        var words = query.lowercased().split(separator: " ").map { String($0) }
        var wasModified = false
        
        for (index, word) in words.enumerated() {
            // Check for exact typo match
            if let correction = typoCorrections[word] {
                words[index] = correction
                wasModified = true
                #if DEBUG
                print("🔤 [TYPO] Corrected '\(word)' → '\(correction)'")
                #endif
            } else {
                // Check for partial matches (typo might be part of a word)
                for (typo, correction) in typoCorrections {
                    if word.contains(typo) && typo.count >= 4 {
                        words[index] = word.replacingOccurrences(of: typo, with: correction)
                        wasModified = true
                        #if DEBUG
                        print("🔤 [TYPO] Partial correction '\(word)' → '\(words[index])'")
                        #endif
                        break
                    }
                }
            }
        }
        
        return (words.joined(separator: " "), wasModified)
    }
    
    /// Get all possible search terms including typo variations
    /// Returns the original query plus any corrected versions
    func getSearchVariations(for query: String) -> [String] {
        var variations: Set<String> = [query.lowercased()]
        
        let (corrected, wasModified) = correctTypos(in: query)
        if wasModified {
            variations.insert(corrected)
        }
        
        // Also add individual word corrections
        let words = query.lowercased().split(separator: " ").map { String($0) }
        for word in words {
            if let correction = typoCorrections[word] {
                variations.insert(correction)
            }
        }
        
        return Array(variations)
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
        
        // ⚡️ FAST PATH: For very short queries (1-2 chars), use ultra-fast prefix matching
        if searchLower.count <= 2 {
            return fastPrefixSearch(searchLower, in: exercises)
        }
        
        // ⚡️ FAST PATH: For simple queries, skip typo correction overhead
        let isSimpleQuery = searchLower.count <= 4 && !searchLower.contains(" ")
        
        let searchWords = searchLower.split(separator: " ").map { String($0) }
        
        // Score all exercises with simplified logic for speed
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
        
        // ⚡️ Only do typo correction for longer queries (5+ chars) with no results
        if scoredResults.isEmpty && !isSimpleQuery {
            let (correctedQuery, wasModified) = correctTypos(in: searchLower)
            if wasModified {
                let correctedWords = correctedQuery.split(separator: " ").map { String($0) }
                for exercise in exercises {
                    if let score = scoreExercise(
                        exercise,
                        searchQuery: correctedQuery,
                        searchWords: correctedWords,
                        userBehavior: userBehavior,
                        categoryFilter: categoryFilter,
                        equipmentFilter: equipmentFilter
                    ) {
                        scoredResults.append((exercise, score + TYPO_CORRECTED_SCORE))
                    }
                }
            }
        }
        
        // Sort by score (highest first)
        scoredResults.sort { $0.score > $1.score }
        
        return scoredResults.map { $0.exercise }
    }
    
    // MARK: - Unified Ultra-Fast Search (Used by all views)
    
    /// Ultra-fast search that combines speed with intelligence.
    /// Searches name + category + equipment + muscleGroups + nickname.
    /// Per-word typo correction upfront. Multi-word variation generation.
    /// Priority bucket sort: exact > startsWith > contains > allWords > secondary field.
    /// Designed for <5ms on 7,000 exercises.
    func searchExercisesUltraFast(
        query: String,
        in exercises: [Exercise],
        userBehavior: UserBehaviorProfile? = nil
    ) -> [Exercise] {
        guard !query.isEmpty else {
            invalidateCache()
            return exercises
        }
        
        let queryLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        // For 1-2 char queries, use simple prefix matching (no typo correction overhead)
        if queryLower.count <= 2 {
            invalidateCache()
            return fastPrefixSearch(queryLower, in: exercises)
        }
        
        // Prefix-aware cache: if new query extends the previous query, search within cached results
        if !lastSearchQuery.isEmpty && queryLower.hasPrefix(lastSearchQuery) && !lastSearchResults.isEmpty {
            let narrowed = searchExercisesUltraFastCore(query: queryLower, in: lastSearchResults, userBehavior: userBehavior)
            lastSearchQuery = queryLower
            lastSearchResults = narrowed
            return narrowed
        }
        
        let results = searchExercisesUltraFastCore(query: queryLower, in: exercises, userBehavior: userBehavior)
        lastSearchQuery = queryLower
        lastSearchResults = results
        return results
    }
    
    /// Core search implementation (called by both main path and prefix-cache path)
    private func searchExercisesUltraFastCore(
        query: String,
        in exercises: [Exercise],
        userBehavior: UserBehaviorProfile?
    ) -> [Exercise] {
        let rawWords = query.split(separator: " ").map { String($0) }
        let correctedWords = rawWords.map { word -> String in
            typoCorrections[word] ?? word
        }
        let correctedQuery = correctedWords.joined(separator: " ")
        let isMultiWord = correctedWords.count > 1
        
        let wordVariationSets: [[String]]
        if isMultiWord {
            wordVariationSets = correctedWords.map { getKeywordVariations($0) }
        } else {
            wordVariationSets = [getKeywordVariations(correctedQuery)]
        }
        let singleWordVariations = isMultiWord ? [correctedQuery] : wordVariationSets[0]
        
        var exactMatches: [(Exercise, Double)] = []
        var startsWithMatches: [(Exercise, Double)] = []
        var containsMatches: [(Exercise, Double)] = []
        var allWordsMatches: [(Exercise, Double)] = []
        var secondaryMatches: [(Exercise, Double)] = []
        
        let hasUserBehavior = userBehavior != nil
        
        for exercise in exercises {
            let name = (exercise.name ?? "").lowercased()
            guard !name.isEmpty else { continue }
            
            var personalScore: Double = 0
            if hasUserBehavior {
                personalScore = personalBoost(for: exercise, name: name, userBehavior: userBehavior!)
            }
            
            var matched = false
            
            if !isMultiWord {
                for variation in singleWordVariations {
                    if name == variation {
                        exactMatches.append((exercise, personalScore))
                        matched = true
                        break
                    } else if name.hasPrefix(variation) {
                        startsWithMatches.append((exercise, personalScore))
                        matched = true
                        break
                    } else if name.contains(variation) {
                        containsMatches.append((exercise, personalScore))
                        matched = true
                        break
                    }
                }
                
                if !matched {
                    let nickname = ExerciseNicknameService.shared.displayName(for: exercise).lowercased()
                    if nickname != name {
                        for variation in singleWordVariations {
                            if nickname == variation {
                                exactMatches.append((exercise, personalScore + 50))
                                matched = true
                                break
                            } else if nickname.hasPrefix(variation) {
                                startsWithMatches.append((exercise, personalScore + 25))
                                matched = true
                                break
                            } else if nickname.contains(variation) {
                                containsMatches.append((exercise, personalScore + 10))
                                matched = true
                                break
                            }
                        }
                    }
                }
            }
            
            if !matched && isMultiWord {
                if name == correctedQuery {
                    exactMatches.append((exercise, personalScore))
                    matched = true
                } else if name.hasPrefix(correctedQuery) {
                    startsWithMatches.append((exercise, personalScore))
                    matched = true
                } else if name.contains(correctedQuery) {
                    containsMatches.append((exercise, personalScore))
                    matched = true
                }
            }
            
            if !matched && isMultiWord {
                let allWordsFound = wordVariationSets.allSatisfy { variations in
                    variations.contains { name.contains($0) }
                }
                if allWordsFound {
                    allWordsMatches.append((exercise, personalScore))
                    matched = true
                }
            }
            
            if !matched {
                let category = (exercise.category ?? "").lowercased()
                let muscles = (exercise.muscleGroups as? [String])?.joined(separator: " ").lowercased() ?? ""
                let equipment = (exercise.equipment ?? "").lowercased()
                
                let searchTerms = isMultiWord ? [correctedQuery] + correctedWords : singleWordVariations
                
                for term in searchTerms {
                    if category.contains(term) || muscles.contains(term) {
                        secondaryMatches.append((exercise, personalScore))
                        matched = true
                        break
                    } else if equipment.contains(term) {
                        secondaryMatches.append((exercise, personalScore - 10))
                        matched = true
                        break
                    }
                }
            }
        }
        
        let sortByScore: ((Exercise, Double), (Exercise, Double)) -> Bool = { $0.1 > $1.1 }
        exactMatches.sort(by: sortByScore)
        startsWithMatches.sort(by: sortByScore)
        containsMatches.sort(by: sortByScore)
        allWordsMatches.sort(by: sortByScore)
        secondaryMatches.sort(by: sortByScore)
        
        return (exactMatches + startsWithMatches + containsMatches + allWordsMatches + secondaryMatches)
            .map { $0.0 }
    }
    
    /// Lightweight personal boost score (no heavy scoring, just key signals)
    private func personalBoost(for exercise: Exercise, name: String, userBehavior: UserBehaviorProfile) -> Double {
        var score: Double = 0
        if exercise.isFavorite { score += 100 }
        let count = userBehavior.completionCount(for: name)
        if count >= 10 { score += 50 }
        else if count >= 5 { score += 30 }
        else if count >= 1 { score += 15 }
        if userBehavior.explicitlySelectedExercises.contains(name) { score += 40 }
        if exercise.popularityScore > 50 { score += 20 }
        return score
    }
    
    // ⚡️ ULTRA-FAST: Simple prefix/contains search for 1-2 character queries
    private func fastPrefixSearch(_ query: String, in exercises: [Exercise]) -> [Exercise] {
        var exactStarts: [Exercise] = []
        var containsMatch: [Exercise] = []
        
        // Get keyword variations for smarter matching
        let variations = getKeywordVariations(query)
        
        for exercise in exercises {
            guard let name = exercise.name?.lowercased() else { continue }
            
            var matched = false
            var isPrefix = false
            
            for variation in variations {
                if name.hasPrefix(variation) {
                    isPrefix = true
                    matched = true
                    break
                } else if name.contains(variation) {
                    matched = true
                }
            }
            
            if matched {
                if isPrefix {
                    exactStarts.append(exercise)
                } else {
                    containsMatch.append(exercise)
                }
            }
        }
        
        // Exact prefix matches first, then contains matches
        return exactStarts + containsMatch
    }
    
    // ═══════════════════════════════════════════════════════════════
    // 🎯 SMART KEYWORD VARIATIONS: Handle common spelling variations
    // ═══════════════════════════════════════════════════════════════
    
    /// Get keyword variations for common exercise terms
    /// e.g., "fly" → ["fly", "flye", "flies", "flyes"]
    private func getKeywordVariations(_ keyword: String) -> [String] {
        let lower = keyword.lowercased()
        var variations = [lower]
        
        // Common exercise term variations
        switch lower {
        case "fly":
            variations += ["flye", "flies", "flyes", "flys"]
        case "flye":
            variations += ["fly", "flies", "flyes", "flys"]
        case "press":
            variations += ["presses"]
        case "curl":
            variations += ["curls"]
        case "row":
            variations += ["rows", "rowing"]
        case "raise":
            variations += ["raises"]
        case "extension":
            variations += ["extensions", "ext"]
        case "pulldown":
            variations += ["pull-down", "pull down", "pulldowns"]
        case "pushdown":
            variations += ["push-down", "push down", "pushdowns"]
        case "pull":
            variations += ["pulls", "pulling"]
        case "push":
            variations += ["pushes", "pushing"]
        case "squat":
            variations += ["squats", "squatting"]
        case "lunge":
            variations += ["lunges", "lunging"]
        case "deadlift":
            variations += ["deadlifts", "dead lift", "dead-lift"]
        case "bench":
            variations += ["benches", "benching"]
        case "crunch":
            variations += ["crunches"]
        case "dip":
            variations += ["dips"]
        case "shrug":
            variations += ["shrugs"]
        case "plank":
            variations += ["planks"]
        case "bicep":
            variations += ["biceps"]
        case "biceps":
            variations += ["bicep"]
        case "tricep":
            variations += ["triceps"]
        case "triceps":
            variations += ["tricep"]
        case "pullup", "pull up":
            variations += ["pullups", "pull ups", "pull-up", "pull-ups"]
        case "pushup", "push up":
            variations += ["pushups", "push ups", "push-up", "push-ups"]
        case "chinup", "chin up":
            variations += ["chinups", "chin ups", "chin-up", "chin-ups"]
        case "dumbbell":
            variations += ["dumbbells"]
        case "dumbbells":
            variations += ["dumbbell"]
        case "barbell":
            variations += ["barbells"]
        default:
            if lower.hasSuffix("s") && lower.count > 3 {
                variations.append(String(lower.dropLast()))
            } else if !lower.hasSuffix("s") && lower.count > 2 {
                variations.append(lower + "s")
            }
        }
        
        return variations
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
        
        // Also check user's custom nickname for this exercise
        let nickname = ExerciseNicknameService.shared.displayName(for: exercise).lowercased()
        let hasNickname = nickname != name
        
        // 🎯 SMART KEYWORD MATCHING: Get variations of search terms
        // e.g., "fly" also matches "flye", "flies", etc.
        let queryVariations = getKeywordVariations(searchQuery)
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 1: Check if exercise matches search (with keyword variations)
        // ═══════════════════════════════════════════════════════════════
        
        var hasMatch = false
        var baseScore: Double = 0
        
        // Check nickname first (if user has set one, prioritize it)
        if hasNickname {
            for variation in queryVariations {
                if nickname == variation {
                    baseScore += EXACT_MATCH_SCORE + 100 // Extra bonus for nickname match
                    hasMatch = true
                    break
                } else if nickname.hasPrefix(variation) {
                    baseScore += STARTS_WITH_SCORE + 50
                    hasMatch = true
                    break
                } else if nickname.contains(variation) {
                    baseScore += CONTAINS_SCORE + 25
                    hasMatch = true
                    break
                }
            }
        }
        
        // Try all query variations for name matching
        if !hasMatch {
            for variation in queryVariations {
                // Exact name match (perfect match)
                if name == variation {
                    baseScore += EXACT_MATCH_SCORE
                    hasMatch = true
                    break
                }
                // Name starts with query (very strong match)
                else if name.hasPrefix(variation) {
                    baseScore += STARTS_WITH_SCORE
                    hasMatch = true
                    break
                }
                // Name contains query (strong match)
                else if name.contains(variation) {
                    baseScore += CONTAINS_SCORE
                    hasMatch = true
                    
                    // Bonus for position (earlier in name = better)
                    if let range = name.range(of: variation) {
                        let position = name.distance(from: name.startIndex, to: range.lowerBound)
                        let positionBonus = max(0, POSITION_BONUS_MAX - Double(position))
                        baseScore += positionBonus
                    }
                    break
                }
            }
        }
        
        // Word boundary matching (e.g., "curl" matches "bicep curl")
        if !hasMatch && searchWords.count == 1 {
            let nameWords = name.split(separator: " ").map { String($0) }
            let nicknameWords = nickname.split(separator: " ").map { String($0) }
            
            for variation in queryVariations {
                if nameWords.contains(variation) || nicknameWords.contains(variation) {
                    baseScore += WORD_BOUNDARY_SCORE
                    hasMatch = true
                    break
                }
                // Partial word match (e.g., "press" matches "bench press")
                if nameWords.contains(where: { $0.contains(variation) }) || 
                   nicknameWords.contains(where: { $0.contains(variation) }) {
                    baseScore += PARTIAL_WORD_MATCH_SCORE
                    hasMatch = true
                    break
                }
            }
        }
        
        // Multi-word fuzzy matching (all words must appear)
        if !hasMatch && searchWords.count > 1 {
            // Get variations for each word
            let allWordVariations = searchWords.map { getKeywordVariations($0) }
            
            let allWordsMatch = allWordVariations.allSatisfy { variations in
                variations.contains { variation in
                    name.contains(variation) || category.contains(variation)
                }
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
            for variation in queryVariations {
                if category.contains(variation) {
                    baseScore += CATEGORY_MATCH_SCORE
                    hasMatch = true
                    break
                } else if muscles.contains(variation) {
                    baseScore += MUSCLE_MATCH_SCORE
                    hasMatch = true
                    break
                } else if equipment.contains(variation) {
                    baseScore += EQUIPMENT_MATCH_SCORE
                    hasMatch = true
                    break
                }
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
        ExerciseFilterService.normalizeEquipment(equipment)
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

