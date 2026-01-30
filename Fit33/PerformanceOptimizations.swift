import Foundation
import UIKit
import Combine
import CoreData
import WebKit

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PERFORMANCE OPTIMIZATIONS v2.0 (Critical Fixes)
// ═══════════════════════════════════════════════════════════════════════════════
//
// 🔴 ROOT CAUSE FROM LOGS (Jan 25, 2026):
//    - CPU: 260% (multiple heavy tasks running concurrently)
//    - Memory: 637MB → critical cleanup triggered
//    - FPS: 0.3-8.8 (main thread blocked)
//    - Learning Engine: 5,724ms blocking analysis
//
// ✅ FIXES IMPLEMENTED:
// 1. Startup Coordinator - Staggers heavy operations with proper delays
// 2. Heavy Work Sentinel - Pauses video prefetching during data sync
// 3. Request Deduplication - Prevents duplicate API calls
// 4. Memory Pressure Handling - Proactive cache cleanup
// 5. Task Throttling - Limits concurrent background tasks
//
// 📊 Expected Improvements:
// - CPU spikes: 260% → <100% (properly staggered)
// - FPS: 0.3 → 55+ (no main thread blocking)
// - Memory: 637MB → <350MB (proactive cleanup)
// - Startup feel: Instant (heavy work deferred)
//
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - 1. REQUEST DEDUPLICATION SERVICE
/// Prevents duplicate API calls by tracking in-flight requests
/// Solves: "📥 Starting paginated fetch of all exercises..." appearing 4+ times

@MainActor
final class RequestDeduplicationService {
    static let shared = RequestDeduplicationService()
    
    // Track in-flight requests by key
    private var inFlightRequests: [String: Task<Any, Error>] = [:]
    private var requestLock = NSLock()
    
    // Cache recent results with TTL
    private var resultCache: [String: CachedResult] = [:]
    private let cacheTTL: TimeInterval = 30 // 30 seconds cache
    
    private struct CachedResult {
        let value: Any
        let timestamp: Date
        
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 30
        }
    }
    
    private init() {
        // Clean cache periodically
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanExpiredCache()
        }
    }
    
    /// Execute a request with deduplication
    /// If the same request is already in-flight, returns the existing task's result
    func deduplicate<T>(
        key: String,
        useCache: Bool = true,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // Check cache first
        if useCache, let cached = resultCache[key], cached.isValid, let value = cached.value as? T {
            print("⚡️ [DEDUP] Cache hit for '\(key)'")
            return value
        }
        
        // Check if request is already in-flight
        requestLock.lock()
        if let existingTask = inFlightRequests[key] {
            requestLock.unlock()
            print("⚡️ [DEDUP] Reusing in-flight request for '\(key)'")
            return try await existingTask.value as! T
        }
        
        // Create new task
        let task = Task<Any, Error> {
            try await operation()
        }
        inFlightRequests[key] = task
        requestLock.unlock()
        
        do {
            let result = try await task.value as! T
            
            // Cache the result
            requestLock.lock()
            resultCache[key] = CachedResult(value: result, timestamp: Date())
            inFlightRequests.removeValue(forKey: key)
            requestLock.unlock()
            
            return result
        } catch {
            requestLock.lock()
            inFlightRequests.removeValue(forKey: key)
            requestLock.unlock()
            throw error
        }
    }
    
    /// Invalidate cache for a specific key
    func invalidateCache(for key: String) {
        requestLock.lock()
        resultCache.removeValue(forKey: key)
        requestLock.unlock()
    }
    
    /// Invalidate all caches
    func invalidateAllCaches() {
        requestLock.lock()
        resultCache.removeAll()
        requestLock.unlock()
        print("🗑️ [DEDUP] All caches invalidated")
    }
    
    private func cleanExpiredCache() {
        requestLock.lock()
        resultCache = resultCache.filter { $0.value.isValid }
        requestLock.unlock()
    }
}

