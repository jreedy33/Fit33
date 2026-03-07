import SwiftUI
import CoreData

struct ExerciseSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedExercises: [Exercise]
    
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMuscleGroup = "All"
    @State private var exercises: [Exercise] = []
    @State private var selectedExerciseForDetail: Exercise?
    
    // ⚡️ SNAPPY SEARCH: Focus state for instant keyboard dismiss
    @FocusState private var isSearchFocused: Bool
    
    // ⚡️ HIGH-PERFORMANCE: Cached results - no recomputation on every render
    @State private var cachedFilteredExercises: [Exercise] = []
    @State private var preFilteredExercises: [Exercise] = []
    @State private var lastFilterKey: String = ""
    @State private var searchCache: [String: [Exercise]] = [:]
    
    // Updated categories for 7000+ exercise library
    private let categories = ExerciseFilterService.allCategories
    private let allMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques", "Hip Flexors", "Adductors", "Rotator Cuff"]
    
    // Smart muscle groups based on selected category (uses centralized service)
    private var muscleGroups: [String] {
        ExerciseFilterService.muscleGroupsForCategory(selectedCategory)
    }
    
    // Updated equipment for 7000+ exercise library
    private let equipmentTypes = ExerciseFilterService.allEquipment
    
    // ⚡️ HIGH-PERFORMANCE: Use cached results, not computed
    var filteredExercises: [Exercise] {
        cachedFilteredExercises
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ⚡️ HIGH-PERFORMANCE SEARCH ENGINE
    // ═══════════════════════════════════════════════════════════════════════
    
    private func updateFilteredExercises() {
        let filterKey = "\(selectedCategory)|\(selectedEquipment)|\(selectedMuscleGroup)"
        
        // Rebuild filter cache if filters changed
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchCache.removeAll()
            preFilteredExercises = applyFiltersOnly(to: exercises)
        }
        
        // Apply search to pre-filtered results
        if !searchText.isEmpty {
            let searchKey = searchText.lowercased()
            if let cached = searchCache[searchKey] {
                cachedFilteredExercises = cached
                return
            }
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
    
    // MARK: - Muscle Group Matching
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
    
    // MARK: - Equipment Matching Helper
    /// Comprehensive equipment matching with normalization
    private func exerciseMatchesEquipment(_ exercise: Exercise, selectedEquipment: String) -> Bool {
        let exerciseEquipment = exercise.equipment?.lowercased() ?? ""
        let targetEquipment = selectedEquipment.lowercased()
        let exerciseName = exercise.name?.lowercased() ?? ""
        
        // Direct match
        if exerciseEquipment == targetEquipment { return true }
        
        // Normalize and compare
        let normalizedExercise = ExerciseFilterService.normalizeEquipment(exercise.equipment)
        if normalizedExercise == selectedEquipment { return true }
        
        // Handle compound equipment
        let equipmentParts = exerciseEquipment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        
        switch targetEquipment {
        case "dumbbells":
            return exerciseEquipment.contains("dumbbell") || exerciseName.contains("dumbbell")
        case "barbell":
            let isBarbell = exerciseEquipment.contains("barbell") || exerciseName.contains("barbell") ||
                           exerciseEquipment.contains("ez bar") || exerciseEquipment.contains("trap bar")
            return isBarbell && !exerciseEquipment.contains("smith")
        case "cables":
            return exerciseEquipment.contains("cable") || exerciseName.contains("cable")
        case "machines":
            // IMPORTANT: Check cables and smith FIRST to exclude them
            let isCable = exerciseEquipment.contains("cable") || exerciseName.contains("cable")
            if isCable { return false }
            
            let isSmith = exerciseEquipment.contains("smith")
            if isSmith { return false }
            
            // Any machine or lever equipment
            return exerciseEquipment.contains("machine") || exerciseEquipment.contains("lever")
        case "bodyweight":
            return exerciseEquipment.isEmpty || exerciseEquipment.contains("bodyweight")
        case "kettlebell":
            return exerciseEquipment.contains("kettlebell") || exerciseName.contains("kettlebell")
        case "resistance bands", "bands":
            return exerciseEquipment.contains("band") || exerciseName.contains("band")
        case "smith machine":
            return exerciseEquipment.contains("smith") || exerciseName.contains("smith")
        default:
            return exerciseEquipment.contains(targetEquipment)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Clean top navigation bar
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .font(.body)
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
            
            // Compact search and filters
            compactFiltersView
            
            // Exercise list
            exerciseListView
        }
        .scrollDismissesKeyboard(.interactively) // Dismiss keyboard when interacting with scrollable content
        .onAppear {
            loadExercises()
            updateFilteredExercises()
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
        .onChange(of: exercises) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .sheet(item: $selectedExerciseForDetail) { exercise in
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                selectedExerciseForDetail = nil
                            }
                        }
                    }
            }
        }
    }
    
    private var compactFiltersView: some View {
        VStack(spacing: 16) {
            // ⚡️ SNAPPY SEARCH: Instant response search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Search exercises...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.body)
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
                        searchText = ""
                        isSearchFocused = false // Also dismiss keyboard when clearing
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color(.systemGray6).opacity(0.6))
            )
            
            // Seamless filter chips in single flow
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            SelectionFilterChip(
                                text: category,
                                isSelected: selectedCategory == category,
                                onTap: { 
                                    selectedCategory = category
                                    selectedMuscleGroup = "All"
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                
                if selectedCategory != "All" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(muscleGroups, id: \.self) { muscle in
                                SelectionFilterChip(
                                    text: muscle,
                                    isSelected: selectedMuscleGroup == muscle,
                                    color: .green,
                                    onTap: { selectedMuscleGroup = muscle }
                                )
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(equipmentTypes, id: \.self) { equipment in
                            SelectionFilterChip(
                                text: equipment,
                                isSelected: selectedEquipment == equipment,
                                color: .gray,
                                onTap: { selectedEquipment = equipment }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
        .padding(.vertical, 20)
    }
    
    private var exerciseListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(filteredExercises.enumerated()), id: \.element.objectID) { index, exercise in
                    SeamlessExerciseSelectionRow(
                        exercise: exercise,
                        isSelected: selectedExercises.contains { $0.id == exercise.id },
                        onToggle: {
                            toggleExerciseSelection(exercise)
                        },
                        onInfoTap: {
                            selectedExerciseForDetail = exercise
                            // 🚀 Priority prefetch when user taps info
                            if let name = exercise.name {
                                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
                            }
                        }
                    )
                    // 🚀 Prefetch when exercise appears in viewport
                    .onAppear {
                        prefetchVisibleExercise(exercise: exercise, index: index)
                    }
                }
                
                if filteredExercises.isEmpty {
                    emptyStateView
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        // ⚡️ SNAPPY SEARCH: Dismiss keyboard instantly when scrolling
        .simultaneousGesture(
            DragGesture().onChanged { _ in
                isSearchFocused = false
            }
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No exercises found")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func loadExercises() {
        // Load exercises from cache/Core Data (don't re-initialize, that causes duplicates)
        exercises = ExerciseLibraryService.shared.getAllExercises()
        print("Loaded \(exercises.count) exercises")
    }
    
    private func toggleExerciseSelection(_ exercise: Exercise) {
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
        }
    }
    
    // MARK: - 🚀 Smart Video Prefetching
    
    /// ⚡️ MEMORY FIX: DISABLED — scroll prefetching was creating AVPlayers for every visible row,
    /// causing 600MB+ memory from XPC video process leaks. Videos load on-demand in detail view.
    private func prefetchVisibleExercise(exercise: Exercise, index: Int) {
        // NO-OP: Disabled to prevent memory pressure
    }
}

// MARK: - Seamless Components

struct SeamlessExerciseSelectionRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .blue : Color(.systemGray4))
                
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: categoryIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(categoryColor)
                }
                
                // Exercise details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(exercise.displayName)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button(action: onInfoTap) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    HStack(spacing: 6) {
                        if let category = exercise.category {
                            Text(category)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(categoryColor)
                        }
                        
                        if let equipment = exercise.equipment {
                            Text("•")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(.systemGray3))
                            
                            Text(equipment)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(.systemGray))
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
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
        // First, check for specific exercise patterns
        if let exerciseName = exercise.name?.lowercased() {
            
            // Dumbbell exercises
            if exerciseName.contains("dumbbell") {
                return "dumbbell.fill"
            }
            
            // Barbell exercises
            if exerciseName.contains("barbell") {
                return "figure.strengthtraining.traditional"
            }
            
            // Bodyweight exercises
            if exerciseName.contains("push") || exerciseName.contains("pull") || exerciseName.contains("squat") {
                return "figure.strengthtraining.functional"
            }
            
            // Cable exercises
            if exerciseName.contains("cable") {
                return "cable.connector"
            }
        }
        
        // Fallback to category-based icons
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.strengthtraining.functional"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell"
        }
    }
}

