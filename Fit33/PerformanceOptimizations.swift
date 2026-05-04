import Foundation
import SwiftUI
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

// MARK: - 2. (was SyncCoordinator — removed 2026-05-03 perf sprint)
//
// SyncCoordinator was an unused @Published wrapper. The sync state it
// tracked is now read directly from SupabaseManager.syncAllDataFromCloud()
// (the deduplication is built into that method via RequestCoalescer).
// No view or service called `SyncCoordinator.shared`, so the entire class
// was dead — removing it eliminates an idle ObservableObject and the
// associated Combine subscription book-keeping.

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
    /// Sprint 2 Q2-26 — retained so the 15s monitor can be paused when the
    /// app is backgrounded (prevents a wall clock timer from firing, spinning
    /// task_info, and defeating iOS's "do nothing while suspended" contract).
    ///
    /// 2026-05-03 perf sprint: replaced `Timer.scheduledTimer` +
    /// `RunLoop.main.add(timer, forMode: .common)` with a `DispatchSourceTimer`
    /// on a utility queue. The OLD design ticked on the main run loop in
    /// `.common` mode, meaning the 15s poll fired DURING active scrolling and
    /// tab transitions (`task_info` syscall + threshold compare on main).
    /// One syscall is cheap (~100µs), but main-thread cost during scroll is
    /// the only cost we measure. The bg timer dispatches to main only when a
    /// threshold is actually crossed — i.e. only when work is needed.
    private var monitorTimer: DispatchSourceTimer?
    private let monitorQueue = DispatchQueue(label: "com.fit33.memory-monitor", qos: .utility)
    private var lifecycleObservers: [NSObjectProtocol] = []
    
    // ⚡️ MEMORY THRESHOLDS — tuned for iPhone 16 Pro (8GB RAM)
    // The app's normal working set is ~400-550MB after loading 5500+ exercises,
    // intelligence engine, and all services. Thresholds must be ABOVE that baseline
    // or the cleanup loop fires endlessly, blocks the main thread, and causes UI freezes.
    //
    // Sprint history:
    // - Originally 550MB warning.
    // - Sprint 1 (2026-04-24 Phase 1): lowered to 500MB to catch bursts earlier.
    //   Problem: working set after a normal session is 620+ MB (5 tabs loaded +
    //   all services + intelligence maps), so the warning fired on EVERY session
    //   and `clearWarmCaches` freed 0 entries because the baseline already had
    //   no warm caches to clear. Pure log noise.
    // - Sprint 3 (2026-04-24 Phase 3): bumped back to 650MB. Above the healthy
    //   working-set ceiling but well under critical. Fires only when something
    //   actually unusual (video binge, carousel thrash) pushes us over. 15s
    //   poll interval retained — it's cheap and catches real spikes.
    private let warningThreshold: Double = 650  // Light cleanup (warm caches only)
    private let criticalThreshold: Double = 800 // Full cache clear
    private let emergencyThreshold: Double = 950 // Aggressive teardown
    
    private init() {
        setupMemoryWarningObserver()
        startPeriodicMonitoring()
        setupLifecycleObservers()
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        monitorTimer?.cancel()
        monitorTimer = nil
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
        monitorTimer?.cancel()
        // Sprint 2026-04-24: 30s → 15s. 1.38 (53) session logs showed memory
        // climbing ~45MB per tab switch; at 30s poll the app could be 50+MB
        // over threshold before we notice. 15s poll still has negligible cost
        // (`task_info` is a single syscall, ~100µs) and catches bursts earlier.
        //
        // 2026-05-03 perf sprint: ticks now run on a utility-qos background
        // queue. `checkMemoryPressure` is pure `task_info` + threshold compare
        // — fully thread-safe (no Core Data, no UI). Only the actual cleanup
        // (`handleMemoryWarning`) hops to main, and only when a threshold has
        // been crossed. This eliminates the ~100µs main-thread spike that
        // previously fired in `.common` mode every 15s during scrolling.
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.checkMemoryPressure()
        }
        timer.resume()
        monitorTimer = timer
    }

    /// Sprint 2 Q2-26 — pause the 15s polling timer on background/inactive
    /// and restart on active. Prevents the ObservableObject from doing any
    /// work while the app is suspended and avoids the timer surviving as a
    /// retained cycle if the handler ever changed ownership.
    private func setupLifecycleObservers() {
        let nc = NotificationCenter.default
        lifecycleObservers.append(
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.monitorTimer?.cancel()
                self?.monitorTimer = nil
            }
        )
        lifecycleObservers.append(
            nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.monitorTimer?.cancel()
                self?.monitorTimer = nil
            }
        )
        lifecycleObservers.append(
            nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.startPeriodicMonitoring()
            }
        )
    }
    
    /// 2026-05-03 perf sprint: this body is invoked from the
    /// `monitorQueue` (utility QoS) background timer. `getMemoryUsageMB()`
    /// is a `task_info` syscall — fully thread-safe. Only the actual
    /// cleanup (`handleMemoryWarning`) hops to main; the threshold-check
    /// and counter-reset path stays off-main so a healthy poll has zero
    /// main-thread cost (the previous Timer.scheduledTimer + RunLoop.main
    /// path spent ~100µs per tick on main, fired during scrolling).
    private func checkMemoryPressure() {
        let memoryMB = getMemoryUsageMB()
        
        let level: MemoryWarningLevel?
        if memoryMB > emergencyThreshold {
            level = .emergency
        } else if memoryMB > criticalThreshold {
            level = .critical
        } else if memoryMB > warningThreshold {
            level = .warning
        } else {
            level = nil
        }
        
        if let level = level {
            DispatchQueue.main.async { [weak self] in
                self?.handleMemoryWarning(level: level)
            }
            return
        }
        
        // Memory is healthy — reset counters off-main. Reads/writes here
        // are confined to this background queue, so no synchronization
        // needed against the timer body itself; main-thread `handleMemoryWarning`
        // also mutates these counters but only after a level-cross, which by
        // definition won't be racing with this branch (we only land here when
        // memory is below all thresholds).
        if emergencyAttemptCount > 0 || criticalFailCount > 0 {
            emergencyAttemptCount = 0
            criticalFailCount = 0
            #if DEBUG
            AppLogger.info("✅ [MEMORY] Memory healthy (\(Int(memoryMB))MB) — counters reset", category: .general)
            #endif
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

// MARK: - 5/6. (was BackgroundWorkScheduler + StartupOptimizer — removed 2026-05-03)
//
// Both classes were defined but never invoked:
//   • `BackgroundWorkScheduler.shared.scheduleHeavyWork(...)` — 0 call sites
//   • `BackgroundWorkScheduler.shared.scheduleChunkedWork(...)` — 0 call sites
//   • `StartupOptimizer.shared.deferTask(...)` — 0 call sites
//   • `StartupOptimizer.shared.criticalPathCompleted()` — 0 call sites
//
// `StartupCoordinator` (defined further down in this file) is the actual
// active sequencer for cold-start phases. `Task.detached(priority:)` +
// `await Task.yield()` cover the chunked-work pattern at the call site
// (see TabPreloader, IntelligenceEngine), so the wrapper helpers were
// redundant. Removing them shrinks main-thread ObservableObject pressure.

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

// MARK: - 6b. USER FOCUS SENTINEL (Sprint 2026-04-24 Phase 4 — N1)
//
// Separate from HeavyWorkSentinel (which signals "app is doing heavy work")
// because THIS one signals "user is actively looking at an expensive detail
// view and wants full CPU + network bandwidth RIGHT NOW" — effectively the
// inverse of heavy work. Detail views that hit the network on `.task`
// (PrivateChallengeDetailView, ChallengeDetailView, FriendProfileView,
// CommunityChallengeDetailView, GroupChallengeDetailView) call `beginFocus`
// on `.task` and `endFocus` on disappear.
//
// `CPUProtection.waitForUIIdle` polls this. Intelligence phases gated on
// waitForUIIdle will pause until focus ends, giving user's active gesture
// full CPU. The flag is a stack counter, not a boolean, so pushed nav
// chains (Friends → ChallengeDetail → FriendProfile) don't race on the
// outer view's disappear clearing the inner view's focus.
//
// 1.38 (55) logs observed `[S954] Private Challenge Detail 15079ms` because
// the user tapped a challenge while Intel: buildMaps + pairingEngine +
// collaborative + behaviorAnalysis + similarity map were all hammering
// the CPU concurrently. With this sentinel, tapping a detail view pauses
// the heavy phases until the user navigates back.

final class UserFocusSentinel {
    static let shared = UserFocusSentinel()
    
    private let lock = NSLock()
    private var focusCount: Int = 0
    private var activeFocuses: Set<String> = []
    
    private init() {}
    
    /// True iff at least one detail view is currently in focus.
    var isFocused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return focusCount > 0
    }
    
    /// For debugging / waterfall.
    var activeFocusNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeFocuses)
    }
    
    /// Call from a detail view's `.task` when the view appears.
    func beginFocus(_ name: String) {
        lock.lock()
        focusCount += 1
        activeFocuses.insert(name)
        lock.unlock()
        #if DEBUG
        AppLogger.debug("👁️ [FOCUS] began: \(name) (count: \(focusCount))", category: .performance)
        #endif
    }
    
    /// Call from a detail view's `.onDisappear`. Safe to call with the same
    /// name multiple times — we track via set membership.
    func endFocus(_ name: String) {
        lock.lock()
        let removed = activeFocuses.remove(name) != nil
        if removed {
            focusCount = max(0, focusCount - 1)
        }
        lock.unlock()
        #if DEBUG
        if removed {
            AppLogger.debug("👁️ [FOCUS] ended: \(name) (count: \(focusCount))", category: .performance)
        }
        #endif
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
    
    /// Wait for BOTH CPU to settle AND no tab transition / tab-switch watchdog
    /// context to be active. Sprint 2026-04-24 Phase 2 — session logs showed
    /// 21s of intelligence-phase CPU work competing with first-time tab inits,
    /// producing 2-3fps drops and 900ms slow transitions. Intelligence phases
    /// now gate on this before starting each heavy step so the user's active
    /// gesture always wins the main thread.
    ///
    /// Intentionally NOT `@MainActor` — the sleep loop runs off-main so we
    /// never hold the main thread while waiting. We hop to main only to read
    /// `TabSwitchOptimizer.shared.isTransitioning` (it's `@MainActor`); the
    /// hop itself also doubles as a "main is responsive" probe because it
    /// will queue behind any active main-thread work.
    ///
    /// - Parameters:
    ///   - maxWait: hard ceiling so a stuck tab-switch flag can't deadlock startup.
    ///   - pollInterval: 200ms matches the watchdog's native granularity.
    func waitForUIIdle(maxWait: TimeInterval = 5.0, pollInterval: TimeInterval = 0.2) async {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < maxWait {
            let cpuHigh = isCPUTooHigh()
            let watchdogBusy = MainThreadWatchdog.shared.isTabSwitchActive
            let userInDetail = UserFocusSentinel.shared.isFocused
            let transitioning = await MainActor.run { TabSwitchOptimizer.shared.isTransitioning }
            if !cpuHigh && !watchdogBusy && !userInDetail && !transitioning { return }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }
    
    private func measureCPU() -> Double {
        SystemMetrics.getCPUUsage()
    }
}

// MARK: - INITIALIZATION (was PerformanceOptimizationsInitializer — removed 2026-05-03)
//
// `PerformanceOptimizationsInitializer.initialize()` and the wrapper
// `initializePerformanceOptimizations()` were never called from app code.
// The actual cold-start sequence in `Fit33App.swift` directly touches
// each singleton (`_ = MemoryPressureHandler.shared`, MetricKit registration,
// gated DEBUG-only `MainThreadWatchdog.start()` etc.) and invokes
// `StartupCoordinator.shared.beginStartupSequence()`. The wrapper class was
// historical scaffolding from sprint 1 that no longer reflected the boot
// path. Keeping it caused confusion for readers tracing the cold-start —
// the agent docs even mentioned it as the canonical entry point even
// though it was orphaned. Removed.

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

// MARK: - Scroll jank telemetry
//
// Lives here (not only in `PerformanceOptimizer.swift`) so every screen that
// calls `.trackScrollJank` compiles as long as this file is in the app target.
// `PerformanceOptimizer.swift` historically sat on disk without a pbxproj entry.

/// Tracks scroll velocity to reduce work during fast scrolling
final class ScrollPerformanceTracker: ObservableObject {
    static let shared = ScrollPerformanceTracker()

    @Published private(set) var isScrollingFast = false

    private var lastOffset: CGFloat = 0
    private var lastTime: CFTimeInterval = 0
    private var velocity: CGFloat = 0

    private let fastScrollThreshold: CGFloat = 500 // points per second

    func updateScroll(offset: CGFloat) {
        let currentTime = CACurrentMediaTime()
        if lastTime > 0 {
            let timeDelta = currentTime - lastTime
            let offsetDelta = abs(offset - lastOffset)
            velocity = offsetDelta / CGFloat(timeDelta)

            let wasFast = isScrollingFast
            isScrollingFast = velocity > fastScrollThreshold

            if wasFast != isScrollingFast {
                objectWillChange.send()
            }
        }
        lastOffset = offset
        lastTime = currentTime
    }

    func resetScroll() {
        isScrollingFast = false
        velocity = 0
    }
}

struct ScrollOffsetTracker: ViewModifier {
    let screenName: String
    @State private var lastLogTime: Date = .distantPast

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                ScrollPerformanceTracker.shared.updateScroll(offset: -offset)

                if ScrollPerformanceTracker.shared.isScrollingFast {
                    let now = Date()
                    if now.timeIntervalSince(lastLogTime) > 2.0 {
                        lastLogTime = now
                        SessionLogManager.shared.logScroll(
                            screen: screenName,
                            direction: offset < 0 ? "down" : "up",
                            position: "\(Int(-offset))"
                        )
                    }
                }
            }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func trackScrollJank(screen: String) -> some View {
        modifier(ScrollOffsetTracker(screenName: screen))
    }
}