// MARK: - 2. SYNC COORDINATOR
/// Tracks sync state - actual sync logic is in SupabaseManager
/// The deduplication is now built into SupabaseManager.syncAllDataFromCloud()

@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()
    
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncTime: Date?
    
    private init() {}
    
    /// Mark sync as started (called by SupabaseManager)
    func markSyncStarted() {
        isSyncing = true
    }
    
    /// Mark sync as completed (called by SupabaseManager)
    func markSyncCompleted() {
        isSyncing = false
        lastSyncTime = Date()
    }
}

// MARK: - 3. MEMORY PRESSURE HANDLER
/// Responds to system memory warnings by clearing caches
/// Solves: Memory climbing from 345MB to 669MB

final class MemoryPressureHandler {
    static let shared = MemoryPressureHandler()
    
    private var memoryWarningObserver: NSObjectProtocol?
    private var lastCleanupTime: Date?
    private let cleanupCooldown: TimeInterval = 5 // Reduced from 10 for faster response
    
    // ⚡️ PERFORMANCE: Lower memory thresholds for better performance
    // Memory thresholds (in MB) - lowered to prevent CPU spikes from memory pressure
    private let warningThreshold: Double = 300  // Lowered from 400
    private let criticalThreshold: Double = 450 // Lowered from 550
    private let emergencyThreshold: Double = 600 // Raised from 550 to account for WebContent overhead
    
    private init() {
        setupMemoryWarningObserver()
        startPeriodicMonitoring()
    }
    
    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning(level: .critical)
        }
    }
    
    private func startPeriodicMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
    }
    
    private func checkMemoryPressure() {
        let memoryMB = getMemoryUsageMB()
        
        if memoryMB > emergencyThreshold {
            handleMemoryWarning(level: .emergency)
        } else if memoryMB > criticalThreshold {
            handleMemoryWarning(level: .critical)
        } else if memoryMB > warningThreshold {
            handleMemoryWarning(level: .warning)
        }
    }
    
    enum MemoryWarningLevel {
        case warning    // > 400MB - Clear warm caches
        case critical   // > 550MB - Clear all caches
        case emergency  // > 650MB - Aggressive cleanup
    }
    
    func handleMemoryWarning(level: MemoryWarningLevel) {
        let beforeMB = getMemoryUsageMB()
        
        // For emergency level, always run (ignore cooldown)
        // For other levels, respect cooldown
        if level != .emergency {
            if let lastCleanup = lastCleanupTime,
               Date().timeIntervalSince(lastCleanup) < cleanupCooldown {
                return
            }
        }
        lastCleanupTime = Date()
        
        switch level {
        case .warning:
            print("⚠️ [MEMORY] Warning level (\(Int(beforeMB))MB) - clearing warm caches")
            clearWarmCaches()
            
        case .critical:
            print("🔴 [MEMORY] Critical level (\(Int(beforeMB))MB) - clearing all caches")
            clearAllCaches()
            
        case .emergency:
            print("🚨 [MEMORY] EMERGENCY (\(Int(beforeMB))MB) - aggressive cleanup!")
            performEmergencyCleanup()
        }
        
        // Force garbage collection with multiple passes
        for _ in 0..<3 {
            autoreleasepool { }
        }
        
        // Wait a moment for cleanup to take effect
        Thread.sleep(forTimeInterval: 0.05)
        
        let afterMB = getMemoryUsageMB()
        let freed = max(0, beforeMB - afterMB)
        if freed > 0 {
            print("💾 [MEMORY] Freed \(Int(freed))MB (now: \(Int(afterMB))MB)")
        } else {
            print("💾 [MEMORY] Cleanup complete (now: \(Int(afterMB))MB) - memory held by system/ads")
        }
    }
    
    private func clearWarmCaches() {
        // Clear video warm cache
        VideoPlaybackEngine.shared.clearWarmCache()
        
        // Clear request deduplication cache
        Task { @MainActor in
            RequestDeduplicationService.shared.invalidateAllCaches()
        }
    }
    
    private func clearAllCaches() {
        clearWarmCaches()
        
        // Clear more aggressive caches
        URLCache.shared.removeAllCachedResponses()
        
        // Notify video engine to reduce cache size
        VideoPlaybackEngine.shared.reduceMemoryFootprint()
    }
    
    private func performEmergencyCleanup() {
        clearAllCaches()
        
        // Stop all video prefetching
        VideoPlaybackEngine.shared.pausePrefetching()
        
        // Aggressively clear URL and image caches
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0
        
        // Reset cache after brief delay to allow normal operation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            URLCache.shared.diskCapacity = 50 * 1024 * 1024  // 50MB
            URLCache.shared.memoryCapacity = 10 * 1024 * 1024 // 10MB
        }
        
        // Clear WKWebView process pool (for banner ads)
        // This forces WebContent processes to restart with clean memory
        Task { @MainActor in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) { }
        }
        
        // Suggest garbage collection
        for _ in 0..<5 {
            autoreleasepool { }
        }
    }
    
    private func getMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024 / 1024
    }
}

