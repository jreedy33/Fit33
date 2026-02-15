import SwiftUI
import CoreData

struct CustomWorkoutBuilderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var exerciseLibrary = ExerciseLibraryService.shared
    
    // MARK: - Mode Configuration
    enum Mode {
        case build          // Default: multi-select to build a workout
        case replace(Exercise, (Exercise) -> Void)  // Single-select to replace an exercise
        case addToWorkout((Exercise) -> Void)       // Single-select to add to active workout
        
        var title: String {
            switch self {
            case .build: return "Build Workout"
            case .replace: return "Replace Exercise"
            case .addToWorkout: return "Add Exercise"
            }
        }
        
        var isSingleSelect: Bool {
            switch self {
            case .build: return false
            case .replace, .addToWorkout: return true
            }
        }
    }
    
    let mode: Mode
    
    // Default initializer for build mode
    init() {
        self.mode = .build
    }
    
    // Initializer for replace mode
    init(replacing exercise: Exercise, onSelect: @escaping (Exercise) -> Void) {
        self.mode = .replace(exercise, onSelect)
    }
    
    // Initializer for add to workout mode
    init(onAddExercise: @escaping (Exercise) -> Void) {
        self.mode = .addToWorkout(onAddExercise)
    }
    
    @State private var exercises: [Exercise] = []
    @State private var selectedExercises: [Exercise] = []
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMuscleGroup = "All"
    @State private var selectedExerciseForDetail: Exercise?
    @State private var forceRenderID = UUID()
    @State private var exerciseFilter: ExerciseFilterType = .all
    @State private var scrollOffset: CGFloat = 0
    @State private var showingAddExercise = false
    @State private var isLoadingExercises = false
    
    // ⚡️ SNAPPY SEARCH: Focus state for instant keyboard dismiss
    @FocusState private var isSearchFocused: Bool
    
    // ⚡️ PERFORMANCE: Cached filtered results to avoid recomputation
    @State private var cachedFilteredExercises: [Exercise] = []
    @State private var filterUpdateTask: Task<Void, Never>?
    
    enum ExerciseFilterType: String, CaseIterable {
        case all = "All Exercises"
        case favorites = "Favorites"
        case custom = "Custom Added"
    }
    
    // Updated categories for 7000+ exercise library
    private let categories = ExerciseFilterService.allCategories
    private let allMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques", "Hip Flexors", "Adductors", "Rotator Cuff"]
    
    // Smart muscle groups based on selected category (uses centralized service)
    private var muscleGroups: [String] {
        ExerciseFilterService.muscleGroupsForCategory(selectedCategory)
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
    
    // Updated equipment for 7000+ exercise library
    private let equipmentTypes = ExerciseFilterService.allEquipment
    
    private var filterIcon: String {
        switch exerciseFilter {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .favorites:
            return "star.fill"
        case .custom:
            return "person.crop.circle.badge.plus"
        }
    }
    
    private var filterColor: Color {
        switch exerciseFilter {
        case .all:
            return Color(.systemGray5)
        case .favorites:
            return .yellow
        case .custom:
            return .blue
        }
    }
    
    // ⚡️ HIGH-PERFORMANCE: Use cached results, not computed
    var filteredExercises: [Exercise] {
        cachedFilteredExercises
    }
    
    // ⚡️ HIGH-PERFORMANCE: Pre-filtered exercises cache
    @State private var preFilteredExercises: [Exercise] = []
    @State private var lastFilterKey: String = ""
    @State private var searchCache: [String: [Exercise]] = [:]
    
    private func rebuildFilterCache() {
        let filterKey = "\(exerciseFilter.rawValue)|\(selectedCategory)|\(selectedEquipment)|\(selectedMuscleGroup)"
        
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchCache.removeAll()
            preFilteredExercises = applyFiltersOnly(to: exercises)
            #if DEBUG
            print("🔧 [FILTER] Rebuilt cache: \(preFilteredExercises.count) exercises")
            // Check for bench/incline/decline exercises
            let benchExercises = preFilteredExercises.filter { ($0.name?.lowercased() ?? "").contains("bench") }
            let declineExercises = preFilteredExercises.filter { ($0.name?.lowercased() ?? "").contains("decline") }
            let inclineExercises = preFilteredExercises.filter { ($0.name?.lowercased() ?? "").contains("incline") }
            print("🔧 [FILTER] bench exercises: \(benchExercises.count), decline: \(declineExercises.count), incline: \(inclineExercises.count)")
            if let first = benchExercises.first { print("🔧 [FILTER] Sample bench: '\(first.name ?? "nil")'") }
            #endif
        }
    }
    
    private func computeSearchResults() {
        if !searchText.isEmpty {
            let searchKey = searchText.lowercased()
            #if DEBUG
            print("🔍 [CACHE] Search key: '\(searchKey)', preFilteredExercises.count: \(preFilteredExercises.count)")
            #endif
            if let cached = searchCache[searchKey] {
                #if DEBUG
                print("🔍 [CACHE] HIT - returning \(cached.count) cached results")
                #endif
                cachedFilteredExercises = cached
                return
            }
            #if DEBUG
            print("🔍 [CACHE] MISS - computing fresh results")
            #endif
            let results = ultraFastSearch(query: searchKey, in: preFilteredExercises)
            searchCache[searchKey] = results
            cachedFilteredExercises = results
        } else {
            cachedFilteredExercises = preFilteredExercises
        }
    }
    
    private func ultraFastSearch(query: String, in exercises: [Exercise]) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        
        // Split query into words and correct typos for each
        let queryWords = query.split(separator: " ").map { correctCommonTypos(String($0)) }
        let isMultiWord = queryWords.count > 1
        let variations = isMultiWord ? [query] : getQuickVariations(query)
        
        // Build corrected query for direct substring matching
        let correctedQuery = queryWords.joined(separator: " ")
        
        #if DEBUG
        print("🔍 [SEARCH] Query: '\(query)', Words: \(queryWords), isMultiWord: \(isMultiWord)")
        print("🔍 [SEARCH] correctedQuery: '\(correctedQuery)', searching \(exercises.count) exercises")
        #endif
        
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
            
            // SINGLE-WORD: Use variations for typo tolerance
            if !isMultiWord {
                for variation in variations {
                    if name == variation { exactMatches.append(exercise); matched = true; break }
                    else if name.hasPrefix(variation) { startsWithPhraseMatches.append(exercise); matched = true; break }
                    else if name.contains(variation) { containsPhraseMatches.append(exercise); matched = true; break }
                }
            }
            
            // MULTI-WORD: Check for exact phrase match first (preserves word order)
            if !matched && isMultiWord {
                if name == correctedQuery {
                    // Exact match
                    exactMatches.append(exercise)
                    matched = true
                } else if name.hasPrefix(correctedQuery) {
                    // Name STARTS with the exact phrase - highest priority for phrase
                    // e.g., "front raise" matches "front raise (dumbbell)"
                    startsWithPhraseMatches.append(exercise)
                    matched = true
                } else if name.contains(correctedQuery) {
                    // Name CONTAINS the exact phrase - second priority
                    // e.g., "front raise" matches "seated front raise"
                    containsPhraseMatches.append(exercise)
                    matched = true
                }
            }
            
            // MULTI-WORD: Word-order-independent matching (lowest priority)
            // e.g., "front raise" matches "front lat raise" or "raise front"
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
        
        #if DEBUG
        let totalResults = exactMatches.count + startsWithPhraseMatches.count + containsPhraseMatches.count + allWordsMatches.count
        print("🔍 [SEARCH] Results: exact=\(exactMatches.count), startsWithPhrase=\(startsWithPhraseMatches.count), containsPhrase=\(containsPhraseMatches.count), allWords=\(allWordsMatches.count), TOTAL=\(totalResults)")
        #endif
        
        // Return in priority order: exact phrase ordering is prioritized
        return exactMatches + startsWithPhraseMatches + containsPhraseMatches + allWordsMatches
    }
    
    private func getQuickVariations(_ query: String) -> [String] {
        let corrected = correctCommonTypos(query)
        var variations = corrected == query ? [query] : [query, corrected]
        
        let baseWord = corrected
        switch baseWord {
        case "fly": variations += ["flye", "flyes", "flies"]
        case "flye": variations += ["fly", "flyes", "flies"]
        case "curl": variations += ["curls"]
        case "curls": variations += ["curl"]
        case "press": variations += ["presses"]
        case "presses": variations += ["press"]
        case "row": variations += ["rows"]
        case "rows": variations += ["row"]
        case "raise": variations += ["raises"]
        case "raises": variations += ["raise"]
        case "bicep": variations += ["biceps"]
        case "biceps": variations += ["bicep"]
        case "tricep": variations += ["triceps"]
        case "triceps": variations += ["tricep"]
        case "pulldown": variations += ["pull-down", "pull down", "pulldowns"]
        case "pushdown": variations += ["push-down", "push down", "pushdowns"]
        case "dumbbell": variations += ["dumbell", "dumbells", "dumbbells"]
        case "dumbbells": variations += ["dumbbell", "dumbell"]
        case "barbell": variations += ["barbel", "barbells"]
        case "extension": variations += ["extensions"]
        case "extensions": variations += ["extension"]
        case "squat": variations += ["squats"]
        case "squats": variations += ["squat"]
        case "lunge": variations += ["lunges"]
        case "lunges": variations += ["lunge"]
        default:
            if baseWord.hasSuffix("s") && baseWord.count > 3 { variations.append(String(baseWord.dropLast())) }
            else if !baseWord.hasSuffix("s") && baseWord.count > 2 { variations.append(baseWord + "s") }
        }
        return variations
    }
    
    private func correctCommonTypos(_ query: String) -> String {
        // Only do EXACT matches - no substring replacement which causes bugs
        // e.g., "decline" was becoming "declinee" because it contains "declin"
        let typoMap: [String: String] = [
            "dumbell": "dumbbell", "dumbel": "dumbbell", "dumble": "dumbbell",
            "dumbells": "dumbbells", "dumbels": "dumbbells",
            "barbel": "barbell", "barble": "barbell",
            "kettleball": "kettlebell", "kettlebel": "kettlebell",
            "cabel": "cable", "cabels": "cables",
            "machien": "machine", "mashine": "machine",
            "flye": "fly", "flyes": "flies",
            "pres": "press", "presss": "press", "curle": "curl",
            "rwo": "row", "sqaut": "squat", "sqat": "squat",
            "deadlif": "deadlift", "dedlift": "deadlift",
            "extention": "extension", "extenstion": "extension",
            "pullup": "pull up", "pushup": "push up", "chinup": "chin up",
            "bycep": "bicep", "byceps": "biceps", "bicept": "bicep",
            "trycep": "tricep", "tryceps": "triceps", "tricept": "tricep",
            "sholder": "shoulder", "sholders": "shoulders",
            "inclin": "incline", "inclien": "incline",
            "declin": "decline", "declien": "decline",
            "laterl": "lateral", "latral": "lateral",
            "revers": "reverse", "bensh": "bench", "banch": "bench", "benc": "bench"
        ]
        
        // Only return correction for EXACT match
        return typoMap[query] ?? query
    }
    
    private func applyFiltersOnly(to exercises: [Exercise]) -> [Exercise] {
        var filtered = exercises
        
        switch exerciseFilter {
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .custom:
            filtered = filtered.filter { $0.instructions?.contains("[CUSTOM_EXERCISE") ?? false }
        case .all:
            break
        }
        
        if selectedCategory != "All" {
            let categoryLower = selectedCategory.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseCategory = (exercise.category ?? "").lowercased()
                return exerciseCategory == categoryLower || exerciseCategory.contains(categoryLower)
            }
        }
        
        if selectedEquipment != "All" {
            filtered = filtered.filter { exercise in
                exerciseMatchesEquipment(exercise, selectedEquipment: selectedEquipment)
            }
        }
        
        if selectedMuscleGroup != "All" {
            filtered = filtered.filter { exercise in
                isExerciseForMuscleGroup(exercise, muscleGroup: selectedMuscleGroup)
            }
        }
        
        return filtered
    }
    
    // ⚡️ PERFORMANCE: Async filter update
    // ⚡️ HIGH-PERFORMANCE: Instant filter updates
    private func updateFilteredExercises() {
        filterUpdateTask?.cancel()
        rebuildFilterCache()
        computeSearchResults()
    }
    
    // MARK: - Equipment Matching Helper
    /// Comprehensive equipment matching with normalization
    private func exerciseMatchesEquipment(_ exercise: Exercise, selectedEquipment: String) -> Bool {
        let exerciseEquipment = exercise.equipment?.lowercased() ?? ""
        let targetEquipment = selectedEquipment.lowercased()
        let exerciseName = exercise.name?.lowercased() ?? ""
        
        // Direct match
        if exerciseEquipment == targetEquipment {
            return true
        }
        
        // Normalize both and compare
        let normalizedExercise = ExerciseFilterService.normalizeEquipment(exercise.equipment)
        if normalizedExercise == selectedEquipment {
            return true
        }
        
        // Handle compound equipment (e.g., "Dumbbells, Incline Bench")
        let equipmentParts = exerciseEquipment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        
        // Check specific equipment types
        switch targetEquipment {
        case "dumbbells":
            return exerciseEquipment.contains("dumbbell") ||
                   exerciseName.contains("dumbbell") ||
                   equipmentParts.contains { $0.contains("dumbbell") }
                   
        case "barbell":
            // Match barbell but NOT smith machine
            let isBarbell = exerciseEquipment.contains("barbell") ||
                           exerciseName.contains("barbell") ||
                           exerciseEquipment.contains("ez bar") ||
                           exerciseEquipment.contains("trap bar") ||
                           equipmentParts.contains { $0.contains("barbell") }
            let isSmith = exerciseEquipment.contains("smith") || exerciseName.contains("smith")
            return isBarbell && !isSmith
            
        case "cables":
            return exerciseEquipment.contains("cable") ||
                   exerciseName.contains("cable") ||
                   equipmentParts.contains { $0.contains("cable") }
                   
        case "machines":
            // Match machines but NOT cables or smith machine (separate categories)
            // IMPORTANT: Cables must be checked FIRST to prevent cable/machine mixing
            let isCable = exerciseEquipment.contains("cable") || exerciseName.contains("cable")
            if isCable { return false }
            
            let isSmith = exerciseEquipment.contains("smith")
            if isSmith { return false }
            
            // Check for any machine-related keywords
            let isMachine = exerciseEquipment.contains("machine") ||
                           exerciseEquipment.contains("lever") ||
                           equipmentParts.contains { part in
                               part.contains("machine") || part.contains("lever")
                           }
            
            return isMachine
            
        case "bodyweight":
            return exerciseEquipment.isEmpty ||
                   exerciseEquipment == "bodyweight" ||
                   exerciseEquipment.contains("bodyweight") ||
                   exerciseEquipment.contains("body weight")
                   
        case "kettlebell":
            return exerciseEquipment.contains("kettlebell") ||
                   exerciseName.contains("kettlebell") ||
                   equipmentParts.contains { $0.contains("kettlebell") }
                   
        case "resistance bands", "bands":
            return exerciseEquipment.contains("band") ||
                   exerciseEquipment.contains("resistance") ||
                   exerciseName.contains("band") ||
                   equipmentParts.contains { $0.contains("band") }
                   
        case "bench":
            return exerciseEquipment.contains("bench") ||
                   equipmentParts.contains { $0.contains("bench") }
                   
        case "smith machine":
            return exerciseEquipment.contains("smith") ||
                   exerciseName.contains("smith")
                   
        case "trx/rings":
            return exerciseEquipment.contains("trx") ||
                   exerciseEquipment.contains("ring") ||
                   exerciseEquipment.contains("suspension") ||
                   exerciseName.contains("trx") ||
                   equipmentParts.contains { $0.contains("trx") || $0.contains("ring") || $0.contains("suspension") }
                   
        case "stability ball":
            return exerciseEquipment.contains("stability ball") ||
                   exerciseEquipment.contains("swiss ball") ||
                   exerciseName.contains("stability ball") ||
                   equipmentParts.contains { $0.contains("stability") || $0.contains("swiss ball") }
                   
        case "medicine ball":
            return exerciseEquipment.contains("medicine ball") ||
                   exerciseName.contains("medicine ball") ||
                   equipmentParts.contains { $0.contains("medicine ball") }
                   
        case "pull-up bar":
            return exerciseEquipment.contains("pull-up bar") ||
                   exerciseEquipment.contains("pullup bar") ||
                   exerciseEquipment.contains("pull up bar") ||
                   exerciseName.contains("pull up") ||
                   exerciseName.contains("pull-up") ||
                   exerciseName.contains("chin up") ||
                   exerciseName.contains("chin-up")
                   
        default:
            // Fallback: check if equipment contains target or vice versa
            return exerciseEquipment.contains(targetEquipment) ||
                   targetEquipment.contains(exerciseEquipment)
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                // Animated blue/cyan orb background
                AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                    VStack(spacing: 0) {
                        // Add top padding for the animated title (accounting for safe area + header)
                        Color.clear.frame(height: 100)
                    
                    // Fixed search and filters (stays in place)
                    compactFiltersView
                    
                    // Scrollable exercise list
                    ScrollView {
                        GeometryReader { geometry in
                            Color.clear.preference(key: CustomWorkoutScrollOffsetKey.self, value: geometry.frame(in: .named("scroll")).minY)
                        }
                        .frame(height: 0)
                        
                        if isLoadingExercises || !exerciseLibrary.isExercisesReady {
                            // Loading state - exercises are syncing from cloud
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text("Loading exercises...")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(cachedFilteredExercises.enumerated()), id: \.element.objectID) { index, exercise in
                                    CustomWorkoutExerciseRowWithNav(
                                        exercise: exercise,
                                        isSelected: selectedExercises.contains { $0.id == exercise.id },
                                        onToggle: {
                                            toggleExerciseSelection(exercise)
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                    // 🚀 Prefetch when exercise appears in viewport
                                    .onAppear {
                                        prefetchVisibleExercise(exercise: exercise, index: index)
                                    }
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 100)
                            .id(forceRenderID)
                        }
                    }
                    .coordinateSpace(name: "scroll")
                    .scrollDismissesKeyboard(.immediately)
                    // ⚡️ SNAPPY SEARCH: Dismiss keyboard instantly when scrolling
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in
                            isSearchFocused = false
                        }
                    )
                }
                .onPreferenceChange(CustomWorkoutScrollOffsetKey.self) { value in
                    scrollOffset = value
                }
                .onAppear {
                    SessionLogManager.shared.logScreen(.customWorkoutBuilder, metadata: [
                        "selected_count": selectedExercises.count
                    ])
                    // Load exercises from cache/Core Data (cloud sync handles population)
                    loadExercises()
                    // ⚡️ Initialize cached results and filter cache immediately
                    lastFilterKey = "" // Force rebuild
                    updateFilteredExercises()
                    forceRenderID = UUID()
                    workoutManager.isOnCustomWorkoutBuilder = true
                    
                    // Check for pre-selected exercise (from "Add to workout" button on ExerciseDetailView)
                    if let exerciseToAdd = workoutManager.exerciseToAddToCustomWorkout {
                        // Only add if not already selected
                        if !selectedExercises.contains(where: { $0.id == exerciseToAdd.id }) {
                            selectedExercises.append(exerciseToAdd)
                            print("✅ Pre-selected exercise: \(exerciseToAdd.name ?? "Unknown")")
                            
                            // Prefetch the video for this exercise
                            if let name = exerciseToAdd.name {
                                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
                            }
                        }
                        // Clear the pre-selected exercise
                        workoutManager.exerciseToAddToCustomWorkout = nil
                    }
                    
                    workoutManager.selectedCustomWorkoutExercises = selectedExercises
                }
                .onDisappear {
                    workoutManager.isOnCustomWorkoutBuilder = false
                    workoutManager.selectedCustomWorkoutExercises = []
                    workoutManager.shouldNavigateToCustomWorkoutBuilder = false
                }
                // 🔄 Reload when exercises become ready after sync
                .onChange(of: exerciseLibrary.isExercisesReady) { _, isReady in
                    if isReady && exercises.isEmpty {
                        print("✅ Exercises now ready - reloading list")
                        loadExercises()
                        lastFilterKey = "" // Force rebuild filters
                        updateFilteredExercises()
                        forceRenderID = UUID()
                    }
                }
                // ⚡️ HIGH-PERFORMANCE: Instant filter updates
                .onChange(of: searchText) { _, _ in updateFilteredExercises() }
                .onChange(of: selectedCategory) { _, _ in 
                    lastFilterKey = ""
                    updateFilteredExercises() 
                }
                .onChange(of: selectedEquipment) { _, _ in 
                    lastFilterKey = ""
                    updateFilteredExercises() 
                }
                .onChange(of: selectedMuscleGroup) { _, _ in 
                    lastFilterKey = ""
                    updateFilteredExercises() 
                }
                .onChange(of: exerciseFilter) { _, _ in 
                    lastFilterKey = ""
                    updateFilteredExercises() 
                }
                .onChange(of: exercises) { _, _ in 
                    lastFilterKey = ""
                    updateFilteredExercises() 
                }
                .onChange(of: exerciseFilter) { _, _ in updateFilteredExercises() }
                .onChange(of: exercises) { _, _ in updateFilteredExercises() }
                .onChange(of: selectedExercises) { _, newValue in
                    workoutManager.selectedCustomWorkoutExercises = newValue
                }
                .onChange(of: workoutManager.shouldStartCustomWorkout) { _, shouldStart in
                    if shouldStart && !selectedExercises.isEmpty {
                        startCustomWorkout()
                        workoutManager.shouldStartCustomWorkout = false
                    }
                }
                .sheet(isPresented: $showingAddExercise) {
                    AddCustomExerciseView(onSave: { newExercise in
                        // Refresh the exercise list after adding
                        loadExercises()
                        forceRenderID = UUID()
                    })
                }
            }
            
            // Custom animated header
            customNavigationHeader
            
            // Banner ad overlay - floats on top, scroll content has space reserved
            if !PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled {
                VStack {
                    Spacer().frame(height: 160) // Position below filters
                    BannerAdView()
                        .padding(.horizontal, 16)
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: selectedExercises.count) { count in
            // Only show GO button in build mode
            guard case .build = mode else { return }
            
            if count > 0 {
                GoButtonState.shared.show(
                    primaryColor: .blue,
                    secondaryColor: Color(red: 0.3, green: 0.5, blue: 0.9)
                ) { [self] in
                    startCustomWorkout()
                }
            } else {
                GoButtonState.shared.hide()
            }
        }
        .onDisappear {
            // Only hide GO button if we showed it (build mode)
            if case .build = mode {
                GoButtonState.shared.hide()
            }
        }
    }
    
    // MARK: - Custom Navigation Header
    private var customNavigationHeader: some View {
        let isScrolled = scrollOffset < -20
        
        return GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                // Back button and Add Exercise button
                HStack {
                    // Liquid glass back button
                    Button(action: {
                        HapticManager.selectionChanged()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.5), .white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                    
                    Spacer()
                    
                    // Liquid glass Add Exercise button
                    Button(action: {
                        HapticManager.impact(.medium)
                        showingAddExercise = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.5), .white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, max(geometry.safeAreaInsets.top + 4, 56))
                
                // Title - left aligned, animates size on scroll
                Text(mode.title)
                    .font(isScrolled ? .title3 : .largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.3, green: 0.5, blue: 0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .background(Color.clear)
        }
        .ignoresSafeArea()
        .frame(height: 110)
    }
    
    private var compactFiltersView: some View {
        VStack(spacing: 12) {
            // Search section with title
            VStack(alignment: .leading, spacing: 8) {
                // Top row: Title and metadata
                HStack {
                    Text("Search & Filter")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
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
                        .foregroundColor(exerciseFilter != .all ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(exerciseFilter != .all ? filterColor : Color(.systemGray5))
                        )
                    }
                    
                    // Small selected counter with blue gradient (only in build mode)
                    if !mode.isSingleSelect && !selectedExercises.isEmpty {
                        HStack(spacing: 4) {
                            Text("\(selectedExercises.count)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("selected")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
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
                            isSearchFocused = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
            }
            
            // Compact filter categories
            VStack(alignment: .leading, spacing: 6) {
                // Categories row
                HStack(spacing: 8) {
                    Text("Categories")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(categories, id: \.self) { category in
                                CompactFilterChip(
                                    text: category,
                                    isSelected: selectedCategory == category,
                                    onTap: {
                                        selectedCategory = category
                                        selectedMuscleGroup = "All"
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                
                // Muscle Groups row (only if category selected)
                if selectedCategory != "All" && muscleGroups.count > 1 {
                    HStack(spacing: 8) {
                        Text("Muscles")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(muscleGroups, id: \.self) { muscle in
                                    CompactFilterChip(
                                        text: muscle,
                                        isSelected: selectedMuscleGroup == muscle,
                                        color: .green,
                                        onTap: { selectedMuscleGroup = muscle }
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
                                CompactFilterChip(
                                    text: equipment,
                                    isSelected: selectedEquipment == equipment,
                                    color: .orange,
                                    onTap: { selectedEquipment = equipment }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .zIndex(10)
    }
    
    // MARK: - Helper Functions
    private func loadExercises() {
        // Only load if exercises are ready (have valid names)
        guard exerciseLibrary.isExercisesReady else {
            print("⏳ Waiting for exercises to be ready...")
            return
        }
        
        exercises = ExerciseLibraryService.shared.getAllExercises()
        let customCount = exercises.filter { $0.instructions?.contains("[CUSTOM_EXERCISE") ?? false }.count
        print("📦 Loaded \(exercises.count) exercises for custom workout builder (including \(customCount) custom)")
        
        // If no exercises found in Core Data, fetch from Supabase
        if exercises.isEmpty || exercises.allSatisfy({ $0.name == nil }) {
            print("⚠️ No exercises found in Core Data, fetching from Supabase...")
            isLoadingExercises = true
            Task {
                do {
                    let exerciseDTOs = try await SupabaseManager.shared.fetchAllExercises()
                    print("✅ Fetched \(exerciseDTOs.count) exercises from Supabase, saving to Core Data...")
                    
                    // Save to Core Data on main thread
                    await MainActor.run {
                        for exerciseDTO in exerciseDTOs {
                            let exercise = Exercise(context: viewContext)
                            // Convert String ID to UUID
                            if let idString = exerciseDTO.id, let uuid = UUID(uuidString: idString) {
                                exercise.id = uuid
                            } else {
                                exercise.id = UUID()
                            }
                            exercise.name = exerciseDTO.name
                            exercise.category = exerciseDTO.category
                            exercise.equipment = exerciseDTO.equipment
                            exercise.instructions = exerciseDTO.instructions
                            exercise.videoFilename = exerciseDTO.videoFilename
                            
                            // Convert muscle arrays to NSObject
                            if let primaryMuscles = exerciseDTO.primaryMusclesRaw?.asArray {
                                exercise.muscleGroups = primaryMuscles as NSObject
                            }
                        }
                        
                        do {
                            try viewContext.save()
                            print("✅ Saved \(exerciseDTOs.count) exercises to Core Data")
                            
                            // Reload exercises from Core Data
                            exercises = ExerciseLibraryService.shared.getAllExercises()
                            ExerciseLibraryService.shared.invalidateCache() // Refresh cache
                            forceRenderID = UUID()
                            isLoadingExercises = false
                        } catch {
                            print("❌ Error saving exercises to Core Data: \(error)")
                            isLoadingExercises = false
                        }
                    }
                } catch {
                    print("❌ Error fetching exercises from Supabase: \(error)")
                    await MainActor.run {
                        isLoadingExercises = false
                    }
                }
            }
        }
    }
    
    private func toggleExerciseSelection(_ exercise: Exercise) {
        // Handle single-select modes (replace/add)
        if mode.isSingleSelect {
            HapticManager.impact(.medium)
            
            // Prefetch video immediately
            if let name = exercise.name {
                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
            }
            
            // Execute the callback and dismiss
            switch mode {
            case .replace(_, let onSelect):
                onSelect(exercise)
                dismiss()
            case .addToWorkout(let onSelect):
                onSelect(exercise)
                dismiss()
            case .build:
                break // Not single-select
            }
            return
        }
        
        // Default multi-select behavior for build mode
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
            
            // 🚀 Smart prefetch: User selected this exercise, priority preload its video
            if let name = exercise.name {
                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
            }
        }
    }
    
    // MARK: - 🚀 Smart Video Prefetching
    
    /// ⚡️ MEMORY FIX: DISABLED — scroll prefetching was creating AVPlayers for every visible row,
    /// causing 600MB+ memory from XPC video process leaks. Videos load on-demand in detail view.
    private func prefetchVisibleExercise(exercise: Exercise, index: Int) {
        // NO-OP: Disabled to prevent memory pressure
    }
    
    private func startCustomWorkout() {
        guard !selectedExercises.isEmpty else {
            print("❌ No exercises selected")
            return
        }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🏋️‍♂️ Starting custom workout with \(selectedExercises.count) exercises")
        #endif
        
        // Generate workout name
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateString = formatter.string(from: Date())
        let workoutName = "Custom Workout - \(dateString)"
        
        // Create new workout
        let newWorkout = Workout(context: viewContext)
        newWorkout.id = UUID()
        newWorkout.name = workoutName
        newWorkout.date = Date()
        newWorkout.isCompleted = false
        newWorkout.user = userManager.currentUser
        
        // Start workout using WorkoutManager FIRST (sets up all state)
        workoutManager.startWorkout(workout: newWorkout, exercises: selectedExercises)
        
        // THEN dismiss this view (after state is stable)
        dismiss()
        
        #if DEBUG
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("✅ Custom workout started in \(String(format: "%.2f", elapsed))ms")
        #endif
    }
}

// MARK: - Custom Workout Exercise Row
struct CustomWorkoutExerciseRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onToggle() }) {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
        .background(cardBackground)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 8, x: 0, y: 4)
        .shadow(color: categoryColor.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 12, x: 0, y: 6)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
    
    private var cardContent: some View {
        HStack(spacing: 12) {
            // Checkbox
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 28, height: 28)
                
                if isSelected {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            
            // Exercise icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: categoryIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(categoryColor)
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
            
            // Info button
            Button(action: { HapticManager.selectionChanged(); onInfoTap() }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            // Bottom shadow layer (deepest) - category colored
            RoundedRectangle(cornerRadius: 28)
                .fill(categoryColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .offset(y: 6)
                .blur(radius: 3)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03))
                .offset(y: 3)
            
            // Main card background
            RoundedRectangle(cornerRadius: 25)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark 
                            ? [Color(white: 0.15), Color(white: 0.12)]
                            : [Color.white, Color.white.opacity(0.98)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Inner highlight (top edge glow)
            RoundedRectangle(cornerRadius: 25)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark 
                            ? [Color.white.opacity(0.08), Color.clear]
                            : [Color.white, Color.white.opacity(0.3), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            
            // Selection/accent border
            if isSelected {
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: [
                                categoryColor.opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryColor.opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
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
    
    private var categoryIcon: String {
        // Check if this is a custom exercise with custom icon
        if let instructions = exercise.instructions,
           instructions.contains("[CUSTOM_EXERCISE|ICON:"),
           let iconRange = instructions.range(of: #"\[CUSTOM_EXERCISE\|ICON:([^\]]+)\]"#, options: .regularExpression),
           let iconName = instructions[iconRange].split(separator: ":").last?.replacingOccurrences(of: "]", with: "") {
            return String(iconName)
        }
        
        if let exerciseName = exercise.name?.lowercased() {
            if exerciseName.contains("dumbbell") {
                return "dumbbell.fill"
            } else if exerciseName.contains("barbell") {
                return "figure.strengthtraining.traditional"
            } else if exerciseName.contains("cable") {
                return "dot.radiowaves.left.and.right"
            } else if exerciseName.contains("push") && exerciseName.contains("up") {
                return "figure.strengthtraining.traditional"
            } else if exerciseName.contains("pull") && (exerciseName.contains("up") || exerciseName.contains("chin")) {
                return "figure.climbing"
            } else if exerciseName.contains("squat") {
                return "figure.squat"
            } else if exerciseName.contains("lunge") {
                return "figure.walk"
            }
        }
        
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

// MARK: - Add Custom Exercise View
struct AddCustomExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let onSave: (Exercise) -> Void
    
    @State private var exerciseName = ""
    @State private var selectedIcon = "dumbbell.fill"
    @State private var selectedCategory = "Chest"
    @State private var primaryMuscleGroups: Set<String> = []
    @State private var secondaryMuscleGroups: Set<String> = []
    @State private var selectedEquipment = "Dumbbells"
    @State private var instructions = ""
    @State private var showingIconPicker = false
    
    // Updated categories for 7000+ exercise library (excludes "All" for custom exercise creation)
    private let categories = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body", "Plyometrics", "Stretching", "Cardio", "Neck"]
    private let equipmentTypes = ["Bodyweight", "Dumbbells", "Barbell", "Cables", "Machines", "Kettlebell", "Resistance Bands", "TRX/Rings", "Stability Ball", "Smith Machine", "Bench", "Other"]
    
    private let allMuscleGroups: [String: [String]] = [
        "Chest": ["Upper Chest", "Lower Chest", "Inner Chest", "Outer Chest"],
        "Back": ["Lats", "Traps", "Rhomboids", "Lower Back", "Upper Back"],
        "Legs": ["Quads", "Hamstrings", "Glutes", "Calves", "Hip Flexors", "Adductors"],
        "Shoulders": ["Front Delts", "Side Delts", "Rear Delts", "Rotator Cuff"],
        "Arms": ["Biceps", "Triceps", "Forearms"],
        "Core": ["Abs", "Obliques", "Lower Back", "Hip Flexors"],
        "Full Body": ["Full Body"],
        "Plyometrics": ["Lower Body", "Upper Body", "Full Body"],
        "Stretching": ["Upper Body", "Lower Body", "Back", "Hips"],
        "Cardio": ["Cardio"],
        "Neck": ["Neck"]
    ]
    
    private let commonIcons = [
        "dumbbell.fill", "figure.strengthtraining.traditional", "figure.climbing",
        "figure.squat", "arrow.up.circle.fill", "figure.core.training",
        "figure.mixed.cardio", "figure.run", "figure.walk", "flame.fill",
        "bolt.fill", "star.fill", "heart.fill", "plus.circle.fill",
        "checkmark.circle.fill", "target", "scope"
    ]
    
    private var availableMuscleGroups: [String] {
        allMuscleGroups[selectedCategory] ?? []
    }
    
    private var canSave: Bool {
        !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !primaryMuscleGroups.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Icon Preview
                        iconPreview
                        
                        // Exercise Name
                        exerciseNameField
                        
                        // Category Selection
                        categorySelection
                        
                        // Primary Muscle Groups
                        muscleGroupSelection(title: "Primary Muscle Groups", selection: $primaryMuscleGroups)
                        
                        // Secondary Muscle Groups
                        muscleGroupSelection(title: "Secondary Muscle Groups (Optional)", selection: $secondaryMuscleGroups)
                        
                        // Equipment Selection
                        equipmentSelection
                        
                        // Instructions
                        instructionsField
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Create Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveExercise()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
        }
    }
    
    // MARK: - View Components
    
    private var iconPreview: some View {
        VStack(spacing: 12) {
            Button(action: {
                HapticManager.selectionChanged()
                showingIconPicker = true
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: selectedIcon)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            Text("Tap to change icon")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    
    private var exerciseNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise Name")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            TextField("e.g., Cable Crossover", text: $exerciseName)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.body)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    private var categorySelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button(action: {
                            HapticManager.selectionChanged()
                            selectedCategory = category
                            // Clear muscle group selections when category changes
                            primaryMuscleGroups.removeAll()
                            secondaryMuscleGroups.removeAll()
                        }) {
                            Text(category)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    selectedCategory == category ?
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color(.systemGray5), Color(.systemGray5)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(20)
                        }
                    }
                }
            }
        }
    }
    
    private func muscleGroupSelection(title: String, selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            FlowLayout(spacing: 8) {
                ForEach(availableMuscleGroups, id: \.self) { muscle in
                    Button(action: {
                        HapticManager.selectionChanged()
                        if selection.wrappedValue.contains(muscle) {
                            selection.wrappedValue.remove(muscle)
                        } else {
                            selection.wrappedValue.insert(muscle)
                        }
                    }) {
                        HStack(spacing: 4) {
                            if selection.wrappedValue.contains(muscle) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            Text(muscle)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selection.wrappedValue.contains(muscle) ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selection.wrappedValue.contains(muscle) ?
                            Color.blue :
                            Color(.systemGray5)
                        )
                        .cornerRadius(16)
                    }
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    private var equipmentSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equipment")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipmentTypes, id: \.self) { equipment in
                        Button(action: {
                            HapticManager.selectionChanged()
                            selectedEquipment = equipment
                        }) {
                            Text(equipment)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(selectedEquipment == equipment ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    selectedEquipment == equipment ?
                                    Color.orange :
                                    Color(.systemGray5)
                                )
                                .cornerRadius(20)
                        }
                    }
                }
            }
        }
    }
    
    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions (Optional)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            TextEditor(text: $instructions)
                .frame(height: 120)
                .padding(8)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
        }
    }
    
    // MARK: - Actions
    
    private func saveExercise() {
        let exercise = Exercise(context: viewContext)
        exercise.id = UUID()
        exercise.name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.category = selectedCategory
        exercise.muscleGroups = (Array(primaryMuscleGroups) + Array(secondaryMuscleGroups)) as NSObject
        exercise.equipment = selectedEquipment
        
        // Mark as custom by adding metadata to instructions
        let customMetadata = "[CUSTOM_EXERCISE|ICON:\(selectedIcon)]"
        exercise.instructions = instructions.isEmpty ? "\(customMetadata) User-created custom exercise." : "\(customMetadata) \(instructions)"
        exercise.isFavorite = false
        
        do {
            try viewContext.save()
            print("✅ Custom exercise saved: \(exerciseName)")
            print("   Name: \(exerciseName)")
            print("   Instructions: \(exercise.instructions ?? "none")")
            print("   Contains metadata: \(exercise.instructions?.contains("[CUSTOM_EXERCISE") ?? false)")
            
            // Sync to cloud (in background)
            Task {
                await syncCustomExerciseToCloud(exercise: exercise)
            }
            
            onSave(exercise)
            dismiss()
        } catch {
            print("❌ Failed to save custom exercise: \(error)")
        }
    }
    
    private func syncCustomExerciseToCloud(exercise: Exercise) async {
        guard SupabaseManager.shared.isAuthenticated else {
            print("ℹ️ User not authenticated, skipping custom exercise cloud sync")
            return
        }
        
        let name = exercise.name ?? "Unknown"
        let category = exercise.category ?? "Other"
        let primaryMuscles = Array(primaryMuscleGroups)
        let secondaryMuscles = Array(secondaryMuscleGroups)
        let equipment = exercise.equipment ?? ""
        let instructions = exercise.instructions ?? ""
        let icon = selectedIcon
        
        // Only sync to cloud if user is authenticated
        if SupabaseManager.shared.isAuthenticated {
            do {
                try await SupabaseManager.shared.createCustomExercise(
                    name: name,
                    category: category,
                    primaryMuscles: primaryMuscles,
                    secondaryMuscles: secondaryMuscles,
                    equipment: equipment,
                    instructions: instructions,
                    iconName: icon
                )
                print("✅ Custom exercise synced to cloud!")
            } catch {
                print("❌ Error syncing custom exercise to cloud: \(error)")
                // Don't block the app if cloud sync fails
            }
        } else {
            print("ℹ️ Custom exercise saved locally (user not signed in)")
        }
    }
}

// MARK: - Icon Picker View
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String
    
    private let commonIcons = [
        "dumbbell.fill", "figure.strengthtraining.traditional", "figure.climbing",
        "figure.squat", "arrow.up.circle.fill", "figure.core.training",
        "figure.mixed.cardio", "figure.run", "figure.walk", "flame.fill",
        "bolt.fill", "star.fill", "heart.fill", "plus.circle.fill",
        "checkmark.circle.fill", "target", "scope", "moon.fill",
        "sparkles", "waveform.path.ecg", "figure.flexibility", "hand.raised.fill"
    ]
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(commonIcons, id: \.self) { icon in
                        Button(action: {
                            HapticManager.selectionChanged()
                            selectedIcon = icon
                            dismiss()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == icon ? Color.blue : Color(.systemGray5))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: icon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(selectedIcon == icon ? .white : .primary)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
struct CustomWorkoutExerciseRowWithNav: View {
    @Environment(\.colorScheme) private var colorScheme
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var showingDetail = false
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: { HapticManager.selectionChanged(); onToggle() }) {
                HStack(spacing: 12) {
                    // Checkbox
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 28, height: 28)
                        
                        if isSelected {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                    
                    // Exercise icon
                    ZStack {
                        Circle()
                            .fill(categoryColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: categoryIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(categoryColor)
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
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Info button - opens full screen detail
            Button(action: {
                HapticManager.selectionChanged()
                showingDetail = true
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.leading, 8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03))
                    .offset(y: 3)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color(white: 0.12)]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: [
                                categoryColor.opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryColor.opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 8, x: 0, y: 4)
        .shadow(color: categoryColor.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 12, x: 0, y: 6)
        .fullScreenCover(isPresented: $showingDetail) {
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { HapticManager.selectionChanged(); showingDetail = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
            }
        }
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
    
    private var categoryIcon: String {
        guard let category = exercise.category else { return "figure.strengthtraining.traditional" }
        switch category.lowercased() {
        case "chest": return "heart.fill"
        case "back": return "person.fill"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "hand.raised.fill"
        case "core": return "circle.circle"
        default: return "figure.strengthtraining.traditional"
        }
    }
}

struct CustomWorkoutScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    CustomWorkoutBuilderView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .environmentObject(WorkoutManager.shared)
        .environmentObject(UserManager())
}

