import SwiftUI
import CoreData
import Combine

// MARK: - App Performance System (Senior Engineer Grade)
/// Comprehensive performance optimization system for buttery-smooth 120fps experience
/// Built with Apple/Google/Meta best practices: aggressive caching, lazy loading, smart prefetch

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 1. STARTUP CACHE (Pre-warm on app launch)
// ═══════════════════════════════════════════════════════════════════════════════

/// Pre-warms critical data on app startup to eliminate first-load delays
@MainActor
final class StartupCache: ObservableObject {
    static let shared = StartupCache()
    
    // MARK: - Cached Data
    @Published private(set) var isWarmed = false
    @Published private(set) var warmupProgress: Double = 0
    
    // Pre-loaded data
    private(set) var cachedExerciseCount: Int = 0
    private(set) var cachedRecentWorkouts: [NSManagedObjectID] = []
    private(set) var cachedUserStats: CachedUserStats?
    private(set) var cachedCategories: [String] = []
    private(set) var cachedEquipment: [String] = []
    private(set) var cachedMuscleGroups: [String] = []
    
    // Cache timestamps for staleness detection
    private var lastWarmTime: Date?
    private var cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    struct CachedUserStats {
        let totalWorkouts: Int
        let currentStreak: Int
        let longestStreak: Int
        let xp: Int
        let lastWorkoutDate: Date?
        
        // Level is computed from XP
        var userLevel: Int { (xp / 100) + 1 }
    }
    
    private init() {}
    
    // MARK: - Warm Up (Call from Fit33App.swift)
    
    /// Call this early in app lifecycle to pre-warm caches
    func warmUp(context: NSManagedObjectContext) async {
        guard !isWarmed || isCacheStale else { return }
        
        let startTime = CACurrentMediaTime()
        print("🚀 [STARTUP CACHE] Beginning warm-up...")
        
        // Stage 1: User stats (fastest, most critical)
        await warmUserStats(context: context)
        warmupProgress = 0.25
        
        // Stage 2: Exercise metadata (categories, equipment)
        await warmExerciseMetadata(context: context)
        warmupProgress = 0.50
        
        // Stage 3: Recent workouts (IDs only, not full objects)
        await warmRecentWorkouts(context: context)
        warmupProgress = 0.75
        
        // Stage 4: Exercise count
        await warmExerciseCount(context: context)
        warmupProgress = 1.0
        
        lastWarmTime = Date()
        isWarmed = true
        
        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        print("🚀 [STARTUP CACHE] Warm-up complete in \(String(format: "%.1f", elapsed))ms")
    }
    
    private var isCacheStale: Bool {
        guard let lastTime = lastWarmTime else { return true }
        return Date().timeIntervalSince(lastTime) > cacheValidityDuration
    }
    
    // MARK: - Individual Warm Functions
    // Note: These run on MainActor with the viewContext, which is safe for reads
    
    private func warmUserStats(context: NSManagedObjectContext) async {
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        do {
            if let user = try context.fetch(fetchRequest).first {
                self.cachedUserStats = CachedUserStats(
                    totalWorkouts: Int(user.totalWorkouts),
                    currentStreak: Int(user.currentStreak),
                    longestStreak: Int(user.longestStreak),
                    xp: Int(user.xp),
                    lastWorkoutDate: user.lastWorkoutDate
                )
            }
        } catch {
            print("⚠️ [STARTUP CACHE] User stats warm failed: \(error)")
        }
    }
    
    private func warmExerciseMetadata(context: NSManagedObjectContext) async {
        // Get unique categories
        let categoryRequest: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "Exercise")
        categoryRequest.resultType = .dictionaryResultType
        categoryRequest.propertiesToFetch = ["category"]
        categoryRequest.returnsDistinctResults = true
        
        do {
            let results = try context.fetch(categoryRequest)
            self.cachedCategories = results.compactMap { $0["category"] as? String }.sorted()
        } catch {
            print("⚠️ [STARTUP CACHE] Categories warm failed: \(error)")
        }
        
