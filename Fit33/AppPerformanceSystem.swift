import SwiftUI
import CoreData
import Combine
import MetricKit

// MARK: - MetricKit Performance Subscriber

final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitSubscriber()
    
    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
        AppLogger.info("[METRICKIT] Subscriber registered", category: .performance)
    }
    
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let json = payload.jsonRepresentation()
            if let data = try? JSONSerialization.data(withJSONObject: json, options: []),
               let summary = String(data: data, encoding: .utf8) {
                AppLogger.info("[METRICKIT] Daily metrics received (\(summary.count) bytes)", category: .performance)
            }
            
            if payload.applicationResponsivenessMetrics != nil {
                AppLogger.warning("[METRICKIT] Responsiveness metrics available", category: .performance)
            }
        }
    }
    
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangDiagnostics = payload.hangDiagnostics {
                for hang in hangDiagnostics {
                    let durationMs = Int(hang.hangDuration.converted(to: .milliseconds).value)
                    AppLogger.error("[METRICKIT] Hang diagnostic: \(durationMs)ms hang detected", category: .performance)
                    
                    if AdvancedSessionLogger.isActive {
                        Task { @MainActor in
                            AdvancedSessionLogger.shared.logPerformance(
                                "METRICKIT_HANG: \(durationMs)ms",
                                durationMs: durationMs
                            )
                        }
                    }
                }
            }
            
            if let crashDiagnostics = payload.crashDiagnostics {
                for crash in crashDiagnostics {
                    AppLogger.error("[METRICKIT] Crash diagnostic received: \(crash.applicationVersion)", category: .performance)
                }
            }
            
            if let cpuDiagnostics = payload.cpuExceptionDiagnostics {
                for cpu in cpuDiagnostics {
                    AppLogger.warning("[METRICKIT] CPU exception: \(cpu.totalCPUTime)", category: .performance)
                }
            }
            
            if let diskDiagnostics = payload.diskWriteExceptionDiagnostics {
                for disk in diskDiagnostics {
                    AppLogger.warning("[METRICKIT] Disk write exception: \(disk.totalWritesCaused)", category: .performance)
                }
            }
        }
    }
}

// MARK: - Production FPS Monitor

final class ProductionFPSMonitor {
    static let shared = ProductionFPSMonitor()
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var lowFPSStartTime: CFTimeInterval = 0
    private var isTrackingLowFPS = false
    private let reportAfterMs: Double = 500.0
    
    /// In Low Power Mode, iOS throttles GPU to ~30-45fps — use lower threshold to avoid log spam
    private var lowFPSThreshold: Double {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 30.0 : 55.0
    }
    
    func start() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        
        frameCount += 1
        let elapsed = link.timestamp - lastTimestamp
        
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            frameCount = 0
            lastTimestamp = link.timestamp
            