struct CompactExerciseSelectionRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator (matching the selected state)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
                
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: categoryIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(categoryColor)
                }
                
                // Exercise details
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(exercise.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button(action: onInfoTap) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
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
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
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
        // First, check for specific exercise patterns
        if let exerciseName = exercise.name?.lowercased() {
            
            // Dumbbell exercises
            if exerciseName.contains("dumbbell") {
                return "dumbbell.fill"
            }
            
            // Barbell exercises
            if exerciseName.contains("barbell") {
                return "figure.strengthtraining.traditional"
            }
            
            // Bodyweight exercises
            if exerciseName.contains("push") || exerciseName.contains("pull") || exerciseName.contains("squat") {
                return "figure.strengthtraining.functional"
            }
            
            // Cable exercises
            if exerciseName.contains("cable") {
                return "cable.connector"
            }
        }
        
        // Fallback to category-based icons
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.strengthtraining.functional"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell"
        }
    }
}



struct SelectionFilterChip: View {
    let text: String
    let isSelected: Bool
    var color: Color = .blue
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            isSelected ? 
                            LinearGradient(
                                gradient: Gradient(colors: [color, color.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                gradient: Gradient(colors: [Color(.systemGray5), Color(.systemGray6)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct ExerciseSelectionCard: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
                
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: categoryIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(categoryColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(exercise.category ?? "")
                            .font(.caption)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(6)
                        
                        Text(exercise.equipment ?? "")
                            .font(.caption)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    
                    if let muscleGroups = exercise.muscleGroups as? [String], !muscleGroups.isEmpty {
                        Text(muscleGroups.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(action: onInfoTap) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.white)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
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

#Preview {
    ExerciseSelectionView(selectedExercises: .constant([]))
}