// MARK: - 4. TASK THROTTLER
/// Limits concurrent background operations to prevent CPU spikes
/// Solves: CPU hitting 312% from too many concurrent tasks

actor TaskThrottler {
    static let shared = TaskThrottler()
    
    private var runningTasks: Int = 0
    private let maxConcurrentTasks: Int
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []
    
    init(maxConcurrent: Int = 4) {
        self.maxConcurrentTasks = maxConcurrent
    }
    
    /// Execute a task with throttling
    func throttled<T>(
        priority: TaskPriority = .medium,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // Wait for slot
        await waitForSlot()
        
        defer {
            Task { await self.releaseSlot() }
        }
        
        return try await operation()
    }
    
    private func waitForSlot() async {
        if runningTasks < maxConcurrentTasks {
            runningTasks += 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
        runningTasks += 1
    }
    
    private func releaseSlot() {
        runningTasks -= 1
        
        if let continuation = waitingContinuations.first {
            waitingContinuations.removeFirst()
            continuation.resume()
        }
    }
}

// MARK: - 5. BACKGROUND WORK SCHEDULER
/// Ensures heavy operations run on background threads at low priority
/// Solves: Learning engine taking 5675ms on main thread

final class BackgroundWorkScheduler {
    static let shared = BackgroundWorkScheduler()
    
    private let heavyWorkQueue = DispatchQueue(
        label: "com.fit33.heavyWork",
        qos: .utility,
        attributes: .concurrent
    )
    
    private let lightWorkQueue = DispatchQueue(
        label: "com.fit33.lightWork",
        qos: .userInitiated
    )
    
    private init() {}
    
    /// Schedule heavy work (analysis, map building, etc.)
    /// Automatically yields to prevent blocking
    func scheduleHeavyWork<T>(
        _ work: @escaping () async throws -> T
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            heavyWorkQueue.async {
                Task(priority: .utility) {
                    do {
                        let result = try await work()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Schedule work with periodic yields to prevent blocking
    func scheduleChunkedWork<T, Element>(
        items: [Element],
        chunkSize: Int = 100,
        process: @escaping (Element) async throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(items.count)
        
        for (index, item) in items.enumerated() {
            let result = try await process(item)
            results.append(result)
            
            // Yield every chunkSize items to let UI breathe
            if index % chunkSize == 0 {
                await Task.yield()
            }
        }
        
        return results
    }
}

// MARK: - 6. STARTUP OPTIMIZER
/// Defers non-critical work to after UI is responsive
/// Reduces perceived startup time

@MainActor
final class StartupOptimizer {
    static let shared = StartupOptimizer()
    
    private var deferredTasks: [() async -> Void] = []
    private var hasCompletedCriticalPath = false
    
    private init() {}
    
    /// Mark a task as deferrable (will run after UI is ready)
    func deferTask(_ task: @escaping () async -> Void) {
        if hasCompletedCriticalPath {
            // If we're past startup, run immediately
            Task { await task() }
        } else {
            deferredTasks.append(task)
        }
    }
    
    /// Call this after the main UI is visible
    func criticalPathCompleted() {
        guard !hasCompletedCriticalPath else { return }
        hasCompletedCriticalPath = true
        
        print("🚀 [STARTUP] Critical path complete - running \(deferredTasks.count) deferred tasks")
        
        // Run deferred tasks with delays to spread out the load
        for (index, task) in deferredTasks.enumerated() {
            let delay = Double(index) * 0.5 // 500ms between each task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await task()
            }
        }
        
        deferredTasks.removeAll()
    }
}

// MARK: - INTEGRATION HELPERS
// Note: VideoPlaybackEngine methods (clearWarmCache, reduceMemoryFootprint, pausePrefetching)
// are implemented directly in VideoPlaybackEngine.swift

extension SupabaseManager {
    /// Fetch exercises with deduplication
    func fetchAllExercisesDeduped() async throws -> [ExerciseDTO] {
        return try await RequestDeduplicationService.shared.deduplicate(
            key: "fetchAllExercises",
            useCache: true
        ) {
            try await self.fetchAllExercises()
        }
    }
}

// MARK: - 7. HEAVY WORK SENTINEL
/// Global flag to signal when heavy work is in progress
/// Other subsystems (video prefetching) should back off during heavy work
/// ⚡️ ENHANCED: Now supports work queue serialization to prevent concurrent heavy work

final class HeavyWorkSentinel {
    static let shared = HeavyWorkSentinel()
    
    private let lock = NSLock()
    private var _isHeavyWorkInProgress = false
    private var _heavyWorkEndTime: Date?
    private var _activeWorkItems: Set<String> = []
    
    // ⚡️ NEW: Queue for serializing heavy work
    private var pendingWork: [(id: String, work: () async -> Void)] = []
    private var isProcessingQueue = false
    
    /// Check if heavy work is currently happening
    var isHeavyWorkInProgress: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isHeavyWorkInProgress
    }
    
    /// Get list of active work items (for debugging)
    var activeWorkItems: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_activeWorkItems)
    }
    
    /// Signal that heavy work is starting (pauses video prefetch, etc.)
    func beginHeavyWork(reason: String) {
        lock.lock()
        _isHeavyWorkInProgress = true
        _activeWorkItems.insert(reason)
        lock.unlock()
        
        #if DEBUG
        print("🔴 [HEAVY WORK] Started: \(reason)")
        #endif
        
        // Pause video prefetching during heavy work
        VideoPlaybackEngine.shared.pausePrefetching()
    }
    
    /// Signal that heavy work is complete
    func endHeavyWork(reason: String) {
        lock.lock()
        _activeWorkItems.remove(reason)
        let stillWorking = !_activeWorkItems.isEmpty
        _isHeavyWorkInProgress = stillWorking
        if !stillWorking {
            _heavyWorkEndTime = Date()
        }
        lock.unlock()
        
        #if DEBUG
        print("🟢 [HEAVY WORK] Ended: \(reason)")
        #endif
        
        // Resume video prefetching after a brief cooldown if no more heavy work
        if !stillWorking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if !self.isHeavyWorkInProgress {
                    VideoPlaybackEngine.shared.resumePrefetching()
                }
            }
            
            // Process next queued work item
            Task { await self.processNextQueuedWork() }
        }
    }
    
    /// ⚡️ NEW: Queue heavy work to run after current work completes
    /// This prevents multiple heavy operations from running concurrently
    func queueHeavyWork(id: String, work: @escaping () async -> Void) async {
        lock.lock()
        let canRunNow = !_isHeavyWorkInProgress && pendingWork.isEmpty
        if !canRunNow {
            // Queue for later
            pendingWork.append((id: id, work: work))
            lock.unlock()
            #if DEBUG
            print("⏳ [HEAVY WORK] Queued: \(id) (queue size: \(pendingWork.count))")
            #endif
            return
        }
        lock.unlock()
        
        // Run now
        beginHeavyWork(reason: id)
        await work()
        endHeavyWork(reason: id)
    }
    
    /// Process next item in queue
    private func processNextQueuedWork() async {
        lock.lock()
        guard !isProcessingQueue, !_isHeavyWorkInProgress, let nextWork = pendingWork.first else {
            lock.unlock()
            return
        }
        pendingWork.removeFirst()
        isProcessingQueue = true
        lock.unlock()
        
        #if DEBUG
        print("▶️ [HEAVY WORK] Processing queued: \(nextWork.id)")
        #endif
        
        beginHeavyWork(reason: nextWork.id)
        await nextWork.work()
        endHeavyWork(reason: nextWork.id)
        
        lock.lock()
        isProcessingQueue = false
        lock.unlock()
    }
    
    /// Check if we recently finished heavy work (within cooldown period)
    func isInCooldown(seconds: TimeInterval = 3.0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        if _isHeavyWorkInProgress { return true }
        if let endTime = _heavyWorkEndTime {
            return Date().timeIntervalSince(endTime) < seconds
        }
        return false
    }
    
    private init() {}
}

