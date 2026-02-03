import SwiftUI
import CoreData

struct ExerciseLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMuscleGroup = "All"
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
    
    // MARK: - Top 500 Recommended Exercises (Curated from database)
    // Comprehensive list covering all major movements, equipment types, and fitness levels
    private let recommendedExercises: Set<String> = [
        // ═══════════════════════════════════════════════════════════
        // CHEST - 65 exercises (all equipment variations)
        // ═══════════════════════════════════════════════════════════
        // Barbell Bench Press Variations
        "bench press", "incline bench press", "decline bench press", "close grip bench press",
        "wide bench press", "reverse grip bench press", "floor press", "pin bench press",
        "paused bench press", "tempo bench press", "board press", "guillotine bench press",
        "jm bench press", "feet flat bench press", "explosive bench press", "banded bench press",
        "weighted chains bench press", "reverse grip decline bench press", "reverse grip incline bench press",
        "wide reverse grip bench press", "pullover with bench press", "pin chest press",
        // Dumbbell Chest
        "dumbbell press", "dumbbell bench press", "incline dumbbell press", "decline dumbbell press",
        "dumbbell fly", "incline dumbbell fly", "decline dumbbell fly", "lying fly on floor",
        "neutral grip bench press", "single arm dumbbell press", "alternating dumbbell press",
        "dumbbell pullover", "squeeze bench press", "squeeze press", "hex press",
        "incline squeeze press", "decline hammer press", "incline hammer press", "hammer press",
        "incline palm in press", "rotational bench press", "glute bridge chest press",
        "2 point bench press", "3 point bench press", "lying one arm press",
        // Cable & Machine Chest
        "cable fly", "cable crossover", "low cable fly", "high cable fly",
        "incline cable fly", "single arm cable fly", "standing cable press",
        "low chest press", "seated single arm chest press", "standing single arm chest press",
        // Machine & Smith Machine Chest
        "machine chest press", "pec deck", "machine fly", "smith bench press",
        "smith incline bench press", "smith decline bench press", "smith close grip bench press",
        "smith wide grip bench press", "smith jm bench press",
        // Bodyweight & Landmine Chest
        "push up", "decline push up", "diamond push up", "wide push up", "archer push up",
        "pike push up", "chest dip", "ring dip", "deficit push up", "clap push up",
        "landmine press", "landmine single arm press",
        
        // ═══════════════════════════════════════════════════════════
        // BACK - 95 exercises (lats, traps, rhomboids, lower back)
        // ═══════════════════════════════════════════════════════════
        // Pull-Ups & Chin-Ups
        "pull up", "chin up", "wide grip pull up", "close grip chin up",
        "neutral grip pull up", "weighted pull up", "weighted chin up", "assisted pull up",
        "assisted chin up", "l sit pull up", "l sit chin up", "wide chin up",
        "reverse grip pull up", "corn cob pull up", "shoulder grip pull up",
        // Lat Pulldowns
        "lat pulldown", "wide grip lat pulldown", "close grip pulldown", "close grip front lat pulldown",
        "neutral grip pulldown", "reverse grip pulldown", "single arm pulldown", "one arm lat pulldown",
        "straight arm pulldown", "rope pulldown", "lat pulldown full range of motion",
        "neutral grip lat pulldown", "seated wide lat pulldown", "underhand pulldown",
        "cross lat pulldown", "twin handle parallel grip lat pulldown",
        // Rows - Barbell
        "barbell row", "bent over row", "pendlay row", "underhand bent over row",
        "yates row", "seal row", "lying seal row", "chest supported row",
        "reverse grip bent over row", "paused bent over row", "t-bar row",
        "incline row", "incline rear delt row",
        // Rows - Dumbbell
        "dumbbell row", "single arm row", "one arm row", "chest supported dumbbell row",
        "kroc row", "renegade row", "plank row", "gorilla row",
        "bent over single arm row", "head supported row", "prone incline seal row",
        "hammer grip incline bench row", "reverse grip incline row",
        // Rows - Cable & Machine
        "cable row", "seated cable row", "seated row", "single arm cable row",
        "high cable row", "low cable row", "rope seated row", "low seated row",
        "machine row", "meadows row", "v-bar row", "straight back seated row",
        "front seated row", "neutral grip seated row", "high row",
        // Deadlifts & Lower Back
        "deadlift", "conventional deadlift", "sumo deadlift", "romanian deadlift",
        "stiff leg deadlift", "trap bar deadlift", "deficit deadlift", "deadlift from deficit",
        "rack pull", "snatch grip deadlift", "jefferson deadlift", "jefferson squat",
        "single leg romanian deadlift", "staggered stance romanian deadlift",
        "good morning", "back extension", "hyperextension", "45 degree hyperextension",
        "reverse hyperextension", "superman", "bird dog", "dimel deadlift",
        "hook grip deadlift", "mixed grip deadlift", "reeves deadlift",
        "sumo romanian deadlift", "staggered stance deadlift",
        // Smith Machine Back
        "smith deadlift", "smith bent over row", "smith staggered stance romanian deadlift",
        // Face Pulls & Other
        "face pull", "standing face pull", "seated face pull", "inverted row",
        "bodyweight row", "trx row", "ring row", "australian pull up",
        
        // ═══════════════════════════════════════════════════════════
        // SHOULDERS - 70 exercises (front/side/rear delts)
        // ═══════════════════════════════════════════════════════════
        // Overhead Press - Barbell
        "overhead press", "military press", "standing military press", "seated overhead press",
        "seated military press", "standing shoulder press", "push press", "behind the neck press",
        "behind head military press", "close grip military press", "reverse grip overhead press",
        "half kneeling shoulders press", "incline shoulders press",
        // Overhead Press - Dumbbell
        "dumbbell shoulder press", "seated shoulder press", "arnold press",
        "single arm shoulder press", "one arm shoulder press", "alternating shoulder press",
        "seated alternate press", "kneeling arnold press", "kneeling opposite shoulder press",
        "alternate z press", "z press", "w press", "seated w press",
        // Cable & Machine Shoulders
        "machine shoulder press", "smith standing military press",
        "smith standing behind head military press", "shoulder press",
        "landmine shoulder to shoulder press", "landmine shoulders press",
        "landmine kneeling single arm shoulder press",
        // Front Raises
        "front raise", "barbell front raise", "dumbbell front raise",
        "plate front raise", "cable front raise", "alternating front raise",
        "seated half circle front raise",
        // Lateral Raises
        "lateral raise", "dumbbell lateral raise", "cable lateral raise",
        "single arm lateral raise", "leaning lateral raise", "seated lateral raise",
        "machine lateral raise", "incline lateral raise",
        // Upright Rows
        "upright row", "wide grip upright row", "cable upright row",
        "shoulder grip upright row", "smith upright row",
        // Rear Delts
        "rear delt fly", "rear delt row", "reverse fly", "bent over lateral raise",
        "cable reverse fly", "pec deck reverse fly", "chest supported rear delt fly",
        "face pull", "band pull apart", "reverse pec deck", "lying rear delt row",
        "incline rear delt row", "prone rear delt raise",
        
        // ═══════════════════════════════════════════════════════════
        // BICEPS - 50 exercises
        // ═══════════════════════════════════════════════════════════
        // Barbell & EZ Bar Curls
        "bicep curl", "barbell curl", "curl", "standing barbell curl", "ez bar curl",
        "wide grip curl", "close grip curl", "reverse curl", "drag curl",
        "cheat curl", "spider curl", "preacher curl", "scott curl",
        // Dumbbell Curls
        "dumbbell curl", "alternate biceps curl", "alternating dumbbell curl", "hammer curl",
        "cross body hammer curl", "incline dumbbell curl", "incline hammer curl",
        "concentration curl", "seated dumbbell curl", "zottman curl", "waiter curl",
        "hammer preacher curl", "single arm preacher curl", "standing reverse curl",
        // Cable & Machine Curls
        "cable curl", "low cable curl", "high cable curl",
        "single arm cable curl", "rope cable curl", "machine curl",
        "preacher curl machine", "bayesian curl", "seated unilateral biceps curl",
        // Specialty Curls
        "incline curl", "decline curl", "prone incline curl", "lying cable curl",
        "standing single arm curl", "alternate curl", "21s",
        // Wrist Curls (Forearm/Bicep)
        "wrist curl", "reverse wrist curl", "barbell wrist curl", "dumbbell wrist curl",
        
        // ═══════════════════════════════════════════════════════════
        // TRICEPS - 50 exercises
        // ═══════════════════════════════════════════════════════════
        // Extensions - Overhead
        "tricep extension", "overhead tricep extension", "french press", "standing french press",
        "dumbbell overhead extension", "single arm overhead extension",
        "cable overhead extension", "rope overhead extension",
        "ez bar overhead extension", "seated overhead triceps extension",
        // Extensions - Lying
        "skull crusher", "lying tricep extension", "lying triceps extension",
        "ez bar skull crusher", "dumbbell skull crusher", "close grip floor press",
        "lying back of the head triceps extension", "decline close grip to skull press",
        "incline triceps extension", "pronate grip triceps extension",
        // Pushdowns
        "tricep pushdown", "triceps pushdown", "cable pushdown", "pushdown",
        "rope pushdown", "straight bar pushdown", "v-bar pushdown", "single arm pushdown",
        "reverse grip pushdown", "reverse grip triceps pushdown",
        "standing one arm triceps pushdown", "incline pushdown",
        "jack hammer pushdown", "single arm triceps pushdown",
        // Kickbacks & Dips
        "tricep kickback", "kickback", "dumbbell kickback", "cable kickback",
        "single arm kickback", "standing kickback",
        "tricep dip", "dip", "bench dip", "weighted dip", "ring dip", "machine dip",
        // Press Variations for Triceps
        "close grip press", "jm press", "tate press",
        "diamond push up", "tricep push up", "decline close grip bench press",
        "close grip bench press", "california press",
        
        // ═══════════════════════════════════════════════════════════
        // LEGS - QUADS - 70 exercises
        // ═══════════════════════════════════════════════════════════
        // Squats - Barbell
        "squat", "back squat", "high bar squat", "low bar squat",
        "front squat", "pause squat", "tempo squat", "pin squat",
        "box squat", "anderson squat", "zercher squat", "overhead squat",
        "safety bar squat", "clean grip front squat", "elevated heel squat",
        "elevated heel clean grip squat", "narrow stance squat", "wide squat",
        "banded bench squat", "squat 2 sec hold", "full squat",
        // Squats - Dumbbell & Goblet
        "goblet squat", "dumbbell squat", "goblet sumo squat", "sumo goblet squat",
        "dumbbell front squat", "elevated heel goblet squat", "elevated heel front squat",
        "goblet 2 sec hold squat", "goblet pulse squat", "narrow squat",
        // Squats - Machine & Smith
        "hack squat", "hack squat machine", "reverse hack squat", "linear hack squat",
        "pendulum squat", "vertical squat", "belt squat", "seated squat",
        "smith squat", "smith front squat", "smith hack squat", "smith low bar squat",
        "smith sumo squat", "smith frankenstein squat", "pistol squat",
        // Leg Press
        "leg press", "45 degree leg press", "angled leg press", "horizontal leg press",
        "single leg press", "narrow stance leg press", "wide stance leg press",
        "vertical leg press", "sled leg press", "smith leg press",
        "seated leg press", "bench leg press",
        // Leg Extensions
        "leg extension", "single leg extension", "seated leg extension",
        "squat to leg extension",
        // Lunges & Step Ups
        "lunge", "forward lunge", "reverse lunge", "rear lunge", "walking lunge",
        "stationary lunge", "static lunge", "lateral lunge", "side lunge",
        "curtsey lunge", "curtsy lunge", "goblet lunge", "front rack lunge",
        "step up", "step up with knee raise", "high step up", "lateral step up",
        
        // ═══════════════════════════════════════════════════════════
        // LEGS - HAMSTRINGS - 40 exercises
        // ═══════════════════════════════════════════════════════════
        // Romanian Deadlifts
        "romanian deadlift", "dumbbell romanian deadlift", "single leg romanian deadlift",
        "stiff leg deadlift", "stiff legged deadlift", "straight leg deadlift",
        "b stance romanian deadlift", "staggered stance romanian deadlift",
        "landmine romanian deadlift", "landmine single leg romanian deadlift",
        "sumo romanian deadlift", "belt romanian deadlift",
        "romanian deadlift to row", "romanian deadlift to squat",
        "ipsilateral single leg stiff leg deadlift",
        // Leg Curls
        "leg curl", "lying leg curl", "seated leg curl",
        "standing leg curl", "single leg curl", "seated single leg curl",
        "decline lying leg curl", "kneeling leg curl",
        "stability ball leg curl", "slider leg curl",
        // Nordic & GHR
        "glute ham raise", "nordic curl", "nordic hamstring curl",
        "inverse leg curl", "assisted inverse leg curl",
        // Good Mornings
        "good morning", "seated good morning", "safety bar good morning",
        "good morning on the hack squat machine",
        // Other Hamstring
        "cable pull through", "kettlebell swing", "single leg deadlift",
        "deficit stiff leg deadlift", "stiff leg deadlift from stepbox",
        
        // ═══════════════════════════════════════════════════════════
        // LEGS - GLUTES - 40 exercises
        // ═══════════════════════════════════════════════════════════
        // Hip Thrusts & Bridges
        "hip thrust", "barbell hip thrust", "single leg hip thrust",
        "banded hip thrust", "pause hip thrust", "banded single leg hip thrust",
        "staggered stance hip thrust", "one leg hip thrust",
        "glute bridge", "single leg glute bridge", "elevated glute bridge",
        "banded glute bridge", "frog pump", "hip thrust machine",
        "smith hip thrust", "landmine single leg hip thrust",
        "glute bridge chest press",
        // Bulgarian & Split Squats
        "bulgarian split squat", "split squat", "rear foot elevated split squat",
        "goblet bulgarian split squat", "dumbbell bulgarian split squat",
        "front rack split squat", "split squat front foot elevated",
        "goblet split squat", "zercher bulgarian split squat",
        "smith split squat", "smith elevated split squat",
        // Hip Abduction & Kickbacks
        "cable kickback", "cable hip abduction", "machine hip abduction",
        "donkey kick", "fire hydrant", "clamshell",
        "side lying hip abduction", "banded abduction", "monster walk",
        // Squats & Lunges (Glute Focus)
        "sumo squat", "wide stance squat", "sumo deadlift",
        "deficit bulgarian split squat", "walking lunge", "deficit reverse lunge",
        "cossack squat", "cossack squats",
        
        // ═══════════════════════════════════════════════════════════
        // CALVES - 20 exercises
        // ═══════════════════════════════════════════════════════════
        "calf raise", "standing calf raise", "seated calf raise",
        "single leg calf raise", "donkey calf raise", "smith machine calf raise",
        "leg press calf raise", "dumbbell calf raise", "hack squat calf raise",
        "rotary calf", "sled calf press", "seated single calf press",
        "outward calf raise", "one leg floor calf raise",
        "tibialis raise", "toe walk", "calf raise clap",
        
        // ═══════════════════════════════════════════════════════════
        // ABS & CORE - 50 exercises
        // ═══════════════════════════════════════════════════════════
        // Crunches
        "crunch", "bicycle crunch", "reverse crunch", "cable crunch",
        "weighted crunch", "decline crunch", "rope crunch", "kneeling crunch",
        "cross body crunch", "oblique crunch", "twisting crunch",
        "side crunch", "tuck reverse crunch", "starfish crunch",
        // Leg Raises
        "leg raise", "hanging leg raise", "lying leg raise", "weighted hanging leg raise",
        "captain's chair leg raise", "decline leg raise", "scissor kick",
        "flutter kick", "vertical leg raise", "lying bent legs raise",
        // Planks & Holds
        "plank", "forearm plank", "front elbow plank", "extended plank",
        "plank to pike", "plank jack", "plank up down", "side plank",
        "plank row", "side plank row", "single leg plank",
        "hollow body hold", "dead bug", "bird dog",
        // Sit Ups & V-Ups
        "sit up", "v up", "tuck up", "knee touch crunch",
        // Rotational & Anti-Rotation
        "russian twist", "wood chop", "pallof press", "half kneeling pallof press",
        "vertical pallof press", "cable wood chop",
        // Other Core
        "ab wheel rollout", "mountain climber", "med ball slam",
        "l sit", "hanging knee raise",
        
        // ═══════════════════════════════════════════════════════════
        // COMPOUND / OLYMPIC / FUNCTIONAL - 35 exercises
        // ═══════════════════════════════════════════════════════════
        // Olympic Lifts
        "clean", "power clean", "hang clean", "clean and press",
        "clean and jerk", "push jerk", "split jerk", "snatch",
        "power snatch", "hang snatch", "muscle snatch", "high pull",
        "clean high pull", "full clean", "hang clean below the knees",
        "hang power clean", "hang snatch below the knees",
        // Functional & Full Body
        "thruster", "burpee", "man maker", "turkish get up",
        "kettlebell swing", "american kettlebell swing", "single arm swing",
        "devil press", "devils press", "dumbbell snatch", "single arm clean and press",
        "farmer walk", "farmer carry", "suitcase carry", "overhead carry",
        "yoke walk", "sandbag carry", "bear crawl", "sled push",
        
        // ═══════════════════════════════════════════════════════════
        // TRAPS & NECK - 20 exercises
        // ═══════════════════════════════════════════════════════════
        // Shrugs
        "shrug", "barbell shrug", "dumbbell shrug", "trap bar shrug",
        "behind the back shrug", "cable shrug", "smith machine shrug",
        "overhead shrug", "snatch grip shrug", "incline shrug",
        "decline shrug", "seated reverse shrug", "smith back shrug",
        // Other Trap Work
        "high pull", "snatch grip high pull", "power shrug",
        "upright row", "face pull", "farmer walk", "dead hang"
    ]
    
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
        
        // Build filter key for caching
        let filterKey = "\(exerciseFilter.rawValue)|\(selectedCategory)|\(selectedEquipment)|\(selectedMuscleGroup)"
        
        // If filters changed, rebuild pre-filtered cache
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchResultsCache.removeAll() // Invalidate search cache
            
            // ⚡️ OPTIMIZED: Use fast filter for default "Recommended" + "All" selections
            if selectedCategory == "All" && selectedEquipment == "All" && selectedMuscleGroup == "All" && exerciseFilter == .recommended {
                // Use optimized recommended filter with precomputed name set
                preFilteredExercises = applyOptimizedRecommendedFilter(to: exercises)
                #if DEBUG
                print("⚡️ [PERF] Optimized recommended filter: \(preFilteredExercises.count) exercises in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms")
                #endif
            } else {
                // Standard filter path
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
        
        // Filter by category
        if selectedCategory != "All" {
            let categoryLower = selectedCategory.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseCategory = (exercise.category ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
                return exerciseCategory == categoryLower || exerciseCategory.contains(categoryLower)
            }
        }
        
        // Filter by equipment
        if selectedEquipment != "All" {
            filtered = filtered.filter { exercise in
                exerciseMatchesEquipmentLib(exercise, selectedEquipment: selectedEquipment)
            }
        }
        
        // Filter by muscle group
        if selectedMuscleGroup != "All" {
            filtered = filtered.filter { exercise in
                isExerciseForMuscleGroup(exercise, muscleGroup: selectedMuscleGroup)
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
                            ForEach(Array(filteredExercises.enumerated()), id: \.element.objectID) { index, exercise in
                                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                    CompactExerciseRowContent(exercise: exercise, showChevron: true)
                                }
                                .buttonStyle(PlainButtonStyle())
                                // 🚀 Smart prefetch: preload video when exercise becomes visible
                                .onAppear {
                                    prefetchVisibleExercise(exercise: exercise, index: index)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        // Add extra top padding when ad banner is showing to prevent overlap
                        .padding(.top, (!PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled) ? 70 : 4)
                        .padding(.bottom, 20)
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
            // Banner ad overlay - floats on top, scroll content has space reserved
            .overlay(alignment: .top) {
                if !PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled {
                    VStack {
                        Spacer().frame(height: 290) // Position below filters
                        BannerAdView()
                            .padding(.horizontal, 16)
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                let startTime = Date()
                
                // ⚡️ PERFORMANCE: Restore state from ViewStateCache for instant tab switch
                let cachedState = ViewStateCache.shared.exerciseLibraryState
                if !cachedState.searchText.isEmpty || cachedState.selectedCategory != "All" {
                    // Restore previous state
                    searchText = cachedState.searchText
                    selectedCategory = cachedState.selectedCategory
                    selectedEquipment = cachedState.selectedEquipment
                    selectedMuscleGroup = cachedState.selectedMuscleGroup
                }
                
                // Load exercises from cache first
                loadExercises()
                
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
                // Save to ViewStateCache for tab persistence
                ViewStateCache.shared.exerciseLibraryState.searchText = newValue
            }
            .onChange(of: selectedCategory) { _, newValue in 
                lastFilterKey = "" // Force filter rebuild
                updateFilteredExercises()
                ViewStateCache.shared.exerciseLibraryState.selectedCategory = newValue
            }
            .onChange(of: selectedEquipment) { _, newValue in 
                lastFilterKey = "" // Force filter rebuild
                updateFilteredExercises()
                ViewStateCache.shared.exerciseLibraryState.selectedEquipment = newValue
            }
            .onChange(of: selectedMuscleGroup) { _, newValue in 
                lastFilterKey = "" // Force filter rebuild
                updateFilteredExercises()
                ViewStateCache.shared.exerciseLibraryState.selectedMuscleGroup = newValue
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
                        RoundedRectangle(cornerRadius: 8)
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
                                    color: .blue,
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
        exercises = ExerciseLibraryService.shared.getAllExercises()
    }
    
    // MARK: - 🚀 Smart Video Prefetching
    
    /// Prefetch video when exercise becomes visible in list
    private func prefetchVisibleExercise(exercise: Exercise, index: Int) {
        guard let name = exercise.name else { return }
        
        // Prefetch this exercise and adjacent ones
        var namesToPrefetch = [name]
        
        // Get next 2 exercises for prefetch
        let exercises = filteredExercises
        if index + 1 < exercises.count, let nextName = exercises[index + 1].name {
            namesToPrefetch.append(nextName)
        }
        if index + 2 < exercises.count, let nextName2 = exercises[index + 2].name {
            namesToPrefetch.append(nextName2)
        }
        
        VideoPlaybackEngine.shared.prefetchVisible(exercises: namesToPrefetch)
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
