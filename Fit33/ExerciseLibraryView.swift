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
    @State private var searchDebounceTask: Task<Void, Never>?
    
    enum ExerciseFilterType: String, CaseIterable {
        case recommended = "Recommended"
        case favorites = "Favorites"
        case custom = "Custom Added"
        case strength = "Strength"
        case cardio = "Cardio"
        case plyometrics = "Plyometrics"
        case stretching = "Stretch"
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
            guard let firstCategory = selectedCategories.first else { return ["All"] }
            return ExerciseFilterService.muscleGroupsForCategory(firstCategory)
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
            searchResultsCache.removeAll()
            SmartExerciseSearchService.shared.invalidateCache()
            
            // ⚡️ INSTANT: For default "Recommended" with no extra filters, use the pre-computed list
            // This was built at startup by TabPreloader — zero work here, just pointer assignment.
            // The cache is already strength-filtered (per Recommended-list spec
            // 2026-04-27); we layer strict-gender on top here so a gender
            // switch in Settings reflects without rebuilding the cache.
            let filterCache = ExerciseLibraryFilterCache.shared
            if selectedCategories.isEmpty && selectedEquipmentItems.isEmpty && selectedMuscleGroups.isEmpty && exerciseFilter == .recommended && filterCache.isReady {
                preFilteredExercises = applyStrictGenderFilter(to: filterCache.preFilteredRecommended)
                #if DEBUG
                AppLogger.debug("⚡️ [PERF] INSTANT recommended from pre-computed cache: \(preFilteredExercises.count) exercises (gender-filtered)", category: .workout)
                #endif
            } else if selectedCategories.isEmpty && selectedEquipmentItems.isEmpty && selectedMuscleGroups.isEmpty && exerciseFilter == .recommended {
                // Fallback: cache not ready yet (very early cold start), compute inline
                preFilteredExercises = applyOptimizedRecommendedFilter(to: exercises)
                #if DEBUG
                AppLogger.debug("⚡️ [PERF] Optimized recommended filter (fallback): \(preFilteredExercises.count) exercises in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms", category: .workout)
                #endif
            } else {
                // Standard filter path for non-default filters
                preFilteredExercises = applyFiltersOnly(to: exercises)
                #if DEBUG
                AppLogger.debug("⚡️ [PERF] Rebuilt filter cache: \(preFilteredExercises.count) exercises in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms", category: .workout)
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
                AppLogger.debug("⚡️ [PERF] Search cache hit for '\(searchKey)': \(cached.count) results", category: .workout)
                #endif
                return
            }
            
            // Ultra-fast search - no heavy processing
            let results = SmartExerciseSearchService.shared.searchExercisesUltraFast(query: searchKey, in: preFilteredExercises)
            searchResultsCache[searchKey] = results
            cachedFilteredExercises = results
            
            #if DEBUG
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            AppLogger.debug("⚡️ [PERF] Search '\(searchKey)': \(results.count) results in \(String(format: "%.1f", elapsed))ms", category: .workout)
            #endif
            return
        }
        
        // No search text - just show pre-filtered results
        cachedFilteredExercises = preFilteredExercises
    }
    
    // ⚡️ OPTIMIZED: Fast recommended filter using precomputed Set lookup.
    // Used only on the cold-start fallback path when ExerciseLibraryFilterCache
    // hasn't finished its background pass yet. Mirrors the precompute logic:
    // (1) curated-list match, (2) strength-only, (3) strict gender.
    private func applyOptimizedRecommendedFilter(to exercises: [Exercise]) -> [Exercise] {
        let recommendedSet = ExerciseLibraryFilterCache.shared.recommendedExerciseNames
        
        return exercises.filter { exercise in
            guard let rawName = exercise.name else { return false }
            let name = rawName.lowercased()
            
            var matchedCurated = false
            for rec in recommendedSet {
                if name == rec || 
                   name.hasPrefix(rec + " ") || 
                   name.hasPrefix(rec + "(") ||
                   name.contains(" " + rec + " ") ||
                   name.contains(" " + rec + "(") {
                    matchedCurated = true
                    break
                }
            }
            guard matchedCurated else { return false }
            guard isStrengthExercise(exercise) else { return false }
            return GenderFilterService.shared.shouldShowExerciseStrict(rawName)
        }
    }

    // MARK: - Recommended-list helpers (strength + strict gender)
    
    /// Mirrors the `.strength` case in `applyFiltersOnly` so the Recommended
    /// list's strength check stays in lock-step with the dedicated Strength
    /// filter. Explicit `workoutType` wins; otherwise fall back to the
    /// name+category+equipment classifier.
    private func isStrengthExercise(_ exercise: Exercise) -> Bool {
        if let workoutType = exercise.workoutType, !workoutType.isEmpty {
            return workoutType.lowercased() == "strength"
        }
        let smartType = ExerciseFilterService.classifyExerciseType(
            name: exercise.name, category: exercise.category, equipment: exercise.equipment
        )
        return smartType == .strength
    }
    
    /// Apply strict gender filter (no opposite-gender fallback) to a
    /// pre-filtered recommended list. Per user request 2026-04-27, the
    /// Recommended initial view should never surface opposite-gender clips
    /// even if that's the only version available — gender-tagged exercises
    /// without our preferred-gender video are simply hidden.
    private func applyStrictGenderFilter(to exercises: [Exercise]) -> [Exercise] {
        let svc = GenderFilterService.shared
        return exercises.filter { exercise in
            guard let name = exercise.name else { return false }
            return svc.shouldShowExerciseStrict(name)
        }
    }
    
    /// Apply category/equipment/muscle filters WITHOUT search
    private func applyFiltersOnly(to exercises: [Exercise]) -> [Exercise] {
        var filtered = exercises
        
        // Filter by exercise filter type
        switch exerciseFilter {
        case .recommended:
            // Curated list + strength-only + strict gender (per user request
            // 2026-04-27). Same predicate set the precomputed cache and the
            // cold-start fallback use, so layered filters (category /
            // equipment / muscle on top of Recommended) stay consistent.
            let svc = GenderFilterService.shared
            filtered = filtered.filter { exercise in
                guard let rawName = exercise.name else { return false }
                let fullName = rawName.lowercased()
                let inCurated = recommendedExercises.contains { rec in
                    fullName == rec || fullName.hasPrefix(rec + " ") || fullName.hasPrefix(rec + "(")
                }
                guard inCurated else { return false }
                guard isStrengthExercise(exercise) else { return false }
                return svc.shouldShowExerciseStrict(rawName)
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
                    ExerciseFilterService.exerciseMatchesEquipment(exercise, selectedEquipment: equipmentItem)
                }
            }
        }
        
        // Filter by muscle group (multi-select - show exercises matching ANY selected muscle)
        if !selectedMuscleGroups.isEmpty {
            filtered = filtered.filter { exercise in
                selectedMuscleGroups.contains { muscleGroup in
                    ExerciseFilterService.isExerciseForMuscleGroup(exercise, muscleGroup: muscleGroup)
                }
            }
        }
        
        return filtered
    }
    
    // Legacy computed property for backwards compatibility (use cachedFilteredExercises instead)
    var filteredExercises: [Exercise] {
        cachedFilteredExercises
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                    .accessibilityHidden(true)

                // Pinned title row matches Home / Workout / Nutrition /
                // Friends — `PinnedTabHeader` provides the same horizontal
                // inset and the outer VStack picks up the shared
                // `TabPinnedChrome.rootTopPullUp` so this tab's title
                // sits at the same vertical position as every other tab.
                VStack(spacing: 0) {
                PinnedTabHeader {
                    customHeaderView
                }

                // Fixed filter section (doesn't scroll)
                VStack(spacing: 0) {
                    compactFiltersView

                    // Banner ad killed (Phase 1, 2026-05-03 monetization
                    // sweep) — Exercise Library is a high-engagement
                    // surface where banner clutter hurt scroll quality
                    // for marginal eCPM. The dashboard `NativeAdCardView`
                    // now carries the heavier ad load on home, and any
                    // user clearly motivated to browse the library is a
                    // higher-value Pro candidate than a banner-impression.
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 12)
                
                // Scrollable exercise list only
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id("top")
                        
                        // No loading / placeholder state — preWarmCache() inline-seeds from the
                        // bundle JSON on a background context during app init, so by the time
                        // this view appears, Core Data already has real Exercise rows to render.
                        // If the list is briefly empty on a very fast tap, show nothing (not a
                        // grey placeholder card) until .onChange(isExercisesReady) refreshes.
                        LazyVStack(spacing: 10) {
                            ForEach(Array(filteredExercises.enumerated()), id: \.element.objectID) { index, exercise in
                                // Skip any faulted row whose name hasn't materialized yet —
                                // rendering those produced the grey "Exercise" placeholder cards.
                                if let name = exercise.name, !name.isEmpty {
                                    NavigationLink(value: exercise) {
                                        CompactExerciseRowContent(exercise: exercise, showChevron: true)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .simultaneousGesture(TapGesture().onEnded {
                                        ExerciseLibraryFilterCache.shared.trackExerciseSelection(exerciseName: name)
                                        VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
                                    })
                                    .onAppear {
                                        prefetchVisibleExercise(exercise: exercise, index: index)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                    .id(forceRenderID)
                    .refreshable {
                        loadExercises()
                    }
                    .onChange(of: scrollToTopTrigger) { _, _ in
                        scrollProxy.scrollTo("top", anchor: .top)
                    }
                }
                }   // closes VStack(spacing: 0) — pinned-header wrapper
                .padding(.top, TabPinnedChrome.rootTopPullUp)
            }
            // ⚡️ SNAPPY SEARCH: Dismiss keyboard immediately when scrolling
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    isSearchFocused = false
                }
            )
            .navigationBarHidden(true)
            .adaptiveToolbarBackground()
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
                
                // Pre-generate poster frames after a delay so the list renders first
                let visibleNames = filteredExercises.prefix(20).compactMap { $0.name }
                if !visibleNames.isEmpty {
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        VideoThumbnailService.shared.preGeneratePosterFrames(for: visibleNames)
                    }
                }
                
                // Log screen appearance with unique ID
                SessionLogManager.shared.logScreen(.exerciseLibrary, metadata: [
                    "exercise_count": exercises.count,
                    "filter": exerciseFilter.rawValue,
                    "load_time_ms": Int(Date().timeIntervalSince(startTime) * 1000)
                ])
                
                // Only trigger cloud sync if we have very few exercises (< 500)
                if exercises.count < 500 && !WorkoutManager.shared.isWorkoutActive {
                    AppLogger.debug("📚 [LIBRARY] Exercise count (\(exercises.count)) very low, triggering cloud sync...", category: .workout)
                    SessionLogManager.shared.logDataSync(type: "Exercises", itemCount: exercises.count, direction: "download")
                    Task {
                        await ExerciseLibraryService.shared.syncExercisesFromCloud()
                        await MainActor.run {
                            loadExercises()
                            lastFilterKey = "" // Force filter rebuild
                            updateFilteredExercises()
                            AppLogger.debug("📚 [LIBRARY] Sync complete, now have \(exercises.count) exercises", category: .workout)
                        }
                    }
                }
            }
            // ⚡️ HIGH-PERFORMANCE: Instant filter updates with state caching
            .onChange(of: searchText) { _, newValue in
                ViewStateCache.shared.exerciseLibraryState.searchText = newValue
                searchDebounceTask?.cancel()
                if searchText.isEmpty {
                    updateFilteredExercises()
                } else {
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        guard !Task.isCancelled else { return }
                        updateFilteredExercises()
                    }
                }
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
            // 🔄 Reload when the CMS realtime pipeline bumps the library
            // revision (admin edited / added / deleted an exercise).
            .onChange(of: exerciseLibrary.libraryRevision) { _, _ in
                AppLogger.info("🔄 [LIBRARY] libraryRevision bumped - reloading list from realtime", category: .workout)
                viewContext.refreshAllObjects()
                loadExercises()
                lastFilterKey = ""
                searchResultsCache.removeAll()
                updateFilteredExercises()
                forceRenderID = UUID()
            }
            // 🔄 Reload when exercises become ready after cloud sync
            .onChange(of: exerciseLibrary.isExercisesReady) { _, isReady in
                if isReady {
                    AppLogger.info("✅ [LIBRARY] Exercises now ready after sync - reloading list", category: .workout)
                    viewContext.refreshAllObjects()
                    loadExercises()
                    
                    // Re-compute the recommended filter cache with actual exercises
                    // (it was pre-computed at startup when Core Data was empty,
                    // OR with bundle-seed objectIDs that the cloud sync just
                    // wiped — bug `3037a6f4`). Reset first so the
                    // `guard !isReady` inside `precomputeRecommendedList`
                    // doesn't no-op and leave us bound to stale objectIDs.
                    if !exercises.isEmpty {
                        ExerciseLibraryFilterCache.shared.reset()
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
                AppLogger.debug("📚 Exercise Library: Favorite changed, refreshing...", category: .workout)
                viewContext.refreshAllObjects()
                loadExercises()
                updateFilteredExercises()
                forceRenderID = UUID()
            }
            // 👤 Refresh when the user switches preferred gender (Settings ->
            // Profile). Recommended list is gender-aware (strict — see
            // `applyStrictGenderFilter`) so we MUST re-filter, not just bump
            // a render ID. `lastFilterKey = ""` forces the filter cache to
            // rebuild on the next call.
            .onReceive(NotificationCenter.default.publisher(for: .genderPreferenceChanged)) { _ in
                AppLogger.debug("📚 Exercise Library: Gender preference changed, refreshing...", category: .workout)
                lastFilterKey = ""
                searchResultsCache.removeAll()
                updateFilteredExercises()
                forceRenderID = UUID()
            }
            // 🔁 Tab tap → reset to Recommended (per user request 2026-04-27).
            // MainTabView posts `.exerciseTabSelected` whenever the user lands
            // on tab 1 from anywhere else. Resetting only the filter (not
            // search/category) keeps any in-progress drill-down intact while
            // still meeting "tapping the tab brings me back to Recommended".
            .onReceive(NotificationCenter.default.publisher(for: .exerciseTabSelected)) { _ in
                if exerciseFilter != .recommended {
                    AppLogger.debug("📚 Exercise Library: Tab tapped, resetting filter to Recommended", category: .workout)
                    exerciseFilter = .recommended
                }
            }
        }
    }
    
    // MARK: - Custom Header View
    private var customHeaderView: some View {
        HStack(alignment: .center) {
            Text("Exercises")
                .font(.ds_displayLarge)
                .italic()
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.72),
                            .init(color: Color.blue, location: 0.85),
                            .init(color: Color.cyan, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color.blue.opacity(0.2), radius: 4, x: 0, y: 1)
                .frame(height: 55)
            
            Spacer()
            
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
        .padding(.horizontal, Spacing.xxs)
    }
    
    private var compactFiltersView: some View {
        VStack(spacing: 16) {
            // Search section with title
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.ds_labelMedium)
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
                                .font(.ds_labelMedium)
                            Text(exerciseFilter.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.ds_caption).fontWeight(.semibold)
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
                            isSearchFocused = false // Also dismiss keyboard when clearing
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.ds_bodySmall)
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
                
                // Main card background — adaptive (frosted ↔ solid via setting)
                AdaptiveCardSurface(cornerRadius: 24)
                
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
    let exercise: Exercise
    var showChevron: Bool = false

    var body: some View {
        ExerciseCardRow(
            exercise: exercise,
            showChevron: showChevron
        )
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
                    .font(.ds_caption).fontWeight(.semibold)
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
            if text != "All" && !selectedItems.contains(text) {
                selectedItems.insert(text)
            } else if text == "All" {
                selectedItems = []
            }
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
                                .font(.ds_labelMedium)
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
                                    .font(.ds_labelMedium)
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