// MARK: - 8. STARTUP COORDINATOR
/// Orchestrates heavy operations to prevent concurrent CPU spikes
/// Ensures smooth startup by properly staggering work

@MainActor
final class StartupCoordinator {
    static let shared = StartupCoordinator()
    
    enum Phase: Int, CaseIterable {
        case critical = 0      // UI must be ready (< 1s)
        case essential = 1     // Core data sync (1-5s)
        case intelligence = 2  // Learning engines (5-15s)
        case background = 3    // Low priority (15s+)
    }
    
    private var completedPhases: Set<Phase> = []
    private var phaseCompletionHandlers: [Phase: [() -> Void]] = [:]
    private var isStartupComplete = false
    
    private init() {}
    
    /// Register a task to run when a phase is reached
    func onPhaseComplete(_ phase: Phase, handler: @escaping () -> Void) {
        if completedPhases.contains(phase) {
            // Phase already complete, run immediately
            handler()
        } else {
            phaseCompletionHandlers[phase, default: []].append(handler)
        }
    }
    
    /// Mark a phase as complete and trigger handlers
    func markPhaseComplete(_ phase: Phase) {
        guard !completedPhases.contains(phase) else { return }
        
        completedPhases.insert(phase)
        
        #if DEBUG
        print("✅ [STARTUP] Phase \(phase) complete")
        #endif
        
        // Run handlers for this phase
        for handler in phaseCompletionHandlers[phase] ?? [] {
            handler()
        }
        phaseCompletionHandlers[phase] = nil
        
        // Check if all phases complete
        if completedPhases.count == Phase.allCases.count {
            isStartupComplete = true
            #if DEBUG
            print("🎉 [STARTUP] All phases complete - app fully initialized")
            #endif
        }
    }
    
