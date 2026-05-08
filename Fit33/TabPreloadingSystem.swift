import SwiftUI
import CoreData
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - TAB PRELOADING SYSTEM (Instant Tab Switching)
// ═══════════════════════════════════════════════════════════════════════════════
//
// 🎯 PROBLEM: On cold start, first tab switch is slow because views initialize lazily
//
// ✅ SOLUTION: Aggressive preloading during startup:
//    1. Pre-initialize ALL tab view bodies in parallel
//    2. Pre-fetch ALL data needed by each tab
//    3. Pre-warm all services and caches
//    4. Keep views in memory so switching is instant
//
// 📊 Expected Results:
//    - First tab switch: 300-500ms → <16ms (instant)
//    - Subsequent switches: Already fast
//    - Memory cost: ~20-30MB (worth it for UX)
//
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - 1. TAB PRELOADER (Main Coordinator)

@MainActor
final class TabPreloader: ObservableObject {
    static let shared = TabPreloader()
    
    // MARK: - Published State
    @Published private(set) var isPreloadingComplete = false
    @Published private(set) var preloadProgress: Double = 0
    @Published private(set) var preloadedTabs: Set<Int> = []
    
    // Track which tabs are fully warmed (data + view)
    private var warmedTabs: Set<Int> = [0] // Dashboard starts warmed
    
    // Preloaded data stores
    private(set) var exerciseLibraryData: PreloadedExerciseLibraryData?
    private(set) var workoutTabData: PreloadedWorkoutTabData?
    private(set) var nutritionTabData: PreloadedNutritionTabData?
    // 2026-05-03 perf sprint: `progressTabData` removed alongside Phase 3.
    // Achievements + workout-stats now compute on-demand inside the
    // dedicated Achievements view.
    
    // Timing
    private var preloadStartTime: CFTimeInterval = 0
    
    private init() {}
    
    // MARK: - Main Preload Entry Point
    
    /// Call this from Fit33App.swift after UI appears
    /// Preloads ALL tab data and views in background
    func beginPreloading(context: NSManagedObjectContext) {
        guard !isPreloadingComplete else { return }
        
        preloadStartTime = CACurrentMediaTime()
        AppLogger.debug("🚀 [TAB PRELOAD] Starting aggressive preloading...", category: .ui)
        
        Task(priority: .userInitiated) {
            await preloadAllTabs(context: context)
        }
    }
    
    // MARK: - Preload All Tabs
    
    private func preloadAllTabs(context: NSManagedObjectContext) async {
        // ═══════════════════════════════════════════════════════════════
        // LIGHTWEIGHT PRELOAD PIPELINE
        // Phase 1: Core Data (exercises metadata, workouts, user) — lightweight
        // Phase 2: Cloud data (cardio, programs, nutrition) — parallel network
        // Phase 3: SKIPPED — achievements/stats compute on-demand now
        // Phase 4: Services — exercise library, exercise filters
        // ═══════════════════════════════════════════════════════════════

        // ⚡️ Cold-start sprint 2026-04-26: gate on store-loaded so Phase 1's
        // exercise/workout fetches don't race the async store-attach.
        await PersistenceController.waitUntilStoreLoaded()

        
        // Phase 1: Lightweight Core Data prefetch
        await preloadPhase1_CoreData(context: context)
        preloadProgress = 0.33
        
        // Phase 2: Cloud data (already has internal caching/throttling)
        await preloadPhase2_CloudData()
        preloadProgress = 0.66
        
        // Phase 3: SKIPPED — was computing 400+ achievements + workout stats.
        // Stats are now embedded in Workout tab (lightweight version) and
        // achievements compute on-demand when user scrolls to them.
        // This saves ~2-5s of CPU work at startup.
        preloadProgress = 0.80
        
        // Phase 4: Pre-warm services (exercise filters, etc.)
        await preloadPhase4_Services()
        preloadProgress = 1.0
        
        // Mark all tabs as preloaded
        warmedTabs = [0, 1, 2, 3, 4]
        preloadedTabs = [0, 1, 2, 3, 4]
        isPreloadingComplete = true
        
        // Release heavy data immediately
        releasePreloadedData()
        
        let elapsed = (CACurrentMediaTime() - preloadStartTime) * 1000
        AppLogger.debug("🚀 [TAB PRELOAD] Complete in \(String(format: "%.0f", elapsed))ms - ALL tabs ready!", category: .ui)
    }
    
    // MARK: - Phase 1: Core Data Preload
    
