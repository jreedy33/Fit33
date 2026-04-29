import SwiftUI
import CoreData

struct CustomWorkoutBuilderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var exerciseLibrary = ExerciseLibraryService.shared
    // Observed so the build-mode "Suggested: {muscle}" strip retries
    // automatically once the precomputed recommended cache warms (cold-
    // start race — the user can land on Build Workout before
    // `precomputeRecommendedList` finishes its background pass).
    @ObservedObject private var filterCache = ExerciseLibraryFilterCache.shared
    
    // MARK: - Mode Configuration
    enum Mode {
        case build          // Default: multi-select to build a workout
        case replace(Exercise, (Exercise) -> Void)  // Single-select to replace an exercise
        case addToWorkout([Exercise], (Exercise) -> Void)  // Single-select to add to active workout
        // Multi-select picker for "send to friend" / similar flows. Recycles every
        // build-mode affordance (poster-ring cards, recommended filter, suggested
        // swaps, search) but commits the selection through a toolbar "Done (N)"
        // button instead of starting a workout via the floating GO button.
        // `initialSelection` is restored on `.onAppear` so the user sees their
        // already-picked exercises checked.
        case pickMultiple([Exercise], ([Exercise]) -> Void)
        
        var title: String {
            switch self {
            case .build: return "Build Workout"
            case .replace: return "Replace Exercise"
            case .addToWorkout: return "Add Exercise"
            case .pickMultiple: return "Add Exercises"
            }
        }
        
        var isSingleSelect: Bool {
            switch self {
            case .build, .pickMultiple: return false
            case .replace, .addToWorkout: return true
            }
        }
        
        var isPickMultiple: Bool {
            if case .pickMultiple = self { return true }
            return false
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
    init(currentExercises: [Exercise] = [], onAddExercise: @escaping (Exercise) -> Void) {
        self.mode = .addToWorkout(currentExercises, onAddExercise)
    }
    
    // Initializer for multi-select picker mode (e.g. send-to-friend). Pre-fills
    // `selectedExercises` from `initialSelection` and commits via the toolbar
    // "Done (N)" button by calling `onConfirm`.
    init(initialSelection: [Exercise], onConfirm: @escaping ([Exercise]) -> Void) {
        self.mode = .pickMultiple(initialSelection, onConfirm)
    }
    
    @State private var exercises: [Exercise] = []
    @State private var selectedExercises: [Exercise] = []
    @State private var searchText = ""
    @State private var selectedCategories: Set<String> = []
    @State private var selectedEquipmentItems: Set<String> = []
    @State private var selectedMuscleGroups: Set<String> = []
    @State private var selectedExerciseForDetail: Exercise?
    @State private var forceRenderID = UUID()
    // Build mode now defaults to Recommended (curated strength list, gender-
    // strict). Replace/Add modes overwrite this in `.onAppear` based on
    // context (replacingExercise / currentWorkoutExercises). Per user request
    // 2026-04-27.
    @State private var exerciseFilter: ExerciseFilterType = .recommended
    @State private var scrollOffset: CGFloat = 0
    @State private var showingAddExercise = false
    @State private var isLoadingExercises = false
    @State private var suggestedSwaps: [SwapSuggestion] = []
    // Shuffle: cached pages of 3 complementary suggestions each. `complementaryPageIndex`
    // is the currently displayed page; pressing the shuffle button advances to the next
    // page (wraps around). We pre-compute all pages once in `loadComplementarySuggestions`
    // so shuffling is instant and doesn't re-query `ExerciseSwapService` on every tap.
    @State private var complementaryPages: [[SwapSuggestion]] = []
    @State private var complementaryPageIndex: Int = 0
    
    // 🆕 Overdue muscle-group suggestions (build mode only — 2026-04-27).
    // Surfaces 3 strength exercises from whichever muscle bucket has gone
    // longest without training (e.g. user hasn't trained legs in a week →
    // 3 leg exercises). Hidden during search and after the user scrolls
    // past `overdueScrollHideThreshold` so the section never competes with
    // active browsing. Source: `WorkoutSuggestionEngine` recovery states ∩
    // `ExerciseLibraryFilterCache.preFilteredRecommended` (already strength
    // + curated-top-200) ∩ `GenderFilterService.shouldShowExerciseStrict`.
    @State private var overdueSuggestions: [Exercise] = []
    @State private var overdueMuscleLabel: String = ""
    @State private var hasComputedOverdueSuggestions = false
    private let overdueScrollHideThreshold: CGFloat = -60
    
    // `.pickMultiple` mode: track whether we've restored `initialSelection` on
    // first appear. Without this guard a tab-back / scenePhase wakeup could
    // re-overwrite the user's in-flight edits.
    @State private var hasRestoredPickMultipleSelection = false
    
    private var replacingExercise: Exercise? {
        if case .replace(let exercise, _) = mode { return exercise }
        return nil
    }
    
    private var currentWorkoutExercises: [Exercise] {
        if case .addToWorkout(let exercises, _) = mode { return exercises }
        return []
    }
    
    /// Only hide the complementary-suggestions block when we're in "Add to workout"
    /// mode (not replace-mode, where suggestions ARE the primary UI) AND the user
    /// is actively searching — either the keyboard is up or there's a non-empty query.
    private var shouldHideComplementsForSearch: Bool {
        guard replacingExercise == nil else { return false }
        return isSearchFocused || !searchText.isEmpty
    }
    
    /// Build-mode-only "Suggested: {muscle group} (overdue)" block visibility.
    /// Hidden when (a) we're not in build mode, (b) we don't have any
    /// suggestions to show yet (cold launch / no overdue group), (c) the
    /// user is actively searching, or (d) the user has scrolled past the
    /// hide threshold (so the section never competes with active list
    /// browsing). Both (c) and (d) auto-revert — clearing search OR scrolling
    /// back to the top brings the suggestions back, matching iOS norms.
    private var shouldShowOverdueSuggestions: Bool {
        guard case .build = mode else { return false }
        guard !overdueSuggestions.isEmpty else { return false }
        if isSearchFocused || !searchText.isEmpty { return false }
        if scrollOffset < overdueScrollHideThreshold { return false }
        return true
    }
    
    // ⚡️ SNAPPY SEARCH: Focus state for instant keyboard dismiss
    @FocusState private var isSearchFocused: Bool
    
    // ⚡️ PERFORMANCE: Cached filtered results to avoid recomputation
    @State private var cachedFilteredExercises: [Exercise] = []
    @State private var filterUpdateTask: Task<Void, Never>?
    
    enum ExerciseFilterType: String, CaseIterable {
        case recommended = "Recommended"
        case all = "All Exercises"
        case favorites = "Favorites"
        case custom = "Custom Added"
    }
    
    // Updated categories for 7000+ exercise library
    private let categories = ExerciseFilterService.allCategories
    private let allMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques", "Hip Flexors", "Adductors", "Rotator Cuff"]
    
    // Smart muscle groups based on selected categories (uses centralized service)
    private var muscleGroups: [String] {
        if selectedCategories.isEmpty { return [] }
        var allMuscles = Set<String>()
        for category in selectedCategories {
            let muscles = ExerciseFilterService.muscleGroupsForCategory(category)
            allMuscles.formUnion(muscles.filter { $0 != "All" })
        }
        return Array(allMuscles).sorted()
    }
    
    // Updated equipment for 7000+ exercise library
    private let equipmentTypes = ExerciseFilterService.allEquipment
    
    private var filterIcon: String {
        switch exerciseFilter {
        case .recommended:
            return "line.3.horizontal.decrease.circle"
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
        case .recommended:
            return .orange
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
        let categoryKey = selectedCategories.isEmpty ? "All" : selectedCategories.sorted().joined(separator: ",")
        let equipmentKey = selectedEquipmentItems.isEmpty ? "All" : selectedEquipmentItems.sorted().joined(separator: ",")
        let muscleKey = selectedMuscleGroups.isEmpty ? "All" : selectedMuscleGroups.sorted().joined(separator: ",")
        let filterKey = "\(exerciseFilter.rawValue)|\(categoryKey)|\(equipmentKey)|\(muscleKey)"
        
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchCache.removeAll()
            preFilteredExercises = applyFiltersOnly(to: exercises)
            #if DEBUG
            AppLogger.debug("🔧 [FILTER] Rebuilt cache: \(preFilteredExercises.count) exercises", category: .workout)
            // Check for bench/incline/decline exercises
            let benchExercises = preFilteredExercises.filter { ($0.name?.lowercased() ?? "").contains("bench") }
            let declineExercises = preFilteredExercises.filter { ($0.name?.lowercased() ?? "").contains("decline") }
            let inclineExercises = preFilteredExercises.filter { ($0.name?.lowercased() ?? "").contains("incline") }
            AppLogger.debug("🔧 [FILTER] bench exercises: \(benchExercises.count), decline: \(declineExercises.count), incline: \(inclineExercises.count)", category: .workout)
            if let first = benchExercises.first { AppLogger.debug("🔧 [FILTER] Sample bench: '\(first.name ?? "nil")'", category: .workout) }
            #endif
        }
    }
    
    private func computeSearchResults() {
        if !searchText.isEmpty {
            let searchKey = searchText.lowercased()
            #if DEBUG
            AppLogger.debug("🔍 [CACHE] Search key: '\(searchKey)', preFilteredExercises.count: \(preFilteredExercises.count)", category: .workout)
            #endif
            if let cached = searchCache[searchKey] {
                #if DEBUG
                AppLogger.debug("🔍 [CACHE] HIT - returning \(cached.count) cached results", category: .workout)
                #endif
                cachedFilteredExercises = cached
                return
            }
            #if DEBUG
            AppLogger.debug("🔍 [CACHE] MISS - computing fresh results", category: .workout)
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
        AppLogger.debug("🔍 [SEARCH] Query: '\(query)', Words: \(queryWords), isMultiWord: \(isMultiWord)", category: .workout)
        AppLogger.debug("🔍 [SEARCH] correctedQuery: '\(correctedQuery)', searching \(exercises.count) exercises", category: .workout)
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
        AppLogger.debug("🔍 [SEARCH] Results: exact=\(exactMatches.count), startsWithPhrase=\(startsWithPhraseMatches.count), containsPhrase=\(containsPhraseMatches.count), allWords=\(allWordsMatches.count), TOTAL=\(totalResults)", category: .workout)
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
        case .recommended:
            if let replacing = replacingExercise {
                let targetCategory = replacing.category?.lowercased()
                let targetEquipment = replacing.equipment?.lowercased()
                filtered = filtered.filter { exercise in
                    let matchesCategory = exercise.category?.lowercased() == targetCategory
                    let matchesEquipment = targetEquipment == nil || exercise.equipment?.lowercased() == targetEquipment
                    return matchesCategory || matchesEquipment
                }
            } else if !currentWorkoutExercises.isEmpty {
                let workoutCategories = Set(currentWorkoutExercises.compactMap { $0.category?.lowercased() })
                let workoutEquipment = Set(currentWorkoutExercises.compactMap { $0.equipment?.lowercased() })
                let workoutIds = Set(currentWorkoutExercises.compactMap { $0.id })
                filtered = filtered.filter { exercise in
                    if let eid = exercise.id, workoutIds.contains(eid) { return false }
                    let matchesCategory = workoutCategories.contains(exercise.category?.lowercased() ?? "")
                    let matchesEquipment = workoutEquipment.contains(exercise.equipment?.lowercased() ?? "")
                    return matchesCategory || matchesEquipment
                }
            } else {
                // Build mode (no replace target / no in-progress workout) —
                // mirror Exercise Library's Recommended definition: curated
                // top-200 list ∩ strength ∩ strict-gender. Per user request
                // 2026-04-27 ("recommended only shows strength specific to
                // their gender — same with custom workout builder view, and
                // don't fall back to opposite gender even if there's no
                // match").
                let recommendedNames = ExerciseLibraryFilterCache.shared.recommendedExerciseNames
                let genderSvc = GenderFilterService.shared
                filtered = filtered.filter { exercise in
                    guard let rawName = exercise.name else { return false }
                    let fullName = rawName.lowercased()
                    let inCurated = recommendedNames.contains { rec in
                        fullName == rec ||
                        fullName.hasPrefix(rec + " ") ||
                        fullName.hasPrefix(rec + "(")
                    }
                    guard inCurated else { return false }
                    let isStrength: Bool = {
                        if let wt = exercise.workoutType, !wt.isEmpty {
                            return wt.lowercased() == "strength"
                        }
                        let smart = ExerciseFilterService.classifyExerciseType(
                            name: exercise.name, category: exercise.category, equipment: exercise.equipment
                        )
                        return smart == .strength
                    }()
                    guard isStrength else { return false }
                    return genderSvc.shouldShowExerciseStrict(rawName)
                }
            }
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .custom:
            filtered = filtered.filter { $0.instructions?.contains("[CUSTOM_EXERCISE") ?? false }
        case .all:
            break
        }
        
        if !selectedCategories.isEmpty {
            let categoriesLower = Set(selectedCategories.map { $0.lowercased() })
            filtered = filtered.filter { exercise in
                let exerciseCategory = (exercise.category ?? "").lowercased()
                return categoriesLower.contains(exerciseCategory) || categoriesLower.contains(where: { exerciseCategory.contains($0) })
            }
        }
        
        if !selectedEquipmentItems.isEmpty {
            filtered = filtered.filter { exercise in
                selectedEquipmentItems.contains { equipment in
                    exerciseMatchesEquipment(exercise, selectedEquipment: equipment)
                }
            }
        }
        
        if !selectedMuscleGroups.isEmpty {
            filtered = filtered.filter { exercise in
                selectedMuscleGroups.contains { muscleGroup in
                    ExerciseFilterService.isExerciseForMuscleGroup(exercise, muscleGroup: muscleGroup)
                }
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
                    // Replace mode header with current exercise info
                    if let replacing = replacingExercise {
                        replaceHeaderView(exercise: replacing)
                    }
                    
                    compactFiltersView
                    
                    // "X selected" counter — relocated out of the filter header row
                    // (which was cramping the "All Exercises" dropdown) onto its
                    // own right-aligned row just above the scrolling list.
                    if !mode.isSingleSelect && !selectedExercises.isEmpty {
                        HStack {
                            Spacer()
                            selectedCountPill
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.xs)
                    }
                    
                    // Scrollable exercise list. The "Add to Workout" path on
                    // ExerciseDetailView pre-selects the exercise but intentionally
                    // does NOT scroll — the list stays at the top so the user
                    // sees the fresh alphabetical list with their selection applied.
                    ScrollView {
                        GeometryReader { geometry in
                            Color.clear.preference(key: CustomWorkoutScrollOffsetKey.self, value: geometry.frame(in: .named("scroll")).minY)
                        }
                        .frame(height: 0)
                        
                        // 🆕 Build-mode "Suggested: {muscle bucket} (overdue)" block
                        // — shows 3 strength exercises from whichever bucket has
                        // gone longest without training. Mutually exclusive with
                        // `suggestedReplacementsSection` (that one is replace /
                        // add-to-workout only); they never both render.
                        if shouldShowOverdueSuggestions {
                            overdueSuggestionsSection
                        }
                        
                        // Hide the "Complements Your Workout" block while the user is
                        // actively searching — the keyboard + dropdown was covering the
                        // intentional search results. Replace-mode suggestions stay
                        // visible because they ARE the primary UI in that flow.
                        if !suggestedSwaps.isEmpty && !shouldHideComplementsForSearch {
                            suggestedReplacementsSection
                        }
                        
                        if isLoadingExercises || !exerciseLibrary.isExercisesReady {
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
                                    .padding(.horizontal, Spacing.md)
                                    .id(exercise.objectID)
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
                    
                    if mode.isSingleSelect {
                        selectedCategories.removeAll()
                        selectedEquipmentItems.removeAll()
                        selectedMuscleGroups.removeAll()
                        searchText = ""
                        if replacingExercise != nil || !currentWorkoutExercises.isEmpty {
                            exerciseFilter = .recommended
                        }
                    }
                    
                    // `.pickMultiple`: restore the caller's `initialSelection`
                    // exactly once so a tab-back / scenePhase wakeup doesn't
                    // trample in-flight edits.
                    if case let .pickMultiple(initialSelection, _) = mode,
                       !hasRestoredPickMultipleSelection {
                        selectedExercises = initialSelection
                        hasRestoredPickMultipleSelection = true
                    }
                    
                    // Load exercises from cache/Core Data (cloud sync handles population)
                    loadExercises()
                    // ⚡️ Initialize cached results and filter cache immediately
                    lastFilterKey = "" // Force rebuild
                    updateFilteredExercises()
                    forceRenderID = UUID()
                    // `.pickMultiple` is rented out to social/share flows; it
                    // must NOT touch workoutManager state (those flags are
                    // reserved for the actual workout-tab build flow).
                    if !mode.isPickMultiple {
                        workoutManager.isOnCustomWorkoutBuilder = true
                    }
                    
                    // Load suggested swaps for replace mode
                    if let replacing = replacingExercise {
                        loadSuggestedSwaps(for: replacing)
                    }
                    
                    if !currentWorkoutExercises.isEmpty {
                        loadComplementarySuggestions(for: currentWorkoutExercises)
                    }
                    
                    // 🆕 Overdue muscle-group nudge (build mode only).
                    // `loadOverdueSuggestions` early-returns for non-build modes,
                    // so it's safe to call unconditionally — it also no-ops
                    // gracefully if the precomputed cache hasn't warmed yet
                    // (the .onChange below picks it up).
                    loadOverdueSuggestions()
                    
                    // Check for pre-selected exercise (from "Add to workout" button on ExerciseDetailView)
                    if let exerciseToAdd = workoutManager.exerciseToAddToCustomWorkout {
                        // Only add if not already selected
                        if !selectedExercises.contains(where: { $0.id == exerciseToAdd.id }) {
                            selectedExercises.append(exerciseToAdd)
                            AppLogger.info("✅ Pre-selected exercise: \(exerciseToAdd.name ?? "Unknown")", category: .workout)
                            
                            // Prefetch the video for this exercise
                            if let name = exerciseToAdd.name {
                                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
                            }
                        }
                        // Clear the pre-selected exercise. Intentionally NOT
                        // auto-scrolling to the added row — the user should land
                        // at the top of the alphabetical list with the selection
                        // already applied (row will render with its checkmark when
                        // it scrolls into view).
                        workoutManager.exerciseToAddToCustomWorkout = nil
                    }
                    
                    if !mode.isPickMultiple {
                        workoutManager.selectedCustomWorkoutExercises = selectedExercises
                    }
                }
                .onDisappear {
                    if !mode.isPickMultiple {
                        workoutManager.isOnCustomWorkoutBuilder = false
                        workoutManager.selectedCustomWorkoutExercises = []
                        workoutManager.shouldNavigateToCustomWorkoutBuilder = false
                    }
                }
                // 🔄 Reload when exercises become ready after sync
                .onChange(of: exerciseLibrary.isExercisesReady) { _, isReady in
                    if isReady && exercises.isEmpty {
                        AppLogger.info("✅ Exercises now ready - reloading list", category: .workout)
                        loadExercises()
                        lastFilterKey = "" // Force rebuild filters
                        updateFilteredExercises()
                        forceRenderID = UUID()
                    }
                    // Also kick off / refresh the overdue nudge once the
                    // library is hydrated — `loadOverdueSuggestions` needs
                    // `ExerciseLibraryFilterCache.preFilteredRecommended` to
                    // be non-empty, which only happens after the cache warms.
                    if isReady && !hasComputedOverdueSuggestions {
                        loadOverdueSuggestions()
                    }
                }
                // 🔄 Recompute when the precomputed recommended cache warms
                // up after `onAppear` (cold-start race — happens on the
                // user's first cold-launch into the builder). `filterCache`
                // is an `@ObservedObject` (declared at the top of this
                // view), so the body re-evaluates when its `@Published`
                // `preFilteredRecommended` flips from `[]` to populated and
                // this `.onChange` fires.
                .onChange(of: filterCache.preFilteredRecommended.count) { oldValue, newValue in
                    guard newValue > oldValue else { return }
                    // Always re-run on count grow — covers (a) cold-start
                    // 0→N transition, (b) admin-add live revision bumps,
                    // and (c) the rare resort that might shuffle the pool
                    // and change which 3 are top-of-bucket.
                    loadOverdueSuggestions()
                }
                // ⚡️ HIGH-PERFORMANCE: Instant filter updates
                .onChange(of: searchText) { _, _ in updateFilteredExercises() }
                .onChange(of: selectedCategories) { _, _ in 
                    lastFilterKey = ""
                    updateFilteredExercises() 
                }
                .onChange(of: selectedEquipmentItems) { _, _ in 
                    lastFilterKey = ""
                    updateFilteredExercises() 
                }
                .onChange(of: selectedMuscleGroups) { _, _ in 
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
                // 👤 Re-filter on gender preference flip (Settings -> Profile).
                // The build-mode Recommended path uses
                // `shouldShowExerciseStrict`, which depends on
                // `preferredGender`, so we MUST invalidate the filter cache.
                // The overdue strip uses the SAME strict filter, so refresh
                // that too — otherwise it'd keep showing exercises with
                // only the opposite-gender video.
                .onReceive(NotificationCenter.default.publisher(for: .genderPreferenceChanged)) { _ in
                    lastFilterKey = ""
                    searchCache.removeAll()
                    updateFilteredExercises()
                    if !overdueMuscleLabel.isEmpty,
                       let bucket = OverdueBucket.fromLabel(overdueMuscleLabel) {
                        applyOverdueBucket(bucket)
                    }
                    forceRenderID = UUID()
                }
                .onChange(of: selectedExercises) { _, newValue in
                    if !mode.isPickMultiple {
                        workoutManager.selectedCustomWorkoutExercises = newValue
                    }
                    // Refresh the overdue strip so a row the user just
                    // selected drops out and the next candidate slides in.
                    // No network / Core Data work — `applyOverdueBucket`
                    // re-filters the in-memory pool synchronously.
                    if !overdueMuscleLabel.isEmpty,
                       let bucket = OverdueBucket.fromLabel(overdueMuscleLabel) {
                        applyOverdueBucket(bucket)
                    }
                }
                .onChange(of: workoutManager.shouldStartCustomWorkout) { _, shouldStart in
                    // `.pickMultiple` is rented out to social flows; never
                    // hijack it into the workout-tab "start workout" path.
                    guard !mode.isPickMultiple else { return }
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
            
            // Banner ad overlay - floats on top, scroll content has space reserved
            if !PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled {
                VStack {
                    Spacer().frame(height: 160) // Position below filters
                    BannerAdView()
                        .padding(.horizontal, Spacing.md)
                    Spacer()
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode.isSingleSelect {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.selectionChanged()
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                // `.pickMultiple` (send-to-friend) commits via "Done (N)";
                // `.build` shows the "+" custom-exercise affordance; single-
                // select modes (`.replace` / `.addToWorkout`) show nothing.
                if case let .pickMultiple(_, onConfirm) = mode {
                    Button(action: {
                        HapticManager.impact(.medium)
                        onConfirm(selectedExercises)
                        dismiss()
                    }) {
                        Text(selectedExercises.isEmpty ? "Done" : "Done (\(selectedExercises.count))")
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Done")
                    .accessibilityHint("Confirm the selected exercises and return")
                } else if !mode.isSingleSelect {
                    Button(action: {
                        HapticManager.impact(.medium)
                        showingAddExercise = true
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Add custom exercise")
                }
            }
        }
        .onChange(of: selectedExercises.count) { count in
            // Only show GO button in build mode
            guard case .build = mode else { return }
            
            if count > 0 {
                GoButtonState.shared.show(
                    primaryColor: .blue,
                    secondaryColor: Color(red: 0.3, green: 0.5, blue: 0.9),
                    accessibilityText: "Start workout with \(count) exercise\(count == 1 ? "" : "s")"
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
    
    
    
    /// Small "N selected" pill shown on its own right-aligned row between
    /// the filter card and the exercise list. Extracted from the filter
    /// header row (where it was crowding the "All Exercises" dropdown)
    /// so both elements have breathing room.
    private var selectedCountPill: some View {
        HStack(spacing: 5) {
            Text("\(selectedExercises.count)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("selected")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.cyan]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(selectedExercises.count) exercise\(selectedExercises.count == 1 ? "" : "s") selected")
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
                                .font(.ds_labelMedium)
                            Text(exerciseFilter.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.ds_caption).fontWeight(.semibold)
                        }
                        .foregroundColor(
                            exerciseFilter == .recommended ? .blue
                            : exerciseFilter != .all ? .white
                            : .secondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    exerciseFilter == .recommended ? Color.clear
                                    : exerciseFilter != .all ? filterColor
                                    : Color(.systemGray5)
                                )
                        )
                        .overlay(
                            exerciseFilter == .recommended
                            ? Capsule().stroke(Color.blue, lineWidth: 1.5)
                            : nil
                        )
                    }
                    
                }
                
                // ⚡️ SNAPPY SEARCH: Instant response search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.ds_bodySmall).fontWeight(.medium)
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
                                .font(.ds_bodySmall)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color(.systemGray6))
                )
            }
            
            // Multi-select filter categories (matches Exercise Library)
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
                            ForEach(categories.filter { $0 != "All" }, id: \.self) { category in
                                CompactFilterChip(
                                    text: category,
                                    isSelected: selectedCategories.contains(category),
                                    onTap: {
                                        if selectedCategories.contains(category) {
                                            selectedCategories.remove(category)
                                        } else {
                                            selectedCategories.insert(category)
                                        }
                                        selectedMuscleGroups.removeAll()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                
                // Muscle Groups row (only if categories selected)
                if !selectedCategories.isEmpty && !muscleGroups.isEmpty {
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
                                        isSelected: selectedMuscleGroups.contains(muscle),
                                        color: .green,
                                        onTap: {
                                            if selectedMuscleGroups.contains(muscle) {
                                                selectedMuscleGroups.remove(muscle)
                                            } else {
                                                selectedMuscleGroups.insert(muscle)
                                            }
                                        }
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
                            ForEach(equipmentTypes.filter { $0 != "All" }, id: \.self) { equipment in
                                CompactFilterChip(
                                    text: equipment,
                                    isSelected: selectedEquipmentItems.contains(equipment),
                                    color: .orange,
                                    onTap: {
                                        if selectedEquipmentItems.contains(equipment) {
                                            selectedEquipmentItems.remove(equipment)
                                        } else {
                                            selectedEquipmentItems.insert(equipment)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, 4)
        .zIndex(10)
    }
    
    // MARK: - Replace Mode Views
    
    private func replaceHeaderView(exercise: Exercise) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.ds_bodySmall)
                .foregroundColor(.blue)
            Text("Swapping:")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text(exercise.name ?? "Exercise")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Spacing.md + Spacing.md)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
    
    /// "Suggested based on workout history" strip — surfaced only in build
    /// mode and seeded from `WorkoutSuggestionEngine` recovery state. The
    /// muscle group is intentionally NOT spelled out in the header
    /// (per user request 2026-04-27) — the 3 exercises themselves reveal
    /// the focus through their category badges. `overdueMuscleLabel`
    /// lives on so we can still update the strip on bucket changes (and
    /// VoiceOver gets the explicit muscle context).
    private var overdueSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.ds_bodySmall)
                    .foregroundColor(.orange)
                Text("Suggested based on workout history")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer(minLength: Spacing.xs)
            }
            .padding(.horizontal, Spacing.md)
            
            ForEach(overdueSuggestions, id: \.objectID) { exercise in
                SuggestedSwapRowWithNav(
                    exercise: exercise,
                    isSelected: selectedExercises.contains(where: { $0.id == exercise.id }),
                    onToggle: {
                        HapticManager.impact(.medium)
                        toggleExerciseSelection(exercise)
                    }
                )
                .padding(.horizontal, Spacing.md)
            }
            
            Divider()
                .foregroundColor(.gray.opacity(0.3))
                .padding(.horizontal, Spacing.md)
                .padding(.top, 4)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested based on workout history — \(overdueMuscleLabel)")
    }
    
    private var suggestedReplacementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.ds_bodySmall)
                    .foregroundColor(.orange)
                Text(replacingExercise != nil ? "Suggested Replacements" : "Complements Your Workout")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer(minLength: Spacing.xs)
                // Shuffle only applies to the "Complements Your Workout" surface, and
                // only when we actually have more than one page of candidates to cycle.
                if replacingExercise == nil && complementaryPages.count > 1 {
                    Button(action: shuffleComplementarySuggestions) {
                        HStack(spacing: 4) {
                            Image(systemName: "shuffle")
                                .font(.ds_labelMedium)
                            Text("Shuffle")
                                .font(.ds_labelMedium)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.12))
                        )
                    }
                    .scaleButtonStyle(.subtle)
                    .accessibilityLabel("Shuffle recommended complementary exercises")
                    .accessibilityHint("Shows a different set of three suggestions")
                }
            }
            .padding(.horizontal, Spacing.md)
            
            ForEach(suggestedSwaps) { suggestion in
                SuggestedSwapRowWithNav(
                    exercise: suggestion.exercise,
                    isSelected: selectedExercises.contains(where: { $0.id == suggestion.exercise.id }),
                    onToggle: {
                        HapticManager.impact(.medium)
                        toggleExerciseSelection(suggestion.exercise)
                    }
                )
                .padding(.horizontal, Spacing.md)
            }
            
            Divider()
                .foregroundColor(.gray.opacity(0.3))
                .padding(.horizontal, Spacing.md)
                .padding(.top, 4)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    private func swapTypeColor(_ type: SwapSuggestion.SwapType) -> Color {
        switch type {
        case .equipmentVariant: return .blue
        case .complementary: return .purple
        case .similar: return .gray
        }
    }
    
    private func loadSuggestedSwaps(for exercise: Exercise) {
        let sections = ExerciseSwapService.shared.getSwapSuggestions(for: exercise)
        var swaps: [SwapSuggestion] = []
        
        // Collect up to 2 equipment variants
        if let variants = sections.first(where: { $0.suggestions.first?.swapType == .equipmentVariant }) {
            swaps.append(contentsOf: variants.suggestions.prefix(2))
        }
        
        // Collect 1 complementary or alternative
        if let complementary = sections.first(where: { $0.suggestions.first?.swapType == .complementary }) {
            swaps.append(contentsOf: complementary.suggestions.prefix(1))
        } else if let fallback = sections.first(where: { $0.suggestions.first?.swapType == .similar }) {
            swaps.append(contentsOf: fallback.suggestions.prefix(1))
        }
        
        // If we still need more to reach 3, fill from any section
        if swaps.count < 3 {
            let existing = Set(swaps.map { $0.id })
            for section in sections {
                for suggestion in section.suggestions {
                    if !existing.contains(suggestion.id) && swaps.count < 3 {
                        swaps.append(suggestion)
                    }
                }
            }
        }
        
        suggestedSwaps = swaps
    }
    
    private func loadComplementarySuggestions(for workoutExercises: [Exercise]) {
        let workoutIds = Set(workoutExercises.compactMap { $0.id })
        let desiredPageCount = 3
        let pageSize = 3
        let maxCandidates = desiredPageCount * pageSize // 9
        var candidates: [SwapSuggestion] = []
        var seenIds = Set<UUID>()
        
        // Pass 1: prioritize truly complementary pairings across all current exercises.
        for exercise in workoutExercises {
            let sections = ExerciseSwapService.shared.getSwapSuggestions(
                for: exercise,
                excludeIds: workoutIds
            )
            for section in sections {
                for suggestion in section.suggestions where suggestion.swapType == .complementary {
                    guard let id = suggestion.exercise.id,
                          !seenIds.contains(id),
                          !workoutIds.contains(id) else { continue }
                    seenIds.insert(id)
                    candidates.append(suggestion)
                    if candidates.count >= maxCandidates { break }
                }
                if candidates.count >= maxCandidates { break }
            }
            if candidates.count >= maxCandidates { break }
        }
        
        // Pass 2: backfill with any remaining suggestions (similar / variants) so we can
        // still offer multiple shuffle pages even when complementary pairings are sparse.
        if candidates.count < maxCandidates {
            for exercise in workoutExercises {
                let sections = ExerciseSwapService.shared.getSwapSuggestions(
                    for: exercise,
                    excludeIds: workoutIds
                )
                for section in sections {
                    for suggestion in section.suggestions {
                        guard let id = suggestion.exercise.id,
                              !seenIds.contains(id),
                              !workoutIds.contains(id) else { continue }
                        seenIds.insert(id)
                        candidates.append(suggestion)
                        if candidates.count >= maxCandidates { break }
                    }
                    if candidates.count >= maxCandidates { break }
                }
                if candidates.count >= maxCandidates { break }
            }
        }
        
        // Partition into pages of `pageSize`. Short trailing pages are kept so even a
        // partial page is reachable via shuffle; if we end up with <=1 page the shuffle
        // button will hide itself.
        var pages: [[SwapSuggestion]] = []
        var index = 0
        while index < candidates.count {
            let end = min(index + pageSize, candidates.count)
            pages.append(Array(candidates[index..<end]))
            index = end
        }
        
        complementaryPages = pages
        complementaryPageIndex = 0
        suggestedSwaps = pages.first ?? []
    }
    
    /// Advance to the next page of complementary suggestions. Wraps back to page 0
    /// after the last page so the user can keep cycling through recommendations.
    private func shuffleComplementarySuggestions() {
        guard complementaryPages.count > 1 else { return }
        HapticManager.selectionChanged()
        complementaryPageIndex = (complementaryPageIndex + 1) % complementaryPages.count
        suggestedSwaps = complementaryPages[complementaryPageIndex]
    }
    
    // MARK: - Overdue Muscle-Group Suggestions
    
    /// What the user thinks of as a "training day". Spans three resolution
    /// levels:
    ///   - SINGLE muscle ("Chest", "Triceps", "Legs", "Core")
    ///   - PAIR (the bro-split classics: Chest & Triceps, Back & Biceps,
    ///     Shoulders & Biceps, Shoulders & Triceps)
    ///   - FULL SPLIT (Push, Pull, Leg Day, Upper Body)
    ///
    /// `detectBucket` walks the resolution from coarse → fine: if 2+ leg
    /// muscles are overdue → "Leg Day"; if all 3 push muscles are overdue
    /// → "Push Day"; if exactly the canonical pair is overdue → use the
    /// pair label; else fall back to the most-overdue single muscle.
    /// Per user request 2026-04-27 ("Suggestions: Shoulder & Bicep, Chest
    /// & Tri, leg day, push pull, etc").
    private enum OverdueBucket {
        // Singles
        case chest, back, shoulders, biceps, triceps, legs, core
        // Bro-split pairs (push variants on top, pull on bottom)
        case chestTriceps, shouldersBiceps, shouldersTriceps, backBiceps
        // Full splits
        case push, pull, upperBody
        
        var label: String {
            switch self {
            case .chest: return "Chest"
            case .back: return "Back"
            case .shoulders: return "Shoulders"
            case .biceps: return "Biceps"
            case .triceps: return "Triceps"
            case .legs: return "Leg Day"
            case .core: return "Core"
            case .chestTriceps: return "Chest & Triceps"
            case .shouldersBiceps: return "Shoulders & Biceps"
            case .shouldersTriceps: return "Shoulders & Triceps"
            case .backBiceps: return "Back & Biceps"
            case .push: return "Push Day"
            case .pull: return "Pull Day"
            case .upperBody: return "Upper Body"
            }
        }
        
        /// Reverse `label` → bucket. Used by `selectedExercises` and gender
        /// change handlers to refresh the strip without re-querying recovery
        /// state.
        static func fromLabel(_ label: String) -> OverdueBucket? {
            for c in Self.allCases where c.label == label { return c }
            return nil
        }
        
        static var allCases: [OverdueBucket] {
            [.chest, .back, .shoulders, .biceps, .triceps, .legs, .core,
             .chestTriceps, .shouldersBiceps, .shouldersTriceps, .backBiceps,
             .push, .pull, .upperBody]
        }
        
        /// Lowercase `Exercise.category` strings that pre-filter the pool.
        /// Bicep / tricep work lives under "arms" in the seed data, so any
        /// arm-touching bucket includes "arms" here. Final muscle-specific
        /// disambiguation happens via `muscleSlots` + `matchesMuscleStrict`.
        var categoryAliases: Set<String> {
            switch self {
            case .chest: return ["chest"]
            case .back: return ["back"]
            case .shoulders: return ["shoulders"]
            case .biceps, .triceps: return ["arms"]
            case .core: return ["core"]
            case .legs: return ["legs", "hips"]
            case .chestTriceps: return ["chest", "arms"]
            case .shouldersBiceps, .shouldersTriceps: return ["shoulders", "arms"]
            case .backBiceps: return ["back", "arms"]
            case .push: return ["chest", "shoulders", "arms"]
            case .pull: return ["back", "arms"]
            case .upperBody: return ["chest", "back", "shoulders", "arms"]
            }
        }
        
        /// 3 muscle slots — one exercise picked per slot, in order. This is
        /// what gives the strip variety: a "Push Day" bucket fills slots
        /// `[Chest, Shoulders, Triceps]` so the user sees one exercise from
        /// each muscle, not 3 chest exercises in a row.
        ///
        /// Single-muscle buckets just repeat the same slot 3 times (the
        /// movement-base-name dedup elsewhere ensures the 3 picks are
        /// distinct movements, not equipment variants).
        var muscleSlots: [String] {
            switch self {
            case .chest: return ["Chest", "Chest", "Chest"]
            case .back: return ["Back", "Back", "Back"]
            case .shoulders: return ["Shoulders", "Shoulders", "Shoulders"]
            case .biceps: return ["Biceps", "Biceps", "Biceps"]
            case .triceps: return ["Triceps", "Triceps", "Triceps"]
            case .core: return ["Abs", "Obliques", "Abs"]
            case .legs: return ["Quads", "Hamstrings", "Glutes"]
            case .chestTriceps: return ["Chest", "Triceps", "Chest"]
            case .shouldersBiceps: return ["Shoulders", "Biceps", "Shoulders"]
            case .shouldersTriceps: return ["Shoulders", "Triceps", "Shoulders"]
            case .backBiceps: return ["Back", "Biceps", "Back"]
            case .push: return ["Chest", "Shoulders", "Triceps"]
            case .pull: return ["Back", "Biceps", "Back"]
            case .upperBody: return ["Chest", "Back", "Shoulders"]
            }
        }
    }
    
    /// Walk overdue muscle categories from coarse-grained to fine-grained
    /// and pick the broadest label that fits. This is what produces
    /// "Push Day" vs "Chest & Triceps" vs "Chest" depending on how much
    /// of the user's split has gone stale.
    ///
    /// Threshold: any muscle with `hoursElapsed >= 60h` (~2.5 days) counts
    /// as "in the overdue set" for split detection. Lower than the
    /// single-muscle threshold so a 3-day-skipped chest + 3-day-skipped
    /// triceps trigger "Chest & Triceps" instead of degrading to just one.
    private static func detectBucket(from strengthStates: [WorkoutSuggestionEngine.MuscleRecoveryState]) -> OverdueBucket {
        let trained = strengthStates.filter { $0.lastTrainedDate != nil }
        guard !trained.isEmpty else { return .legs } // brand-new user
        
        let overdueThresholdHours = 60
        let overdue = Set(trained.filter { $0.hoursElapsed >= overdueThresholdHours }.map { $0.category })
        let mostOverdue = trained.max(by: { $0.hoursElapsed < $1.hoursElapsed })?.category
        
        // === FULL SPLIT TIER ===
        let pushCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [.chest, .shoulders, .triceps]
        let pullCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [.back, .biceps]
        let legCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [.quads, .hamstrings, .glutes, .calves]
        let upperCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [.chest, .back, .shoulders, .biceps, .triceps]
        
        if overdue.intersection(legCats).count >= 2 { return .legs }
        if overdue.intersection(pushCats).count >= 3 { return .push }
        if overdue.intersection(upperCats).count >= 4 { return .upperBody }
        
        // === PAIR TIER (only fires if pair is genuinely overdue together) ===
        if overdue.contains(.chest) && overdue.contains(.triceps) { return .chestTriceps }
        if overdue.contains(.back) && overdue.contains(.biceps) { return .backBiceps }
        if overdue.contains(.shoulders) && overdue.contains(.biceps) { return .shouldersBiceps }
        if overdue.contains(.shoulders) && overdue.contains(.triceps) { return .shouldersTriceps }
        if overdue.intersection(pullCats).count >= 2 { return .pull }
        // Two of {chest, shoulders, triceps} that didn't hit the pair
        // labels above (only chest+shoulders qualifies) → call it Push.
        if overdue.intersection(pushCats).count >= 2 { return .push }
        // Single leg muscle still triggers Leg Day — quads-only is enough.
        if overdue.intersection(legCats).count >= 1 { return .legs }
        
        // === SINGLE TIER (fallback — use whatever is most-overdue) ===
        guard let cat = mostOverdue else { return .legs }
        switch cat {
        case .chest: return .chest
        case .back: return .back
        case .shoulders: return .shoulders
        case .biceps: return .biceps
        case .triceps: return .triceps
        case .quads, .hamstrings, .glutes, .calves: return .legs
        case .core: return .core
        case .cardio: return .legs // never reached — cardio pre-filtered out
        }
    }
    
    /// Compute the overdue suggestion block. Picks the most-overdue strength
    /// muscle bucket (≥4 days untrained) and shows up to 3 curated /
    /// strength / gender-strict exercises that hit it.
    ///
    /// Build-mode only — replace / add-to-workout flows already have their
    /// own contextual surface (`suggestedReplacementsSection`).
    ///
    /// Source pipeline:
    ///   `WorkoutSuggestionEngine.getMuscleRecoveryStatesAsync()` (off-main
    ///   bgContext) → choose top-overdue category with `hoursElapsed ≥ 96`
    ///   → map to `OverdueBucket` → filter the precomputed
    ///   `ExerciseLibraryFilterCache.preFilteredRecommended` (already
    ///   strength + curated-top-200) by category/muscle alias →
    ///   `GenderFilterService.shouldShowExerciseStrict` → drop anything the
    ///   user has already selected → take 3.
    ///
    /// If the user has no training history yet (brand-new account), we
    /// surface "Legs" as a sensible default — it's the most commonly
    /// skipped split and a great anchor for first-workout selection.
    private func loadOverdueSuggestions() {
        guard case .build = mode else { return }
        
        Task {
            let states = await WorkoutSuggestionEngine.shared.getMuscleRecoveryStatesAsync()
            
            // Strength categories only — never surface "go do another HIIT
            // sprint" here because that's not what Custom Workout Builder
            // is for (cardio has its own dedicated entry point).
            let strengthCats: Set<WorkoutSuggestionEngine.MuscleCategory> = [
                .chest, .back, .shoulders, .biceps, .triceps,
                .quads, .hamstrings, .glutes, .calves, .core
            ]
            let strengthStates = states.filter { strengthCats.contains($0.category) }
            
            let bucket = Self.detectBucket(from: strengthStates)
            
            #if DEBUG
            let topThree = strengthStates
                .filter { $0.lastTrainedDate != nil }
                .sorted { $0.hoursElapsed > $1.hoursElapsed }
                .prefix(3)
                .map { "\($0.category.rawValue):\($0.hoursElapsed)h" }
                .joined(separator: ", ")
            AppLogger.debug("🏋️ [Overdue] Top overdue: [\(topThree)] → bucket: \(bucket.label)", category: .workout)
            #endif
            
            await MainActor.run {
                applyOverdueBucket(bucket)
                hasComputedOverdueSuggestions = true
            }
        }
    }
    
    /// Resolves a bucket to 3 concrete exercises using a slot-based spread
    /// strategy. Each `bucket.muscleSlots` entry gets one pick — for
    /// "Push Day" that means [Chest pick, Shoulders pick, Triceps pick]
    /// so the user sees ONE exercise per muscle, not three chest
    /// exercises in a row.
    ///
    /// Pool fallback ladder: precomputed Recommended cache (already
    /// strength + curated) → curated-name match against the loaded
    /// `exercises` array (warm but no popularity sort). Each tier applies
    /// the same strict filters: category match, gender-strict, drop
    /// already-selected, movement-base-name dedup so we don't show two
    /// flavors of the same lift (e.g. "21s Bicep Curl (Dumbbell)" + "21s
    /// Bicep Curl (EZ Bar)"), and per-slot muscle disambiguation via
    /// `matchesMuscleStrict` so "Triceps" actually means triceps and not
    /// every exercise with "extension" in its name (Back Extension / Leg
    /// Extension bug, 2026-04-27).
    ///
    /// Re-run cheaply on selection changes — picking suggestion #1 drops
    /// it from the row and the next pool entry slides in.
    private func applyOverdueBucket(_ bucket: OverdueBucket) {
        let pool: [Exercise]
        let cachedPool = filterCache.preFilteredRecommended
        if !cachedPool.isEmpty {
            pool = cachedPool
        } else {
            // Cache cold — derive an inline pool from the loaded library
            // so the strip still renders on the user's first cold launch
            // into Build Workout. Curated-name match keeps quality high.
            let recommendedNames = ExerciseLibraryFilterCache.shared.recommendedExerciseNames
            pool = exercises.filter { exercise in
                guard let raw = exercise.name?.lowercased() else { return false }
                let inCurated = recommendedNames.contains { rec in
                    raw == rec || raw.hasPrefix(rec + " ") || raw.hasPrefix(rec + "(")
                }
                guard inCurated else { return false }
                if let wt = exercise.workoutType, !wt.isEmpty {
                    return wt.lowercased() == "strength"
                }
                let smart = ExerciseFilterService.classifyExerciseType(
                    name: exercise.name, category: exercise.category, equipment: exercise.equipment
                )
                return smart == .strength
            }
            #if DEBUG
            AppLogger.debug("🏋️ [Overdue] Cache cold — inline pool: \(pool.count) exercises", category: .workout)
            #endif
        }
        
        let categoryAliases = bucket.categoryAliases
        let svc = GenderFilterService.shared
        let selectedIds = Set(selectedExercises.compactMap { $0.id })
        
        // Pre-filter the pool down to the bucket's category set so the
        // per-slot muscle pass only runs over relevant rows.
        let bucketPool = pool.filter { exercise in
            if let eid = exercise.id, selectedIds.contains(eid) { return false }
            let exCategory = (exercise.category ?? "").lowercased()
            guard categoryAliases.contains(exCategory) else { return false }
            guard let name = exercise.name, svc.shouldShowExerciseStrict(name) else { return false }
            return true
        }
        
        var picked: [Exercise] = []
        var seenBaseNames = Set<String>()
        var seenIds = Set<UUID>()
        
        // Slot-by-slot fill — one exercise per muscle target, in order.
        for slotMuscle in bucket.muscleSlots {
            if let match = bucketPool.first(where: { exercise in
                if let eid = exercise.id, seenIds.contains(eid) { return false }
                guard let name = exercise.name else { return false }
                if seenBaseNames.contains(Self.movementBaseName(name)) { return false }
                return Self.matchesMuscleStrict(exercise, target: slotMuscle)
            }) {
                if let eid = match.id { seenIds.insert(eid) }
                if let name = match.name { seenBaseNames.insert(Self.movementBaseName(name)) }
                picked.append(match)
            }
        }
        
        // Backfill if any slot came up empty (e.g. user has zero
        // tricep-tagged exercises in the curated set) — pull the next
        // category-matched exercise that hasn't been seen.
        if picked.count < 3 {
            for exercise in bucketPool {
                if picked.count >= 3 { break }
                if let eid = exercise.id, seenIds.contains(eid) { continue }
                guard let name = exercise.name else { continue }
                if seenBaseNames.contains(Self.movementBaseName(name)) { continue }
                if let eid = exercise.id { seenIds.insert(eid) }
                seenBaseNames.insert(Self.movementBaseName(name))
                picked.append(exercise)
            }
        }
        
        overdueSuggestions = Array(picked.prefix(3))
        overdueMuscleLabel = bucket.label
        prefetchOverduePosterFrames()
        #if DEBUG
        let pickedNames = overdueSuggestions.compactMap { $0.name }.joined(separator: ", ")
        AppLogger.debug("🏋️ [Overdue] Bucket=\(bucket.label) pool=\(pool.count) bucketPool=\(bucketPool.count) shown=\(overdueSuggestions.count) → [\(pickedNames)]", category: .workout)
        #endif
    }
    
    /// Kick off poster-frame generation for the 3 suggestion exercises so
    /// the round thumbnail in `ExercisePosterRingIcon` swaps from the
    /// gradient fallback to the real character clip within a beat or two.
    /// Without this, only the alphabetical list rows below get warmed
    /// (via their natural `onAppear` in the LazyVStack) — the strip
    /// exercises sat on the SF-symbol fallback for the full network round-
    /// trip on cold launch (see screenshot 2026-04-27 — Decline Bench
    /// Press / Tricep Extension / Skull Crusher all rendering as
    /// generic gradient circles).
    ///
    /// Mirrors the pattern `ExerciseLibraryView.onAppear` already uses for
    /// its first-20 visible rows. 500ms delay lets the scroll view paint
    /// first so we don't hijack the network during initial layout.
    private func prefetchOverduePosterFrames() {
        let names = overdueSuggestions.compactMap { $0.name }
        guard !names.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            VideoThumbnailService.shared.preGeneratePosterFrames(for: names)
        }
    }
    
    /// Strip the trailing equipment parenthetical from an exercise name so
    /// equipment variants of the same movement collapse to a single key.
    /// "21s Bicep Curl (Dumbbell)" → "21s bicep curl". Used for in-strip
    /// dedup ONLY — the underlying Exercise rows stay distinct.
    private static func movementBaseName(_ name: String) -> String {
        let lowered = name.lowercased()
        if let parenIdx = lowered.firstIndex(of: "(") {
            return String(lowered[..<parenIdx]).trimmingCharacters(in: .whitespaces)
        }
        return lowered.trimmingCharacters(in: .whitespaces)
    }
    
    /// Conservative muscle-group match for the suggestion strip ONLY.
    /// Unlike `ExerciseFilterService.isExerciseForMuscleGroup` (which is
    /// tuned for "show me every exercise that touches this muscle" — too
    /// broad for our 3-item starter strip; it pulls in "Back Extension"
    /// for "Triceps" via the bare "extension" alias), this checks:
    ///   1. The Exercise's `muscleGroups` array (most reliable when
    ///      populated by the seed JSON).
    ///   2. A short list of unambiguous name tokens — e.g. "tricep" /
    ///      "pushdown" / "skull crusher" for Triceps, NEVER "extension"
    ///      or "close grip" or "dip" because those over-match.
    /// Returns true if either signal fires.
    private static func matchesMuscleStrict(_ exercise: Exercise, target: String) -> Bool {
        let muscles = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
        let nameLower = exercise.name?.lowercased() ?? ""
        let targetLower = target.lowercased()
        
        // 1) muscleGroups array — fastest and most reliable when present.
        for m in muscles where m.contains(targetLower) || targetLower.contains(m) {
            return true
        }
        
        // 2) Conservative name tokens (per-target whitelist).
        switch targetLower {
        case "biceps", "bicep":
            return nameLower.contains("bicep") ||
                   nameLower.contains("preacher") ||
                   nameLower.contains("hammer curl") ||
                   nameLower.contains("concentration curl") ||
                   nameLower.contains("21s") ||
                   // "curl" is mostly biceps but exclude wrist/leg variants
                   (nameLower.contains("curl") &&
                    !nameLower.contains("wrist") &&
                    !nameLower.contains("leg") &&
                    !nameLower.contains("reverse"))
        case "triceps", "tricep":
            return nameLower.contains("tricep") ||
                   nameLower.contains("pushdown") ||
                   nameLower.contains("skull crusher") ||
                   nameLower.contains("skullcrusher") ||
                   nameLower.contains("kickback") ||
                   nameLower.contains("french press") ||
                   nameLower.contains("close grip bench") ||
                   nameLower.contains("close-grip bench")
        case "chest":
            return nameLower.contains("bench press") ||
                   nameLower.contains("chest press") ||
                   nameLower.contains("chest fly") ||
                   nameLower.contains("pec deck") ||
                   nameLower.contains("push up") ||
                   nameLower.contains("pushup") ||
                   nameLower.contains("push-up") ||
                   nameLower.contains("fly") ||
                   nameLower.contains("flye") ||
                   nameLower.contains("crossover")
        case "back":
            return nameLower.contains("row") ||
                   nameLower.contains("pulldown") ||
                   nameLower.contains("pull-down") ||
                   nameLower.contains("pull up") ||
                   nameLower.contains("pullup") ||
                   nameLower.contains("pull-up") ||
                   nameLower.contains("chin up") ||
                   nameLower.contains("chinup") ||
                   nameLower.contains("chin-up") ||
                   nameLower.contains("deadlift") ||
                   nameLower.contains("face pull") ||
                   nameLower.contains("rack pull")
        case "shoulders":
            return nameLower.contains("shoulder press") ||
                   nameLower.contains("overhead press") ||
                   nameLower.contains("military press") ||
                   nameLower.contains("arnold press") ||
                   nameLower.contains("lateral raise") ||
                   nameLower.contains("front raise") ||
                   nameLower.contains("rear delt") ||
                   nameLower.contains("upright row") ||
                   nameLower.contains("push press") ||
                   nameLower.contains("shrug")
        case "quads":
            return nameLower.contains("squat") ||
                   nameLower.contains("lunge") ||
                   nameLower.contains("leg press") ||
                   nameLower.contains("leg extension") ||
                   nameLower.contains("step up") ||
                   nameLower.contains("step-up") ||
                   nameLower.contains("bulgarian")
        case "hamstrings":
            return nameLower.contains("leg curl") ||
                   nameLower.contains("romanian") ||
                   nameLower.contains("rdl") ||
                   nameLower.contains("good morning") ||
                   nameLower.contains("nordic") ||
                   nameLower.contains("stiff leg") ||
                   nameLower.contains("stiff-leg") ||
                   nameLower.contains("glute ham raise")
        case "glutes":
            return nameLower.contains("hip thrust") ||
                   nameLower.contains("glute bridge") ||
                   nameLower.contains("glute kickback") ||
                   nameLower.contains("donkey kick") ||
                   nameLower.contains("frog pump") ||
                   nameLower.contains("hip abduction")
        case "calves":
            return nameLower.contains("calf raise") ||
                   nameLower.contains("calf press")
        case "abs":
            return nameLower.contains("crunch") ||
                   nameLower.contains("sit up") ||
                   nameLower.contains("sit-up") ||
                   nameLower.contains("situp") ||
                   nameLower.contains("plank") ||
                   nameLower.contains("leg raise") ||
                   nameLower.contains("knee raise") ||
                   nameLower.contains("hollow") ||
                   nameLower.contains("dead bug") ||
                   nameLower.contains("v up") ||
                   nameLower.contains("v-up") ||
                   nameLower.contains("ab wheel")
        case "obliques":
            return nameLower.contains("oblique") ||
                   nameLower.contains("russian twist") ||
                   nameLower.contains("side bend") ||
                   nameLower.contains("side plank") ||
                   nameLower.contains("woodchop") ||
                   nameLower.contains("wood chop") ||
                   nameLower.contains("pallof") ||
                   nameLower.contains("windshield wiper")
        default:
            return false
        }
    }
    
    // MARK: - Helper Functions
    private func loadExercises() {
        // Only load if exercises are ready (have valid names)
        guard exerciseLibrary.isExercisesReady else {
            AppLogger.debug("⏳ Waiting for exercises to be ready...", category: .workout)
            return
        }
        
        exercises = ExerciseLibraryService.shared.getAllExercises()
        let customCount = exercises.filter { $0.instructions?.contains("[CUSTOM_EXERCISE") ?? false }.count
        AppLogger.debug("📦 Loaded \(exercises.count) exercises for custom workout builder (including \(customCount) custom)", category: .workout)
        
        // If no exercises found in Core Data, fetch from Supabase
        if exercises.isEmpty || exercises.allSatisfy({ $0.name == nil }) {
            AppLogger.warning("⚠️ No exercises found in Core Data, fetching from Supabase...", category: .network)
            isLoadingExercises = true
            Task {
                do {
                    let exerciseDTOs = try await SupabaseManager.shared.fetchAllExercises()
                    AppLogger.info("✅ Fetched \(exerciseDTOs.count) exercises from Supabase, saving to Core Data...", category: .network)
                    
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
                                exercise.muscleGroups = primaryMuscles as NSArray
                            }
                        }
                        
                        do {
                            try viewContext.save()
                            AppLogger.info("✅ Saved \(exerciseDTOs.count) exercises to Core Data", category: .workout)
                            
                            // Reload exercises from Core Data
                            exercises = ExerciseLibraryService.shared.getAllExercises()
                            ExerciseLibraryService.shared.invalidateCache() // Refresh cache
                            forceRenderID = UUID()
                            isLoadingExercises = false
                        } catch {
                            AppLogger.error("❌ Error saving exercises to Core Data: \(error)", category: .workout)
                            isLoadingExercises = false
                        }
                    }
                } catch {
                    AppLogger.error("❌ Error fetching exercises from Supabase: \(error)", category: .network)
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
            case .addToWorkout(_, let onSelect):
                onSelect(exercise)
                dismiss()
            case .build, .pickMultiple:
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
            AppLogger.error("❌ No exercises selected", category: .workout)
            return
        }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("🏋️‍♂️ Starting custom workout with \(selectedExercises.count) exercises", category: .workout)
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
        AppLogger.info("✅ Custom workout started in \(String(format: "%.2f", elapsed))ms", category: .workout)
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
                        .font(.ds_bodySmall).fontWeight(.bold)
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
                    .font(.ds_labelMedium)
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
                    .font(.ds_bodyRegular).fontWeight(.medium)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
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
                            ? [Color(white: 0.15), Color.cardBackground]
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
                return "figure.strengthtraining.traditional"
            } else if exerciseName.contains("lunge") {
                return "figure.walk"
            }
        }
        
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing"
        case "legs": return "figure.strengthtraining.traditional"
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
    private let categories = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body", "Plyometrics", "Stretch", "Cardio", "Neck"]
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
        "Stretch": ["Upper Body", "Lower Body", "Back", "Hips"],
        "Cardio": ["Cardio"],
        "Neck": ["Neck"]
    ]
    
    private let commonIcons = [
        "dumbbell.fill", "figure.strengthtraining.traditional", "figure.climbing",
        "figure.strengthtraining.traditional", "arrow.up.circle.fill", "figure.core.training",
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
        NavigationStack {
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
        .padding(.vertical, Spacing.sm)
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
                .cornerRadius(CornerRadius.md)
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
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
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
                                    .font(.ds_bodySmall)
                            }
                            Text(muscle)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selection.wrappedValue.contains(muscle) ? .white : .primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            selection.wrappedValue.contains(muscle) ?
                            Color.blue :
                            Color(.systemGray5)
                        )
                        .cornerRadius(CornerRadius.lg)
                    }
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(CornerRadius.md)
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
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
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
                .padding(Spacing.xs)
                .background(Color.white)
                .cornerRadius(CornerRadius.md)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
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
        exercise.muscleGroups = (Array(primaryMuscleGroups) + Array(secondaryMuscleGroups)) as NSArray
        exercise.equipment = selectedEquipment
        
        // Mark as custom by adding metadata to instructions
        let customMetadata = "[CUSTOM_EXERCISE|ICON:\(selectedIcon)]"
        exercise.instructions = instructions.isEmpty ? "\(customMetadata) User-created custom exercise." : "\(customMetadata) \(instructions)"
        exercise.isFavorite = false
        
        do {
            try viewContext.save()
            AppLogger.info("✅ Custom exercise saved: \(exerciseName)", category: .workout)
            AppLogger.debug("   Name: \(exerciseName)", category: .workout)
            AppLogger.debug("   Instructions: \(exercise.instructions ?? "none")", category: .workout)
            AppLogger.debug("   Contains metadata: \(exercise.instructions?.contains("[CUSTOM_EXERCISE") ?? false)", category: .workout)
            
            // Sync to cloud (in background)
            Task {
                await syncCustomExerciseToCloud(exercise: exercise)
            }
            
            onSave(exercise)
            dismiss()
        } catch {
            AppLogger.error("❌ Failed to save custom exercise: \(error)", category: .workout)
        }
    }
    
    private func syncCustomExerciseToCloud(exercise: Exercise) async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("ℹ️ User not authenticated, skipping custom exercise cloud sync", category: .workout)
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
                AppLogger.info("✅ Custom exercise synced to cloud!", category: .workout)
            } catch {
                AppLogger.error("❌ Error syncing custom exercise to cloud: \(error)", category: .workout)
                // Don't block the app if cloud sync fails
            }
        } else {
            AppLogger.debug("ℹ️ Custom exercise saved locally (user not signed in)", category: .workout)
        }
    }
}

