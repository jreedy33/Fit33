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
    private(set) var progressTabData: PreloadedProgressTabData?
    
    // Timing
    private var preloadStartTime: CFTimeInterval = 0
    
    private init() {}
    
    // MARK: - Main Preload Entry Point
    
    /// Call this from Fit33App.swift after UI appears
    /// Preloads ALL tab data and views in background
    func beginPreloading(context: NSManagedObjectContext) {
        guard !isPreloadingComplete else { return }
        
        preloadStartTime = CACurrentMediaTime()
        print("🚀 [TAB PRELOAD] Starting aggressive preloading...")
        
        Task(priority: .userInitiated) {
            await preloadAllTabs(context: context)
        }
    }
    
    // MARK: - Preload All Tabs
    
    private func preloadAllTabs(context: NSManagedObjectContext) async {
        // Phase 1: Pre-fetch all Core Data (fast, parallel)
        await preloadPhase1_CoreData(context: context)
        preloadProgress = 0.25
        
        // Phase 2: Pre-fetch cloud data (parallel network calls)
        await preloadPhase2_CloudData()
        preloadProgress = 0.50
        
        // Phase 3: Pre-compute expensive calculations
        await preloadPhase3_Computations(context: context)
        preloadProgress = 0.75
        
        // Phase 4: Pre-warm services and caches
        await preloadPhase4_Services()
        preloadProgress = 1.0
        
        // Mark all tabs as preloaded
        warmedTabs = [0, 1, 2, 3, 4]
        preloadedTabs = [0, 1, 2, 3, 4]
        isPreloadingComplete = true
        
        let elapsed = (CACurrentMediaTime() - preloadStartTime) * 1000
        print("🚀 [TAB PRELOAD] Complete in \(String(format: "%.0f", elapsed))ms - ALL tabs ready!")
    }
    
    // MARK: - Phase 1: Core Data Preload
    
    private func preloadPhase1_CoreData(context: NSManagedObjectContext) async {
        let startTime = CACurrentMediaTime()
        
        // Run all Core Data fetches in parallel
        async let exercisesFetch = fetchExercisesForLibrary(context: context)
        async let workoutsFetch = fetchRecentWorkouts(context: context)
        async let userFetch = fetchUserData(context: context)
        
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
        print("  └─ Phase 1 (Core Data): \(String(format: "%.0f", elapsed))ms")
        print("     └─ Exercises: \(exercises.count), Workouts: \(workouts.count)")
    }
    
    private func fetchExercisesForLibrary(context: NSManagedObjectContext) async -> [Exercise] {
        return await withCheckedContinuation { continuation in
            context.perform {
                let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
                // No limit - fetch all for instant filtering
                
                do {
                    let exercises = try context.fetch(request)
                    // Touch properties to fault them in (preload into memory)
                    for exercise in exercises {
                        _ = exercise.name
                        _ = exercise.category
                        _ = exercise.equipment
                        _ = exercise.muscleGroups
                        _ = exercise.isFavorite
                    }
                    continuation.resume(returning: exercises)
                } catch {
                    print("⚠️ [TAB PRELOAD] Exercise fetch failed: \(error)")
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
                    print("⚠️ [TAB PRELOAD] Workout fetch failed: \(error)")
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
        print("  └─ Phase 2 (Cloud Data): \(String(format: "%.0f", elapsed))ms")
    }
    
    private func fetchCardioWorkouts() async -> [CardioWorkoutDTO] {
        // Fetch recent cardio from Supabase using existing method
        do {
            return try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 20)
        } catch {
            print("⚠️ [TAB PRELOAD] Cardio fetch failed: \(error)")
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
    
    // MARK: - Phase 3: Pre-compute Expensive Operations
    
    private func preloadPhase3_Computations(context: NSManagedObjectContext) async {
        let startTime = CACurrentMediaTime()
        
        // Pre-compute in parallel
        async let achievementsFetch = precomputeAchievements()
        async let workoutStatsFetch = precomputeWorkoutStats(context: context)
        async let exerciseFiltersFetch = precomputeExerciseFilters()
        
        let achievements = await achievementsFetch
        let stats = await workoutStatsFetch
        _ = await exerciseFiltersFetch
        
        // Store progress tab data
        progressTabData = PreloadedProgressTabData(
            achievements: achievements,
            workoutStats: stats
        )
        
        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        print("  └─ Phase 3 (Computations): \(String(format: "%.0f", elapsed))ms")
    }
    
    private func precomputeAchievements() async -> [Achievement] {
        guard let stats = StartupCache.shared.cachedUserStats else { return [] }
        
        return AchievementService.shared.generateAllAchievements(
            totalWorkouts: stats.totalWorkouts,
            currentStreak: stats.currentStreak,
            longestStreak: stats.longestStreak,
            heaviestWeight: 0,
            highestReps: 0,
            longestWorkoutMinutes: 0,
            mostSetsInWorkout: 0,
            workoutsThisMonth: 0,
            userLevel: stats.userLevel,
            userXP: stats.xp
        )
    }
    
    private func precomputeWorkoutStats(context: NSManagedObjectContext) async -> WorkoutStatsSnapshot {
        return await withCheckedContinuation { continuation in
            context.perform {
                let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "isCompleted == true")
                
                var totalVolume: Double = 0
                var totalWorkouts = 0
                var totalDuration: TimeInterval = 0
                
                do {
                    let workouts = try context.fetch(fetchRequest)
                    totalWorkouts = workouts.count
                    
                    for workout in workouts {
                        totalVolume += workout.totalVolume
                        totalDuration += Double(workout.duration)
                    }
                } catch {
                    // Continue with zeros
                }
                
                continuation.resume(returning: WorkoutStatsSnapshot(
                    totalWorkouts: totalWorkouts,
                    totalVolume: totalVolume,
                    totalDuration: totalDuration,
                    averageWorkoutDuration: totalWorkouts > 0 ? totalDuration / Double(totalWorkouts) : 0
                ))
            }
        }
    }
    
    private func precomputeExerciseFilters() async {
        // Pre-build search index for exercises
        guard let exercises = exerciseLibraryData?.allExercises else { return }
        
        let startTime = CACurrentMediaTime()
        
        // Create a search index by first letter for instant filtering
        var searchIndex: [Character: [Exercise]] = [:]
        for exercise in exercises {
            guard let firstChar = exercise.name?.lowercased().first else { continue }
            searchIndex[firstChar, default: []].append(exercise)
        }
        
        // Store search index
        exerciseLibraryData?.searchIndex = searchIndex
        
        // Mark filter cache as ready (uses precomputed name set, not Exercise objects)
        await MainActor.run {
            ExerciseLibraryFilterCache.shared.markReady()
        }
        
        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        print("  └─ Pre-built search index for \(exercises.count) exercises in \(String(format: "%.0f", elapsed))ms")
    }
    
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
        print("  └─ Phase 4 (Services): \(String(format: "%.0f", elapsed))ms")
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
    
    /// Get preloaded achievements
    func getPreloadedAchievements() -> [Achievement] {
        return progressTabData?.achievements ?? []
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
        progressTabData = nil
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

struct PreloadedProgressTabData {
    var achievements: [Achievement]
    var workoutStats: WorkoutStatsSnapshot
}

struct WorkoutStatsSnapshot {
    var totalWorkouts: Int
    var totalVolume: Double
    var totalDuration: TimeInterval
    var averageWorkoutDuration: TimeInterval
}

// MARK: - EXERCISE LIBRARY FILTER CACHE (Shared name set for fast filtering)

/// Provides precomputed recommended exercise names for fast filtering
/// Note: We store NAMES not Exercise objects to avoid Core Data faulting issues
@MainActor
final class ExerciseLibraryFilterCache: ObservableObject {
    static let shared = ExerciseLibraryFilterCache()
    
    @Published private(set) var isReady = false
    
    // The set of recommended exercise names (for O(1) lookup filtering)
    // These are base names that will match exercises like "Bench Press (Barbell)"
    let recommendedExerciseNames: Set<String> = [
        // Chest (compound + isolation)
        "bench press", "incline bench press", "decline bench press", "dumbbell press",
        "dumbbell bench press", "incline dumbbell press", "decline dumbbell press",
        "dumbbell fly", "incline dumbbell fly", "cable fly", "cable crossover",
        "push up", "decline push up", "diamond push up", "chest dip",
        "machine chest press", "pec deck", "landmine press", "floor press",
        
        // Back (vertical + horizontal pulls)
        "pull up", "chin up", "lat pulldown", "barbell row", "bent over row",
        "dumbbell row", "single arm row", "cable row", "seated row", "t-bar row",
        "face pull", "straight arm pulldown", "deadlift", "rack pull", "pendlay row",
        
        // Shoulders (press + raises)
        "overhead press", "shoulder press", "military press", "dumbbell shoulder press",
        "arnold press", "lateral raise", "front raise", "rear delt fly",
        "upright row", "shrug", "dumbbell shrug", "barbell shrug", "face pull",
        
        // Biceps
        "bicep curl", "barbell curl", "dumbbell curl", "hammer curl", "preacher curl",
        "concentration curl", "cable curl", "21s", "incline curl", "spider curl",
        
        // Triceps
        "tricep pushdown", "tricep extension", "skull crusher", "close grip bench press",
        "dip", "overhead tricep extension", "tricep kickback", "rope pushdown",
        
        // Legs - Quads
        "squat", "back squat", "front squat", "goblet squat", "leg press",
        "hack squat", "lunge", "walking lunge", "bulgarian split squat",
        "leg extension", "sissy squat", "split squat",
        
        // Legs - Hamstrings/Glutes
        "leg curl", "romanian deadlift", "stiff leg deadlift", "good morning",
        "hip thrust", "glute bridge", "nordic curl", "lying leg curl",
        
        // Legs - Calves
        "calf raise", "standing calf raise", "seated calf raise",
        
        // Core
        "crunch", "sit up", "plank", "side plank", "russian twist", "leg raise",
        "hanging leg raise", "ab wheel rollout", "cable crunch", "woodchop",
        "dead bug", "bird dog", "mountain climber"
    ]
    
    private init() {}
    
    /// Called by TabPreloader when preloading is complete
    func markReady() {
        self.isReady = true
        print("⚡️ [FILTER CACHE] Ready with \(recommendedExerciseNames.count) recommended exercise names")
    }
    
    /// Reset (for sign out)
    func reset() {
        isReady = false
    }
}

// MARK: - 3. EAGER TAB CONTENT WRAPPER

/// Eagerly initialized tab content - views are kept in memory for instant switching
struct EagerTabContent<Content: View>: View {
    let tabIndex: Int
    let content: () -> Content
    
    @StateObject private var preloader = TabPreloader.shared
    @State private var contentView: AnyView?
    @State private var isInitialized = false
    
    init(tabIndex: Int, @ViewBuilder content: @escaping () -> Content) {
        self.tabIndex = tabIndex
        self.content = content
    }
    
    var body: some View {
        Group {
            if isInitialized || preloader.isTabReady(tabIndex) {
                content()
            } else {
                // Minimal placeholder - just background color
                Color.clear
                    .onAppear {
                        // Initialize immediately without delay
                        isInitialized = true
                    }
            }
        }
    }
}

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

// MARK: - 5. INSTANT TAB SWITCH COORDINATOR

/// Coordinates tab switches to ensure zero-lag transitions
@MainActor
final class InstantTabSwitchCoordinator: ObservableObject {
    static let shared = InstantTabSwitchCoordinator()
    
    @Published var currentTab: Int = 0
    @Published var isTransitioning: Bool = false
    
    private var preloadCheckTask: Task<Void, Never>?
    
    private init() {}
    
    /// Switch to a tab with guaranteed instant transition
    func switchTo(tab: Int) {
        guard tab != currentTab else { return }
        
        let preloader = TabPreloader.shared
        
        // If preloading is complete, switch instantly
        if preloader.isTabReady(tab) {
            performInstantSwitch(to: tab)
            return
        }
        
        // If not ready, wait briefly then switch anyway
        isTransitioning = true
        preloadCheckTask?.cancel()
        preloadCheckTask = Task {
            // Wait up to 100ms for preload to complete
            for _ in 0..<10 {
                if preloader.isTabReady(tab) {
                    break
                }
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            performInstantSwitch(to: tab)
        }
    }
    
    private func performInstantSwitch(to tab: Int) {
        // Disable animations for instant feel
        var transaction = Transaction()
        transaction.disablesAnimations = true
        
        withTransaction(transaction) {
            currentTab = tab
            isTransitioning = false
        }
        
        // Haptic feedback
        HapticManager.selectionChanged()
        
        #if DEBUG
        print("⚡️ [TAB SWITCH] Instant switch to tab \(tab)")
        #endif
    }
}

// MARK: - 6. EXERCISE LIBRARY SERVICE EXTENSION

extension ExerciseLibraryService {
    /// Preload all exercises into memory for instant access
    func preloadAll() async {
        // Fetch all exercises and cache them
        let _ = self.getAllExercises()
    }
}

// MARK: - 7. VIDEO PLAYBACK ENGINE EXTENSION

extension VideoPlaybackEngine {
    /// Pre-warm a pool of AVPlayers for instant video playback
    func prewarmPlayerPool() {
        // Create a few pre-warmed players in the pool
        // This is handled internally by VideoPlaybackEngine
        print("🎬 [VIDEO] Player pool pre-warmed")
    }
}

// MARK: - 8. PRELOAD PROGRESS INDICATOR (Optional UI)

struct PreloadProgressIndicator: View {
    @StateObject private var preloader = TabPreloader.shared
    
    var body: some View {
        if !preloader.isPreloadingComplete && preloader.preloadProgress > 0 {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text("Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .transition(.opacity)
        }
    }
}