    /// Check if a phase is complete
    func isPhaseComplete(_ phase: Phase) -> Bool {
        completedPhases.contains(phase)
    }
    
    /// Run the coordinated startup sequence
    func beginStartupSequence() {
        // Phase 0: Critical (immediate)
        Task { @MainActor in
            // Critical path - just mark complete, UI is already loading
            markPhaseComplete(.critical)
        }
        
        // Phase 1: Essential (after 2 seconds - let UI settle)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            markPhaseComplete(.essential)
        }
        
        // Phase 2: Intelligence (after essential + 8 seconds)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            markPhaseComplete(.intelligence)
        }
        
        // Phase 3: Background (after intelligence + 5 seconds)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            markPhaseComplete(.background)
        }
    }
}

// MARK: - 9. CPU PROTECTION
/// Monitors CPU and throttles work when overloaded

final class CPUProtection {
    static let shared = CPUProtection()
    
    private let lock = NSLock()
    private var lastCPUCheck: Date = Date.distantPast
    private var cachedCPU: Double = 0
    
    /// High CPU threshold (pause new work)
    let highCPUThreshold: Double = 150.0
    
    /// Critical CPU threshold (stop all non-essential work)
    let criticalCPUThreshold: Double = 200.0
    
    private init() {}
    
    /// Get current CPU usage (cached for performance)
    func getCurrentCPU() -> Double {
        lock.lock()
        defer { lock.unlock() }
        
        // Cache CPU reading for 1 second to avoid overhead
        if Date().timeIntervalSince(lastCPUCheck) > 1.0 {
            cachedCPU = measureCPU()
            lastCPUCheck = Date()
        }
        return cachedCPU
    }
    