        // Get unique equipment
        let equipmentRequest: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "Exercise")
        equipmentRequest.resultType = .dictionaryResultType
        equipmentRequest.propertiesToFetch = ["equipment"]
        equipmentRequest.returnsDistinctResults = true
        
        do {
            let results = try context.fetch(equipmentRequest)
            self.cachedEquipment = results.compactMap { $0["equipment"] as? String }.sorted()
        } catch {
            print("⚠️ [STARTUP CACHE] Equipment warm failed: \(error)")
        }
        
        // Muscle groups are static, cache them directly
        self.cachedMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", 
                                   "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", 
                                   "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques"]
    }
    
    private func warmRecentWorkouts(context: NSManagedObjectContext) async {
        let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        fetchRequest.fetchLimit = 20
        fetchRequest.predicate = NSPredicate(format: "isCompleted == true")
        
        do {
            let workouts = try context.fetch(fetchRequest)
            self.cachedRecentWorkouts = workouts.map { $0.objectID }
        } catch {
            print("⚠️ [STARTUP CACHE] Workouts warm failed: \(error)")
        }
    }
    
    private func warmExerciseCount(context: NSManagedObjectContext) async {
        let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        do {
            self.cachedExerciseCount = try context.count(for: fetchRequest)
        } catch {
            print("⚠️ [STARTUP CACHE] Exercise count warm failed: \(error)")
        }
    }
    
    // MARK: - Invalidation
    
    func invalidate() {
        lastWarmTime = nil
        isWarmed = false
    }
    
    func invalidateWorkouts() {
        cachedRecentWorkouts = []
    }
    
    func invalidateUserStats() {
        cachedUserStats = nil
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 2. LAZY TAB MANAGER (Eager Mode for Instant Switching)
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages tab initialization - supports both lazy and eager (preloaded) modes
/// When eager mode is enabled, all tabs are pre-initialized for instant switching
@MainActor
final class LazyTabManager: ObservableObject {
    static let shared = LazyTabManager()
    
    enum Tab: Int, CaseIterable {
        case dashboard = 0
        case exercises = 1
        case workout = 2
        case nutrition = 3
        case progress = 4
    }
    
    // Track which tabs have been visited (and thus initialized)
    @Published private(set) var visitedTabs: Set<Tab> = [.dashboard] // Dashboard always loaded
    @Published var selectedTab: Tab = .dashboard
    
    // ⚡️ EAGER MODE: When true, all tabs render immediately (no placeholders)
    @Published private(set) var isEagerModeEnabled: Bool = false
    
    // Pre-render hints (user is likely to visit these tabs soon)
    private var hintedTabs: Set<Tab> = []
    
    // Track when eager preloading started
    private var eagerPreloadStartTime: CFTimeInterval = 0
    
    private init() {}
    
    /// Mark a tab as visited (triggers lazy load)
    func markVisited(_ tab: Tab) {
        if !visitedTabs.contains(tab) {
            visitedTabs.insert(tab)
            print("📱 [LAZY TAB] Tab \(tab) initialized on first visit")
        }
    }
    
    /// Check if a tab should render its full content
    func shouldRenderContent(for tab: Tab) -> Bool {
        // In eager mode, always render all tabs
        if isEagerModeEnabled {
            return true
        }
        return visitedTabs.contains(tab) || hintedTabs.contains(tab)
    }
    
    /// Hint that user might visit a tab soon (e.g., hover, swipe gesture)
    func hintTab(_ tab: Tab) {
        if !visitedTabs.contains(tab) {
            hintedTabs.insert(tab)
            
            // Pre-render after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                if self.hintedTabs.contains(tab) {
                    self.visitedTabs.insert(tab)
                    print("📱 [LAZY TAB] Tab \(tab) pre-rendered from hint")
                }
            }
        }
    }
    
    // MARK: - Eager Mode (Pre-initialize ALL tabs)
    
    /// Enable eager mode - pre-initializes all tabs for instant switching
    /// Call this after startup cache is warmed
    func enableEagerMode() {
        guard !isEagerModeEnabled else { return }
        
        eagerPreloadStartTime = CACurrentMediaTime()
        
        // Mark all tabs as ready to render
        isEagerModeEnabled = true
        
        // Pre-initialize all tabs in sequence with tiny delays
        // This spreads the work across multiple frames
        for (index, tab) in Tab.allCases.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) { [weak self] in
                self?.visitedTabs.insert(tab)
            }
        }
        
        let elapsed = (CACurrentMediaTime() - eagerPreloadStartTime) * 1000
        print("⚡️ [EAGER MODE] Enabled - all tabs will render immediately (\(String(format: "%.1f", elapsed))ms)")
    }
    
    /// Pre-warm all tabs immediately (synchronous version for startup)
    func preWarmAllTabs() {
        isEagerModeEnabled = true
        visitedTabs = Set(Tab.allCases)
        print("⚡️ [EAGER MODE] All tabs pre-warmed synchronously")
    }
    
    /// Reset (for testing or sign out)
    func reset() {
        visitedTabs = [.dashboard]
        hintedTabs = []
        selectedTab = .dashboard
        isEagerModeEnabled = false
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 3. VIEW STATE CACHE (Preserve state across tab switches)
// ═══════════════════════════════════════════════════════════════════════════════

/// Caches view state to prevent expensive recomputation on tab switches
@MainActor
final class ViewStateCache: ObservableObject {
    static let shared = ViewStateCache()
    
    // MARK: - Dashboard State
    struct DashboardState {
        var scrollOffset: CGFloat = 0
        var lastRecommendation: String?
        var lastMotivationalMessage: String = ""
        var combinedWorkoutsComputed: Bool = false
    }
    var dashboardState = DashboardState()
    
    // MARK: - Exercise Library State
    struct ExerciseLibraryState {
        var searchText: String = ""
        var selectedCategory: String = "All"
        var selectedEquipment: String = "All"
        var selectedMuscleGroup: String = "All"
        var scrollPosition: String? // ID of exercise to scroll to
        var filteredExerciseIDs: [NSManagedObjectID] = []
        var lastFilterHash: String = ""
    }
    var exerciseLibraryState = ExerciseLibraryState()
    
    // MARK: - Workout Tab State
    struct WorkoutTabState {
        var lastNavigationPath: [String] = []
        var forceRenderID: UUID = UUID()
    }
    var workoutTabState = WorkoutTabState()
    
    // MARK: - Progress State
    struct ProgressState {
        var cachedAchievements: [String: Bool] = [:] // achievement_id -> isEarned
        var selectedTimeRange: Int = 0 // 0 = week, 1 = month, 2 = year
        var scrollOffset: CGFloat = 0
    }
    var progressState = ProgressState()
    
    // MARK: - Nutrition State
    struct NutritionState {
        var selectedDate: Date = Date()
        var expandedMeals: Set<String> = []
        var dailyTotals: (calories: Int, protein: Int, carbs: Int, fat: Int)?
    }
    var nutritionState = NutritionState()
    
    private init() {}
    
    func clearAll() {
        dashboardState = DashboardState()
        exerciseLibraryState = ExerciseLibraryState()
        workoutTabState = WorkoutTabState()
        progressState = ProgressState()
        nutritionState = NutritionState()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 4. SMART PREFETCH (Predictive data loading)
// ═══════════════════════════════════════════════════════════════════════════════

/// Predicts which data the user needs next and prefetches it
@MainActor
final class SmartPrefetch: ObservableObject {
    static let shared = SmartPrefetch()
    
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private var prefetchedData: [String: Any] = [:]
    
    private init() {}
    
    // MARK: - Tab-Based Prefetch
    
    /// Call when user shows intent to visit a tab (gesture, hover)
    func prefetchForTab(_ tab: LazyTabManager.Tab) {
        switch tab {
        case .exercises:
            prefetchExerciseLibrary()
        case .progress:
            prefetchProgressData()
        case .nutrition:
            prefetchNutritionData()
        default:
            break
        }
    }
    
    private func prefetchExerciseLibrary() {
        guard prefetchTasks["exercises"] == nil else { return }
        
        prefetchTasks["exercises"] = Task(priority: .userInitiated) {
            // Pre-load exercise categories and counts on main actor (viewContext is main thread)
            await MainActor.run {
                let context = PersistenceController.shared.container.viewContext
                let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                fetchRequest.fetchLimit = 100 // First batch
                fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
                
                do {
                    let exercises = try context.fetch(fetchRequest)
                    self.prefetchedData["exercises_first_batch"] = exercises.map { $0.objectID }
                } catch {
                    print("⚠️ [PREFETCH] Exercise prefetch failed: \(error)")
                }
            }
            
            self.prefetchTasks["exercises"] = nil
        }
    }
    
    private func prefetchProgressData() {
        guard prefetchTasks["progress"] == nil else { return }
        
        prefetchTasks["progress"] = Task(priority: .background) {
            // Pre-compute achievement states (expensive operation)
            if let stats = StartupCache.shared.cachedUserStats {
                let _ = AchievementService.shared.generateAllAchievements(
                    totalWorkouts: stats.totalWorkouts,
                    currentStreak: stats.currentStreak,
                    longestStreak: stats.longestStreak,
                    heaviestWeight: 0, // Will be updated
                    highestReps: 0,
                    longestWorkoutMinutes: 0,
                    mostSetsInWorkout: 0,
                    workoutsThisMonth: 0,
                    userLevel: stats.userLevel,
                    userXP: stats.xp
                )
            }
            
            self.prefetchTasks["progress"] = nil
        }
    }
    
    private func prefetchNutritionData() {
        // Nutrition prefetch is handled by the view itself
        // No additional prefetch needed here
    }
    
    // MARK: - Retrieve Prefetched Data
    
    func getPrefetchedExercises() -> [NSManagedObjectID]? {
        return prefetchedData["exercises_first_batch"] as? [NSManagedObjectID]
    }
    
    func clearPrefetchCache() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        prefetchedData.removeAll()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 5. RENDER COALESCER (Batch state updates)
// ═══════════════════════════════════════════════════════════════════════════════

/// Batches multiple state updates into single render passes
final class RenderCoalescer {
    static let shared = RenderCoalescer()
    
    private var pendingUpdates: [() -> Void] = []
    private var isScheduled = false
    private let queue = DispatchQueue(label: "com.fit33.renderCoalescer", qos: .userInteractive)
    
    private init() {}
    
    /// Schedule a state update to be batched
    func scheduleUpdate(_ update: @escaping @MainActor () -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.pendingUpdates.append {
                Task { @MainActor in
                    update()
                }
            }
            
            if !self.isScheduled {
                self.isScheduled = true
                
                // Batch updates in next run loop
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Execute all pending updates in one transaction
                    let updates = self.queue.sync {
                        let u = self.pendingUpdates
                        self.pendingUpdates = []
                        self.isScheduled = false
                        return u
                    }
                    
                    // Single withAnimation block for all updates
                    withAnimation(.none) {
                        updates.forEach { $0() }
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 6. MEMOIZED COMPUTATIONS (Cache expensive operations)
// ═══════════════════════════════════════════════════════════════════════════════

/// Thread-safe memoization cache for expensive computed properties
actor ComputationCache {
    static let shared = ComputationCache()
    
    private var cache: [String: CacheEntry] = [:]
    private let maxEntries = 50
    
    struct CacheEntry {
        let value: Any
        let timestamp: Date
        let ttl: TimeInterval
        
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }
    
    func get<T>(_ key: String) -> T? {
        guard let entry = cache[key], entry.isValid else {
            return nil
        }
        return entry.value as? T
    }
    
    func set<T>(_ key: String, value: T, ttl: TimeInterval = 60) {
        // Evict oldest entries if at capacity
        if cache.count >= maxEntries {
            let oldestKey = cache.min { $0.value.timestamp < $1.value.timestamp }?.key
            if let key = oldestKey {
                cache.removeValue(forKey: key)
            }
        }
        
        cache[key] = CacheEntry(value: value, timestamp: Date(), ttl: ttl)
    }
    
    func invalidate(_ key: String) {
        cache.removeValue(forKey: key)
    }
    
    func invalidateAll() {
        cache.removeAll()
    }
}

// MARK: - Memoize Property Wrapper

@propertyWrapper
struct Memoized<Value> {
    private let key: String
    private let ttl: TimeInterval
    private let compute: () -> Value
    
    init(key: String, ttl: TimeInterval = 60, compute: @escaping () -> Value) {
        self.key = key
        self.ttl = ttl
        self.compute = compute
    }
    
    var wrappedValue: Value {
        // For now, always compute (actor access is async)
        // In production, use a sync cache or Task
        return compute()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 7. TAB SWITCH OPTIMIZER
// ═══════════════════════════════════════════════════════════════════════════════

/// Optimizes tab switch performance
@MainActor
final class TabSwitchOptimizer: ObservableObject {
    static let shared = TabSwitchOptimizer()
    
    @Published private(set) var isTransitioning = false
    private var transitionStartTime: CFTimeInterval = 0
    
    private init() {}
    
    /// Call when tab switch begins
    func beginTransition(from: Int, to: Int) {
        transitionStartTime = CACurrentMediaTime()
        isTransitioning = true
        
        // Prepare destination tab
        if let tab = LazyTabManager.Tab(rawValue: to) {
            LazyTabManager.shared.markVisited(tab)
            SmartPrefetch.shared.prefetchForTab(tab)
        }
        
        // Haptic feedback (already warm from HapticManager)
        HapticManager.selectionChanged()
    }
    
    /// Call when tab switch animation completes
    func endTransition() {
        let elapsed = (CACurrentMediaTime() - transitionStartTime) * 1000
        isTransitioning = false
        
        #if DEBUG
        // Note: Humans perceive <200ms as "instant", <500ms as "fast"
        // Only warn if transition takes longer than 300ms (noticeable delay)
        if elapsed > 300 {
            print("⚠️ [TAB SWITCH] Slow transition: \(String(format: "%.1f", elapsed))ms")
        } else if elapsed > 150 {
            print("🟡 [TAB SWITCH] Transition: \(String(format: "%.1f", elapsed))ms")
        } else {
            print("✅ [TAB SWITCH] Fast transition: \(String(format: "%.1f", elapsed))ms")
        }
        #endif
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 8. FETCH REQUEST OPTIMIZER
// ═══════════════════════════════════════════════════════════════════════════════

/// Optimized fetch request helpers that minimize main thread work
enum FetchOptimizer {
    
    /// Create a non-animated fetch request (prevents UI stutters)
    static func optimizedWorkoutFetch(limit: Int = 20) -> NSFetchRequest<Workout> {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        request.fetchLimit = limit
        request.predicate = NSPredicate(format: "isCompleted == true")
        request.returnsObjectsAsFaults = true // Lazy load properties
        request.includesPropertyValues = false // Don't pre-fetch all properties
        return request
    }
    
    /// Create optimized exercise fetch
    static func optimizedExerciseFetch(limit: Int = 100) -> NSFetchRequest<Exercise> {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        request.fetchLimit = limit
        request.returnsObjectsAsFaults = true
        // Only fetch properties needed for list display
        request.propertiesToFetch = ["name", "category", "equipment"]
        return request
    }
    
    /// Perform fetch in background and return IDs
    static func backgroundFetch<T: NSManagedObject>(
        request: NSFetchRequest<T>,
        context: NSManagedObjectContext
    ) async -> [NSManagedObjectID] {
        await withCheckedContinuation { continuation in
            context.perform {
                do {
                    let results = try context.fetch(request)
                    continuation.resume(returning: results.map { $0.objectID })
                } catch {
                    print("⚠️ [FETCH] Background fetch failed: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 9. VIEW EXTENSIONS FOR PERFORMANCE
// ═══════════════════════════════════════════════════════════════════════════════

/// Lazy loading wrapper for tab content - supports both lazy and eager modes
/// In eager mode: Views are always rendered (no placeholder)
/// In lazy mode: Views only render when first visited
struct LazyTabContent<Content: View>: View {
    let tab: LazyTabManager.Tab
    let content: () -> Content
    
    @StateObject private var lazyTabManager = LazyTabManager.shared
    @StateObject private var tabPreloader = TabPreloader.shared
    @State private var hasInitialized = false
    
    init(tab: LazyTabManager.Tab, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.content = content
    }
    
    var body: some View {
        Group {
            // ⚡️ EAGER MODE: Always render content immediately when preloading is complete
            if tabPreloader.isPreloadingComplete || lazyTabManager.isEagerModeEnabled || hasInitialized {
                content()
                    .onAppear {
                        hasInitialized = true
                        lazyTabManager.markVisited(tab)
                    }
            } else if lazyTabManager.shouldRenderContent(for: tab) {
                // Tab was explicitly visited or hinted
                content()
                    .onAppear {
                        hasInitialized = true
                    }
            } else {
                // Lightweight placeholder - show VERY briefly while initializing
                TabPlaceholderView(tab: tab)
                    .onAppear {
                        // Initialize immediately - no delay
                        hasInitialized = true
                        lazyTabManager.markVisited(tab)
                    }
            }
        }
    }
}

/// Lightweight placeholder shown briefly while tab initializes
struct TabPlaceholderView: View {
    let tab: LazyTabManager.Tab
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Match the background of each tab
            backgroundForTab
                .ignoresSafeArea()
            
            // Optional: subtle loading indicator
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .gray.opacity(0.5)))
                .scaleEffect(0.8)
        }
    }
    
    @ViewBuilder
    private var backgroundForTab: some View {
        switch tab {
        case .dashboard:
            AdaptiveGradient.home(for: colorScheme)
        case .exercises:
            AdaptiveGradient.exercises(for: colorScheme)
        case .workout:
            AdaptiveGradient.workout(for: colorScheme)
        case .nutrition:
            AdaptiveGradient.meals(for: colorScheme)
        case .progress:
            AdaptiveGradient.stats(for: colorScheme)
        }
    }
}

extension View {
    /// Only render content if tab has been visited (lazy loading)
    @ViewBuilder
    func lazyTab(_ tab: LazyTabManager.Tab) -> some View {
        if LazyTabManager.shared.shouldRenderContent(for: tab) {
            self
        } else {
            // Placeholder while not yet visited
            Color.clear
                .onAppear {
                    LazyTabManager.shared.markVisited(tab)
                }
        }
    }
    
    /// Debounced task that won't run on every appear
    func debouncedTask(
        id: String,
        debounce: TimeInterval = 0.5,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping () async -> Void
    ) -> some View {
        self.task(id: id, priority: priority) {
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            if !Task.isCancelled {
                await action()
            }
        }
    }
    
    /// Optimized for tab content - reduces unnecessary updates
    /// ⚡️ Enhanced: Also disables animation when tabs are preloaded for instant switching
    func tabContentOptimized() -> some View {
        self
            .transaction { transaction in
                // Disable animations during tab switch OR when preloading is complete for instant feel
                if TabSwitchOptimizer.shared.isTransitioning || TabPreloader.shared.isPreloadingComplete {
                    transaction.animation = nil
                }
            }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 10. ISO8601 PARSER
// Note: ISO8601Parser is defined in SharedUtilities.swift - use that instead
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 11. PERFORMANCE METRICS (Debug)
// ═══════════════════════════════════════════════════════════════════════════════

#if DEBUG
@MainActor
final class PerformanceMetrics: ObservableObject {
    static let shared = PerformanceMetrics()
    
    struct TabMetrics {
        var firstLoadTime: CFTimeInterval = 0
        var avgSwitchTime: CFTimeInterval = 0
        var switchCount: Int = 0
    }
    
    private var tabMetrics: [Int: TabMetrics] = [:]
    private var currentTabStart: CFTimeInterval = 0
    
    func startTabLoad(_ tab: Int) {
        currentTabStart = CACurrentMediaTime()
    }
    
    func endTabLoad(_ tab: Int, isFirstLoad: Bool) {
        let elapsed = CACurrentMediaTime() - currentTabStart
        
        if tabMetrics[tab] == nil {
            tabMetrics[tab] = TabMetrics()
        }
        
        if isFirstLoad {
            tabMetrics[tab]?.firstLoadTime = elapsed
            print("📊 [PERF] Tab \(tab) first load: \(String(format: "%.1f", elapsed * 1000))ms")
        } else {
            let existing = tabMetrics[tab]!
            let newAvg = (existing.avgSwitchTime * Double(existing.switchCount) + elapsed) / Double(existing.switchCount + 1)
            tabMetrics[tab]?.avgSwitchTime = newAvg
            tabMetrics[tab]?.switchCount += 1
            
            if elapsed * 1000 > 50 {
                print("⚠️ [PERF] Tab \(tab) slow switch: \(String(format: "%.1f", elapsed * 1000))ms")
            }
        }
    }
    
    func printSummary() {
        print("\n📊 === PERFORMANCE SUMMARY ===")
        for (tab, metrics) in tabMetrics.sorted(by: { $0.key < $1.key }) {
            print("Tab \(tab): First=\(String(format: "%.1f", metrics.firstLoadTime * 1000))ms, Avg=\(String(format: "%.1f", metrics.avgSwitchTime * 1000))ms (\(metrics.switchCount) switches)")
        }
        print("==============================\n")
    }
}
#endif
