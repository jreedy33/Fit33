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
    
    private var inFlightRequests: [String: Task<Any, Error>] = [:]
    
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
    
    private var cleanupTimer: Timer?
    
    private init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanExpiredCache()
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
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
            AppLogger.debug("⚡️ [DEDUP] Cache hit for '\(key)'", category: .general)
            return value
        }
        
        if let existingTask = inFlightRequests[key] {
            AppLogger.debug("⚡️ [DEDUP] Reusing in-flight request for '\(key)'", category: .general)
            let existingResult = try await existingTask.value
            guard let typedResult = existingResult as? T else {
                throw NSError(domain: "RequestDeduplication", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Type mismatch for deduplicated request '\(key)'"])
            }
            return typedResult
        }
        
        let task = Task<Any, Error> {
            try await operation()
        }
        inFlightRequests[key] = task
        
        do {
            let rawResult = try await task.value
            guard let result = rawResult as? T else {
                inFlightRequests.removeValue(forKey: key)
                throw NSError(domain: "RequestDeduplication", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Type mismatch for request '\(key)'"])
            }
            
            resultCache[key] = CachedResult(value: result, timestamp: Date())
            inFlightRequests.removeValue(forKey: key)
            
            return result
        } catch {
            inFlightRequests.removeValue(forKey: key)
            throw error
        }
    }
    
    func invalidateCache(for key: String) {
        resultCache.removeValue(forKey: key)
    }
    
    func invalidateAllCaches() {
        resultCache.removeAll()
        AppLogger.debug("🗑️ [DEDUP] All caches invalidated", category: .general)
    }
    
    private func cleanExpiredCache() {
        resultCache = resultCache.filter { $0.value.isValid }
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
    private var lastEmergencyTime: Date?
    private var emergencyAttemptCount: Int = 0
    private var criticalFailCount: Int = 0 // Track consecutive critical cleanups that freed 0 bytes
    private let maxCriticalAttempts: Int = 3 // Stop critical cleanup after 3 failed attempts
    private let cleanupCooldown: TimeInterval = 15 // Generous cooldown to prevent main thread churn
    private let emergencyCooldown: TimeInterval = 60 // Prevent emergency spam loop
    private let maxEmergencyAttempts: Int = 3 // Stop after 3 failed attempts
    
    // ⚡️ MEMORY THRESHOLDS — tuned for iPhone 16 Pro (8GB RAM)
    // The app's normal working set is ~400-550MB after loading 5500+ exercises,
    // intelligence engine, and all services. Thresholds must be ABOVE that baseline
    // or the cleanup loop fires endlessly, blocks the main thread, and causes UI freezes.
    private let warningThreshold: Double = 550  // Light cleanup (warm caches only)
    private let criticalThreshold: Double = 700 // Full cache clear
    private let emergencyThreshold: Double = 850 // Aggressive teardown
    
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
            // OS memory warning — always respect, but use the cooldown
            self?.handleMemoryWarning(level: .critical)
        }
    }
    
    private func startPeriodicMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
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
        } else {
            // Memory is back to healthy — reset all attempt counters
            if emergencyAttemptCount > 0 || criticalFailCount > 0 {
                emergencyAttemptCount = 0
                criticalFailCount = 0
                #if DEBUG
                AppLogger.info("✅ [MEMORY] Memory healthy (\(Int(memoryMB))MB) — counters reset", category: .general)
                #endif
            }
        }
    }
    
    enum MemoryWarningLevel {
        case warning    // > 550MB - Clear warm caches
        case critical   // > 700MB - Clear all caches
        case emergency  // > 850MB - Aggressive cleanup
    }
    
    func handleMemoryWarning(level: MemoryWarningLevel) {
        let beforeMB = getMemoryUsageMB()
        let now = Date()
        
        // 🔍 FREEZE DEBUG: Log if memory cleanup happens during a tab transition
        // (Use watchdog's thread-safe context instead of @MainActor TabSwitchOptimizer)
        let isDuringTabSwitch = MainThreadWatchdog.shared.isTabSwitchActive
        if isDuringTabSwitch {
            AppLogger.warning("🔍 [TAB FREEZE] ⚠️ MEMORY CLEANUP during active tab transition! level=\(level) memory=\(Int(beforeMB))MB thread=\(Thread.isMainThread ? "MAIN" : "bg")", category: .general)
        }
        
        // Respect cooldown for ALL levels to prevent main-thread churn
        if level == .emergency {
            if emergencyAttemptCount >= maxEmergencyAttempts { return }
            if let lastEmergency = lastEmergencyTime,
               now.timeIntervalSince(lastEmergency) < emergencyCooldown { return }
            lastEmergencyTime = now
            emergencyAttemptCount += 1
        } else {
            // Skip critical cleanup if previous attempts freed nothing
            if level == .critical && criticalFailCount >= maxCriticalAttempts { return }
            
            if let lastCleanup = lastCleanupTime,
               now.timeIntervalSince(lastCleanup) < cleanupCooldown { return }
        }
        lastCleanupTime = now
        
        let cleanupStart = CACurrentMediaTime()
        
        switch level {
        case .warning:
            AppLogger.warning("⚠️ [MEMORY] Warning level (\(Int(beforeMB))MB) - clearing warm caches", category: .general)
            clearWarmCaches()
            
        case .critical:
            AppLogger.debug("🔴 [MEMORY] Critical level (\(Int(beforeMB))MB) - clearing all caches", category: .general)
            clearAllCaches()
            
        case .emergency:
            AppLogger.debug("🚨 [MEMORY] EMERGENCY (\(Int(beforeMB))MB) - aggressive cleanup! (attempt \(emergencyAttemptCount)/\(maxEmergencyAttempts))", category: .general)
            performEmergencyCleanup()
        }
        
        let cleanupMs = (CACurrentMediaTime() - cleanupStart) * 1000
        if cleanupMs > 50 || isDuringTabSwitch {
            AppLogger.debug("🔍 [TAB FREEZE] Memory cleanup took \(String(format: "%.1f", cleanupMs))ms (during_tab_switch=\(isDuringTabSwitch))", category: .general)
        }
        
        // Check if cleanup had any effect (no Thread.sleep — never block main thread)
        let afterMB = getMemoryUsageMB()
        let freed = max(0, beforeMB - afterMB)
        if freed > 5 {
            // Reset fail counter on success
            criticalFailCount = 0
            AppLogger.debug("💾 [MEMORY] Freed \(Int(freed))MB (now: \(Int(afterMB))MB)", category: .general)
        } else if level == .critical {
            criticalFailCount += 1
            if criticalFailCount >= maxCriticalAttempts {
                AppLogger.debug("ℹ️ [MEMORY] Critical cleanup ineffective \(criticalFailCount)x — suppressing until memory drops", category: .general)
            }
        } else if level == .emergency && freed <= 5 {
            AppLogger.debug("💾 [MEMORY] Emergency cleanup had no effect (\(Int(afterMB))MB) — memory held by active objects", category: .general)
        }
    }
    
    // ⚡️ MEMORY FIX: Comprehensive cleanup across ALL caching systems.
    // Previously only cleared VideoPlaybackEngine warm cache — missed 5+ other caches.
    
    private func clearWarmCaches() {
        // Clear video warm cache (VideoPlaybackEngine)
        VideoPlaybackEngine.shared.clearWarmCache()
        
        // Clear VideoPreloadManager cache (separate AVPlayer pool)
        VideoPreloadManager.shared.reduceCache()
        
        // Clear VideoStreamingService preloaded players
        VideoStreamingService.shared.clearPreloadCache()
        
        // Clear request deduplication cache
        Task { @MainActor in
            RequestDeduplicationService.shared.invalidateAllCaches()
        }
        
        #if DEBUG
        AppLogger.debug("🧹 [MEMORY] Warm caches cleared (3 video systems + dedup)", category: .general)
        #endif
    }
    
    private func clearAllCaches() {
        clearWarmCaches()
        
        // Clear ALL video caches fully
        VideoPlaybackEngine.shared.reduceMemoryFootprint()
        VideoPreloadManager.shared.clearCache()
        
        // Clear friend photo memory cache (disk cache stays)
        FriendPhotoCache.shared.clearMemoryCache()
        
        // Clear video thumbnail memory cache (disk cache stays — they're tiny)
        VideoThumbnailService.shared.clearMemoryCache()
        
        // Clear URL caches
        URLCache.shared.removeAllCachedResponses()
        
        // Release TabPreloader data if still held
        Task { @MainActor in
            TabPreloader.shared.releaseDataForMemoryPressure()
        }
        
        #if DEBUG
        AppLogger.debug("🧹 [MEMORY] All caches cleared (video + photos + URL + tab data)", category: .network)
        #endif
    }
    
    private func performEmergencyCleanup() {
        clearAllCaches()
        
        // Stop ALL video prefetching across all systems
        VideoPlaybackEngine.shared.pausePrefetching()
        VideoPlaybackEngine.shared.clearAllCaches()
        VideoPreloadManager.shared.clearCache()
        VideoStreamingService.shared.clearPreloadCache()
        
        // Clear profile photo from memory (disk stays)
        ProfilePhotoCache.shared.clearMemoryOnly()
        
        // Aggressively clear URL and image caches
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            URLCache.shared.diskCapacity = 50 * 1024 * 1024  // 50MB
            URLCache.shared.memoryCapacity = 10 * 1024 * 1024 // 10MB
        }
        
        // Clear WKWebView process pool (for banner ads)
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
        
        #if DEBUG
        AppLogger.debug("🚨 [MEMORY] Emergency cleanup complete — all video players, photos, URL caches, and tab data freed", category: .network)
        #endif
    }
    
    private func getMemoryUsageMB() -> Double {
        SystemMetrics.getMemoryUsageMB()
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
        
        AppLogger.debug("🚀 [STARTUP] Critical path complete - running \(deferredTasks.count) deferred tasks", category: .general)
        
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
        AppLogger.debug("🔴 [HEAVY WORK] Started: \(reason)", category: .general)
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
        AppLogger.debug("🟢 [HEAVY WORK] Ended: \(reason)", category: .general)
        #endif
        
        // Resume video prefetching after a brief cooldown if no more heavy work
        if !stillWorking {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { return }
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
            AppLogger.debug("⏳ [HEAVY WORK] Queued: \(id) (queue size: \(pendingWork.count))", category: .general)
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
        AppLogger.debug("▶️ [HEAVY WORK] Processing queued: \(nextWork.id)", category: .general)
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
        AppLogger.info("✅ [STARTUP] Phase \(phase) complete", category: .general)
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
            AppLogger.debug("🎉 [STARTUP] All phases complete - app fully initialized", category: .general)
            #endif
        }
    }
    
    /// Check if a phase is complete
    func isPhaseComplete(_ phase: Phase) -> Bool {
        completedPhases.contains(phase)
    }
    
    /// Event-driven startup: phases fire based on actual completion, not hardcoded timers.
    /// - critical: marked by Fit33App.task after auth + limitations load
    /// - essential: marked by Fit33App.task after syncAllDataFromCloud completes
    /// - intelligence: auto-fires when essential completes + CPU settles
    /// - background: auto-fires when intelligence completes
    ///
    /// Fallback timers ensure phases eventually fire even if events are missed.
    func beginStartupSequence() {
        // Intelligence fires when essential completes (event-driven)
        onPhaseComplete(.essential) {
            Task { @MainActor in
                // Wait for CPU to settle before starting heavy intelligence work
                await CPUProtection.shared.waitForCPUSettled(maxWait: 5.0)
                self.markPhaseComplete(.intelligence)
            }
        }
        
        // Background fires when intelligence completes (event-driven)
        onPhaseComplete(.intelligence) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.markPhaseComplete(.background)
            }
        }
        
        // Safety fallback: if essential never fires (e.g. no auth, offline),
        // mark it after 8 seconds so intelligence isn't blocked forever
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if !self.isPhaseComplete(.essential) {
                AppLogger.warning("[STARTUP] Essential phase fallback timer fired (sync may be slow)", category: .performance)
                self.markPhaseComplete(.essential)
            }
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
        SystemMetrics.getCPUUsage()
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
        
        MainThreadWatchdog.shared.start()
        
        _ = MetricKitSubscriber.shared
        
        ProductionFPSMonitor.shared.start()

        Task { @MainActor in
            StartupCoordinator.shared.beginStartupSequence()
        }

        AppLogger.info("✅ [PERF] Performance optimizations initialized (watchdog + MetricKit + FPS monitor)", category: .general)
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
            AppLogger.debug("⚡️ [WARMUP] Already warmed up", category: .general)
            return
        }
        
        AppLogger.debug("🔥 [WARMUP] Starting for \(exercises.count) exercises...", category: .general)
        
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
            AppLogger.debug("🔥 [WARMUP] Complete in \(String(format: "%.0f", elapsed))ms", category: .general)
            AppLogger.debug("   └─ Previous: \(self.preFetchedPreviousSets.count), Smart: \(self.smartRecommendationsCache.count)", category: .general)
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
                numberOfSets: WorkoutManager.userDefaultSetCount,
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
            preInitializedSets[exerciseId] = (0..<WorkoutManager.userDefaultSetCount).map { _ in WorkoutSetData() }
        }
    }
}