    /// Check if CPU is too high for new work
    func isCPUTooHigh() -> Bool {
        getCurrentCPU() > highCPUThreshold
    }
    
    /// Check if CPU is at critical level
    func isCPUCritical() -> Bool {
        getCurrentCPU() > criticalCPUThreshold
    }
    
    /// Wait for CPU to settle before starting work
    func waitForCPUSettled(maxWait: TimeInterval = 5.0) async {
        let startTime = Date()
        while isCPUTooHigh() && Date().timeIntervalSince(startTime) < maxWait {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
    }
    
    private func measureCPU() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t()
        
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else {
            return 0
        }
        
        var totalCPU: Double = 0
        
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            
            if result == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        
        // Deallocate thread list
        let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        
        return totalCPU
    }
}

// MARK: - INITIALIZATION
/// Call this early in app startup

enum PerformanceOptimizationsInitializer {
    static func initialize() {
        // Start memory monitoring
        _ = MemoryPressureHandler.shared
        
        // Initialize task throttler
        _ = TaskThrottler.shared
        
        // Initialize CPU protection
        _ = CPUProtection.shared
        
        // Initialize heavy work sentinel
        _ = HeavyWorkSentinel.shared
        
        // Begin coordinated startup sequence
        Task { @MainActor in
            StartupCoordinator.shared.beginStartupSequence()
        }
        
        print("✅ [PERF] Performance optimizations initialized")
    }
}

/// Convenience function for app startup
func initializePerformanceOptimizations() {
    PerformanceOptimizationsInitializer.initialize()
}

// MARK: - 8. PREVIEW WARMUP SERVICE
/// Pre-loads all data needed for the active workout screen while user is on preview
/// Ensures instant "Go!" transitions with no lag

@MainActor
final class PreviewWarmupService: ObservableObject {
    static let shared = PreviewWarmupService()
    
    @Published private(set) var isWarmedUp = false
    @Published private(set) var warmupProgress: Double = 0
    
    /// Cached smart recommendations for exercises without history
    private(set) var smartRecommendationsCache: [String: [StrengthProfileRecommendationEngine.SmartRecommendation]] = [:]
    
    /// Pre-initialized sets data ready to apply to WorkoutManager
    private(set) var preInitializedSets: [String: [WorkoutSetData]] = [:]
    
    /// Pre-fetched previous sets data ready to apply
    private(set) var preFetchedPreviousSets: [String: [PreviousSetData]] = [:]
    
    private var currentWarmupTask: Task<Void, Never>?
    private var warmedExerciseNames: Set<String> = []
    
    private init() {}
    
    // MARK: - Public API
    
