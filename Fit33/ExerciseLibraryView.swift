import SwiftUI
import CoreData

struct ExerciseLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var exerciseLibrary = ExerciseLibraryService.shared
    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    
    // Multi-select filter sets
    @State private var selectedCategories: Set<String> = []
    @State private var selectedEquipmentItems: Set<String> = []
    @State private var selectedMuscleGroups: Set<String> = []
    
    @State private var selectedExercise: Exercise?
    @State private var forceRenderID = UUID()
    @State private var exerciseFilter: ExerciseFilterType = .recommended
    
    // ⚡️ SNAPPY SEARCH: Focus state for instant keyboard dismiss
    @FocusState private var isSearchFocused: Bool
    
    // ⚡️ PERFORMANCE: Cached filtered results to avoid recomputation on every render
    @State private var cachedFilteredExercises: [Exercise] = []
    @State private var filterUpdateTask: Task<Void, Never>?
    
    // ⚡️ HIGH-PERFORMANCE: Pre-filtered cache by category/equipment
    @State private var preFilteredExercises: [Exercise] = []
    @State private var lastFilterKey: String = ""
    
    // ⚡️ INSTANT SEARCH: Simple in-memory search for zero-lag typing
    @State private var searchResultsCache: [String: [Exercise]] = [:]
    
    enum ExerciseFilterType: String, CaseIterable {
        case recommended = "Recommended"
        case favorites = "Favorites"
        case custom = "Custom Added"
        case strength = "Strength"
        case cardio = "Cardio"
        case plyometrics = "Plyometrics"
        case stretching = "Stretching"
        case all = "All Exercises"
    }
    
    // MARK: - Recommended Exercise Names
    // Now uses the shared top-200 curated list from ExerciseLibraryFilterCache
    // (single source of truth — no duplicate lists)
    private var recommendedExercises: Set<String> {
        ExerciseLibraryFilterCache.shared.recommendedExerciseNames
    }
    
    // Categories filtered by selected exercise types (combines all selected)
    private var categories: [String] {
        var allCategories = Set<String>(["All"])
        
        // Get categories based on current filter type
        switch exerciseFilter {
        case .strength:
            allCategories.formUnion(ExerciseFilterService.categories(for: .strength))
        case .cardio:
            allCategories.formUnion(ExerciseFilterService.categories(for: .cardio))
        case .plyometrics:
            allCategories.formUnion(ExerciseFilterService.categories(for: .plyometrics))
        case .stretching:
            allCategories.formUnion(ExerciseFilterService.categories(for: .stretching))
        case .recommended, .favorites, .custom, .all:
            // Show all categories for these filters
            for type in ExerciseFilterService.ExerciseType.allCases {
                allCategories.formUnion(ExerciseFilterService.categories(for: type))
            }
        }
        
        return ["All"] + Array(allCategories).filter { $0 != "All" }.sorted()
    }
    
    private let allMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques", "Hip Flexors", "Adductors", "Rotator Cuff"]
    
    // Smart muscle groups based on selected category (uses centralized service)
    private var muscleGroups: [String] {
        if selectedCategories.isEmpty {
            return ["All"]
        } else if selectedCategories.count == 1 {
            return ExerciseFilterService.muscleGroupsForCategory(selectedCategories.first!)
        } else {
            // Combine muscle groups from all selected categories
            var allMuscles = Set<String>()
            for category in selectedCategories {
                let muscles = ExerciseFilterService.muscleGroupsForCategory(category)
                allMuscles.formUnion(muscles.filter { $0 != "All" })
            }
            return ["All"] + Array(allMuscles).sorted()
        }
    }
    
    // Comprehensive muscle group matching with ALL nicknames/shortnames/aliases
    // Handles official names, anatomical terms, slang, and common abbreviations
    private func isExerciseForMuscleGroup(_ exercise: Exercise, muscleGroup: String) -> Bool {
        let exerciseName = exercise.name?.lowercased() ?? ""
        let exerciseMuscleGroups = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
        let category = exercise.category?.lowercased() ?? ""
        
        // Helper: Check if any string contains any of the aliases
        func matchesAny(_ text: String, aliases: [String]) -> Bool {
            aliases.contains { text.contains($0) }
        }
        
        func muscleGroupsContainAny(_ aliases: [String]) -> Bool {
            exerciseMuscleGroups.contains { group in
                aliases.contains { alias in group.contains(alias) }
            }
        }
        
        // Helper to check if exercise is a fly/flye movement
        let isFlyMovement = exerciseName.contains("fly") || exerciseName.contains("flye") || 
                           exerciseName.contains("pec deck") || exerciseName.contains("crossover")
        
        switch muscleGroup {
        // ═══════════════════════════════════════════════════════════════════════
        // CHEST
        // ═══════════════════════════════════════════════════════════════════════
        case "Upper Chest":
            let isIncline = exerciseName.contains("incline") && !exerciseName.contains("decline")
            let isLowToHigh = exerciseName.contains("low to high") || exerciseName.contains("low-to-high")
            if isFlyMovement && isIncline { return true }
            return isIncline || isLowToHigh ||
                   matchesAny(exerciseName, aliases: ["landmine press", "reverse grip bench"]) ||
                   muscleGroupsContainAny(["upper pec", "upper chest", "clavicular"])
                   
        case "Lower Chest":
            let isDecline = exerciseName.contains("decline") && !exerciseName.contains("incline")
            let isHighToLow = exerciseName.contains("high to low") || exerciseName.contains("high-to-low")
            let isDip = exerciseName.contains("dip") && !exerciseName.contains("hip")
            if isFlyMovement && isDecline { return true }
            return isDecline || isHighToLow || isDip ||
                   muscleGroupsContainAny(["lower pec", "lower chest", "sternal"])
                   
        case "Inner Chest":
            return matchesAny(exerciseName, aliases: ["close grip", "close-grip", "squeeze", "diamond", "crossover", "cross over", "svend"]) ||
                   muscleGroupsContainAny(["inner pec", "inner chest", "medial pec"])
                   
        case "Outer Chest":
            return isFlyMovement ||
                   matchesAny(exerciseName, aliases: ["wide grip", "wide-grip"]) ||
                   muscleGroupsContainAny(["outer pec", "outer chest", "lateral pec"])
                   
        case "Chest", "Pecs", "Pectorals":
            let chestAliases = ["pec", "chest", "bench press", "push up", "pushup"]
            return category == "chest" ||
                   matchesAny(exerciseName, aliases: chestAliases) ||
                   muscleGroupsContainAny(chestAliases)
                   
        // ═══════════════════════════════════════════════════════════════════════
        // BACK
        // ═══════════════════════════════════════════════════════════════════════
        case "Lats", "Latissimus", "Wings":
            let latAliases = ["lat", "latissimus", "wing", "pulldown", "pull down", "pull-down", "chin up", "chinup", "chin-up", "pull up", "pullup", "pull-up"]
            return matchesAny(exerciseName, aliases: latAliases) ||
                   muscleGroupsContainAny(["lat", "latissimus"])
                   
        case "Traps", "Trapezius":
            let trapAliases = ["trap", "trapezius", "shrug", "upright row"]
            return matchesAny(exerciseName, aliases: trapAliases) ||
                   muscleGroupsContainAny(["trap"])
                   
        case "Rhomboids", "Upper Back", "Mid Back":
            let rhomboidAliases = ["rhomboid", "upper back", "mid back", "middle back", "row", "face pull", "rear delt"]
            return matchesAny(exerciseName, aliases: rhomboidAliases) ||
                   muscleGroupsContainAny(["rhomboid", "upper back", "mid back"])
                   
        case "Lower Back", "Erectors", "Lumbar":
            let lowerBackAliases = ["lower back", "erector", "lumbar", "deadlift", "hyperextension", "back extension", "good morning", "superman"]
            return matchesAny(exerciseName, aliases: lowerBackAliases) ||
                   muscleGroupsContainAny(["lower back", "erector", "lumbar", "spinae"])
                   
        case "Back":
            let backAliases = ["lat", "trap", "rhomboid", "erector", "back", "row", "pull"]
            return category == "back" ||
                   muscleGroupsContainAny(backAliases)
                   
        // ═══════════════════════════════════════════════════════════════════════
        // SHOULDERS / DELTS
        // ═══════════════════════════════════════════════════════════════════════
        case "Front Delts", "Anterior Delts", "Front Shoulders":
            let frontDeltAliases = ["front raise", "military press", "overhead press", "shoulder press", "arnold press", "push press", "front delt", "anterior delt"]
            let isPress = exerciseName.contains("press") && !exerciseName.contains("bench") && !exerciseName.contains("leg") && !exerciseName.contains("chest")
            return matchesAny(exerciseName, aliases: frontDeltAliases) || isPress ||
                   muscleGroupsContainAny(["front delt", "anterior delt"])
                   
        case "Side Delts", "Lateral Delts", "Middle Delts", "Medial Delts":
            let sideDeltAliases = ["lateral raise", "side raise", "side delt", "lateral delt", "upright row", "lu raise", "y raise"]
            return matchesAny(exerciseName, aliases: sideDeltAliases) ||
                   muscleGroupsContainAny(["lateral delt", "side delt", "medial delt", "middle delt"])
                   
        case "Rear Delts", "Posterior Delts", "Back Delts":
            let rearDeltAliases = ["rear delt", "posterior delt", "reverse fly", "reverse flye", "face pull", "bent over fly", "bent over raise", "rear lateral"]
            return matchesAny(exerciseName, aliases: rearDeltAliases) ||
                   muscleGroupsContainAny(["rear delt", "posterior delt"])
                   
        case "Shoulders", "Delts", "Deltoids":
            let shoulderAliases = ["delt", "shoulder", "raise", "press"]
            return category == "shoulders" ||
                   muscleGroupsContainAny(shoulderAliases)
                   
        // ═══════════════════════════════════════════════════════════════════════
        // ARMS
        // ═══════════════════════════════════════════════════════════════════════
        case "Biceps", "Bicep", "Bis":
            let bicepAliases = ["bicep", "curl", "chin up", "chinup", "chin-up", "preacher", "hammer", "concentration"]
            return matchesAny(exerciseName, aliases: bicepAliases) ||
                   muscleGroupsContainAny(["bicep", "brachialis"])
                   
        case "Triceps", "Tricep", "Tris":
            let tricepAliases = ["tricep", "extension", "pushdown", "push down", "push-down", "skull crusher", "skullcrusher", "close grip", "diamond push", "kickback", "dip"]
            return matchesAny(exerciseName, aliases: tricepAliases) ||
                   muscleGroupsContainAny(["tricep", "anconeus"])
                   
        case "Forearms", "Forearm", "Wrists":
            let forearmAliases = ["forearm", "wrist", "grip", "farmer", "reverse curl", "hammer curl", "brachioradialis"]
            return matchesAny(exerciseName, aliases: forearmAliases) ||
                   muscleGroupsContainAny(["forearm", "brachioradialis", "wrist"])
                   
        case "Arms":
            let armAliases = ["bicep", "tricep", "forearm", "curl", "extension", "pushdown"]
            return category == "arms" ||
                   muscleGroupsContainAny(armAliases)
                   
        // ═══════════════════════════════════════════════════════════════════════
        // LEGS
        // ═══════════════════════════════════════════════════════════════════════
        case "Quads", "Quadriceps", "Thighs", "Front Thighs":
            let quadAliases = ["quad", "squat", "lunge", "leg press", "leg extension", "step up", "step-up", "front squat", "goblet", "sissy", "split squat", "hack squat", "bulgarian", "vastus", "rectus femoris"]
            return matchesAny(exerciseName, aliases: quadAliases) ||
                   muscleGroupsContainAny(["quad", "vastus", "rectus femoris"])
                   
        case "Hamstrings", "Hams", "Hammies", "Back Thighs":
            let hamstringAliases = ["hamstring", "ham", "leg curl", "romanian", "rdl", "stiff leg", "stiff-leg", "good morning", "nordic", "glute ham", "biceps femoris", "semitendinosus"]
            return matchesAny(exerciseName, aliases: hamstringAliases) ||
                   muscleGroupsContainAny(["hamstring", "biceps femoris", "semitendinosus", "semimembranosus"])
                   
        case "Glutes", "Glute", "Gluteus", "Butt", "Booty":
            let gluteAliases = ["glute", "gluteus", "hip thrust", "hip-thrust", "glute bridge", "kickback", "donkey kick", "fire hydrant", "sumo", "frog pump", "clamshell", "maximus", "medius", "minimus"]
            return matchesAny(exerciseName, aliases: gluteAliases) ||
                   muscleGroupsContainAny(["glute", "gluteus"])
                   
        case "Calves", "Calf":
            let calfAliases = ["calf", "calve", "gastrocnemius", "soleus", "heel raise", "toe raise", "calf raise", "tibialis"]
            return matchesAny(exerciseName, aliases: calfAliases) ||
                   muscleGroupsContainAny(["calf", "calve", "gastrocnemius", "soleus"])
                   
        case "Adductors", "Inner Thighs":
            let adductorAliases = ["adduct", "inner thigh", "copenhagen", "sumo", "groin"]
            return matchesAny(exerciseName, aliases: adductorAliases) ||
                   muscleGroupsContainAny(["adduct", "inner thigh", "groin"])
                   
        case "Hip Flexors", "Iliopsoas", "Psoas":
            let hipFlexorAliases = ["hip flexor", "psoas", "iliopsoas", "leg raise", "knee raise", "hanging raise", "flutter kick", "bicycle"]
            return matchesAny(exerciseName, aliases: hipFlexorAliases) ||
                   muscleGroupsContainAny(["hip flexor", "psoas", "iliopsoas"])
                   
        case "Legs":
            let legAliases = ["quad", "hamstring", "glute", "calf", "leg", "squat", "lunge"]
            return category == "legs" ||
                   muscleGroupsContainAny(legAliases)
                   
        // ═══════════════════════════════════════════════════════════════════════
        // CORE / ABS
        // ═══════════════════════════════════════════════════════════════════════
        case "Abs", "Abdominals", "Six Pack", "Rectus Abdominis":
            let absAliases = ["ab", "crunch", "sit up", "situp", "sit-up", "leg raise", "plank", "v-up", "vup", "hollow", "dead bug", "rectus abdominis", "six pack"]
            return matchesAny(exerciseName, aliases: absAliases) ||
                   muscleGroupsContainAny(["ab", "rectus abdominis"]) ||
                   category == "core"
                   
        case "Upper Abs":
            let upperAbsAliases = ["crunch", "sit up", "situp", "sit-up", "upper ab"]
            return matchesAny(exerciseName, aliases: upperAbsAliases) ||
                   muscleGroupsContainAny(["upper ab"])
                   
        case "Lower Abs":
            let lowerAbsAliases = ["leg raise", "knee raise", "reverse crunch", "hanging raise", "flutter", "scissor", "lower ab"]
            return matchesAny(exerciseName, aliases: lowerAbsAliases) ||
                   muscleGroupsContainAny(["lower ab"])
                   
        case "Obliques", "Oblique", "Love Handles", "Side Abs":
            let obliqueAliases = ["oblique", "side bend", "russian twist", "woodchop", "wood chop", "bicycle", "windshield wiper", "side plank", "pallof"]
            return matchesAny(exerciseName, aliases: obliqueAliases) ||
                   muscleGroupsContainAny(["oblique"])
                   
        case "Core":
            let coreAliases = ["ab", "oblique", "plank", "crunch", "core", "hollow", "dead bug"]
            return category == "core" ||
                   muscleGroupsContainAny(coreAliases)
                   
        // ═══════════════════════════════════════════════════════════════════════
        // SPECIAL
        // ═══════════════════════════════════════════════════════════════════════
        case "Rotator Cuff", "Rotators":
            let rotatorAliases = ["rotator", "external rotation", "internal rotation", "cuban", "face pull", "infraspinatus", "supraspinatus", "subscapularis", "teres minor"]
            return matchesAny(exerciseName, aliases: rotatorAliases) ||
                   muscleGroupsContainAny(["rotator", "infraspinatus", "supraspinatus"])
                   
        default:
            // Generic fallback: try direct match on muscle group name
            let target = muscleGroup.lowercased()
            return exerciseMuscleGroups.contains { $0.contains(target) } ||
                   exerciseName.contains(target)
        }
    }
    // Updated equipment types for 7000+ exercise library
    private let equipmentTypes = ExerciseFilterService.allEquipment
    
    private var filterIcon: String {
        switch exerciseFilter {
        case .recommended:
            return "star.circle.fill"
        case .favorites:
            return "heart.fill"
        case .custom:
            return "person.crop.circle.badge.plus"
        case .strength:
            return "dumbbell.fill"
        case .cardio:
            return "heart.text.square.fill"
        case .plyometrics:
            return "figure.jumprope"
        case .stretching:
            return "figure.flexibility"
        case .all:
            return "line.3.horizontal.decrease.circle"
        }
    }
    
    private var filterColor: Color {
        switch exerciseFilter {
        case .recommended:
            return .blue  // Blue to match theme
        case .favorites:
            return .yellow
        case .custom:
            return .blue
        case .strength:
            return .purple
        case .cardio:
            return .red
        case .plyometrics:
            return .orange
        case .stretching:
            return .green
        case .all:
            return .secondary
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ⚡️ HIGH-PERFORMANCE SEARCH ENGINE - Senior Engineer Level
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Ultra-fast filter update - typing should feel INSTANT
    private func updateFilteredExercises() {
        filterUpdateTask?.cancel()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Build filter key for caching (using sorted sets for consistent hashing)
        let categoryKey = selectedCategories.isEmpty ? "All" : selectedCategories.sorted().joined(separator: ",")
        let equipmentKey = selectedEquipmentItems.isEmpty ? "All" : selectedEquipmentItems.sorted().joined(separator: ",")
        let muscleKey = selectedMuscleGroups.isEmpty ? "All" : selectedMuscleGroups.sorted().joined(separator: ",")
        let filterKey = "\(exerciseFilter.rawValue)|\(categoryKey)|\(equipmentKey)|\(muscleKey)"
        
        // If filters changed, rebuild pre-filtered cache
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchResultsCache.removeAll() // Invalidate search cache
            
            // ⚡️ INSTANT: For default "Recommended" with no extra filters, use the pre-computed list
            // This was built at startup by TabPreloader — zero work here, just pointer assignment
            let filterCache = ExerciseLibraryFilterCache.shared
            if selectedCategories.isEmpty && selectedEquipmentItems.isEmpty && selectedMuscleGroups.isEmpty && exerciseFilter == .recommended && filterCache.isReady {
                preFilteredExercises = filterCache.preFilteredRecommended
                #if DEBUG
                print("⚡️ [PERF] INSTANT recommended from pre-computed cache: \(preFilteredExercises.count) exercises (0ms)")
                #endif
            } else if selectedCategories.isEmpty && selectedEquipmentItems.isEmpty && selectedMuscleGroups.isEmpty && exerciseFilter == .recommended {
                // Fallback: cache not ready yet (very early cold start), compute inline
                preFilteredExercises = applyOptimizedRecommendedFilter(to: exercises)
                #if DEBUG
                print("⚡️ [PERF] Optimized recommended filter (fallback): \(preFilteredExercises.count) exercises in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms")
                #endif
            } else {
                // Standard filter path for non-default filters
                preFilteredExercises = applyFiltersOnly(to: exercises)
                #if DEBUG
                print("⚡️ [PERF] Rebuilt filter cache: \(preFilteredExercises.count) exercises in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms")
                #endif
            }
        }
        
        // For search: use ultra-fast local search on pre-filtered results
        if !searchText.isEmpty {
            let searchKey = searchText.lowercased()
            
            // Check search cache first
            if let cached = searchResultsCache[searchKey] {
                cachedFilteredExercises = cached
                #if DEBUG
                print("⚡️ [PERF] Search cache hit for '\(searchKey)': \(cached.count) results")
                #endif
                return
            }
            
            // Ultra-fast search - no heavy processing
            let results = ultraFastSearch(query: searchKey, in: preFilteredExercises)
            searchResultsCache[searchKey] = results
                cachedFilteredExercises = results
            
            #if DEBUG
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("⚡️ [PERF] Search '\(searchKey)': \(results.count) results in \(String(format: "%.1f", elapsed))ms")
            #endif
            return
        }
        
        // No search text - just show pre-filtered results
        cachedFilteredExercises = preFilteredExercises
    }
    
    /// Ultra-fast search - O(n) with word-order-independent matching
    private func ultraFastSearch(query: String, in exercises: [Exercise]) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        
        let queryLower = query.lowercased()
        
        // Split query into words and correct typos for each
        let queryWords = queryLower.split(separator: " ").map { correctCommonTypos(String($0)) }
        let isMultiWord = queryWords.count > 1
        
        // Get keyword variations for single-word queries
        let variations = isMultiWord ? [queryLower] : getQuickVariations(queryLower)
        
        // Build corrected query for direct substring matching
        let correctedQuery = queryWords.joined(separator: " ")
        
        // Priority buckets (highest to lowest):
        // 1. exactMatches: name equals query exactly
        // 2. startsWithPhraseMatches: name STARTS with the exact phrase (e.g., "front raise" → "Front Raise (Dumbbell)")
        // 3. containsPhraseMatches: name CONTAINS the exact phrase (e.g., "front raise" → "Seated Front Raise")
        // 4. allWordsMatches: all words found but not as contiguous phrase (e.g., "front raise" → "Front Lat Raise")
        var exactMatches: [Exercise] = []
        var startsWithPhraseMatches: [Exercise] = []
        var containsPhraseMatches: [Exercise] = []
        var allWordsMatches: [Exercise] = []
        
        for exercise in exercises {
            guard let name = exercise.name?.lowercased() else { continue }
            
            var matched = false
            
            // SINGLE-WORD: Use variation matching for typo tolerance
            if !isMultiWord {
                for variation in variations {
                    if name == variation {
                        exactMatches.append(exercise)
                        matched = true
                        break
                    } else if name.hasPrefix(variation) {
                        startsWithPhraseMatches.append(exercise)
                        matched = true
                        break
                    } else if name.contains(variation) {
                        containsPhraseMatches.append(exercise)
                        matched = true
                        break
                    }
                }
            }
            
            // MULTI-WORD: Check for exact phrase match first (preserves word order)
            if !matched && isMultiWord {
                if name == correctedQuery {
                    exactMatches.append(exercise)
                    matched = true
                } else if name.hasPrefix(correctedQuery) {
                    // Name STARTS with the exact phrase - highest priority
                    startsWithPhraseMatches.append(exercise)
                    matched = true
                } else if name.contains(correctedQuery) {
                    // Name CONTAINS the exact phrase - second priority
                    containsPhraseMatches.append(exercise)
                    matched = true
                }
            }
            
            // MULTI-WORD: Word-order-independent matching (lowest priority)
            if !matched && isMultiWord {
                let allWordsFound = queryWords.allSatisfy { word in
                    let wordVariations = getQuickVariations(word)
                    return wordVariations.contains { variation in name.contains(variation) }
                }
                if allWordsFound {
                    allWordsMatches.append(exercise)
                }
            }
        }
        
        // Return in priority order: exact phrase ordering is prioritized
        return exactMatches + startsWithPhraseMatches + containsPhraseMatches + allWordsMatches
    }
    
    /// Quick keyword variations with typo correction and singular/plural - minimal overhead
    private func getQuickVariations(_ query: String) -> [String] {
        // First, correct common typos
        let corrected = correctCommonTypos(query)
        var variations = corrected == query ? [query] : [query, corrected]
        
        // Add singular/plural and spelling variations
        let baseWord = corrected
        switch baseWord {
        // Fly variations
        case "fly": variations += ["flye", "flyes", "flies"]
        case "flye": variations += ["fly", "flyes", "flies"]
        case "flyes", "flies": variations += ["fly", "flye"]
        
        // Curl variations (singular/plural)
        case "curl": variations += ["curls"]
        case "curls": variations += ["curl"]
        
        // Press variations
        case "press": variations += ["presses"]
        case "presses": variations += ["press"]
        
        // Row variations
        case "row": variations += ["rows"]
        case "rows": variations += ["row"]
        
        // Raise variations
        case "raise": variations += ["raises"]
        case "raises": variations += ["raise"]
        
        // Bicep/Tricep variations (singular/plural)
        case "bicep": variations += ["biceps"]
        case "biceps": variations += ["bicep"]
        case "tricep": variations += ["triceps"]
        case "triceps": variations += ["tricep"]
        
        // Pulldown/Pushdown variations
        case "pulldown": variations += ["pull-down", "pull down", "pulldowns"]
        case "pushdown": variations += ["push-down", "push down", "pushdowns"]
        
        // Equipment variations
        case "dumbbell": variations += ["dumbell", "dumbells", "dumbbells"]
        case "dumbbells": variations += ["dumbbell", "dumbell"]
        case "barbell": variations += ["barbel", "barbells"]
        case "barbells": variations += ["barbell", "barbel"]
        
        // Extension variations
        case "extension": variations += ["extensions"]
        case "extensions": variations += ["extension"]
        
        // Squat variations
        case "squat": variations += ["squats"]
        case "squats": variations += ["squat"]
        
        // Lunge variations
        case "lunge": variations += ["lunges"]
        case "lunges": variations += ["lunge"]
        
        // Deadlift variations
        case "deadlift": variations += ["deadlifts"]
        case "deadlifts": variations += ["deadlift"]
        
        // Shrug variations
        case "shrug": variations += ["shrugs"]
        case "shrugs": variations += ["shrug"]
        
        // Crunch variations
        case "crunch": variations += ["crunches"]
        case "crunches": variations += ["crunch"]
        
        // Dip variations
        case "dip": variations += ["dips"]
        case "dips": variations += ["dip"]
        
        // Pullup/Pushup variations
        case "pullup", "pull up": variations += ["pullups", "pull ups", "pull-up", "pull-ups"]
        case "pushup", "push up": variations += ["pushups", "push ups", "push-up", "push-ups"]
        case "chinup", "chin up": variations += ["chinups", "chin ups", "chin-up", "chin-ups"]
        
        default:
            // Generic: if ends in 's', try without; if doesn't, try with 's'
            if baseWord.hasSuffix("s") && baseWord.count > 3 {
                variations.append(String(baseWord.dropLast()))
            } else if !baseWord.hasSuffix("s") && baseWord.count > 2 {
                variations.append(baseWord + "s")
            }
        }
        
        return variations
    }
    
    /// Fast typo correction for common misspellings
    private func correctCommonTypos(_ query: String) -> String {
        // Only do EXACT matches - no substring replacement which causes bugs
        // e.g., "decline" was becoming "declinee" because it contains "declin"
        let typoMap: [String: String] = [
            // Equipment typos
            "dumbell": "dumbbell",
            "dumbel": "dumbbell", 
            "dumble": "dumbbell",
            "dumbells": "dumbbells",
            "dumbels": "dumbbells",
            "barbel": "barbell",
            "barble": "barbell",
            "kettleball": "kettlebell",
            "kettlebel": "kettlebell",
            "cabel": "cable",
            "cabels": "cables",
            "machien": "machine",
            "mashine": "machine",
            
            // Exercise type typos
            "flye": "fly",
            "flyes": "flies",
            "pres": "press",
            "presss": "press",
            "curle": "curl",
            "rwo": "row",
            "sqaut": "squat",
            "sqat": "squat",
            "squatt": "squat",
            "deadlif": "deadlift",
            "dedlift": "deadlift",
            "extention": "extension",
            "extenstion": "extension",
            "pullup": "pull up",
            "pushup": "push up",
            "chinup": "chin up",
            
            // Muscle group typos
            "bycep": "bicep",
            "byceps": "biceps",
            "bicept": "bicep",
            "trycep": "tricep",
            "tryceps": "triceps",
            "tricept": "tricep",
            "sholder": "shoulder",
            "sholders": "shoulders",
            "shouder": "shoulder",
            "hamstring": "hamstrings",
            "hammstring": "hamstrings",
            "calfs": "calves",
            "quatricep": "quadricep",
            "glute": "glutes",
            
            // Other common typos
            "inclin": "incline",
            "inclien": "incline",
            "declin": "decline",
            "declien": "decline",
            "laterl": "lateral",
            "latral": "lateral",
            "revers": "reverse",
            "reverese": "reverse",
            "bensh": "bench",
            "banch": "bench",
            "benc": "bench"
        ]
        
        // Only return correction for EXACT match
        return typoMap[query] ?? query
    }
    
    // ⚡️ OPTIMIZED: Fast recommended filter using precomputed Set lookup
    private func applyOptimizedRecommendedFilter(to exercises: [Exercise]) -> [Exercise] {
        // Use precomputed set for O(1) lookup instead of O(n) contains check
        let recommendedSet = ExerciseLibraryFilterCache.shared.recommendedExerciseNames
        
        return exercises.filter { exercise in
            guard let name = exercise.name?.lowercased() else { return false }
            
            // Fast check: does name contain any recommended exercise?
            // First try exact word boundary matches (most common case)
            for rec in recommendedSet {
                if name == rec || 
                   name.hasPrefix(rec + " ") || 
                   name.hasPrefix(rec + "(") ||
                   name.contains(" " + rec + " ") ||
                   name.contains(" " + rec + "(") {
                    return true
                }
            }
            return false
        }
    }
    
    /// Apply category/equipment/muscle filters WITHOUT search
    private func applyFiltersOnly(to exercises: [Exercise]) -> [Exercise] {
        var filtered = exercises
        
        // Filter by exercise filter type
        switch exerciseFilter {
        case .recommended:
            filtered = filtered.filter { exercise in
                let fullName = (exercise.name ?? "").lowercased()
                return recommendedExercises.contains { rec in
                    fullName == rec || fullName.hasPrefix(rec + " ") || fullName.hasPrefix(rec + "(")
                }
            }
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .custom:
            filtered = filtered.filter { $0.instructions?.contains("[CUSTOM_EXERCISE") ?? false }
        case .strength:
            filtered = filtered.filter { exercise in
                if let workoutType = exercise.workoutType, !workoutType.isEmpty {
                    return workoutType.lowercased() == "strength"
                }
                let smartType = ExerciseFilterService.classifyExerciseType(
                    name: exercise.name, category: exercise.category, equipment: exercise.equipment
                )
                return smartType == .strength
            }
        case .cardio:
            filtered = filtered.filter { exercise in
                if let workoutType = exercise.workoutType, !workoutType.isEmpty {
                    return workoutType.lowercased() == "cardio"
                }
                let smartType = ExerciseFilterService.classifyExerciseType(
                    name: exercise.name, category: exercise.category, equipment: exercise.equipment
                )
                return smartType == .cardio
            }
        case .plyometrics:
            filtered = filtered.filter { exercise in
                if let workoutType = exercise.workoutType, !workoutType.isEmpty {
                    return workoutType.lowercased() == "plyometrics"
                }
                let smartType = ExerciseFilterService.classifyExerciseType(
                    name: exercise.name, category: exercise.category, equipment: exercise.equipment
                )
                return smartType == .plyometrics
            }
        case .stretching:
            filtered = filtered.filter { exercise in
                if let workoutType = exercise.workoutType, !workoutType.isEmpty {
                    let normalizedType = workoutType.lowercased()
                    return normalizedType == "stretch" || normalizedType == "stretching"
                }
                let smartType = ExerciseFilterService.classifyExerciseType(
                    name: exercise.name, category: exercise.category, equipment: exercise.equipment
                )
                return smartType == .stretching
            }
        case .all:
            break
        }
        
        // Filter by category (multi-select - show exercises matching ANY selected category)
        if !selectedCategories.isEmpty {
            let selectedLower = Set(selectedCategories.map { $0.lowercased() })
            filtered = filtered.filter { exercise in
                let exerciseCategory = (exercise.category ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
                return selectedLower.contains { categoryLower in
                    exerciseCategory == categoryLower || exerciseCategory.contains(categoryLower)
                }
            }
        }
        
        // Filter by equipment (multi-select - show exercises matching ANY selected equipment)
        if !selectedEquipmentItems.isEmpty {
            filtered = filtered.filter { exercise in
                selectedEquipmentItems.contains { equipmentItem in
                    exerciseMatchesEquipmentLib(exercise, selectedEquipment: equipmentItem)
                }
            }
        }
        
        // Filter by muscle group (multi-select - show exercises matching ANY selected muscle)
        if !selectedMuscleGroups.isEmpty {
            filtered = filtered.filter { exercise in
                selectedMuscleGroups.contains { muscleGroup in
                    isExerciseForMuscleGroup(exercise, muscleGroup: muscleGroup)
                }
            }
        }
        
        return filtered
    }
    
    // Legacy computed property for backwards compatibility (use cachedFilteredExercises instead)
    var filteredExercises: [Exercise] {
        cachedFilteredExercises
    }
    
    // MARK: - Equipment Matching
    /// Comprehensive equipment matching with normalization
    private func exerciseMatchesEquipmentLib(_ exercise: Exercise, selectedEquipment: String) -> Bool {
        let exerciseEquipment = exercise.equipment?.lowercased() ?? ""
        let targetEquipment = selectedEquipment.lowercased()
        let exerciseName = exercise.name?.lowercased() ?? ""
        
        // Direct match
        if exerciseEquipment == targetEquipment { return true }
        
        // Normalize and compare
        let normalizedExercise = ExerciseFilterService.normalizeEquipment(exercise.equipment)
        if normalizedExercise == selectedEquipment { return true }
        
        // Handle compound equipment (comma-separated)
        let equipmentParts = exerciseEquipment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        
        switch targetEquipment {
        case "dumbbells":
            return exerciseEquipment.contains("dumbbell") || exerciseName.contains("dumbbell") ||
                   equipmentParts.contains { $0.contains("dumbbell") }
        case "barbell":
            let isBarbell = exerciseEquipment.contains("barbell") || exerciseName.contains("barbell") ||
                           exerciseEquipment.contains("ez bar") || exerciseEquipment.contains("trap bar") ||
                           equipmentParts.contains { $0.contains("barbell") }
            return isBarbell && !exerciseEquipment.contains("smith")
        case "cables":
            return exerciseEquipment.contains("cable") || exerciseName.contains("cable") ||
                   equipmentParts.contains { $0.contains("cable") }
        case "machines":
            // IMPORTANT: Check cables and smith FIRST to exclude them
            let isCable = exerciseEquipment.contains("cable") || exerciseName.contains("cable")
            if isCable { return false }
            
            let isSmith = exerciseEquipment.contains("smith")
            if isSmith { return false }
            
            // Any machine or lever equipment
            let isMachine = exerciseEquipment.contains("machine") ||
                           exerciseEquipment.contains("lever") ||
                           equipmentParts.contains { $0.contains("machine") || $0.contains("lever") }
            
            return isMachine
        case "bodyweight":
            return exerciseEquipment.isEmpty || exerciseEquipment.contains("bodyweight") ||
                   exerciseEquipment == "body weight"
        case "kettlebell":
            return exerciseEquipment.contains("kettlebell") || exerciseName.contains("kettlebell") ||
                   equipmentParts.contains { $0.contains("kettlebell") }
        case "resistance bands", "bands":
            return exerciseEquipment.contains("band") || exerciseName.contains("band") ||
                   equipmentParts.contains { $0.contains("band") }
        case "bench":
            return exerciseEquipment.contains("bench") || equipmentParts.contains { $0.contains("bench") }
        case "smith machine":
            return exerciseEquipment.contains("smith") || exerciseName.contains("smith")
        case "trx/rings":
            return exerciseEquipment.contains("trx") || exerciseEquipment.contains("ring") ||
                   exerciseEquipment.contains("suspension") || exerciseName.contains("trx") ||
                   equipmentParts.contains { $0.contains("trx") || $0.contains("ring") || $0.contains("suspension") }
        case "stability ball":
            return exerciseEquipment.contains("stability ball") || exerciseEquipment.contains("swiss ball") ||
                   exerciseName.contains("stability ball")
        case "medicine ball":
            return exerciseEquipment.contains("medicine ball") || exerciseName.contains("medicine ball")
        case "pull-up bar":
            return exerciseEquipment.contains("pull-up bar") || exerciseEquipment.contains("pullup") ||
                   exerciseName.contains("pull up") || exerciseName.contains("pull-up") ||
                   exerciseName.contains("chin up") || exerciseName.contains("chin-up")
        default:
            // Fallback: check if equipment contains target or vice versa
            return exerciseEquipment.contains(targetEquipment) || targetEquipment.contains(exerciseEquipment) ||
                   equipmentParts.contains { $0.contains(targetEquipment) || targetEquipment.contains($0) }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed header section (doesn't scroll)
                VStack(spacing: 0) {
                    // Custom header
                    customHeaderView
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    
                    // Compact search and filters
                    compactFiltersView
                    
                    // Banner ad - integrated below filters for free users
                    if !PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled {
                        BannerAdView()
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
                .padding(.bottom, 12)
                
                // Scrollable exercise list only
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id("top")
                        
                        if filteredExercises.isEmpty && !exerciseLibrary.isExercisesReady {
                            VStack(spacing: Spacing.md) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.blue)
                                Text("Loading exercises...")
                                    .font(.ds_bodyMedium)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, Spacing.xxl)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(Array(filteredExercises.enumerated()), id: \.element.objectID) { index, exercise in
                                    NavigationLink(value: exercise) {
                                        CompactExerciseRowContent(exercise: exercise, showChevron: true)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .simultaneousGesture(TapGesture().onEnded {
                                        // ⚡️ Track exercise selection for dynamic popularity ranking
                                        if let name = exercise.name {
                                            ExerciseLibraryFilterCache.shared.trackExerciseSelection(exerciseName: name)
                                        }
                                    })
                                    // 🚀 Smart prefetch: preload video when exercise becomes visible
                                    .onAppear {
                                        prefetchVisibleExercise(exercise: exercise, index: index)
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, 4)
                            .padding(.bottom, 20)
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .id(forceRenderID)
                    .refreshable {
                        loadExercises()
                    }
                    .onChange(of: scrollToTopTrigger) { _, _ in
                        scrollProxy.scrollTo("top", anchor: .top)
                    }
                }
            }
            // ⚡️ SNAPPY SEARCH: Dismiss keyboard immediately when scrolling
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    isSearchFocused = false
                }
            )
            .background(
                AnimatedOrbBackground.exercises(colorScheme: colorScheme)
            )
            // Banner ad is now integrated into the fixed header section above
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .onAppear {
                let startTime = Date()
                
                // Restore state from ViewStateCache for instant tab switch
                let cachedState = ViewStateCache.shared.exerciseLibraryState
                let hasState = !cachedState.searchText.isEmpty
                    || cachedState.selectedCategory != "All"
                    || cachedState.selectedEquipment != "All"
                    || cachedState.selectedMuscleGroup != "All"
                if hasState {
                    searchText = cachedState.searchText
                    if cachedState.selectedCategory != "All" {
                        selectedCategories = [cachedState.selectedCategory]
                    }
                    if cachedState.selectedEquipment != "All" {
                        selectedEquipmentItems = [cachedState.selectedEquipment]
                    }
                    if cachedState.selectedMuscleGroup != "All" {
                        selectedMuscleGroups = [cachedState.selectedMuscleGroup]
                    }
                }
                
                // Load exercises from cache first
                loadExercises()
                
                // Re-compute recommended filter cache if it was built with 0 exercises
                // (happens when tab preloader ran before cloud sync completed)
                let filterCache = ExerciseLibraryFilterCache.shared
                if !exercises.isEmpty && filterCache.preFilteredRecommended.isEmpty {
                    filterCache.precomputeRecommendedList(allExercises: exercises)
                }
                
                // ⚡️ HIGH-PERFORMANCE: Initialize filter cache immediately
                updateFilteredExercises()
                
                // Log screen appearance with unique ID
                SessionLogManager.shared.logScreen(.exerciseLibrary, metadata: [
                    "exercise_count": exercises.count,
                    "filter": exerciseFilter.rawValue,
                    "load_time_ms": Int(Date().timeIntervalSince(startTime) * 1000)
                ])
                
                // Only trigger cloud sync if we have very few exercises (< 500)
                if exercises.count < 500 && !WorkoutManager.shared.isWorkoutActive {
                    print("📚 [LIBRARY] Exercise count (\(exercises.count)) very low, triggering cloud sync...")
                    SessionLogManager.shared.logDataSync(type: "Exercises", itemCount: exercises.count, direction: "download")
                    Task {
                        await ExerciseLibraryService.shared.syncExercisesFromCloud()
                        await MainActor.run {
                            loadExercises()
                            lastFilterKey = "" // Force filter rebuild
                            updateFilteredExercises()
                            print("📚 [LIBRARY] Sync complete, now have \(exercises.count) exercises")
                        }
                    }
                }
            }
            // ⚡️ HIGH-PERFORMANCE: Instant filter updates with state caching
            .onChange(of: searchText) { _, newValue in
                updateFilteredExercises()
                ViewStateCache.shared.exerciseLibraryState.searchText = newValue
            }
            .onChange(of: selectedCategories) { _, newValue in 
                lastFilterKey = ""
                selectedMuscleGroups = []
                updateFilteredExercises()
                ViewStateCache.shared.exerciseLibraryState.selectedCategory = newValue.first ?? "All"
            }
            .onChange(of: selectedEquipmentItems) { _, newValue in 
                lastFilterKey = ""
                updateFilteredExercises()
                ViewStateCache.shared.exerciseLibraryState.selectedEquipment = newValue.first ?? "All"
            }
            .onChange(of: selectedMuscleGroups) { _, newValue in 
                lastFilterKey = ""
                updateFilteredExercises()
                ViewStateCache.shared.exerciseLibraryState.selectedMuscleGroup = newValue.first ?? "All"
            }
            .onChange(of: exerciseFilter) { _, _ in 
                lastFilterKey = "" // Force filter rebuild
                updateFilteredExercises() 
            }
            .onChange(of: exercises) { _, _ in 
                lastFilterKey = "" // Force filter rebuild
                updateFilteredExercises() 
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // ⚡️ PERFORMANCE: Only refresh if this tab was previously visited
                // Prevents heavy work when user isn't on this tab
                guard LazyTabManager.shared.shouldRenderContent(for: .exercises) else { return }
                
                // Debounced refresh - don't block foreground transition
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
                    await MainActor.run {
                        viewContext.refreshAllObjects()
                        loadExercises()
                        updateFilteredExercises()
                    }
                }
            }
            // 🔄 Reload when exercises become ready after cloud sync
            .onChange(of: exerciseLibrary.isExercisesReady) { _, isReady in
                if isReady {
                    print("✅ [LIBRARY] Exercises now ready after sync - reloading list")
                    viewContext.refreshAllObjects()
                    loadExercises()
                    
                    // Re-compute the recommended filter cache with actual exercises
                    // (it was pre-computed at startup when Core Data was empty)
                    if !exercises.isEmpty {
                        ExerciseLibraryFilterCache.shared.precomputeRecommendedList(allExercises: exercises)
                    }
                    
                    lastFilterKey = "" // Force filter rebuild
                    searchResultsCache.removeAll()
                    updateFilteredExercises()
                    forceRenderID = UUID()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FavoriteExerciseChanged"))) { _ in
                // Refresh when favorites are changed
                print("📚 Exercise Library: Favorite changed, refreshing...")
                viewContext.refreshAllObjects()
                loadExercises()
                updateFilteredExercises()
                forceRenderID = UUID()
            }
        }
    }
    
    // MARK: - Custom Header View
    private var customHeaderView: some View {
        HStack {
            Text("Exercises")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.blue, Color.cyan.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 2)
            
            Spacer()
            
            // Active workout timer (only shows when workout is active)
            if WorkoutManager.shared.isWorkoutActive {
                Text(WorkoutManager.shared.formattedDuration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.leading, 4)
    }
    
    private var compactFiltersView: some View {
        VStack(spacing: 16) {
            // Search section with title
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        Text("\(filteredExercises.count.formatted()) exercises")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Exercise filter dropdown
                    Menu {
                        ForEach(ExerciseFilterType.allCases, id: \.self) { filterType in
                    Button(action: {
                        HapticManager.selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    exerciseFilter = filterType
                        }
                    }) {
                                HStack {
                                    Text(filterType.rawValue)
                                    if exerciseFilter == filterType {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filterIcon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(exerciseFilter.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(exerciseFilter == .all ? .secondary : filterColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .stroke(exerciseFilter == .all ? Color(.systemGray4) : filterColor, lineWidth: 1.5)
                        )
                    }
                }
                
                // ⚡️ SNAPPY SEARCH: Instant response search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Search exercises...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .focused($isSearchFocused)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit {
                            // ⚡️ INSTANT keyboard dismiss on return
                            isSearchFocused = false
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { 
                            HapticManager.selectionChanged()
                            searchText = ""
                            isSearchFocused = false // Also dismiss keyboard when clearing
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6).opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.03), lineWidth: 1)
                )
            }
            
            // Compact filter categories with expandable multi-select dropdowns
            VStack(alignment: .leading, spacing: 8) {
                // Categories row
                HStack(spacing: 8) {
                    Text("Category")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(categories, id: \.self) { category in
                                MultiSelectFilterChip(
                                    text: category,
                                    isSelected: category == "All" ? selectedCategories.isEmpty : selectedCategories.contains(category),
                                    color: .blue,
                                    secondaryColor: .cyan,
                                    allOptions: categories,
                                    selectedItems: $selectedCategories
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                
                // Muscle Groups row (only if category selected)
                if !selectedCategories.isEmpty && muscleGroups.count > 1 {
                    HStack(spacing: 8) {
                        Text("Muscles")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(muscleGroups, id: \.self) { muscle in
                                    MultiSelectFilterChip(
                                        text: muscle,
                                        isSelected: muscle == "All" ? selectedMuscleGroups.isEmpty : selectedMuscleGroups.contains(muscle),
                                        color: .green,
                                        secondaryColor: .teal,
                                        allOptions: muscleGroups,
                                        selectedItems: $selectedMuscleGroups
                                    )
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }
                
                // Equipment row
                HStack(spacing: 8) {
                    Text("Equipment")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(equipmentTypes, id: \.self) { equipment in
                                MultiSelectFilterChip(
                                    text: equipment,
                                    isSelected: equipment == "All" ? selectedEquipmentItems.isEmpty : selectedEquipmentItems.contains(equipment),
                                    color: .orange,
                                    secondaryColor: .red.opacity(0.7),
                                    allOptions: equipmentTypes,
                                    selectedItems: $selectedEquipmentItems
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - blue tinted (subtle)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.blue.opacity(colorScheme == .dark ? 0.08 : 0.04))
                    .offset(y: 5)
                    .blur(radius: 3)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.1 : 0.02))
                    .offset(y: 3)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Colored accent border - soft blue
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(colorScheme == .dark ? 0.35 : 0.25),
                                Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.05), radius: 8, x: 0, y: 4)
        .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 12, x: 0, y: 6)
    }
    
    private func loadExercises() {
        let loaded = ExerciseLibraryService.shared.getAllExercises()
        if !loaded.isEmpty {
            exercises = loaded
        } else if !exerciseLibrary.isExercisesReady {
            seedFromBundleIfNeeded()
        }
    }
    
    private func seedFromBundleIfNeeded() {
        guard exercises.isEmpty else { return }
        Task {
            ExerciseLibraryService.shared.seedFromBundle()
            loadExercises()
            updateFilteredExercises()
        }
    }
    
    // MARK: - 🚀 Smart Video Prefetching
    
    /// ⚡️ MEMORY FIX: DISABLED scroll-based video prefetching.
    /// This was creating AVPlayers for every visible exercise row on scroll (~8 rows × 3 prefetches = 24 players).
    /// Each player leaks ~20-50MB through iOS's XPC video process that can't be reclaimed fast enough.
    /// Videos now load on-demand only when user taps into ExerciseDetailView (via RemoteVideoPlayerView).
    /// Poster frames from VideoThumbnailService provide instant visual feedback instead.
    private func prefetchVisibleExercise(exercise: Exercise, index: Int) {
        // NO-OP: Scroll prefetching disabled to prevent memory pressure.
        // Video loads on-demand in ExerciseDetailView.
    }
}

struct CompactExerciseRowContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let exercise: Exercise
    var showChevron: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Compact exercise icon with vibrant gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: categoryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                if exercise.category?.lowercased() == "core" {
                    CoreIcon(size: 22, color: .white)
                } else {
                    Image(systemName: categoryIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let category = exercise.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(categoryColor)
                            .fontWeight(.medium)
                    }
                    
                    if let equipment = exercise.equipment {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(equipment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // Favorite star indicator
            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.yellow)
            }
            
            // Chevron inside the card
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .sleekCardSubtle(cornerRadius: 16)
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }
    
    // Exact gradients matching the Workout tab style
    private var categoryGradient: [Color] {
        switch exercise.category?.lowercased() {
        case "chest":
            // Pink/Magenta (like Auto Workout)
            return [Color.purple, Color.pink]
        case "back":
            // Blue/Cyan (like Custom Workout)
            return [Color.blue, Color.cyan]
        case "legs":
            // Green/Teal (like Training Programs)
            return [Color.green, Color.teal]
        case "shoulders":
            // Orange/Yellow (like Favorites)
            return [Color.orange, Color.yellow]
        case "arms":
            // Purple/Indigo (same style)
            return [Color.purple, Color.indigo]
        case "core":
            // Yellow/Orange (inverted Favorites style)
            return [Color.yellow, Color.orange]
        case "full body":
            // Pink/Red (same style)
            return [Color.pink, Color.red]
        default:
            return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
    
    private var categoryIcon: String {
        // Check if this is a custom exercise with custom icon
        if let instructions = exercise.instructions,
           instructions.contains("[CUSTOM_EXERCISE|ICON:"),
           let iconRange = instructions.range(of: #"\[CUSTOM_EXERCISE\|ICON:([^\]]+)\]"#, options: .regularExpression),
           let iconName = instructions[iconRange].split(separator: ":").last?.replacingOccurrences(of: "]", with: "") {
            return String(iconName)
        }
        
        // First, check for specific exercise patterns
        if let exerciseName = exercise.name?.lowercased() {
            
            // Dumbbell exercises
            if exerciseName.contains("dumbbell") {
                return "dumbbell.fill"
            }
            
            // Barbell exercises  
            else if exerciseName.contains("barbell") {
                return "figure.strengthtraining.traditional"
            }
            
            // Cable exercises
            else if exerciseName.contains("cable") {
                return "dot.radiowaves.left.and.right"
            }
            
            // Push-up variations
            else if exerciseName.contains("push") && exerciseName.contains("up") {
                return "figure.strengthtraining.traditional"
            }
            
            // Pull-up variations  
            else if exerciseName.contains("pull") && (exerciseName.contains("up") || exerciseName.contains("chin")) {
                return "figure.climbing"
            }
            
            // Squat variations
            else if exerciseName.contains("squat") {
                return "figure.squat"
            }
            
            // Lunge variations
            else if exerciseName.contains("lunge") {
                return "figure.walk"
            }
            
            // Hip thrust variations
            else if exerciseName.contains("thrust") || exerciseName.contains("bridge") {
                return "figure.strengthtraining.functional"
            }
            
            // Deadlift variations
            else if exerciseName.contains("deadlift") {
                return "figure.strengthtraining.functional"
            }
            
            // Curl variations (bicep/tricep)
            else if exerciseName.contains("curl") {
                return "figure.arms.open"
            }
            
            // Press variations (shoulder/chest)
            else if exerciseName.contains("press") && !exerciseName.contains("leg") {
                return "arrow.up.circle.fill"
            }
            
            // Row variations
            else if exerciseName.contains("row") {
                return "arrow.left.and.right.circle.fill"
            }
            
            // Fly variations
            else if exerciseName.contains("fly") || exerciseName.contains("flye") {
                return "arrow.up.left.and.arrow.down.right.circle.fill"
            }
            
            // Raise variations (lateral, front)
            else if exerciseName.contains("raise") {
                return "arrow.up.circle"
            }
            
            // Shrug variations
            else if exerciseName.contains("shrug") {
                return "arrow.up.and.down.circle.fill"
            }
            
            // Plank variations
            else if exerciseName.contains("plank") {
                return "figure.core.training"
            }
            
            // Running/cardio
            else if exerciseName.contains("run") || exerciseName.contains("jog") {
                return "figure.run"
            }
            
            // Jump exercises
            else if exerciseName.contains("jump") {
                return "figure.jumprope"
            }
        }
        
        // Fallback to equipment-based icons
        if let equipment = exercise.equipment?.lowercased() {
            switch equipment {
            case "dumbbells":
                return "dumbbell.fill"
            case "barbell":
                return "figure.strengthtraining.traditional"
            case "cables":
                return "dot.radiowaves.left.and.right"
            case "machines":
                return "gearshape.fill"
            case "bodyweight":
                return "figure.strengthtraining.traditional"
            default:
                break
            }
        }
        
        // Final fallback to category icons
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing" 
        case "legs": return "figure.squat"
        case "shoulders": return "arrow.up.circle.fill"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

struct CompactFilterChip: View {
    let text: String
    let isSelected: Bool
    var color: Color = .blue
    var secondaryColor: Color? = nil
    let onTap: () -> Void
    
    private var gradientColors: [Color] {
        [color, secondaryColor ?? color.opacity(0.7)]
    }
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color(.systemGray6))
                        )
                )
                .foregroundColor(isSelected ? .white : .primary.opacity(0.7))
                .shadow(color: isSelected ? color.opacity(0.2) : .clear, radius: 3, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Exercise Type Chip (Strength/Cardio/Plyometrics/Stretching)
struct ExerciseTypeChip: View {
    let exerciseType: ExerciseFilterService.ExerciseType
    let isSelected: Bool
    let onTap: () -> Void
    
    private var chipColor: Color {
        switch exerciseType {
        case .strength: return .blue
        case .cardio: return .red
        case .plyometrics: return .orange
        case .stretching: return .green
        }
    }
    
    private var secondaryColor: Color {
        switch exerciseType {
        case .strength: return .purple
        case .cardio: return .pink
        case .plyometrics: return .yellow
        case .stretching: return .mint
        }
    }
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
            HStack(spacing: 4) {
                Image(systemName: exerciseType.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(exerciseType.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(colors: [chipColor, secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color(.systemGray6))
                    )
            )
            .foregroundColor(isSelected ? .white : .primary.opacity(0.7))
            .shadow(color: isSelected ? chipColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TagView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(0.2), color.opacity(0.1)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(color)
    }
}

// MARK: - Multi-Select Filter Chip (Shows persistent dropdown for multi-select)
struct MultiSelectFilterChip: View {
    let text: String
    let isSelected: Bool
    var color: Color = .blue
    var secondaryColor: Color? = nil
    let allOptions: [String]
    @Binding var selectedItems: Set<String>
    
    @State private var showingDropdown = false
    
    private var gradientColors: [Color] {
        [color, secondaryColor ?? color.opacity(0.7)]
    }
    
    var body: some View {
        Button(action: {
            HapticManager.selectionChanged()
            showingDropdown = true
        }) {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color(.systemGray6))
                        )
                )
                .foregroundColor(isSelected ? .white : .primary.opacity(0.7))
                .shadow(color: isSelected ? color.opacity(0.2) : .clear, radius: 3, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showingDropdown, arrowEdge: .top) {
            MultiSelectDropdownContent(
                allOptions: allOptions,
                selectedItems: $selectedItems,
                accentColor: color
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Multi-Select Dropdown Content (Stays open for multiple selections)
struct MultiSelectDropdownContent: View {
    let allOptions: [String]
    @Binding var selectedItems: Set<String>
    let accentColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // "All" option (clears selection)
                Button(action: {
                    HapticManager.selectionChanged()
                    selectedItems = []
                }) {
                    HStack(spacing: 12) {
                        Text("All")
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if selectedItems.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(selectedItems.isEmpty ? accentColor.opacity(0.1) : Color.clear)
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .padding(.horizontal, Spacing.sm)
                
                // All other options
                ForEach(allOptions.filter { $0 != "All" }, id: \.self) { option in
                    Button(action: {
                        HapticManager.selectionChanged()
                        if selectedItems.contains(option) {
                            selectedItems.remove(option)
                        } else {
                            selectedItems.insert(option)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text(option)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedItems.contains(option) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accentColor)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(selectedItems.contains(option) ? accentColor.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .frame(minWidth: 200, maxHeight: 350)
        .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
    }
}

#Preview {
    ExerciseLibraryView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