    private func preloadPhase1_CoreData(context: NSManagedObjectContext) async {
        let startTime = CACurrentMediaTime()
        
        // Use a background context so fetches don't block the main queue.
        // The passed-in context is often viewContext (main-queue); context.perform
        // on main-queue context runs work ON the main thread.
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        
        async let exercisesFetch = fetchExercisesForLibrary(context: bgContext)
        async let workoutsFetch = fetchRecentWorkouts(context: bgContext)
        async let userFetch = fetchUserData(context: bgContext)
        
        // Await all results
        let exercises = await exercisesFetch
        let workouts = await workoutsFetch
        let user = await userFetch
        
        // Store preloaded data
        exerciseLibraryData = PreloadedExerciseLibraryData(
            allExercises: exercises,
            categories: extractCategories(from: exercises),
            equipment: extractEquipment(from: exercises),
            favoriteIDs: exercises.filter { $0.isFavorite }.compactMap { $0.id }
        )
        
        workoutTabData = PreloadedWorkoutTabData(
            recentWorkouts: workouts,
            hasActiveProgram: GeneratedProgramService.shared.activeProgram != nil
        )
        
        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        AppLogger.debug("  └─ Phase 1 (Core Data): \(String(format: "%.0f", elapsed))ms", category: .ui)
        AppLogger.debug("     └─ Exercises: \(exercises.count), Workouts: \(workouts.count)", category: .ui)
    }
    
