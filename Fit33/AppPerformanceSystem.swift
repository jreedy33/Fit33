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
            
            // isValidJSONObject guards against NSInvalidArgumentException (ObjC exception
            // that bypasses Swift try/catch and causes SIGABRT)
            guard JSONSerialization.isValidJSONObject(json) else {
                AppLogger.warning("[METRICKIT] Payload failed isValidJSONObject check — skipping serialization (type: \(type(of: json)))", category: .performance)
                continue
            }
            
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
                    let callStackJSON = Self.jsonString(from: hang.callStackTree.jsonRepresentation())
                    let metaBaseline = hang.metaData.jsonRepresentation()
                    let metaJSON = Self.jsonString(from: metaBaseline)

                    AppLogger.warning(
                        "[METRICKIT] Hang diagnostic: \(durationMs)ms hang detected",
                        category: .performance
                    )

                    // Persist full hang payload to dev_session_logs.extra so
                    // the next occurrence is fingerprint-able by call stack
                    // instead of just duration — this is the signal
                    // previously missing from Cluster A bug reports.
                    if AdvancedSessionLogger.isActive {
                        let capturedDuration = durationMs
                        let capturedStack = callStackJSON
                        let capturedMeta = metaJSON
                        Task { @MainActor in
                            AdvancedSessionLogger.shared.log(
                                type: "metrickit_hang",
                                detail: "METRICKIT_HANG: \(capturedDuration)ms",
                                screen: nil,
                                durationMs: capturedDuration,
                                extra: [
                                    "mx_kind": "hang",
                                    "duration_ms": capturedDuration,
                                    "call_stack_tree": capturedStack ?? "unavailable",
                                    "meta_data": capturedMeta ?? "unavailable"
                                ]
                            )
                        }
                    }
                }
            }

            if let crashDiagnostics = payload.crashDiagnostics {
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                for crash in crashDiagnostics {
                    let crashVersion = crash.applicationVersion
                    let signal = crash.signal?.intValue ?? -1
                    let exceptionType = crash.exceptionType?.intValue ?? -1
                    let exceptionCode = crash.exceptionCode?.intValue ?? -1
                    let terminationReason = crash.terminationReason ?? "unknown"
                    let callStackJSON = Self.jsonString(from: crash.callStackTree.jsonRepresentation())
                    let metaJSON = Self.jsonString(from: crash.metaData.jsonRepresentation())

                    // MetricKit reports crashes the OS already recorded (often
                    // SIGKILL/jetsam, OOM, watchdog) AFTER the fact via its own
                    // crash channel — they are not signals OUR catch path can
                    // act on. Log at .warning (not .error) so MetricKit
                    // diagnostics flow into dev_session_logs + the
                    // AdvancedSessionLogger persist below WITHOUT firing a
                    // duplicate `crash_reports` row via Logger.swift's
                    // `level >= .error → CrashReportingService.reportError`
                    // gate. The `metrickit_crash` AdvancedSessionLogger entry
                    // already carries the canonical record. (Bug-intel
                    // `64dc8967` — MetricKit signal 9 cluster.)
                    AppLogger.warning(
                        "[METRICKIT] Crash diagnostic v\(crashVersion) (current: v\(currentVersion)), signal: \(signal) exc: \(exceptionType)/\(exceptionCode)",
                        category: .performance
                    )

                    // Persist crash callStackTree so the crash_reports row has
                    // a fingerprint-able stack (complements symbolicated
                    // stack traces from CrashReportingService).
                    if AdvancedSessionLogger.isActive {
                        let capturedVersion = crashVersion
                        let capturedStack = callStackJSON
                        let capturedMeta = metaJSON
                        let capturedSignal = signal
                        let capturedTermination = terminationReason
                        Task { @MainActor in
                            AdvancedSessionLogger.shared.log(
                                type: "metrickit_crash",
                                detail: "METRICKIT_CRASH: signal=\(capturedSignal)",
                                screen: nil,
                                error: "signal=\(capturedSignal)",
                                extra: [
                                    "mx_kind": "crash",
                                    "app_version": capturedVersion,
                                    "signal": capturedSignal,
                                    "termination_reason": capturedTermination,
                                    "call_stack_tree": capturedStack ?? "unavailable",
                                    "meta_data": capturedMeta ?? "unavailable"
                                ]
                            )
                        }
                    }
                }
            }

            if let cpuDiagnostics = payload.cpuExceptionDiagnostics {
                for cpu in cpuDiagnostics {
                    AppLogger.warning("[METRICKIT] CPU exception: \(cpu.totalCPUTime)", category: .performance)
                    if AdvancedSessionLogger.isActive {
                        let stack = Self.jsonString(from: cpu.callStackTree.jsonRepresentation())
                        Task { @MainActor in
                            AdvancedSessionLogger.shared.log(
                                type: "metrickit_cpu",
                                detail: "METRICKIT_CPU",
                                screen: nil,
                                extra: [
                                    "mx_kind": "cpu_exception",
                                    "call_stack_tree": stack ?? "unavailable"
                                ]
                            )
                        }
                    }
                }
            }

            if let diskDiagnostics = payload.diskWriteExceptionDiagnostics {
                for disk in diskDiagnostics {
                    AppLogger.warning("[METRICKIT] Disk write exception: \(disk.totalWritesCaused)", category: .performance)
                }
            }
        }
    }

    /// Convert raw JSON payload Data returned by MetricKit to a UTF-8 string
    /// suitable for dev_session_logs.extra. Large payloads are truncated to
    /// 16 KB to avoid blowing up the session log row size (which has a JSONB
    /// column cap of ~1 MB — defensive).
    private static func jsonString(from data: Data) -> String? {
        guard JSONSerialization.isValidJSONObject((try? JSONSerialization.jsonObject(with: data)) ?? [:]) ||
              !data.isEmpty else {
            return nil
        }
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        return s.count <= 16_384 ? s : String(s.prefix(16_384)) + "...[truncated]"
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
        // DEBUG-only: ProductionFPSMonitor samples every frame and logs at
        // `.warning` when FPS drops — in Release/TestFlight this becomes
        // noise in bug_intelligence_fingerprints. MetricKit provides the
        // Release-side FPS signal via MXCPUExceptionDiagnostic.
        #if DEBUG
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
        #endif
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

/// Pre-warms critical data on app startup to eliminate first-load delays.
///
/// Sprint 2026-04-25 (cold-start speedup Phase 1.2): the class was previously
/// `@MainActor`. Even though every Core Data fetch was scoped to
/// `bgContext.perform`, the surrounding async function lived on the main actor
/// — so each stage's return-to-main hop joined the queue behind ContentView /
/// MainTabView body evaluations during cold start. Wall-clock for the 5-stage
/// warm-up was 3019ms in 1.38(55) logs despite < 200ms of real bg work.
///
/// New shape: the class is no longer `@MainActor`. All bg-context fetches run
/// off main as before, results are accumulated into local snapshots, and ONE
/// `MainActor.run` block publishes the full snapshot at the end. `@Published`
/// (`isWarmed`, `warmupProgress`) is only mutated from main; private(set)
/// caches are written from main to keep readers (SwiftUI views) thread-safe.
final class StartupCache: ObservableObject {
    static let shared = StartupCache()

    // MARK: - Cached Data
    @Published private(set) var isWarmed = false
    @Published private(set) var warmupProgress: Double = 0

    // Pre-loaded data — written via `MainActor.run` at the end of `warmUp` so
    // SwiftUI readers always see a fully-coherent snapshot.
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

    /// Call this early in app lifecycle to pre-warm caches.
    /// All Core Data fetches run on a background context to avoid blocking the main thread.
    /// Single `MainActor.run` at the end publishes all results coherently.
    func warmUp(context: NSManagedObjectContext) async {
        if isWarmed && !isCacheStale { return }

        let startTime = CACurrentMediaTime()
        AppLogger.debug("🚀 [STARTUP CACHE] Beginning warm-up (background)...", category: .performance)

        // ⚡️ Cold-start sprint 2026-04-26 (async Core Data store load):
        // With `shouldAddStoreAsynchronously = true`, the persistent store
        // attaches a few hundred ms AFTER `PersistenceController.init`
        // returns. Fetches against an unattached store silently return
        // empty arrays — without this gate, `warmUp` would cache "0
        // workouts / 0 stats" on cold start and the dashboard would render
        // those zeros until a later refresh trigger. Suspending here
        // costs us the wait time only IF the store hasn't loaded yet;
        // typically returns immediately because the iOS framework gap
        // already gave the bg-thread store-load enough time to finish.
        await PersistenceController.waitUntilStoreLoaded()

        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()

        let userStats = await fetchUserStats(context: bgContext)
        let (categories, equipment) = await fetchExerciseMetadata(context: bgContext)
        let workoutIDs = await fetchRecentWorkouts(context: bgContext)
        let exerciseCount = await fetchExerciseCount(context: bgContext)

        let muscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings",
                            "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back",
                            "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques"]

        // Single coherent publish — no inter-stage main-actor hops.
        await MainActor.run {
            self.cachedUserStats = userStats
            self.cachedCategories = categories
            self.cachedEquipment = equipment
            self.cachedMuscleGroups = muscleGroups
            self.cachedRecentWorkouts = workoutIDs
            self.cachedExerciseCount = exerciseCount
            self.lastWarmTime = Date()
            self.warmupProgress = 1.0
            self.isWarmed = true
        }

        // Pre-warm exercise library so Exercise tab has data immediately.
        // Self-dispatches a Task.detached internally — no main-actor cost here.
        ExerciseLibraryService.shared.preWarmCache()

        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        AppLogger.debug("🚀 [STARTUP CACHE] Warm-up complete in \(String(format: "%.1f", elapsed))ms", category: .performance)
    }

    private var isCacheStale: Bool {
        guard let lastTime = lastWarmTime else { return true }
        return Date().timeIntervalSince(lastTime) > cacheValidityDuration
    }

    // MARK: - Individual Fetch Functions
    // All fetches use bgContext.perform to run off the main thread.
    // Pure functions — return their result; the caller publishes in one batch.

    private func fetchUserStats(context: NSManagedObjectContext) async -> CachedUserStats? {
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.fetchLimit = 1
        do {
            return try await context.perform {
                guard let user = try context.fetch(fetchRequest).first else { return nil }
                return CachedUserStats(
                    totalWorkouts: Int(user.totalWorkouts),
                    currentStreak: Int(user.currentStreak),
                    longestStreak: Int(user.longestStreak),
                    xp: Int(user.xp),
                    lastWorkoutDate: user.lastWorkoutDate
                )
            }
        } catch {
            AppLogger.error("⚠️ [STARTUP CACHE] User stats warm failed: \(error)", category: .performance)
            return nil
        }
    }

    private func fetchExerciseMetadata(context: NSManagedObjectContext) async -> (categories: [String], equipment: [String]) {
        do {
            return try await context.perform {
                let categoryRequest: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "Exercise")
                categoryRequest.resultType = .dictionaryResultType
                categoryRequest.propertiesToFetch = ["category"]
                categoryRequest.returnsDistinctResults = true
                let catResults = try context.fetch(categoryRequest)
                let cats = catResults.compactMap { $0["category"] as? String }.sorted()

                let equipmentRequest: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "Exercise")
                equipmentRequest.resultType = .dictionaryResultType
                equipmentRequest.propertiesToFetch = ["equipment"]
                equipmentRequest.returnsDistinctResults = true
                let eqResults = try context.fetch(equipmentRequest)
                let eqs = eqResults.compactMap { $0["equipment"] as? String }.sorted()

                return (cats, eqs)
            }
        } catch {
            AppLogger.error("⚠️ [STARTUP CACHE] Metadata warm failed: \(error)", category: .performance)
            return ([], [])
        }
    }

    private func fetchRecentWorkouts(context: NSManagedObjectContext) async -> [NSManagedObjectID] {
        do {
            return try await context.perform {
                let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
                fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
                fetchRequest.fetchLimit = 20
                fetchRequest.predicate = NSPredicate(format: "isCompleted == true")
                let workouts = try context.fetch(fetchRequest)
                return workouts.map { $0.objectID }
            }
        } catch {
            AppLogger.error("⚠️ [STARTUP CACHE] Workouts warm failed: \(error)", category: .performance)
            return []
        }
    }

    private func fetchExerciseCount(context: NSManagedObjectContext) async -> Int {
        do {
            return try await context.perform {
                let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                return try context.count(for: fetchRequest)
            }
        } catch {
            AppLogger.error("⚠️ [STARTUP CACHE] Exercise count warm failed: \(error)", category: .performance)
            return 0
        }
    }

    // MARK: - Invalidation

    func invalidate() {
        Task { @MainActor in
            lastWarmTime = nil
            isWarmed = false
        }
    }

    func invalidateWorkouts() {
        Task { @MainActor in
            cachedRecentWorkouts = []
        }
    }

    func invalidateUserStats() {
        Task { @MainActor in
            cachedUserStats = nil
        }
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
            let bgContext = PersistenceController.shared.container.newBackgroundContext()
            let objectIDs: [NSManagedObjectID] = await withCheckedContinuation { continuation in
                bgContext.perform {
                    let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                    fetchRequest.fetchLimit = 100
                    fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
                    
                    do {
                        let exercises = try bgContext.fetch(fetchRequest)
                        continuation.resume(returning: exercises.map { $0.objectID })
                    } catch {
                        AppLogger.error("⚠️ [PREFETCH] Exercise prefetch failed: \(error)", category: .performance)
                        continuation.resume(returning: [])
                    }
                }
            }
            
            await MainActor.run {
                self.prefetchedData["exercises_first_batch"] = objectIDs
            }
            self.prefetchTasks["exercises"] = nil
        }
    }
    
    // 2026-05-03 perf sprint: `prefetchProgressData` removed. The Progress
    // tab no longer exists as a top-level tab — achievements compute on
    // demand inside the dedicated Achievements view, and the
    // `prefetchForTab(_:)` switch above no longer routes `.progress`. The
    // prefetcher was running `AchievementService.generateAllAchievements`
    // on every tab switch and discarding the result (no return path), pure
    // CPU waste.
    
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
// MARK: - 5/6. (was RenderCoalescer + ComputationCache + Memoized — removed 2026-05-03)
// ═══════════════════════════════════════════════════════════════════════════════
//
// All three were defined but never invoked anywhere in the app:
//   • `RenderCoalescer.shared.scheduleUpdate(...)` — 0 call sites
//   • `ComputationCache.shared.get/set/invalidate` — 0 call sites
//   • `@Memoized` property wrapper — 0 usages (its `wrappedValue`
//     impl was a no-op TODO that always computed; even if used, it
//     wouldn't memoize anything)
//
// SwiftUI already coalesces state updates within a single run-loop pass,
// and concrete memoization is implemented at the call site by services
// that need it (`ExercisePopularityService.popCache`, `ExerciseLibraryService`
// in-memory cache, `RequestDeduplicationService.resultCache`, etc.). The
// generic infrastructure was never adopted because per-call-site
// memoization gave better control over invalidation. Removed.

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
                // Phase 11J — 2026-04-24 release-level log demotion.
                //
                // Previously `AppLogger.error` → writes dev_session_logs row
                // type='error' → picked up by compute_daily_bug_rollup →
                // fingerprinted as CRITICAL bug. This was the #1 source of
                // fake-critical reports in the 2026-04-24T11:10 Cursor
                // export (6 structural fingerprints, 15 CRITICAL report
                // rows). The watchdog is *instrumentation*, not a bug —
                // we put it here on purpose to know freezes are
                // happening. In release, use `.warning` so it still
                // writes a dev_session_logs row (now `type='warning'`,
                // which the rollup ignores after Phase 9), but doesn't
                // manufacture CRITICAL bugs. In DEBUG keep `.error` for
                // the red/bold console formatting dev expects. Also
                // noise-filtered server-side (see
                // `supabase/20260517_bug_intel_noise_filter_expand.sql`
                // rule `watchdog_tab_freeze`) as a belt-and-suspenders.
                #if DEBUG
                AppLogger.error("🚨🚨🚨 [TAB FREEZE] FREEZE DETECTED! Tab \(from)→\(to) seq#\(seq) stuck for \(String(format: "%.0f", elapsed))ms!", category: .ui)
                #else
                AppLogger.warning("🚨🚨🚨 [TAB FREEZE] FREEZE DETECTED! Tab \(from)→\(to) seq#\(seq) stuck for \(String(format: "%.0f", elapsed))ms!", category: .ui)
                #endif
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
        guard isTransitioning else { return }
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
    
    /// Start the watchdog — call once at app launch.
    ///
    /// DEBUG-only. The watchdog thread samples the main thread every 100ms
    /// and emits `.warning`/`.error` logs on freeze, which AppLogger pipes
    /// into `dev_session_logs.entries[type=error]` and then into
    /// `bug_intelligence_fingerprints`. In TestFlight/Release this produces
    /// 20+ false-positive fingerprints per session (the user opening
    /// Dashboard during a cold start = 2-3s initial load = "freeze").
    /// Release build uses MetricKit's `MXHangDiagnostic` instead.
    func start() {
        #if DEBUG
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
        #endif
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
                // Race guard: app may have gone to background between ping dispatch and
                // this timeout. If so, the main run loop was suspended by iOS — not frozen.
                lock.lock()
                let pausedDuringWait = isPaused
                lock.unlock()
                if pausedDuringWait { continue }
                
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
                
                // Structured context so the Bug Intelligence rollup fingerprints
                // freezes by active UI context (tab switch source, screen) and
                // ctx duration — previously every freeze collapsed into a single
                // fingerprint with no way to tell "dashboard cold start" apart
                // from "workout detail tab swap".
                let freezeCtx = DiagnosticContext(
                    op: "ui.main_thread_freeze",
                    endpoint: ctx,
                    elapsedMs: Int(ctxDuration),
                    retryAttempt: count
                )
                // Phase 11J — 2026-04-24. Watchdog is DEBUG-only
                // instrumentation (MainThreadWatchdog.start() is gated via
                // `#if DEBUG` per QP invariant #5), but this specific log
                // line was surviving into TestFlight builds because the
                // entire surrounding `detectFreeze` block was
                // conditionally-compiled-out except for this `.warning`.
                // Downgrade to `.debug` on release so it never round-trips
                // to dev_session_logs. DEBUG builds keep `.warning`
                // formatting for dev console visibility. Writing out both
                // branches of the `#if` in full rather than splitting a
                // single call across preprocessor directives because Swift
                // parses function arguments as a single expression — a
                // `#if` inside the arg list would leave an incomplete
                // expression in the "else" branch and fail to compile.
                let freezeMsg = "🚨🚨🚨 [WATCHDOG] MAIN THREAD FROZEN! (freeze #\(count)) context=\(ctx) tab=\(tabInfo) mem=\(Int(mem))MB"
                #if DEBUG
                AppLogger.warning(freezeMsg, category: .performance, context: freezeCtx)
                #else
                AppLogger.debug(freezeMsg, category: .performance, context: freezeCtx)
                #endif
                AppLogger.debug("   └─ context: \(ctx) (running \(String(format: "%.0f", ctxDuration))ms)", category: .performance)
                AppLogger.debug("   └─ last_tab_switch: \(tabInfo)", category: .performance)
                AppLogger.debug("   └─ memory: \(Int(mem))MB", category: .performance)
                // Phase 11J — see comment at the parent freeze log.
                #if DEBUG
                AppLogger.warning("   └─ ⚠️ UI is unresponsive — user cannot interact", category: .performance)
                #else
                AppLogger.debug("   └─ ⚠️ UI is unresponsive — user cannot interact", category: .performance)
                #endif
                
                logThreadInfo()
                
                // Now wait for unblock (up to 30s)
                let unblockResult = semaphore.wait(timeout: .now() + 30.0)
                let totalBlocked = CACurrentMediaTime() - pingStart
                
                // If the app was paused/backgrounded during the wait, discard this measurement
                lock.lock()
                let wasPaused = isPaused
                lock.unlock()
                if wasPaused { continue }
                
                let unblockCtx = DiagnosticContext(
                    op: "ui.main_thread_freeze",
                    endpoint: ctx,
                    elapsedMs: Int(totalBlocked * 1000),
                    retryAttempt: count
                )
                if unblockResult == .timedOut {
                    AppLogger.warning(
                        "🧊🧊🧊 [WATCHDOG] Main thread blocked >30s! Possible DEADLOCK! context=\(ctx)",
                        category: .performance,
                        context: unblockCtx
                    )
                } else if totalBlocked >= criticalThreshold {
                    AppLogger.warning(
                        "🧊🧊 [WATCHDOG] Main thread unblocked after \(String(format: "%.1f", totalBlocked))s (CRITICAL) context=\(ctx)",
                        category: .performance,
                        context: unblockCtx
                    )
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
        var endThread: String?
        
        var durationMs: Double? {
            guard let end = endOffset else { return nil }
            return (end - startOffset) * 1000
        }
        
        var effectiveThread: String {
            guard let et = endThread else { return thread }
            if thread == et { return thread }
            return "mixed"
        }
    }
    
    private init() {}

    // Phase 4 (Snappiness Overhaul, 2026-05-07): runtime-detected thread tag.
    //
    // The previous shape was `Thread.isMainThread ? "main" : "bg"` — fine for
    // distinguishing "this ran on the main actor" from "this didn't", but it
    // reported `[bg]` for every off-main task regardless of QoS. The intel
    // build / similarity-map / TabPreloader chains all run at different QoS
    // classes (background vs userInitiated vs utility), and a freeze on a
    // userInitiated bg task is a very different signal from a slow .background
    // task. Reading `Thread.current.qualityOfService` lets the waterfall
    // attribute work to the correct lane. Gated on `PerfFlags.phase4Telemetry`
    // at each emit site so the existing waterfall format stays byte-identical
    // when the flag is off.
    private static var threadTag: String {
        if Thread.isMainThread { return "main" }
        switch Thread.current.qualityOfService {
        case .userInteractive: return "bg-ui"
        case .userInitiated:   return "bg-init"
        case .utility:         return "bg-util"
        case .background:      return "bg-bg"
        case .default:         return "bg-default"
        @unknown default:      return "bg-unknown"
        }
    }

    /// Mark the START of an operation. Returns immediately.
    func mark(_ label: String) {
        let offset = CACurrentMediaTime() - appLaunch
        let thread: String
        if PerfFlags.phase4Telemetry {
            thread = Self.threadTag
        } else {
            thread = Thread.isMainThread ? "main" : "bg"
        }
        lock.lock()
        events.append(Event(label: label, startOffset: offset, endOffset: nil, thread: thread))
        lock.unlock()
    }
    
    /// Mark the END of a previously-started operation.
    func end(_ label: String) {
        let offset = CACurrentMediaTime() - appLaunch
        let thread: String
        if PerfFlags.phase4Telemetry {
            thread = Self.threadTag
        } else {
            thread = Thread.isMainThread ? "main" : "bg"
        }
        lock.lock()
        if let idx = events.lastIndex(where: { $0.label == label && $0.endOffset == nil }) {
            events[idx].endOffset = offset
            events[idx].endThread = thread
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
            let thr = event.effectiveThread
            let durStr: String
            if let dur = event.durationMs {
                durStr = String(format: "%5.0fms", dur)
                if thr == "main" { mainThreadMs += dur }
            } else {
                durStr = "  ···  "
            }
            let warn = (event.durationMs ?? 0) > 500 && thr == "main" ? " ⚠️" : ""
            lines.append("  \(String(format: "%6.0f", startMs))ms \(durStr)  [\(thr)]  \(event.label)\(warn)")
        }
        
        lines.append("  ──────   ─────  ───  ─────────────────────────────────────")
        lines.append("  Main thread budget: \(String(format: "%.0f", mainThreadMs))ms")
        lines.append("═══════════════════════════════════════════════════════════════")
        
        for line in lines {
            AppLogger.debug(line, category: .performance)
        }
    }
    
    /// Returns the total milliseconds of work that ran entirely on the main thread.
    func mainThreadBudgetMs() -> Int {
        lock.lock()
        let snapshot = events
        lock.unlock()
        var total: Double = 0
        for event in snapshot {
            if let dur = event.durationMs, event.effectiveThread == "main" {
                total += dur
            }
        }
        return Int(total)
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
// MARK: - 8. (was FetchOptimizer — removed 2026-05-03 perf sprint)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Three static helpers that were never called:
//   • `FetchOptimizer.optimizedWorkoutFetch(limit:)` — 0 call sites
//   • `FetchOptimizer.optimizedExerciseFetch(limit:)` — 0 call sites
//   • `FetchOptimizer.backgroundFetch(request:context:)` — 0 call sites
//
// In practice each `@FetchRequest` site applies these settings inline
// (see `DashboardView` `recentWorkouts` with `fetchLimit: 10` +
// `returnsObjectsAsFaults: true`), and bulk background fetches use
// `bgContext.perform { context.fetch(request) }` directly — there's no
// shared call shape that benefits from a wrapper. Removed.

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

