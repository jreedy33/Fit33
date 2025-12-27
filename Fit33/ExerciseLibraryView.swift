import SwiftUI
import CoreData

struct ExerciseLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @State private var selectedExerciseTypes: Set<ExerciseFilterService.ExerciseType> = [.strength] // Default to Strength, allows multiple
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMuscleGroup = "All"
    @State private var selectedExercise: Exercise?
    @State private var forceRenderID = UUID()
    @State private var exerciseFilter: ExerciseFilterType = .recommended
    
    enum ExerciseFilterType: String, CaseIterable {
        case recommended = "Recommended"
        case all = "All Exercises"
        case favorites = "Favorites"
        case custom = "Custom Added"
    }
    
    // MARK: - Essential Recommended Exercises (Curated ~180 exercises)
    // One primary variation per movement - the essentials everyone should know
    private let recommendedExercises: Set<String> = [
        // ═══════════════════════════════════════════════════════════
        // CHEST (12 essential movements)
        // ═══════════════════════════════════════════════════════════
        "bench press", "incline bench press", "decline bench press",
        "dumbbell press", "push up", "chest dip",
        "dumbbell fly", "cable fly", "pec deck",
        "machine chest press", "cable crossover", "landmine press",
        
        // ═══════════════════════════════════════════════════════════
        // BACK (14 essential movements)
        // ═══════════════════════════════════════════════════════════
        "pull up", "chin up", "lat pulldown",
        "barbell row", "dumbbell row", "cable row", "seated row",
        "t-bar row", "face pull", "straight arm pulldown",
        "inverted row", "machine row", "deadlift", "rack pull",
        
        // ═══════════════════════════════════════════════════════════
        // SHOULDERS (12 essential movements)
        // ═══════════════════════════════════════════════════════════
        "overhead press", "shoulder press", "dumbbell shoulder press",
        "arnold press", "lateral raise", "front raise",
        "rear delt fly", "reverse fly", "upright row",
        "face pull", "machine shoulder press", "push press",
        
        // ═══════════════════════════════════════════════════════════
        // BICEPS (10 essential movements)
        // ═══════════════════════════════════════════════════════════
        "bicep curl", "barbell curl", "dumbbell curl",
        "hammer curl", "preacher curl", "concentration curl",
        "cable curl", "incline curl", "ez bar curl", "spider curl",
        
        // ═══════════════════════════════════════════════════════════
        // TRICEPS (10 essential movements)
        // ═══════════════════════════════════════════════════════════
        "tricep pushdown", "tricep extension", "skull crusher",
        "close grip bench press", "tricep dip", "overhead extension",
        "cable pushdown", "rope pushdown", "tricep kickback", "diamond push up",
        
        // ═══════════════════════════════════════════════════════════
        // QUADS (12 essential movements)
        // ═══════════════════════════════════════════════════════════
        "squat", "back squat", "front squat", "goblet squat",
        "leg press", "leg extension", "hack squat",
        "lunge", "walking lunge", "bulgarian split squat",
        "step up", "sissy squat",
        
        // ═══════════════════════════════════════════════════════════
        // HAMSTRINGS (8 essential movements)
        // ═══════════════════════════════════════════════════════════
        "romanian deadlift", "stiff leg deadlift", "leg curl",
        "lying leg curl", "seated leg curl", "good morning",
        "nordic curl", "glute ham raise",
        
        // ═══════════════════════════════════════════════════════════
        // GLUTES (10 essential movements)
        // ═══════════════════════════════════════════════════════════
        "hip thrust", "glute bridge", "cable kickback",
        "donkey kick", "sumo deadlift", "sumo squat",
        "cable pull through", "fire hydrant", "clamshell", "kickback",
        
        // ═══════════════════════════════════════════════════════════
        // CALVES (5 essential movements)
        // ═══════════════════════════════════════════════════════════
        "calf raise", "standing calf raise", "seated calf raise",
        "leg press calf raise", "single leg calf raise",
        
        // ═══════════════════════════════════════════════════════════
        // ABS (12 essential movements)
        // ═══════════════════════════════════════════════════════════
        "crunch", "sit up", "leg raise", "hanging leg raise",
        "plank", "russian twist", "bicycle crunch",
        "mountain climber", "dead bug", "ab wheel",
        "cable crunch", "v up",
        
        // ═══════════════════════════════════════════════════════════
        // OBLIQUES (6 essential movements)
        // ═══════════════════════════════════════════════════════════
        "side plank", "wood chop", "side bend",
        "oblique crunch", "pallof press", "windshield wiper",
        
        // ═══════════════════════════════════════════════════════════
        // TRAPS (5 essential movements)
        // ═══════════════════════════════════════════════════════════
        "shrug", "barbell shrug", "dumbbell shrug",
        "farmer carry", "upright row",
        
        // ═══════════════════════════════════════════════════════════
        // FOREARMS (4 essential movements)
        // ═══════════════════════════════════════════════════════════
        "wrist curl", "reverse wrist curl", "farmer walk", "dead hang",
        
        // ═══════════════════════════════════════════════════════════
        // COMPOUND / FULL BODY (8 essential movements)
        // ═══════════════════════════════════════════════════════════
        "deadlift", "clean", "clean and press", "power clean",
        "kettlebell swing", "thruster", "burpee", "turkish get up",
        
        // ═══════════════════════════════════════════════════════════
        // ROTATOR CUFF / PREHAB (5 essential movements)
        // ═══════════════════════════════════════════════════════════
        "external rotation", "internal rotation", "band pull apart",
        "face pull", "y raise"
    ]
    
    // Categories filtered by selected exercise types (combines all selected)
    private var categories: [String] {
        var allCategories = Set<String>(["All"])
        for type in selectedExerciseTypes {
            allCategories.formUnion(ExerciseFilterService.categories(for: type))
        }
        return ["All"] + Array(allCategories).filter { $0 != "All" }.sorted()
    }
    
    private let allMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques", "Hip Flexors", "Adductors", "Rotator Cuff"]
    
    // Smart muscle groups based on selected category (uses centralized service)
    private var muscleGroups: [String] {
        ExerciseFilterService.muscleGroupsForCategory(selectedCategory)
    }
    
    // Extremely precise exercise-specific muscle group mapping based on biomechanics
    private func isExerciseForMuscleGroup(_ exercise: Exercise, muscleGroup: String) -> Bool {
        let exerciseName = exercise.name?.lowercased() ?? ""
        let exerciseMuscleGroups = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
        
        switch muscleGroup {
        case "Upper Chest":
            // Only incline movements and exercises specifically targeting upper pecs
            return (exerciseName.contains("incline") && !exerciseName.contains("decline")) ||
                   exerciseMuscleGroups.contains("upper pectoralis major") ||
                   exerciseMuscleGroups.contains("clavicular pectoralis") ||
                   exerciseMuscleGroups.contains("upper chest") ||
                   (exerciseName.contains("reverse grip") && exerciseName.contains("bench")) ||
                   exerciseName.contains("landmine press") ||
                   exerciseName.contains("low to high")
                   
        case "Lower Chest":
            // Only decline movements and exercises specifically targeting lower pecs
            return (exerciseName.contains("decline") && !exerciseName.contains("incline")) ||
                   exerciseMuscleGroups.contains("lower pectoralis major") ||
                   exerciseMuscleGroups.contains("sternal pectoralis") ||
                   exerciseMuscleGroups.contains("lower chest") ||
                   exerciseName.contains("dip") ||
                   (exerciseName.contains("high to low") && exerciseName.contains("cable"))
                   
        case "Inner Chest":
            // Close grip movements and exercises targeting inner pecs
            return exerciseName.contains("close grip") ||
                   exerciseName.contains("squeeze") ||
                   exerciseName.contains("diamond") ||
                   exerciseMuscleGroups.contains("inner pectoralis major") ||
                   exerciseMuscleGroups.contains("medial pectoralis") ||
                   exerciseMuscleGroups.contains("inner chest") ||
                   (exerciseName.contains("cable") && exerciseName.contains("crossover"))
                   
        case "Outer Chest":
            // Wide grip movements and exercises targeting outer pecs
            return exerciseName.contains("wide grip") ||
                   exerciseName.contains("fly") ||
                   exerciseName.contains("flye") ||
                   exerciseMuscleGroups.contains("outer pectoralis major") ||
                   exerciseMuscleGroups.contains("lateral pectoralis") ||
                   exerciseMuscleGroups.contains("outer chest") ||
                   exerciseName.contains("pec deck")
                   
        case "Chest":
            // All chest exercises (but exclude specific targeting when other filters are active)
            return exercise.category?.lowercased() == "chest" ||
                   exerciseMuscleGroups.contains { $0.contains("pectoral") } ||
                   exerciseMuscleGroups.contains { $0.contains("chest") }
                   
        case "Lats":
            return exerciseName.contains("pulldown") ||
                   exerciseName.contains("pull down") ||
                   exerciseName.contains("lat") ||
                   exerciseName.contains("chin up") ||
                   exerciseName.contains("pull up") ||
                   exerciseName.contains("pullup") ||
                   exerciseMuscleGroups.contains("latissimus dorsi") ||
                   exerciseMuscleGroups.contains("lats")
                   
        case "Traps":
            return exerciseName.contains("shrug") ||
                   exerciseName.contains("upright row") ||
                   exerciseName.contains("face pull") ||
                   exerciseName.contains("trap") ||
                   exerciseMuscleGroups.contains("trapezius") ||
                   exerciseMuscleGroups.contains("traps")
                   
        case "Rhomboids":
            return exerciseName.contains("row") ||
                   exerciseName.contains("reverse fly") ||
                   exerciseName.contains("reverse flye") ||
                   exerciseName.contains("rear delt") ||
                   exerciseMuscleGroups.contains("rhomboids") ||
                   exerciseMuscleGroups.contains("rhomboid")
                   
        case "Lower Back":
            return exerciseName.contains("deadlift") ||
                   exerciseName.contains("hyperextension") ||
                   exerciseName.contains("good morning") ||
                   exerciseName.contains("back extension") ||
                   exerciseMuscleGroups.contains("erector spinae") ||
                   exerciseMuscleGroups.contains("lower back") ||
                   exerciseMuscleGroups.contains("lumbar")
                   
        case "Back":
            return exercise.category?.lowercased() == "back" ||
                   exerciseMuscleGroups.contains { $0.contains("latissimus") } ||
                   exerciseMuscleGroups.contains { $0.contains("trapezius") } ||
                   exerciseMuscleGroups.contains { $0.contains("rhomboid") } ||
                   exerciseMuscleGroups.contains { $0.contains("erector") }
                   
        case "Front Delts":
            // Only front raises, overhead presses, and exercises specifically targeting anterior delts
            return exerciseName.contains("front raise") ||
                   exerciseName.contains("military press") ||
                   exerciseName.contains("overhead press") ||
                   exerciseName.contains("shoulder press") ||
                   (exerciseName.contains("press") && !exerciseName.contains("bench") && !exerciseName.contains("close grip")) ||
                   exerciseName.contains("arnold press") ||
                   exerciseName.contains("push press") ||
                   exerciseMuscleGroups.contains("anterior deltoids") ||
                   exerciseMuscleGroups.contains("front deltoids") ||
                   // Exclude lateral and rear delt specific exercises
                   !(exerciseName.contains("lateral") || exerciseName.contains("side") || exerciseName.contains("rear"))
                   
        case "Side Delts":
            // Only lateral raises and exercises specifically targeting medial/lateral delts
            return exerciseName.contains("lateral raise") ||
                   exerciseName.contains("side raise") ||
                   exerciseName.contains("lateral") ||
                   exerciseName.contains("upright row") ||
                   exerciseMuscleGroups.contains("lateral deltoids") ||
                   exerciseMuscleGroups.contains("side deltoids") ||
                   exerciseMuscleGroups.contains("medial deltoids") ||
                   exerciseMuscleGroups.contains("middle deltoids") ||
                   // Must NOT be front or rear specific
                   !(exerciseName.contains("front") || exerciseName.contains("rear") || exerciseName.contains("reverse"))
                   
        case "Rear Delts":
            // Only rear delt flies, reverse flies, face pulls, and rear-specific exercises
            return exerciseName.contains("rear delt") ||
                   exerciseName.contains("rear lateral") ||
                   exerciseName.contains("reverse fly") ||
                   exerciseName.contains("reverse flye") ||
                   exerciseName.contains("face pull") ||
                   exerciseName.contains("bent over") && (exerciseName.contains("fly") || exerciseName.contains("raise")) ||
                   exerciseName.contains("rear") ||
                   exerciseName.contains("reverse") ||
                   exerciseMuscleGroups.contains("posterior deltoids") ||
                   exerciseMuscleGroups.contains("rear deltoids") ||
                   // Must NOT be front or side specific
                   !(exerciseName.contains("front") || exerciseName.contains("lateral") || exerciseName.contains("side") || exerciseName.contains("military") || exerciseName.contains("overhead"))
                   
        case "Shoulders":
            return exercise.category?.lowercased() == "shoulders" ||
                   exerciseMuscleGroups.contains { $0.contains("deltoid") } ||
                   exerciseMuscleGroups.contains { $0.contains("shoulder") }
                   
        case "Biceps":
            return exerciseName.contains("curl") ||
                   exerciseName.contains("chin up") ||
                   exerciseName.contains("pull up") ||
                   exerciseMuscleGroups.contains("biceps") ||
                   exerciseMuscleGroups.contains("brachialis")
                   
        case "Triceps":
            return exerciseName.contains("extension") ||
                   exerciseName.contains("pushdown") ||
                   exerciseName.contains("push down") ||
                   exerciseName.contains("close grip") ||
                   exerciseName.contains("diamond") ||
                   exerciseName.contains("dip") ||
                   exerciseMuscleGroups.contains("triceps") ||
                   exerciseMuscleGroups.contains("anconeus")
                   
        case "Forearms":
            return exerciseName.contains("wrist") ||
                   exerciseName.contains("forearm") ||
                   exerciseName.contains("hammer") ||
                   exerciseName.contains("reverse curl") ||
                   exerciseMuscleGroups.contains("forearms") ||
                   exerciseMuscleGroups.contains("brachioradialis")
                   
        case "Arms":
            return exercise.category?.lowercased() == "arms" ||
                   exerciseMuscleGroups.contains { $0.contains("biceps") } ||
                   exerciseMuscleGroups.contains { $0.contains("triceps") } ||
                   exerciseMuscleGroups.contains { $0.contains("forearm") }
                   
        case "Quadriceps":
            return exerciseName.contains("squat") ||
                   exerciseName.contains("lunge") ||
                   exerciseName.contains("leg press") ||
                   exerciseName.contains("leg extension") ||
                   exerciseName.contains("front squat") ||
                   exerciseMuscleGroups.contains("quadriceps") ||
                   exerciseMuscleGroups.contains("quads")
                   
        case "Hamstrings":
            return exerciseName.contains("deadlift") ||
                   exerciseName.contains("leg curl") ||
                   exerciseName.contains("romanian") ||
                   exerciseName.contains("stiff leg") ||
                   exerciseName.contains("good morning") ||
                   exerciseMuscleGroups.contains("hamstrings") ||
                   exerciseMuscleGroups.contains("biceps femoris")
                   
        case "Glutes":
            return exerciseName.contains("hip thrust") ||
                   exerciseName.contains("glute bridge") ||
                   exerciseName.contains("bulgarian") ||
                   exerciseName.contains("sumo") ||
                   exerciseName.contains("deadlift") ||
                   exerciseMuscleGroups.contains("glutes") ||
                   exerciseMuscleGroups.contains("gluteus")
                   
        case "Calves":
            return exerciseName.contains("calf") ||
                   exerciseName.contains("raise") && (exerciseName.contains("heel") || exerciseName.contains("toe")) ||
                   exerciseMuscleGroups.contains("calves") ||
                   exerciseMuscleGroups.contains("gastrocnemius") ||
                   exerciseMuscleGroups.contains("soleus")
                   
        case "Legs":
            return exercise.category?.lowercased() == "legs" ||
                   exerciseMuscleGroups.contains { $0.contains("quadriceps") } ||
                   exerciseMuscleGroups.contains { $0.contains("hamstring") } ||
                   exerciseMuscleGroups.contains { $0.contains("glute") } ||
                   exerciseMuscleGroups.contains { $0.contains("calf") }
                   
        case "Upper Abs":
            return exerciseName.contains("crunch") ||
                   exerciseName.contains("sit up") ||
                   exerciseName.contains("situp") ||
                   exerciseMuscleGroups.contains("upper abs") ||
                   exerciseMuscleGroups.contains("upper abdominals")
                   
        case "Lower Abs":
            return exerciseName.contains("leg raise") ||
                   exerciseName.contains("knee raise") ||
                   exerciseName.contains("reverse crunch") ||
                   exerciseName.contains("mountain climber") ||
                   exerciseMuscleGroups.contains("lower abs") ||
                   exerciseMuscleGroups.contains("lower abdominals")
                   
        case "Obliques":
            return exerciseName.contains("oblique") ||
                   exerciseName.contains("side bend") ||
                   exerciseName.contains("russian twist") ||
                   exerciseName.contains("wood chop") ||
                   exerciseName.contains("bicycle") ||
                   exerciseMuscleGroups.contains("obliques")
                   
        case "Core":
            return exercise.category?.lowercased() == "core" ||
                   exerciseName.contains("plank") ||
                   exerciseName.contains("ab") ||
                   exerciseMuscleGroups.contains { $0.contains("abs") } ||
                   exerciseMuscleGroups.contains { $0.contains("abdominal") } ||
                   exerciseMuscleGroups.contains { $0.contains("oblique") }
                   
        default:
            return false
        }
    }
    // Updated equipment types for 7000+ exercise library
    private let equipmentTypes = ExerciseFilterService.allEquipment
    
    private var filterIcon: String {
        switch exerciseFilter {
        case .recommended:
            return "star.circle.fill"
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .favorites:
            return "heart.fill"
        case .custom:
            return "person.crop.circle.badge.plus"
        }
    }
    
    private var filterColor: Color {
        switch exerciseFilter {
        case .recommended:
            return Color(red: 0.0, green: 0.75, blue: 0.75)  // Vibrant teal to match theme
        case .all:
            return Color(.systemGray5)
        case .favorites:
            return .yellow
        case .custom:
            return .blue
        }
    }
    
    // 🚀 PERFORMANCE: Computed property with minimal logging
    var filteredExercises: [Exercise] {
        var filtered = exercises
        
        // Filter by exercise filter type (Recommended/All/Favorites/Custom)
        switch exerciseFilter {
        case .recommended:
            // First filter to matching exercises
            var matchingExercises = filtered.filter { exercise in
                let fullName = (exercise.name ?? "").lowercased()
                let baseName = fullName.replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "  ", with: " ")
                
                for recommended in recommendedExercises {
                    if baseName == recommended { return true }
                    if baseName.hasPrefix(recommended) && baseName.count <= recommended.count + 15 { return true }
                }
                return false
            }
            
            // Group by base exercise name and keep only the primary variation (prefer Barbell > Dumbbell > Cable > Machine > Bodyweight)
            var seenBaseNames: Set<String> = []
            let equipmentPriority = ["barbell", "dumbbell", "cable", "machine", "bodyweight", "band", "kettlebell"]
            
            // Sort by equipment priority first
            matchingExercises.sort { ex1, ex2 in
                let equip1 = (ex1.equipment ?? "").lowercased()
                let equip2 = (ex2.equipment ?? "").lowercased()
                let priority1 = equipmentPriority.firstIndex(where: { equip1.contains($0) }) ?? 99
                let priority2 = equipmentPriority.firstIndex(where: { equip2.contains($0) }) ?? 99
                return priority1 < priority2
            }
            
            // Keep only the first (best) variation of each base exercise
            filtered = matchingExercises.filter { exercise in
                let fullName = (exercise.name ?? "").lowercased()
                let baseName = fullName.replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                
                if seenBaseNames.contains(baseName) {
                    return false
                }
                seenBaseNames.insert(baseName)
                return true
            }
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .custom:
            filtered = filtered.filter { $0.instructions?.contains("[CUSTOM_EXERCISE") ?? false }
        case .all:
            break
        }
        
        // Filter by exercise type(s) (Strength/Cardio/Plyometrics/Stretching)
        // Allows multiple types to be selected
        // Uses workout_type field from database, falls back to smart classification
        if !selectedExerciseTypes.isEmpty {
            filtered = filtered.filter { exercise in
                // First check the workout_type field from database
                if let workoutType = exercise.workoutType, !workoutType.isEmpty {
                    let normalizedType = workoutType.lowercased()
                    
                    // Check if any selected type matches
                    for selectedType in selectedExerciseTypes {
                        switch selectedType {
                        case .strength:
                            if normalizedType == "strength" { return true }
                        case .cardio:
                            if normalizedType == "cardio" { return true }
                        case .plyometrics:
                            if normalizedType == "plyometrics" { return true }
                        case .stretching:
                            if normalizedType == "stretch" || normalizedType == "stretching" { return true }
                        }
                    }
                    return false
                }
                
                // Fallback to smart classification for exercises without workout_type
                let smartType = ExerciseFilterService.classifyExerciseType(
                    name: exercise.name,
                    category: exercise.category,
                    equipment: exercise.equipment
                )
                return selectedExerciseTypes.contains(smartType)
            }
        }
        
        // 🔍 INTELLIGENT SEARCH with fuzzy matching and personalization
        // Pass filter context to prioritize common exercises for new users
        let userBehavior = UserBehaviorLearningEngine.shared.userPreferences
        
        // Prepare filter context for smart search
        let categoryForSearch = selectedCategory != "All" ? selectedCategory : nil
        let equipmentForSearch = selectedEquipment != "All" ? selectedEquipment : nil
        
        if !searchText.isEmpty {
            // Use smart search with filter context
            filtered = SmartExerciseSearchService.shared.searchExercises(
                query: searchText,
                in: filtered,
                userBehavior: userBehavior,
                categoryFilter: categoryForSearch,
                equipmentFilter: equipmentForSearch
            )
        } else {
            // No search query - rank by common exercises for filters
            // This ensures "Chest + Dumbbells" shows common dumbbell chest exercises first
            filtered = SmartExerciseSearchService.shared.searchExercises(
                query: "", // Empty query triggers ranking by common exercises
                in: filtered,
                userBehavior: userBehavior,
                categoryFilter: categoryForSearch,
                equipmentFilter: equipmentForSearch
            )
        }
        
        // Filter by category (within the selected exercise type)
        if selectedCategory != "All" {
            let categoryLower = selectedCategory.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseCategory = (exercise.category ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
                return exerciseCategory == categoryLower || exerciseCategory.contains(categoryLower)
            }
        }
        
        // Filter by equipment - STRICT matching
        if selectedEquipment != "All" {
            let selectedEquipmentLower = selectedEquipment.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseEquipment = exercise.equipment?.lowercased() ?? ""
                
                // Parse comma-separated equipment (e.g., "Dumbbell, Bench")
                let equipmentParts = exerciseEquipment
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                
                // Check if any equipment part matches the selected equipment
                return equipmentParts.contains { part in
                    part.contains(selectedEquipmentLower) || selectedEquipmentLower.contains(part)
                }
            }
        }
        
        // Filter by muscle group
        if selectedMuscleGroup != "All" {
            let muscleLower = selectedMuscleGroup.lowercased()
            filtered = filtered.filter { exercise in
                let muscleGroups = (exercise.muscleGroups as? [String]) ?? []
                return muscleGroups.contains { $0.lowercased().contains(muscleLower) }
            }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Fixed header section (doesn't scroll)
                VStack(spacing: 0) {
                    // Custom header
                    customHeaderView
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    
                    // Compact search and filters
                    compactFiltersView
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                
                // Scrollable exercise list only
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id("top")
                        
                        LazyVStack(spacing: 10) {
                            ForEach(filteredExercises, id: \.objectID) { exercise in
                                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                    CompactExerciseRowContent(exercise: exercise, showChevron: true)
                                }
                                .buttonStyle(PlainButtonStyle())
                                // No prefetching - videos load on-demand when exercise is tapped
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 100)
                    }
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in
                            // Dismiss keyboard when user starts scrolling
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    )
                    .id(forceRenderID)
                    .refreshable {
                        loadExercises()
                    }
                    .onChange(of: scrollToTopTrigger) { _, _ in
                        scrollProxy.scrollTo("top", anchor: .top)
                    }
                }
            }
            .onChange(of: searchText) { oldValue, newValue in
                // Log search after debounce (when user stops typing)
                if !newValue.isEmpty && newValue.count >= 2 {
                    // Using task with delay for debouncing
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                        // Check if search text is still the same (user stopped typing)
                        await MainActor.run {
                            if searchText == newValue {
                                let resultCount = filteredExercises.count
                                let filters = [selectedCategory, selectedEquipment, selectedMuscleGroup].filter { $0 != "All" }
                                if resultCount == 0 {
                                    SessionLogManager.shared.logExerciseSearchNoResults(query: newValue, filters: filters.isEmpty ? nil : filters)
                                } else {
                                    SessionLogManager.shared.logExerciseSearch(query: newValue, resultCount: resultCount, filters: filters.isEmpty ? nil : filters)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                AdaptiveGradient.exercises(for: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            )
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                let startTime = Date()
                
                // Load exercises from cache first
                loadExercises()
                
                // Log screen appearance with unique ID
                SessionLogManager.shared.logScreen(.exerciseLibrary, metadata: [
                    "exercise_count": exercises.count,
                    "filter": exerciseFilter.rawValue,
                    "load_time_ms": Int(Date().timeIntervalSince(startTime) * 1000)
                ])
                
                // Only trigger cloud sync if we have very few exercises (< 500)
                // This prevents duplicate syncs when we already have cloud data
                // Full library is ~6900 exercises - if we have 500+, we've already synced
                if exercises.count < 500 && !WorkoutManager.shared.isWorkoutActive {
                    print("📚 [LIBRARY] Exercise count (\(exercises.count)) very low, triggering cloud sync...")
                    SessionLogManager.shared.logDataSync(type: "Exercises", itemCount: exercises.count, direction: "download")
                    Task {
                        await ExerciseLibraryService.shared.syncExercisesFromCloud()
                        await MainActor.run {
                loadExercises()
                            print("📚 [LIBRARY] Sync complete, now have \(exercises.count) exercises")
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Refresh when app comes to foreground
                viewContext.refreshAllObjects()
                loadExercises()
                forceRenderID = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FavoriteExerciseChanged"))) { _ in
                // Refresh when favorites are changed
                print("📚 Exercise Library: Favorite changed, refreshing...")
                viewContext.refreshAllObjects()
                loadExercises()
                forceRenderID = UUID()
            }
        }
    }
    
    @State private var showStretchMode = false
    
    // MARK: - Custom Header View
    private var customHeaderView: some View {
        HStack {
            Text("Exercises")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.0, green: 0.75, blue: 0.75), Color(red: 0.0, green: 0.75, blue: 0.75), Color(red: 0.0, green: 0.85, blue: 0.85).opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 0.0, green: 0.75, blue: 0.75).opacity(0.4), radius: 6, x: 0, y: 2)
            
            Spacer()
            
            // Stretch Mode button
            Button(action: { HapticManager.selectionChanged(); showStretchMode = true }) {
                HStack(spacing: 4) {
                    Text("🧘")
                        .font(.system(size: 14))
                    Text("Stretch")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.mint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.mint.opacity(0.15))
                        .overlay(
                            Capsule()
                                .stroke(Color.mint.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            
            // Active workout timer (only shows when workout is active)
            if WorkoutManager.shared.isWorkoutActive {
                Text(WorkoutManager.shared.formattedDuration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.leading, 4)
        .fullScreenCover(isPresented: $showStretchMode) {
            StretchModeView()
        }
    }
    
    private var compactFiltersView: some View {
        VStack(spacing: 16) {
            // Search section with title
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.75))
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
                
                // Compact search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Search exercises...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    if !searchText.isEmpty {
                        Button(action: { HapticManager.selectionChanged(); searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6).opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.03), lineWidth: 1)
                )
            }
            
            // Compact filter categories
            VStack(alignment: .leading, spacing: 8) {
                // Exercise Type row (Strength/Cardio/Plyometrics/Stretching)
                HStack(spacing: 8) {
                    Text("Type")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ExerciseFilterService.ExerciseType.allCases, id: \.self) { exerciseType in
                                ExerciseTypeChip(
                                    exerciseType: exerciseType,
                                    isSelected: selectedExerciseTypes.contains(exerciseType),
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            // Toggle selection - allows multiple types
                                            if selectedExerciseTypes.contains(exerciseType) {
                                                // Keep at least one selected
                                                if selectedExerciseTypes.count > 1 {
                                                    selectedExerciseTypes.remove(exerciseType)
                                                }
                                            } else {
                                                selectedExerciseTypes.insert(exerciseType)
                                            }
                                            selectedCategory = "All"
                                            selectedMuscleGroup = "All"
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                
                // Categories row (filtered by exercise type)
                HStack(spacing: 8) {
                    Text("Category")
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
                                    color: .blue,
                                    secondaryColor: .cyan,
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
                                        secondaryColor: .teal,
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
                                    color: Color(red: 0.0, green: 0.75, blue: 0.75),
                                    secondaryColor: .cyan,
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
        .padding(.vertical, 16)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - teal tinted (subtle)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.0, green: 0.75, blue: 0.75).opacity(colorScheme == .dark ? 0.08 : 0.04))
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
                
                // Colored accent border - soft teal
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.75, blue: 0.75).opacity(colorScheme == .dark ? 0.35 : 0.25),
                                Color(red: 0.0, green: 0.75, blue: 0.75).opacity(colorScheme == .dark ? 0.2 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.05), radius: 8, x: 0, y: 4)
        .shadow(color: Color(red: 0.0, green: 0.75, blue: 0.75).opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 12, x: 0, y: 6)
    }
    
    private func loadExercises() {
        exercises = ExerciseLibraryService.shared.getAllExercises()
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
                    .shadow(color: categoryGradient[0].opacity(0.25), radius: 4, x: 0, y: 2)
                
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
                Text(exercise.name ?? "Unknown Exercise")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
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
                                categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
        .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
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
                .padding(.horizontal, 12)
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
            .padding(.horizontal, 12)
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


#Preview {
    ExerciseLibraryView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