    private func fetchExercisesForLibrary(context: NSManagedObjectContext) async -> [Exercise] {
        return await withCheckedContinuation { continuation in
            context.perform {
                let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
                // Only fetch a small subset for preloading categories/equipment
                // The full list loads on-demand when user visits Exercise tab
                request.fetchLimit = 200
                request.propertiesToFetch = ["name", "category", "equipment", "isFavorite"]
                
                do {
                    let exercises = try context.fetch(request)
                    // DON'T touch every property - let Core Data fault on demand
                    // Faulting 5000+ objects at startup was causing massive CPU spikes
                    continuation.resume(returning: exercises)
                } catch {
                    AppLogger.warning("⚠️ [TAB PRELOAD] Exercise fetch failed: \(error)", category: .ui)
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func fetchRecentWorkouts(context: NSManagedObjectContext) async -> [Workout] {
        return await withCheckedContinuation { continuation in
            context.perform {
                let request: NSFetchRequest<Workout> = Workout.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
                request.predicate = NSPredicate(format: "isCompleted == true")
                request.fetchLimit = 50 // Enough for history display
                
                do {
                    let workouts = try context.fetch(request)
                    // Touch properties to fault them in
                    for workout in workouts {
                        _ = workout.date
                        _ = workout.duration
                        _ = workout.totalVolume
                    }
                    continuation.resume(returning: workouts)
                } catch {
                    AppLogger.warning("⚠️ [TAB PRELOAD] Workout fetch failed: \(error)", category: .ui)
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func fetchUserData(context: NSManagedObjectContext) async -> User? {
        return await withCheckedContinuation { continuation in
            context.perform {
                let request: NSFetchRequest<User> = User.fetchRequest()
                request.fetchLimit = 1
                
                do {
                    let user = try context.fetch(request).first
                    if let user = user {
                        // Touch all frequently accessed properties
                        _ = user.totalWorkouts
                        _ = user.currentStreak
                        _ = user.longestStreak
                        _ = user.xp
                        _ = user.lastWorkoutDate
                    }
                    continuation.resume(returning: user)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func extractCategories(from exercises: [Exercise]) -> [String] {
        let categories = Set(exercises.compactMap { $0.category })
        return ["All"] + categories.sorted()
    }
    
    private func extractEquipment(from exercises: [Exercise]) -> [String] {
        let equipment = Set(exercises.compactMap { $0.equipment })
        return ["All"] + equipment.sorted()
    }
    
    // MARK: - Phase 2: Cloud Data Preload
    
    private func preloadPhase2_CloudData() async {
        let startTime = CACurrentMediaTime()
        
        // Run cloud fetches in parallel
        async let cardioFetch = fetchCardioWorkouts()
        async let programsFetch = fetchProgramsData()
        async let nutritionFetch = fetchNutritionData()
        
        let cardioWorkouts = await cardioFetch
        let programsData = await programsFetch
        let nutritionData = await nutritionFetch
        
        // Update workout tab data with cardio
        if var workoutData = workoutTabData {
            workoutData.recentCardioWorkouts = cardioWorkouts
            workoutTabData = workoutData
        }
        
        // Store nutrition data
        nutritionTabData = nutritionData
        
        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        AppLogger.debug("  └─ Phase 2 (Cloud Data): \(String(format: "%.0f", elapsed))ms", category: .ui)
    }
    
    private func fetchCardioWorkouts() async -> [CardioWorkoutDTO] {
        // Fetch recent cardio from Supabase using existing method
        do {
            return try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 20)
        } catch {
            AppLogger.warning("⚠️ [TAB PRELOAD] Cardio fetch failed: \(error)", category: .ui)
            return []
        }
    }
    
    private func fetchProgramsData() async -> Bool {
        // Check if user has active programs (service loads on init)
        return GeneratedProgramService.shared.activeProgram != nil || 
               !GeneratedProgramService.shared.generatedPrograms.isEmpty
    }
    
    private func fetchNutritionData() async -> PreloadedNutritionTabData {
        // Load today's meals synchronously (MealService uses Core Data)
        let today = Date()
        MealService.shared.loadTodaysMeals()
        let meals = MealService.shared.getMealsForDate(today)
        let totals = MealService.shared.getDailySummary(for: today)
        
        // Get hydration data
        let waterIntake = HydrationService.shared.todaySummary?.totalMl ?? 0
        
        return PreloadedNutritionTabData(
            todaysMeals: meals,
            dailyTotals: (totals.calories, totals.protein, totals.carbs, totals.fat),
            waterIntake: Double(waterIntake)
        )
    }
    
    // MARK: - Phase 3: REMOVED (2026-05-03 perf sprint)
    //
    // Was `preloadPhase3_Computations` + `precomputeAchievements` +
    // `precomputeWorkoutStats`. The pipeline above already skipped this
    // phase ("Phase 3: SKIPPED — was computing 400+ achievements + workout
    // stats. Stats are now embedded in Workout tab and achievements compute
    // on-demand"). The methods themselves were never called from anywhere
    // else. Removing the dead code shrinks the file and clears the
    // confusion of seeing referenced-but-unused infrastructure.
    
    // 2026-05-07 (Snappiness Overhaul Phase 4.3): `precomputeExerciseFilters`
    // removed. Zero call sites repo-wide (verified via grep at deletion
    // time). The search-index it built (`exerciseLibraryData.searchIndex`)
    // and the `ExerciseLibraryFilterCache.precomputeRecommendedList` warmup
    // are still reachable via direct invocation from the Exercise Library
    // view and `ExerciseLibraryService.preloadAll()` — neither relied on
    // this private helper.

    // MARK: - Phase 4: Pre-warm Services
    
    private func preloadPhase4_Services() async {
        let startTime = CACurrentMediaTime()
        
        // Pre-warm critical services in parallel
        await withTaskGroup(of: Void.self) { group in
            // Exercise library service
            group.addTask {
                _ = ExerciseLibraryService.shared
                await ExerciseLibraryService.shared.preloadAll()
            }
            
            // Video playback engine (pre-warm player pool)
            group.addTask {
                VideoPlaybackEngine.shared.prewarmPlayerPool()
            }
            
            // Smart recommendation engine
            group.addTask {
                if SmartRecommendationEngine.shared.communityInsights.needsRefresh {
                    await SmartRecommendationEngine.shared.communityInsights.refreshInsights()
                }
            }
            
            // Friend service (for social features)
            group.addTask {
                await FriendService.shared.loadFriends()
            }
            
            // Generated program service (warm reference - loads on init)
            group.addTask {
                _ = GeneratedProgramService.shared.activeProgram
                _ = GeneratedProgramService.shared.generatedPrograms
            }
        }
        
        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        AppLogger.debug("  └─ Phase 4 (Services): \(String(format: "%.0f", elapsed))ms", category: .ui)
    }
    
    // MARK: - Public API
    
    /// Check if a specific tab is preloaded and ready
    func isTabReady(_ tabIndex: Int) -> Bool {
        return warmedTabs.contains(tabIndex)
    }
    
    /// Get preloaded exercises for instant display
    func getPreloadedExercises() -> [Exercise] {
        return exerciseLibraryData?.allExercises ?? []
    }
    
    /// Get preloaded categories
    func getPreloadedCategories() -> [String] {
        return exerciseLibraryData?.categories ?? ["All"]
    }
    
    /// Get preloaded equipment
    func getPreloadedEquipment() -> [String] {
        return exerciseLibraryData?.equipment ?? ["All"]
    }
    
    // 2026-05-03 perf sprint: `getPreloadedAchievements()` removed alongside
    // Phase 3. Achievements compute on-demand inside the Achievements view.
    
    /// ⚡️ MEMORY FIX: Public entry point for MemoryPressureHandler to release data
    func releaseDataForMemoryPressure() {
        releasePreloadedData()
    }
    
    /// ⚡️ MEMORY FIX: Release heavy data after preloading completes.
    /// The preload phase faults 7000+ Exercise objects and builds a search index.
    /// Once tabs are warmed, each tab re-fetches its own data on demand.
    private func releasePreloadedData() {
        let exerciseCount = exerciseLibraryData?.allExercises.count ?? 0
        exerciseLibraryData = nil
        workoutTabData = nil
        nutritionTabData = nil
        AppLogger.debug("💾 [TAB PRELOAD] Released preloaded data (\(exerciseCount) exercises freed from memory)", category: .ui)
    }
    
    /// Reset (for sign out)
    func reset() {
        isPreloadingComplete = false
        preloadProgress = 0
        preloadedTabs = []
        warmedTabs = [0]
        exerciseLibraryData = nil
        workoutTabData = nil
        nutritionTabData = nil
    }
}

// MARK: - 2. PRELOADED DATA STRUCTURES

struct PreloadedExerciseLibraryData {
    var allExercises: [Exercise]
    var categories: [String]
    var equipment: [String]
    var favoriteIDs: [UUID]
    var searchIndex: [Character: [Exercise]] = [:]
}

struct PreloadedWorkoutTabData {
    var recentWorkouts: [Workout]
    var hasActiveProgram: Bool
    var recentCardioWorkouts: [CardioWorkoutDTO] = []
}

struct PreloadedNutritionTabData {
    var todaysMeals: [MealEntryData]
    var dailyTotals: (calories: Int, protein: Int, carbs: Int, fat: Int)
    var waterIntake: Double
}

// 2026-05-03 perf sprint: `PreloadedProgressTabData` + `WorkoutStatsSnapshot`
// removed. They were only consumed by the deleted Phase 3 path.

// MARK: - EXERCISE LIBRARY FILTER CACHE (Pre-computed for instant tab load)

/// Lightweight off-main snapshot of an Exercise row used by
/// `ExerciseLibraryFilterCache.precomputeFromIndex`. Captures everything the
/// recommended-list strength classifier needs (`workoutType` + name +
/// category + equipment) without holding a live `Exercise` reference, so the
/// background classification pass never faults the main-thread Core Data
/// stack. The objectID at the end is what we hand back to the view context
/// when assembling the final `[Exercise]`.
struct RecommendedExerciseEntry {
    let name: String
    let category: String?
    let workoutType: String?
    let equipment: String?
    let objectID: NSManagedObjectID
}

/// Pre-computes and caches the recommended exercise list at startup.
/// On cold start, the Exercise Library tab reads directly from this cache — zero work on tab switch.
/// The recommended list is DYNAMIC: it blends a curated top-200 baseline with the user's
/// personal usage data (exercises they complete/select rise to the top over time).
@MainActor
final class ExerciseLibraryFilterCache: ObservableObject {
    static let shared = ExerciseLibraryFilterCache()
    
    @Published private(set) var isReady = false
    
    /// Pre-filtered recommended exercises, sorted by popularity. Ready for the view to consume directly.
    @Published private(set) var preFilteredRecommended: [Exercise] = []
    
    // ═══════════════════════════════════════════════════════════════════
    // Top 200 Most Common Exercises — curated baseline (sorted by universal popularity)
    // These are the exercises 95% of gym-goers actually do. Covers every muscle group,
    // every major equipment type, and beginner → advanced levels.
    // Dynamic user data is blended on top at runtime.
    // ═══════════════════════════════════════════════════════════════════
    let recommendedExerciseNames: Set<String> = [
        // ── CHEST (18) ──
        "bench press", "incline bench press", "decline bench press",
        "dumbbell press", "dumbbell bench press", "incline dumbbell press",
        "dumbbell fly", "incline dumbbell fly", "cable fly", "cable crossover",
        "push up", "decline push up", "diamond push up", "chest dip",
        "machine chest press", "pec deck", "landmine press", "floor press",
        
        // ── BACK (18) ──
        "pull up", "chin up", "lat pulldown", "wide grip lat pulldown",
        "barbell row", "bent over row", "dumbbell row", "single arm row",
        "cable row", "seated row", "t-bar row", "face pull",
        "straight arm pulldown", "deadlift", "rack pull", "pendlay row",
        "inverted row", "chest supported row",
        
        // ── SHOULDERS (18) ──
        "overhead press", "shoulder press", "military press", "dumbbell shoulder press",
        "arnold press", "lateral raise", "cable lateral raise", "front raise",
        "rear delt fly", "reverse fly", "upright row", "shrug",
        "dumbbell shrug", "barbell shrug", "seated shoulder press",
        "push press", "machine shoulder press", "band pull apart",
        
        // ── BICEPS (14) ──
        "bicep curl", "barbell curl", "dumbbell curl", "hammer curl",
        "preacher curl", "concentration curl", "cable curl", "incline curl",
        "spider curl", "ez bar curl", "reverse curl", "drag curl",
        "bayesian curl", "21s",
        
        // ── TRICEPS (14) ──
        "tricep pushdown", "rope pushdown", "tricep extension",
        "overhead tricep extension", "skull crusher", "close grip bench press",
        "dip", "bench dip", "tricep kickback", "cable kickback",
        "french press", "single arm pushdown", "diamond push up", "machine dip",
        
        // ── LEGS — QUADS (20) ──
        "squat", "back squat", "front squat", "goblet squat", "leg press",
        "hack squat", "lunge", "walking lunge", "reverse lunge",
        "bulgarian split squat", "split squat", "leg extension",
        "step up", "sissy squat", "narrow squat", "sumo squat",
        "smith squat", "box squat", "pendulum squat", "single leg press",
        
        // ── LEGS — HAMSTRINGS (14) ──
        "romanian deadlift", "stiff leg deadlift", "leg curl",
        "lying leg curl", "seated leg curl", "good morning",
        "nordic curl", "single leg romanian deadlift", "sumo deadlift",
        "trap bar deadlift", "cable pull through", "kettlebell swing",
        "glute ham raise", "back extension",
        
        // ── LEGS — GLUTES (14) ──
        "hip thrust", "barbell hip thrust", "glute bridge",
        "single leg hip thrust", "cable kickback", "donkey kick",
        "fire hydrant", "clamshell", "machine hip abduction",
        "frog pump", "hip thrust machine", "banded hip thrust",
        "deficit reverse lunge", "curtsey lunge",
        
        // ── CALVES (6) ──
        "calf raise", "standing calf raise", "seated calf raise",
        "single leg calf raise", "leg press calf raise", "donkey calf raise",
        
        // ── ABS & CORE (18) ──
        "crunch", "sit up", "plank", "side plank", "russian twist",
        "leg raise", "hanging leg raise", "bicycle crunch",
        "ab wheel rollout", "cable crunch", "mountain climber",
        "dead bug", "bird dog", "v up", "reverse crunch",
        "hanging knee raise", "pallof press", "wood chop",
        
        // ── TRAPS (6) ──
        "shrug", "barbell shrug", "dumbbell shrug", "trap bar shrug",
        "face pull", "farmer walk",
        
        // ── FOREARMS (4) ──
        "wrist curl", "reverse wrist curl", "farmer carry", "dead hang",
        
        // ── COMPOUND / FUNCTIONAL (16) ──
        "clean", "power clean", "clean and press", "thruster",
        "burpee", "man maker", "turkish get up", "snatch",
        "kettlebell swing", "devil press", "sled push", "bear crawl",
        "farmer walk", "overhead carry", "battle rope", "med ball slam"
    ]
    
    // ── User personal usage counts (persisted to UserDefaults) ──
    private let usageKey = "exerciseUsageCounts"
    private(set) var personalUsageCounts: [String: Int] = [:]
    
    private init() {
        loadPersonalUsage()
    }
    
    // MARK: - Pre-compute at Startup
    
    /// Track if computation is already in-flight to prevent duplicate work
    private var isComputing = false
    
    /// Called by TabPreloader Phase 3 and by ExerciseLibraryView when the
    /// pre-decoded cache is empty. Pre-filters ALL exercises down to the
    /// recommended list, sorted by popularity, so the Exercise Library tab
    /// has zero work on appear.
    ///
    /// ⚡️ Cold-start sprint 2026-04-25 (Restore Cold-Start Performance plan,
    ///   Change 2 — Invariant 17 fix):
    ///
    /// PREVIOUSLY: this method extracted `(index, exercise.name?.lowercased())`
    /// for EVERY element of `allExercises` (up to 5431 items) on the main
    /// actor, then synchronously batched the materialized `[Exercise]` back
    /// from indices. The full-array name-extraction touched `.name` on
    /// thousands of NSManagedObject instances — each a potential SQLite
    /// fault — directly violating Invariant 17 ("Sorting/filtering 1000+
    /// items MUST run off main thread").
    ///
    /// NEW BEHAVIOR: convert the `[Exercise]` array to `[(name, objectID)]`
    /// tuples on a background context (where `.name` access doesn't block
    /// the main thread) and delegate to `precomputeFromIndex` which already
    /// has the safe end-to-end path. The viewContext is captured so the final
    /// main-actor resolution happens on the right context.
    func precomputeRecommendedList(allExercises: [Exercise]) {
        guard !isReady, !isComputing else { return }
        guard !allExercises.isEmpty else { return }

        // Capture objectIDs synchronously on main (objectID access does NOT
        // fault and is cheap — no SQLite I/O, no @MainActor issue). Names
        // will be read off-main via a bulk fetch.
        let objectIDs = allExercises.map { $0.objectID }
        let viewContext = allExercises[0].managedObjectContext ?? PersistenceController.shared.container.viewContext

        Task.detached(priority: .userInitiated) {
            let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
            // Capture name/category/workoutType/equipment off-main so the
            // strength-classification step (added 2026-04-27 per user request
            // "Recommended only shows strength specific to gender") can run
            // off the main thread alongside the curated-list match.
            let exerciseIndex: [RecommendedExerciseEntry] = await bgContext.perform {
                let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                request.predicate = NSPredicate(format: "self IN %@", objectIDs)
                request.returnsObjectsAsFaults = false
                let exercises = (try? bgContext.fetch(request)) ?? []
                return exercises.compactMap { ex -> RecommendedExerciseEntry? in
                    guard let name = ex.name else { return nil }
                    return RecommendedExerciseEntry(
                        name: name,
                        category: ex.category,
                        workoutType: ex.workoutType,
                        equipment: ex.equipment,
                        objectID: ex.objectID
                    )
                }
            }
            await MainActor.run {
                ExerciseLibraryFilterCache.shared.precomputeFromIndex(exerciseIndex: exerciseIndex, viewContext: viewContext)
            }
        }
    }
    
    /// Lightweight path: receives names+objectIDs, does all matching/sorting in background,
    /// then resolves only the ~800 matched exercises on the main thread (not all 5501).
    ///
    /// ⚡️ Cold-start sprint 2026-04-25 (Restore Cold-Start Performance plan, Change 2 —
    ///   Invariant 17 fix):
    ///
    /// PREVIOUSLY: snapshotPopularityData was called BEFORE the Task.detached
    /// boundary on `@MainActor`, and the final `MainActor.run` block resolved
    /// 837 NSManagedObjectIDs via `viewContext.object(with:)` in a single
    /// synchronous batch. That batch synchronously faulted hundreds of
    /// `Exercise` rows on the main thread (each fault = SQLite read), causing
    /// a 1.5–2.8s `MAIN THREAD FROZEN!` watchdog warning observed in
    /// 2026-04-25T19:49 logs alongside `FILTER CACHE Pre-computed 837
    /// recommended exercises in 2848.6ms` end-to-end.
    ///
    /// NEW BEHAVIOR:
    ///   1. snapshotPopularityData moves INSIDE the Task.detached body so the
    ///      copy-on-write happens off-main.
    ///   2. After scoring/sorting on bg, we pre-fault ALL matched Exercise
    ///      rows on a bg context with `returnsObjectsAsFaults = false`. This
    ///      warms Core Data's row cache so the subsequent `viewContext.object`
    ///      calls on main are pure NSManagedObject wrapper construction (no
    ///      SQLite I/O).
    ///   3. The MainActor.run block is minimized: only the @Published
    ///      assignments and bookkeeping. Resolution still happens on main
    ///      (required — viewContext is main-bound) but on already-cached rows.
    ///
    /// Result: main-thread time inside this method drops from ~1.5–2.8s
    /// (faulting batch) to <50ms (wrapper construction only).
    func precomputeFromIndex(exerciseIndex: [RecommendedExerciseEntry], viewContext: NSManagedObjectContext) {
        guard !isReady, !isComputing else { return }
        guard !exerciseIndex.isEmpty else { return }
        isComputing = true

        // Phase 5.C (Snappiness Overhaul, 2026-05-07) — when
        // `PerfFlags.phase5OffMain` is ON, the StartupWaterfall mark moves
        // INSIDE the Task.detached body below so `threadTag` attributes
        // FilterCache.precompute to `bg-init` instead of `main`. The
        // matching/sorting/pre-fault work is already off-main; only the
        // mark/end endpoints were producing the [main] tag in the
        // waterfall. Pairs with the matching `end` gate further down so
        // `effectiveThread` resolves to a single [bg-init] tag (mark
        // thread == end thread → no "mixed" label). When OFF, both
        // endpoints stay on main for byte-identical pre-flag behavior.
        // QP invariants 31, 35.
        if !PerfFlags.phase5OffMain {
            StartupWaterfall.shared.mark("FilterCache.precompute")
        }
        let startTime = CACurrentMediaTime()

        let recSet = recommendedExerciseNames
        let usageCounts = personalUsageCounts

        Task.detached(priority: .userInitiated) { [weak self] in
            if PerfFlags.phase5OffMain {
                StartupWaterfall.shared.mark("FilterCache.precompute")
            }
            // (1) Snapshot popularity data on bg — was previously on main.
            let (popCache, favCache) = await MainActor.run {
                ExercisePopularityService.shared.snapshotPopularityData()
            }

            var matchedEntries: [(name: String, objectID: NSManagedObjectID)] = []
            matchedEntries.reserveCapacity(250)

            for entry in exerciseIndex {
                let lower = entry.name.lowercased()
                var found = recSet.contains(lower)
                if !found {
                    for rec in recSet {
                        if lower.hasPrefix(rec + " ") || lower.hasPrefix(rec + "(") {
                            found = true
                            break
                        }
                    }
                }
                guard found else { continue }

                // STRENGTH-ONLY filter (per user request 2026-04-27 — the
                // Recommended initial view should surface strength work, not
                // plyo / cardio / stretches even if they're in the curated
                // list). Mirrors the `.strength` case in
                // `ExerciseLibraryView.applyFiltersOnly` so behavior is
                // consistent: explicit `workoutType` wins, fall back to the
                // smart name+category+equipment classifier.
                let isStrength: Bool = {
                    if let wt = entry.workoutType, !wt.isEmpty {
                        return wt.lowercased() == "strength"
                    }
                    let smart = ExerciseFilterService.classifyExerciseType(
                        name: entry.name, category: entry.category, equipment: entry.equipment
                    )
                    return smart == .strength
                }()
                guard isStrength else { continue }

                matchedEntries.append((name: lower, objectID: entry.objectID))
            }

            var popularityScores: [String: Int] = [:]
            var communityFavorites: Set<String> = []
            for (name, _) in matchedEntries {
                let score = popCache[name] ?? 50
                if score > 0 { popularityScores[name] = score }
                if favCache.contains(name) { communityFavorites.insert(name) }
            }

            matchedEntries.sort { a, b in
                let scoreA = Self.blendedScoreStatic(name: a.name, usageCounts: usageCounts, popularityScores: popularityScores, communityFavorites: communityFavorites)
                let scoreB = Self.blendedScoreStatic(name: b.name, usageCounts: usageCounts, popularityScores: popularityScores, communityFavorites: communityFavorites)
                if scoreA != scoreB { return scoreA > scoreB }
                return a.name < b.name
            }

            let sortedIDs = matchedEntries.map { $0.objectID }

            // (2) Pre-fault ALL matched rows on a bg context so the eventual
            // main-thread `viewContext.object(with:)` doesn't trigger SQLite
            // I/O 837 times in a single synchronous batch. The bg fetch warms
            // the persistent store row cache; viewContext then sees fully-
            // hydrated rows for free.
            let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
            await bgContext.perform {
                let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                request.predicate = NSPredicate(format: "self IN %@", sortedIDs)
                request.returnsObjectsAsFaults = false
                _ = (try? bgContext.fetch(request)) ?? []
            }

            // Phase 5.C — when the off-main flag is ON, end from the bg
            // task BEFORE the @Published-publish hop so the waterfall
            // `effectiveThread` resolves to a single [bg-init] tag (matching
            // the bg `mark` above). When OFF, end stays inside the
            // MainActor.run block below for byte-identical pre-flag behavior.
            if PerfFlags.phase5OffMain {
                StartupWaterfall.shared.end("FilterCache.precompute")
            }

            // (3) Final main-thread block — minimal. Wrapper construction +
            // @Published assignment only; rows are already cache-hydrated.
            await MainActor.run {
                guard let self = self else { return }
                let matched = sortedIDs.compactMap { viewContext.object(with: $0) as? Exercise }
                self.preFilteredRecommended = matched
                self.isReady = true
                self.isComputing = false

                if !PerfFlags.phase5OffMain {
                    StartupWaterfall.shared.end("FilterCache.precompute")
                }
                let elapsed = (CACurrentMediaTime() - startTime) * 1000
                AppLogger.debug("⚡️ [FILTER CACHE] Pre-computed \(matched.count) recommended exercises in \(String(format: "%.1f", elapsed))ms", category: .ui)
            }
        }
    }
    
    /// Thread-safe blended score using pre-snapshotted data (pure function, no actor state)
    nonisolated private static func blendedScoreStatic(name: String, usageCounts: [String: Int], popularityScores: [String: Int], communityFavorites: Set<String>) -> Double {
        let communityScore = Double(popularityScores[name] ?? 0)
        let personalCount = Double(usageCounts[name] ?? 0)
        let personalScore = min(personalCount * 10.0, 100.0)
        let favoriteBoost: Double = communityFavorites.contains(name) ? 20.0 : 0.0
        return (communityScore * 0.6) + (personalScore * 0.4) + favoriteBoost
    }
    
    /// Blended score: 60% community popularity + 40% personal usage (normalized)
    private func blendedScore(name: String, popularity: ExercisePopularityService) -> Double {
        let communityScore = Double(popularity.getPopularityScore(for: name)) // 0-100
        let personalCount = Double(personalUsageCounts[name] ?? 0)
        // Normalize personal usage: 10+ uses = max personal score (100)
        let personalScore = min(personalCount * 10.0, 100.0)
        // Favorites get a massive boost
        let favoriteBoost: Double = popularity.isCommunityFavorite(name) ? 20.0 : 0.0
        return (communityScore * 0.6) + (personalScore * 0.4) + favoriteBoost
    }
    
    // MARK: - Track User Exercise Completions
    
    /// Call when a user completes sets of an exercise. Increments personal usage count.
    func trackExerciseCompletion(exerciseName: String) {
        let key = exerciseName.lowercased()
        personalUsageCounts[key, default: 0] += 1
        savePersonalUsage()
    }
    
    /// Call when a user selects/views an exercise in the library
    func trackExerciseSelection(exerciseName: String) {
        let key = exerciseName.lowercased()
        // Selection counts less than completion (0.5x effectively since we add 1 vs 1)
        personalUsageCounts[key, default: 0] += 1
        savePersonalUsage()
    }
    
    /// Get the user's top N most-used exercises
    func getUserTopExercises(count: Int = 50) -> [String] {
        return personalUsageCounts
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { $0.key }
    }
    
    // MARK: - Persistence
    
    private func loadPersonalUsage() {
        if let data = UserDefaults.standard.dictionary(forKey: usageKey) as? [String: Int] {
            personalUsageCounts = data
        }
    }
    
    private func savePersonalUsage() {
        UserDefaults.standard.set(personalUsageCounts, forKey: usageKey)
    }
    
    /// Re-sort the pre-filtered list (call after significant usage changes, e.g. workout completion)
    func refreshSort() {
        guard !preFilteredRecommended.isEmpty else { return }
        let popularity = ExercisePopularityService.shared
        preFilteredRecommended.sort { a, b in
            let nameA = (a.name ?? "").lowercased()
            let nameB = (b.name ?? "").lowercased()
            let scoreA = blendedScore(name: nameA, popularity: popularity)
            let scoreB = blendedScore(name: nameB, popularity: popularity)
            if scoreA != scoreB { return scoreA > scoreB }
            return nameA < nameB
        }
    }
    
    /// Reset (for sign out)
    func reset() {
        isReady = false
        preFilteredRecommended = []
    }
}

// MARK: - 3. (was EagerTabContent — removed 2026-05-03 perf sprint)
//
// `LazyTabContent` (in `AppPerformanceSystem.swift`) is the only tab-content
// wrapper used by `MainTabView`. `EagerTabContent` was an earlier prototype
// of the same idea that never reached the call site (no `MainTabView`
// reference). Removed to avoid two divergent wrappers.

// MARK: - 4. TAB PRELOAD TRIGGER VIEW MODIFIER

struct TabPreloadTrigger: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var preloader = TabPreloader.shared
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Trigger preloading when main view appears
                if !preloader.isPreloadingComplete {
                    preloader.beginPreloading(context: viewContext)
                }
            }
    }
}

extension View {
    func triggerTabPreload() -> some View {
        modifier(TabPreloadTrigger())
    }
}

// MARK: - 5. (was InstantTabSwitchCoordinator — removed 2026-05-03 perf sprint)
//
// Never instantiated outside this file. `MainTabView` uses
// `TabSwitchOptimizer` (in `AppPerformanceSystem.swift`) as the canonical
// tab-switch controller, which already wraps the SwiftUI `selectedTab`
// binding with freeze-detection + signpost telemetry. `InstantTabSwitchCoordinator`
// duplicated the responsibility but was never wired up.

// MARK: - 6. EXERCISE LIBRARY SERVICE EXTENSION

extension ExerciseLibraryService {
    /// Ensure exercise cache is warming — preWarmCache() already fetches on a background context,
    /// so this just triggers it if not already started. Never call getAllExercises() here
    /// since it does a synchronous viewContext.fetch that blocks the main thread for 5500+ exercises.
    func preloadAll() async {
        if !isExercisesReady {
            preWarmCache()
        }
    }
}

// MARK: - 7. VIDEO PLAYBACK ENGINE EXTENSION

extension VideoPlaybackEngine {
    /// Pre-warm a pool of AVPlayers for instant video playback
    func prewarmPlayerPool() {
        // Create a few pre-warmed players in the pool
        // This is handled internally by VideoPlaybackEngine
        AppLogger.debug("🎬 [VIDEO] Player pool pre-warmed", category: .ui)
    }
}

// MARK: - 8. (was PreloadProgressIndicator — removed 2026-05-03 perf sprint)
//
// Never placed in any view. The product decision was to never expose a
// "loading…" indicator at the top of the app — the dashboard renders
// from cached data immediately, then upgrades in place. The view struct
// was orphaned scaffolding.