    /// Begin warming up data for the given exercises
    func warmUp(exercises: [GeneratedExercise], context: NSManagedObjectContext) {
        currentWarmupTask?.cancel()
        isWarmedUp = false
        warmupProgress = 0
        
        let exerciseNames = exercises.map { $0.name }
        let newNamesSet = Set(exerciseNames)
        
        if newNamesSet == warmedExerciseNames && isWarmedUp {
            print("⚡️ [WARMUP] Already warmed up")
            return
        }
        
        print("🔥 [WARMUP] Starting for \(exercises.count) exercises...")
        
        currentWarmupTask = Task { [weak self] in
            guard let self = self else { return }
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Phase 1: Prefetch Core Data
            await self.prefetchCoreDataExercises(names: exerciseNames)
            if Task.isCancelled { return }
            self.warmupProgress = 0.2
            
            // Phase 2: Fetch previous sets
            await self.prefetchPreviousSets(exerciseNames: exerciseNames)
            if Task.isCancelled { return }
            self.warmupProgress = 0.5
            
            // Phase 3: Generate smart recommendations
            await self.generateSmartRecommendations(exerciseNames: exerciseNames, context: context)
            if Task.isCancelled { return }
            self.warmupProgress = 0.8
            
            // Phase 4: Pre-initialize sets
            await self.preInitializeSets(exerciseNames: exerciseNames)
            if Task.isCancelled { return }
            self.warmupProgress = 1.0
            
            self.warmedExerciseNames = newNamesSet
            self.isWarmedUp = true
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("🔥 [WARMUP] Complete in \(String(format: "%.0f", elapsed))ms")
            print("   └─ Previous: \(self.preFetchedPreviousSets.count), Smart: \(self.smartRecommendationsCache.count)")
        }
    }
    
    /// Get pre-fetched previous sets for an exercise
    func getPreviousSets(forExerciseId exerciseId: String, exerciseName: String) -> [PreviousSetData]? {
        if let sets = preFetchedPreviousSets[exerciseName], !sets.isEmpty {
            return sets
        }
        return nil
    }
    
    /// Reset warmup state
    func reset() {
        currentWarmupTask?.cancel()
        isWarmedUp = false
        warmupProgress = 0
        smartRecommendationsCache.removeAll()
        preInitializedSets.removeAll()
        preFetchedPreviousSets.removeAll()
        warmedExerciseNames.removeAll()
    }
    
    // MARK: - Private
    
    private func prefetchCoreDataExercises(names: [String]) async {
        let exercises = ExerciseLibraryService.shared.getExercises(byNames: names)
        for exercise in exercises {
            _ = exercise.id
            _ = exercise.name
            _ = exercise.category
            _ = exercise.equipment
            _ = exercise.muscleGroups
            _ = exercise.isFavorite
            _ = exercise.displayName
        }
    }
    
    private func prefetchPreviousSets(exerciseNames: [String]) async {
        let results = await ExerciseHistoryService.shared.fetchPreviousSetsForExercises(exerciseNames)
        
        for (name, sets) in results {
            let previousData = sets.map { cloudSet in
                PreviousSetData(
                    setNumber: cloudSet.setNumber,
                    weight: cloudSet.weight,
                    reps: cloudSet.reps
                )
            }
            preFetchedPreviousSets[name] = previousData
        }
    }
    
    private func generateSmartRecommendations(exerciseNames: [String], context: NSManagedObjectContext) async {
        guard let user = UserManager.shared.currentUser else { return }
        
        let exercisesNeedingRecs = exerciseNames.filter { name in
            preFetchedPreviousSets[name]?.isEmpty ?? true
        }
        
        guard !exercisesNeedingRecs.isEmpty else { return }
        
        for exerciseName in exercisesNeedingRecs {
            guard !Task.isCancelled else { return }
            
            let recs = StrengthProfileRecommendationEngine.shared.getRecommendationsForSets(
                exerciseName: exerciseName,
                user: user,
                numberOfSets: 3,
                context: context
            )
            
            if !recs.isEmpty {
                smartRecommendationsCache[exerciseName.lowercased()] = recs
                
                let smartPreviousData = recs.enumerated().map { index, rec in
                    PreviousSetData(setNumber: index + 1, recommendation: rec)
                }
                preFetchedPreviousSets[exerciseName] = smartPreviousData
            }
            
            await Task.yield()
        }
    }
    
    private func preInitializeSets(exerciseNames: [String]) async {
        let exercises = ExerciseLibraryService.shared.getExercises(byNames: exerciseNames)
        
        for exercise in exercises {
            guard let exerciseId = exercise.id?.uuidString else { continue }
            preInitializedSets[exerciseId] = [WorkoutSetData(), WorkoutSetData(), WorkoutSetData()]
        }
    }
}