// MARK: - Icon Picker View
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String
    
    private let commonIcons = [
        "dumbbell.fill", "figure.strengthtraining.traditional", "figure.climbing",
        "figure.strengthtraining.traditional", "arrow.up.circle.fill", "figure.core.training",
        "figure.mixed.cardio", "figure.run", "figure.walk", "flame.fill",
        "bolt.fill", "star.fill", "heart.fill", "plus.circle.fill",
        "checkmark.circle.fill", "target", "scope", "moon.fill",
        "sparkles", "waveform.path.ecg", "figure.flexibility", "hand.raised.fill"
    ]
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
    
    var body: some View {
        NavigationStack {
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
                                    .font(.ds_heading2)
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
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var showingDetail = false

    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onToggle() }) {
            ExerciseCardRow(
                exercise: exercise,
                showCheckbox: true,
                isSelected: isSelected,
                showInfoButton: true,
                onInfo: { showingDetail = true }
            )
        }
        .buttonStyle(PlainButtonStyle())
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
}

struct SuggestedSwapRowWithNav: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var showingDetail = false

    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onToggle() }) {
            ExerciseCardRow(
                exercise: exercise,
                showCheckbox: true,
                isSelected: isSelected,
                showInfoButton: true,
                onInfo: { showingDetail = true }
            )
        }
        .buttonStyle(PlainButtonStyle())
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