            if fps < lowFPSThreshold {
                if !isTrackingLowFPS {
                    isTrackingLowFPS = true
                    lowFPSStartTime = CACurrentMediaTime()
                } else {
                    let dropDuration = (CACurrentMediaTime() - lowFPSStartTime) * 1000
                    if dropDuration >= reportAfterMs {
                        AppLogger.warning("[FPS] Sustained drop: \(String(format: "%.0f", fps))fps for \(String(format: "%.0f", dropDuration))ms", category: .performance)
                        
                        if AdvancedSessionLogger.isActive {
                            let fpsVal = fps
                            let durVal = Int(dropDuration)
                            Task { @MainActor in
                                AdvancedSessionLogger.shared.logPerformance(
                                    "FPS_DROP: \(String(format: "%.0f", fpsVal))fps",
                                    durationMs: durVal
                                )
                            }
                        }
                        isTrackingLowFPS = false
                    }
                }
            } else {
                isTrackingLowFPS = false
            }
        }
    }
}

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
        AppLogger.debug("🚀 [STARTUP CACHE] Beginning warm-up...", category: .performance)
        
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
        warmupProgress = 0.90
        
        // Stage 5: Pre-warm exercise library so Exercise tab has data immediately
        // This triggers ExerciseLibraryService init (eager Core Data check) + cache build
        // at ~T=500ms instead of waiting for TabPreloader Phase 4 at T=4s
        ExerciseLibraryService.shared.preWarmCache()
        warmupProgress = 1.0
        
        lastWarmTime = Date()
        isWarmed = true
        
        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        AppLogger.debug("🚀 [STARTUP CACHE] Warm-up complete in \(String(format: "%.1f", elapsed))ms", category: .performance)
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
            AppLogger.error("⚠️ [STARTUP CACHE] User stats warm failed: \(error)", category: .performance)
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
            AppLogger.error("⚠️ [STARTUP CACHE] Categories warm failed: \(error)", category: .performance)
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
            AppLogger.error("⚠️ [STARTUP CACHE] Equipment warm failed: \(error)", category: .performance)
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
            AppLogger.error("⚠️ [STARTUP CACHE] Workouts warm failed: \(error)", category: .performance)
        }
    }
    
    private func warmExerciseCount(context: NSManagedObjectContext) async {
        let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        do {
            self.cachedExerciseCount = try context.count(for: fetchRequest)
        } catch {
            AppLogger.error("⚠️ [STARTUP CACHE] Exercise count warm failed: \(error)", category: .performance)
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
            AppLogger.debug("📱 [LAZY TAB] Tab \(tab) initialized on first visit", category: .ui)
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
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled, let self = self else { return }
                if self.hintedTabs.contains(tab) {
                    self.visitedTabs.insert(tab)
                    AppLogger.debug("📱 [LAZY TAB] Tab \(tab) pre-rendered from hint", category: .ui)
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
            let delay = Double(index) * 0.05
            Task { @MainActor [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                self?.visitedTabs.insert(tab)
            }
        }
        
        let elapsed = (CACurrentMediaTime() - eagerPreloadStartTime) * 1000
        AppLogger.debug("⚡️ [EAGER MODE] Enabled - all tabs will render immediately (\(String(format: "%.1f", elapsed))ms)", category: .ui)
    }
    
    /// Pre-warm all tabs immediately (synchronous version for startup)
    func preWarmAllTabs() {
        isEagerModeEnabled = true
        visitedTabs = Set(Tab.allCases)
        AppLogger.debug("⚡️ [EAGER MODE] All tabs pre-warmed synchronously", category: .ui)
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
    /// NOTE: Progress tab prefetch (achievements) was removed — too expensive to run on every switch
    func prefetchForTab(_ tab: LazyTabManager.Tab) {
        switch tab {
        case .exercises:
            prefetchExerciseLibrary()
        case .nutrition:
            prefetchNutritionData()
        default:
            // .progress (now Friends tab) and others — let them load on-demand
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
                    AppLogger.error("⚠️ [PREFETCH] Exercise prefetch failed: \(error)", category: .performance)
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
    
    // 🔍 FREEZE DETECTION: Timer that fires if transition never completes
    private var freezeDetectionTimer: DispatchWorkItem?
    private var pendingFrom: Int = -1
    private var pendingTo: Int = -1
    private var transitionSequence: Int = 0 // Increments on every beginTransition
    
    private init() {}
    
    /// Call when tab switch begins
    func beginTransition(from: Int, to: Int) {
        transitionStartTime = CACurrentMediaTime()
        isTransitioning = true
        pendingFrom = from
        pendingTo = to
        transitionSequence += 1
        let seq = transitionSequence
        
        let tabNames = ["Home", "Exercises", "Workout", "Nutrition", "Friends"]
        let fromName = from < tabNames.count ? tabNames[from] : "Tab\(from)"
        let toName = to < tabNames.count ? tabNames[to] : "Tab\(to)"
        
        let memoryMB = Self.quickMemoryMB()
        AppLogger.debug("🔍 [TAB FREEZE] beginTransition: \(fromName)(\(from))→\(toName)(\(to)) seq#\(seq) memory:\(Int(memoryMB))MB thread:\(Thread.isMainThread ? "main" : "bg")", category: .ui)
        
        // 🐕 Tell watchdog about this tab switch
        MainThreadWatchdog.shared.trackTabSwitch(from: from, to: to)
        
        // Prepare destination tab
        let prepStart = CACurrentMediaTime()
        if let tab = LazyTabManager.Tab(rawValue: to) {
            LazyTabManager.shared.markVisited(tab)
            SmartPrefetch.shared.prefetchForTab(tab)
        }
        let prepMs = (CACurrentMediaTime() - prepStart) * 1000
        AppLogger.debug("🔍 [TAB FREEZE] beginTransition: prefetch done for seq#\(seq) (\(String(format: "%.1f", prepMs))ms)", category: .ui)
        
        // Haptic feedback (already warm from HapticManager)
        HapticManager.selectionChanged()
        
        // 🔍 FREEZE DETECTION: If endTransition isn't called within 3s, log a freeze warning
        freezeDetectionTimer?.cancel()
        let freezeCheck = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Only fire if this transition is still the active one
            if self.transitionSequence == seq && self.isTransitioning {
                let elapsed = (CACurrentMediaTime() - self.transitionStartTime) * 1000
                let mem = Self.quickMemoryMB()
                AppLogger.error("🚨🚨🚨 [TAB FREEZE] FREEZE DETECTED! Tab \(from)→\(to) seq#\(seq) stuck for \(String(format: "%.0f", elapsed))ms!", category: .ui)
                AppLogger.debug("   └─ memory: \(Int(mem))MB", category: .performance)
                AppLogger.debug("   └─ isTransitioning still true — endTransition() was NEVER called", category: .ui)
                AppLogger.debug("   └─ main_thread: \(Thread.isMainThread)", category: .performance)
                
                // Log what's happening on the main run loop
                MainThreadWatchdog.shared.logFreezeSnapshot(context: "tab_switch_\(from)→\(to)_seq\(seq)")
            }
        }
        freezeDetectionTimer = freezeCheck
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.0))
            freezeCheck.perform()
        }
    }
    
    /// Call when tab switch animation completes
    func endTransition() {
        let elapsed = (CACurrentMediaTime() - transitionStartTime) * 1000
        let seq = transitionSequence
        isTransitioning = false
        
        // Cancel freeze detection — transition completed normally
        freezeDetectionTimer?.cancel()
        freezeDetectionTimer = nil
        
        // 🐕 Clear watchdog context
        MainThreadWatchdog.shared.clearContext()
        
        // Note: Humans perceive <200ms as "instant", <500ms as "fast"
        // Only warn if transition takes longer than 300ms (noticeable delay)
        if elapsed > 2000 {
            AppLogger.warning("🚨 [TAB SWITCH] VERY slow transition: \(String(format: "%.1f", elapsed))ms (seq#\(seq))", category: .ui)
        } else if elapsed > 300 {
            AppLogger.warning("⚠️ [TAB SWITCH] Slow transition: \(String(format: "%.1f", elapsed))ms", category: .ui)
        } else if elapsed > 150 {
            AppLogger.debug("🟡 [TAB SWITCH] Transition: \(String(format: "%.1f", elapsed))ms", category: .ui)
        } else {
            AppLogger.debug("✅ [TAB SWITCH] Fast transition: \(String(format: "%.1f", elapsed))ms", category: .ui)
        }
    }
    
    nonisolated static func quickMemoryMB() -> Double {
        SystemMetrics.getMemoryUsageMB()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 7b. MAIN THREAD WATCHDOG (Freeze Detection)
// ═══════════════════════════════════════════════════════════════════════════════

/// Monitors the main thread for hangs/freezes by pinging it from a background thread.
/// Uses semaphore-based detection for precise timing.
/// If the main thread doesn't respond within the threshold, logs detailed diagnostics.
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()
    
    private var watchdogThread: Thread?
    private var isRunning = false
    private let checkInterval: TimeInterval = 0.5      // Check every 500ms
    private let freezeThreshold: TimeInterval = 1.5     // 1.5s without response = freeze
    private let criticalThreshold: TimeInterval = 3.0   // 3s = critical freeze
    
    /// Paused when the app enters background to prevent false-positive freeze reports.
    /// The watchdog loop skips checks while paused but stays alive for fast resume.
    private var isPaused = false
    
    // Track what was happening when freeze started
    private var activeContext: String = "none"
    private var contextStartTime: CFTimeInterval = 0
    private var lastTabFrom: Int = -1
    private var lastTabTo: Int = -1
    private var lastTabTime: CFTimeInterval = 0
    private var freezeCount: Int = 0
    private let lock = NSLock()
    
    private init() {}
    
    /// Start the watchdog — call once at app launch
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        let thread = Thread { [weak self] in
            self?.watchdogLoop()
        }
        thread.name = "com.gofit.mainthread-watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
        watchdogThread = thread
        
        AppLogger.debug("🐕 [WATCHDOG] Main thread freeze detector started (threshold: \(freezeThreshold)s)", category: .performance)
    }
    
    /// Set current context (e.g., "tab_switch_0→1") — helps correlate freezes
    func setContext(_ context: String) {
        lock.lock()
        activeContext = context
        contextStartTime = CACurrentMediaTime()
        lock.unlock()
    }
    
    func clearContext() {
        lock.lock()
        activeContext = "none"
        lock.unlock()
    }
    
    /// Thread-safe check if a tab switch is currently in progress
    var isTabSwitchActive: Bool {
        lock.lock()
        let active = activeContext.contains("tab_switch")
        lock.unlock()
        return active
    }
    
    /// Track tab switch for better freeze context
    func trackTabSwitch(from: Int, to: Int) {
        let tabNames = ["Home", "Exercises", "Workout", "Nutrition", "Friends"]
        let fromName = from < tabNames.count ? tabNames[from] : "Tab\(from)"
        let toName = to < tabNames.count ? tabNames[to] : "Tab\(to)"
        lock.lock()
        lastTabFrom = from
        lastTabTo = to
        lastTabTime = CACurrentMediaTime()
        activeContext = "tab_switch:\(fromName)→\(toName)"
        contextStartTime = CACurrentMediaTime()
        lock.unlock()
    }
    
    /// Log a snapshot of current state (called from freeze detection timer)
    @MainActor
    func logFreezeSnapshot(context: String) {
        let mem = TabSwitchOptimizer.quickMemoryMB()
        let runLoopMode = RunLoop.current.currentMode?.rawValue ?? "unknown"
        
        AppLogger.debug("🔍 [WATCHDOG] Freeze snapshot for: \(context)", category: .performance)
        AppLogger.debug("   └─ memory: \(Int(mem))MB", category: .performance)
        AppLogger.debug("   └─ runloop_mode: \(runLoopMode)", category: .performance)
        AppLogger.debug("   └─ isTransitioning: \(TabSwitchOptimizer.shared.isTransitioning)", category: .ui)
        AppLogger.debug("   └─ thread: \(Thread.isMainThread ? "main" : "background")", category: .performance)
        AppLogger.debug("   └─ active_tasks: check console for pending operations", category: .performance)
    }
    
    private func watchdogLoop() {
        while isRunning {
            Thread.sleep(forTimeInterval: checkInterval)
            
            // Skip checks while app is backgrounded to prevent false positives
            lock.lock()
            let paused = isPaused
            lock.unlock()
            if paused { continue }
            
            let pingStart = CACurrentMediaTime()
            let semaphore = DispatchSemaphore(value: 0)
            
            // Capture context BEFORE pinging
            lock.lock()
            let ctx = activeContext
            let ctxStart = contextStartTime
            let tabFrom = lastTabFrom
            let tabTo = lastTabTo
            let tabTime = lastTabTime
            lock.unlock()
            
            // Ping the main thread
            DispatchQueue.main.async {
                semaphore.signal()
            }
            
            // Wait for the main thread to respond within threshold
            let result = semaphore.wait(timeout: .now() + freezeThreshold)
            
            if result == .timedOut {
                // Main thread didn't respond — it's frozen!
                lock.lock()
                freezeCount += 1
                let count = freezeCount
                lock.unlock()
                
                let mem = TabSwitchOptimizer.quickMemoryMB()
                let ctxDuration = ctxStart > 0 ? (CACurrentMediaTime() - ctxStart) * 1000 : 0
                let tabAge = tabTime > 0 ? CACurrentMediaTime() - tabTime : -1
                
                let tabNames = ["Home", "Exercises", "Workout", "Nutrition", "Friends"]
                let tabInfo: String
                if tabFrom >= 0 && tabTo >= 0 {
                    let fromName = tabFrom < tabNames.count ? tabNames[tabFrom] : "Tab\(tabFrom)"
                    let toName = tabTo < tabNames.count ? tabNames[tabTo] : "Tab\(tabTo)"
                    tabInfo = "\(fromName)→\(toName) (\(String(format: "%.1f", tabAge))s ago)"
                } else {
                    tabInfo = "none"
                }
                
                AppLogger.error("🚨🚨🚨 [WATCHDOG] MAIN THREAD FROZEN! (freeze #\(count))", category: .performance)
                AppLogger.debug("   └─ context: \(ctx) (running \(String(format: "%.0f", ctxDuration))ms)", category: .performance)
                AppLogger.debug("   └─ last_tab_switch: \(tabInfo)", category: .performance)
                AppLogger.debug("   └─ memory: \(Int(mem))MB", category: .performance)
                AppLogger.error("   └─ ⚠️ UI is unresponsive — user cannot interact", category: .performance)
                
                // Log thread count
                logThreadInfo()
                
                // Now wait for unblock (up to 30s)
                let unblockResult = semaphore.wait(timeout: .now() + 30.0)
                let totalBlocked = CACurrentMediaTime() - pingStart
                
                // If the app was paused/backgrounded during the wait, discard this measurement
                lock.lock()
                let wasPaused = isPaused
                lock.unlock()
                if wasPaused { continue }
                
                if unblockResult == .timedOut {
                    AppLogger.error("🧊🧊🧊 [WATCHDOG] Main thread blocked >30s! Possible DEADLOCK!", category: .performance)
                    AppLogger.debug("   └─ context: \(ctx)", category: .performance)
                } else if totalBlocked >= criticalThreshold {
                    AppLogger.error("🧊🧊 [WATCHDOG] Main thread unblocked after \(String(format: "%.1f", totalBlocked))s (CRITICAL)", category: .performance)
                    AppLogger.debug("   └─ context: \(ctx)", category: .performance)
                } else {
                    AppLogger.debug("🧊 [WATCHDOG] Main thread unblocked after \(String(format: "%.1f", totalBlocked))s", category: .performance)
                    AppLogger.debug("   └─ context: \(ctx)", category: .performance)
                }
            }
        }
    }
    
    private func logThreadInfo() {
        // Log basic thread counts to help diagnose contention
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        if result == KERN_SUCCESS {
            AppLogger.debug("   └─ active_threads: \(threadCount)", category: .performance)
            // Deallocate the thread list
            if let list = threadList {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.size))
            }
        }
    }
    
    /// Pause the watchdog when app enters background to prevent false-positive freeze reports.
    /// Without this, background suspension time (minutes/hours) is counted as freeze duration.
    func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
        AppLogger.debug("🐕 [WATCHDOG] Paused (app backgrounded)", category: .performance)
    }
    
    /// Resume the watchdog when app returns to foreground.
    func resume() {
        lock.lock()
        isPaused = false
        freezeCount = 0
        lock.unlock()
        AppLogger.debug("🐕 [WATCHDOG] Resumed (app foregrounded)", category: .performance)
    }
    
    func stop() {
        isRunning = false
        watchdogThread = nil
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - STARTUP WATERFALL (Consolidated Timeline)
// ═══════════════════════════════════════════════════════════════════════════════

/// Records every major startup milestone with wall-clock timestamps.
/// Call `StartupWaterfall.shared.mark("label")` at the start of an operation
/// and `StartupWaterfall.shared.end("label")` when it finishes.
/// A formatted waterfall timeline is emitted once `printWaterfall()` is called.
final class StartupWaterfall {
    static let shared = StartupWaterfall()
    
    private let appLaunch = CACurrentMediaTime()
    private let lock = NSLock()
    private var events: [Event] = []
    private var hasPrinted = false
    
    struct Event {
        let label: String
        let startOffset: Double
        var endOffset: Double?
        let thread: String
        
        var durationMs: Double? {
            guard let end = endOffset else { return nil }
            return (end - startOffset) * 1000
        }
    }
    
    private init() {}
    
    /// Mark the START of an operation. Returns immediately.
    func mark(_ label: String) {
        let offset = CACurrentMediaTime() - appLaunch
        let thread = Thread.isMainThread ? "main" : "bg"
        lock.lock()
        events.append(Event(label: label, startOffset: offset, endOffset: nil, thread: thread))
        lock.unlock()
    }
    
    /// Mark the END of a previously-started operation.
    func end(_ label: String) {
        let offset = CACurrentMediaTime() - appLaunch
        lock.lock()
        if let idx = events.lastIndex(where: { $0.label == label && $0.endOffset == nil }) {
            events[idx].endOffset = offset
        }
        lock.unlock()
    }
    
    /// One-shot convenience: times a block and records it.
    func measure<T>(_ label: String, block: () throws -> T) rethrows -> T {
        mark(label)
        let result = try block()
        end(label)
        return result
    }
    
    /// Async variant of measure.
    func measure<T>(_ label: String, block: () async throws -> T) async rethrows -> T {
        mark(label)
        let result = try await block()
        end(label)
        return result
    }
    
    /// Print the full waterfall timeline (call once after startup completes).
    func printWaterfall() {
        guard !hasPrinted else { return }
        hasPrinted = true
        
        lock.lock()
        let snapshot = events
        lock.unlock()
        
        guard !snapshot.isEmpty else { return }
        
        let totalTime = (snapshot.compactMap { $0.endOffset }.max() ?? (CACurrentMediaTime() - appLaunch))
        
        var lines: [String] = []
        lines.append("")
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("⏱️ STARTUP WATERFALL  (total: \(String(format: "%.1f", totalTime * 1000))ms)")
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("  TIME     DUR    THR  OPERATION")
        lines.append("  ──────   ─────  ───  ─────────────────────────────────────")
        
        let sorted = snapshot.sorted { $0.startOffset < $1.startOffset }
        var mainThreadMs: Double = 0
        
        for event in sorted {
            let startMs = event.startOffset * 1000
            let durStr: String
            if let dur = event.durationMs {
                durStr = String(format: "%5.0fms", dur)
                if event.thread == "main" { mainThreadMs += dur }
            } else {
                durStr = "  ···  "
            }
            let warn = (event.durationMs ?? 0) > 500 && event.thread == "main" ? " ⚠️" : ""
            lines.append("  \(String(format: "%6.0f", startMs))ms \(durStr)  [\(event.thread)]  \(event.label)\(warn)")
        }
        
        lines.append("  ──────   ─────  ───  ─────────────────────────────────────")
        lines.append("  Main thread budget: \(String(format: "%.0f", mainThreadMs))ms")
        lines.append("═══════════════════════════════════════════════════════════════")
        
        for line in lines {
            AppLogger.debug(line, category: .performance)
        }
    }
    
    /// Reset for next session (e.g. after background → foreground).
    func reset() {
        lock.lock()
        events.removeAll()
        hasPrinted = false
        lock.unlock()
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
                    AppLogger.error("⚠️ [FETCH] Background fetch failed: \(error)", category: .performance)
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
                        AppLogger.debug("🔍 [TAB FREEZE] ✅ Tab \(tab.rawValue) onAppear fired (eager/initialized)", category: .ui)
                    }
            } else if lazyTabManager.shouldRenderContent(for: tab) {
                // Tab was explicitly visited or hinted
                content()
                    .onAppear {
                        hasInitialized = true
                        AppLogger.debug("🔍 [TAB FREEZE] ✅ Tab \(tab.rawValue) onAppear fired (shouldRender)", category: .ui)
                    }
            } else {
                // Lightweight placeholder - show VERY briefly while initializing
                TabPlaceholderView(tab: tab)
                    .onAppear {
                        // Initialize immediately - no delay
                        hasInitialized = true
                        lazyTabManager.markVisited(tab)
                        AppLogger.debug("🔍 [TAB FREEZE] ⏳ Tab \(tab.rawValue) showing PLACEHOLDER (first init)", category: .ui)
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
    
    /// Optimized for tab content - reduces unnecessary updates during active tab transitions
    func tabContentOptimized() -> some View {
        self
            .transaction { transaction in
                // Only disable animations during an ACTIVE tab transition (not permanently)
                // Previously this also checked isPreloadingComplete which killed ALL animations forever
                if TabSwitchOptimizer.shared.isTransitioning {
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
            AppLogger.debug("📊 [PERF] Tab \(tab) first load: \(String(format: "%.1f", elapsed * 1000))ms", category: .ui)
        } else {
            let existing = tabMetrics[tab]!
            let newAvg = (existing.avgSwitchTime * Double(existing.switchCount) + elapsed) / Double(existing.switchCount + 1)
            tabMetrics[tab]?.avgSwitchTime = newAvg
            tabMetrics[tab]?.switchCount += 1
            
            if elapsed * 1000 > 50 {
                AppLogger.warning("⚠️ [PERF] Tab \(tab) slow switch: \(String(format: "%.1f", elapsed * 1000))ms", category: .ui)
            }
        }
    }
    
    func printSummary() {
        AppLogger.debug("\n📊 === PERFORMANCE SUMMARY ===", category: .performance)
        for (tab, metrics) in tabMetrics.sorted(by: { $0.key < $1.key }) {
            AppLogger.debug("Tab \(tab): First=\(String(format: "%.1f", metrics.firstLoadTime * 1000))ms, Avg=\(String(format: "%.1f", metrics.avgSwitchTime * 1000))ms (\(metrics.switchCount) switches)", category: .ui)
        }
        AppLogger.debug("==============================\n", category: .performance)
    }
}
#endif

