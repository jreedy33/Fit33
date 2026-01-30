import SwiftUI
import Combine
import os.log

// MARK: - Performance Monitoring System
/// Comprehensive, automatic performance monitoring that tracks everything as users navigate
/// Logs all metrics to SessionLogManager for review and performance improvements
///
/// Features:
/// - Real-time FPS (frames per second) tracking
/// - Memory usage monitoring
/// - CPU usage tracking
/// - View load time measurement
/// - Navigation transition timing
/// - UI lag/jank detection
/// - Automatic logging to session logs

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 1. PERFORMANCE MONITOR (Main Coordinator)
// ═══════════════════════════════════════════════════════════════════════════════

@MainActor
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    // MARK: - Published State
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var currentFPS: Double = 60.0
    @Published private(set) var currentMemoryMB: Double = 0
    @Published private(set) var currentCPUPercent: Double = 0
    @Published private(set) var performanceIssues: [PerformanceIssue] = []
    
    // MARK: - Sub-monitors
    private let fpsTracker = FPSTracker()
    private let memoryTracker = MemoryTracker()
    private let cpuTracker = CPUTracker()
    private let viewLoadTracker = ViewLoadTracker()
    private let transitionTracker = TransitionTracker()
    
    // MARK: - Timers & State
    private var updateTimer: Timer?
    private var sessionStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Performance Thresholds
    struct Thresholds {
        static let minAcceptableFPS: Double = 50.0  // Below this = lag
        static let maxMemoryMB: Double = 300.0      // Above this = memory warning
        static let maxCPUPercent: Double = 80.0     // Above this = CPU overload
        static let maxViewLoadMs: Double = 500.0    // Above this = slow view
        static let maxTransitionMs: Double = 300.0  // Above this = janky transition
    }
    
    // MARK: - Performance Metrics Storage
    struct PerformanceSnapshot {
        let timestamp: Date
        let fps: Double
        let memoryMB: Double
        let cpuPercent: Double
        let viewName: String?
    }
    
    private var snapshots: [PerformanceSnapshot] = []
    private let maxSnapshots = 1000  // Keep last 1000 samples
    
    private init() {
        setupAutoMonitoring()
    }
    
    // MARK: - Start/Stop Monitoring
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        sessionStartTime = Date()
        snapshots.removeAll()
        performanceIssues.removeAll()
        
        // Start sub-monitors
        fpsTracker.startTracking()
        memoryTracker.startTracking()
        cpuTracker.startTracking()
        
        // Update metrics every 1 second
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
        
        SessionLogManager.shared.log(.info, category: .session, message: "🎯 Performance monitoring started")
        
        print("🎯 [PERF MONITOR] Started - tracking FPS, memory, CPU, and view loads")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        fpsTracker.stopTracking()
        memoryTracker.stopTracking()
        cpuTracker.stopTracking()
        
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Log summary
        logSessionSummary()
        
        SessionLogManager.shared.log(.info, category: .session, message: "🎯 Performance monitoring stopped")
        
        print("🎯 [PERF MONITOR] Stopped")
    }
    
    // MARK: - Update Metrics
    
    private func updateMetrics() {
        // Get current metrics from trackers
        currentFPS = fpsTracker.currentFPS
        currentMemoryMB = memoryTracker.currentMemoryMB
        currentCPUPercent = cpuTracker.currentCPUPercent
        
        // Record snapshot
        let snapshot = PerformanceSnapshot(
            timestamp: Date(),
            fps: currentFPS,
            memoryMB: currentMemoryMB,
            cpuPercent: currentCPUPercent,
            viewName: viewLoadTracker.currentViewName
        )
        
        snapshots.append(snapshot)
        
        // Trim old snapshots
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }
        
        // Check for performance issues
        detectPerformanceIssues(snapshot)
        
        // Log metrics periodically (every 10 seconds)
        if snapshots.count % 10 == 0 {
            logCurrentMetrics()
        }
    }
    
    // MARK: - Issue Detection
    
    private func detectPerformanceIssues(_ snapshot: PerformanceSnapshot) {
        // FPS issues
        if snapshot.fps < Thresholds.minAcceptableFPS {
            let issue = PerformanceIssue(
                type: .lowFPS,
                severity: snapshot.fps < 30 ? .critical : .warning,
                message: "Low FPS: \(String(format: "%.1f", snapshot.fps))",
                timestamp: snapshot.timestamp,
                metrics: ["fps": snapshot.fps]
            )
            recordIssue(issue)
        }
        
        // Memory issues
        if snapshot.memoryMB > Thresholds.maxMemoryMB {
            let issue = PerformanceIssue(
                type: .highMemory,
                severity: snapshot.memoryMB > 400 ? .critical : .warning,
                message: "High memory: \(String(format: "%.0f", snapshot.memoryMB))MB",
                timestamp: snapshot.timestamp,
                metrics: ["memoryMB": snapshot.memoryMB]
            )
            recordIssue(issue)
        }
        
        // CPU issues
        if snapshot.cpuPercent > Thresholds.maxCPUPercent {
            let issue = PerformanceIssue(
                type: .highCPU,
                severity: snapshot.cpuPercent > 95 ? .critical : .warning,
                message: "High CPU: \(String(format: "%.0f", snapshot.cpuPercent))%",
                timestamp: snapshot.timestamp,
                metrics: ["cpuPercent": snapshot.cpuPercent]
            )
            recordIssue(issue)
        }
    }
    
    private func recordIssue(_ issue: PerformanceIssue) {
        // Don't spam with same issue type
        if let lastIssue = performanceIssues.last,
           lastIssue.type == issue.type,
           Date().timeIntervalSince(lastIssue.timestamp) < 5.0 {
            return
        }
        
        performanceIssues.append(issue)
        
        // Log to session
        let level: LogLevel = issue.severity == .critical ? .error : .warning
        SessionLogManager.shared.log(level, category: .session, message: "⚠️ Performance issue: \(issue.message)", metadata: issue.metrics)
        
        // Keep only recent issues
        if performanceIssues.count > 50 {
            performanceIssues.removeFirst(performanceIssues.count - 50)
        }
    }
    
    // MARK: - View Load Tracking
    
    func trackViewLoad(name: String, loadTimeMs: Double) {
        viewLoadTracker.recordViewLoad(name: name, loadTimeMs: loadTimeMs)
        
        // Log if slow
        if loadTimeMs > Thresholds.maxViewLoadMs {
            let issue = PerformanceIssue(
                type: .slowViewLoad,
                severity: loadTimeMs > 1000 ? .critical : .warning,
                message: "Slow view load: \(name) (\(Int(loadTimeMs))ms)",
                timestamp: Date(),
                metrics: ["viewName": name, "loadTimeMs": loadTimeMs]
            )
            recordIssue(issue)
        }
        
        // Always log view loads for analysis
        SessionLogManager.shared.logPerformance(operation: "View load: \(name)", duration: loadTimeMs / 1000.0)
    }
    
    // MARK: - Transition Tracking
    
    func trackTransition(from: String, to: String, durationMs: Double) {
        transitionTracker.recordTransition(from: from, to: to, durationMs: durationMs)
        
        // Log if janky
        if durationMs > Thresholds.maxTransitionMs {
            let issue = PerformanceIssue(
                type: .jankyTransition,
                severity: durationMs > 500 ? .critical : .warning,
                message: "Janky transition: \(from) → \(to) (\(Int(durationMs))ms)",
                timestamp: Date(),
                metrics: ["from": from, "to": to, "durationMs": durationMs]
            )
            recordIssue(issue)
        }
        
        SessionLogManager.shared.logPerformance(operation: "Transition: \(from) → \(to)", duration: durationMs / 1000.0)
    }
    
    // MARK: - Metrics Retrieval
    
    func getAverageFPS() -> Double {
        let recentSnapshots = snapshots.suffix(60)  // Last 60 seconds
        guard !recentSnapshots.isEmpty else { return 60.0 }
        return recentSnapshots.map { $0.fps }.reduce(0, +) / Double(recentSnapshots.count)
    }
    
    func getAverageMemory() -> Double {
        let recentSnapshots = snapshots.suffix(60)
        guard !recentSnapshots.isEmpty else { return 0 }
        return recentSnapshots.map { $0.memoryMB }.reduce(0, +) / Double(recentSnapshots.count)
    }
    
    func getAverageCPU() -> Double {
        let recentSnapshots = snapshots.suffix(60)
        guard !recentSnapshots.isEmpty else { return 0 }
        return recentSnapshots.map { $0.cpuPercent }.reduce(0, +) / Double(recentSnapshots.count)
    }
    
    func getSlowestViews() -> [(name: String, avgMs: Double)] {
        return viewLoadTracker.getSlowestViews()
    }
    
    func getSlowestTransitions() -> [(from: String, to: String, avgMs: Double)] {
        return transitionTracker.getSlowestTransitions()
    }
    
    // MARK: - Logging
    
    private func logCurrentMetrics() {
        SessionLogManager.shared.log(.debug, category: .session, message: "📊 Performance metrics", metadata: [
            "fps": String(format: "%.1f", currentFPS),
            "memory_mb": String(format: "%.0f", currentMemoryMB),
            "cpu_percent": String(format: "%.0f", currentCPUPercent),
            "current_view": viewLoadTracker.currentViewName ?? "Unknown"
        ])
    }
    
    private func logSessionSummary() {
        guard let startTime = sessionStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        let avgFPS = getAverageFPS()
        let avgMemory = getAverageMemory()
        let avgCPU = getAverageCPU()
        
        SessionLogManager.shared.log(.info, category: .session, message: "📊 Performance session summary", metadata: [
            "duration_seconds": Int(duration),
            "avg_fps": String(format: "%.1f", avgFPS),
            "avg_memory_mb": String(format: "%.0f", avgMemory),
            "avg_cpu_percent": String(format: "%.0f", avgCPU),
            "total_issues": performanceIssues.count,
            "critical_issues": performanceIssues.filter { $0.severity == .critical }.count
        ])
        
        // Log slowest views
        let slowestViews = getSlowestViews().prefix(5)
        for (index, view) in slowestViews.enumerated() {
            SessionLogManager.shared.log(.info, category: .session, message: "🐢 Slow view #\(index + 1): \(view.name) (\(Int(view.avgMs))ms)")
        }
        
        // Log slowest transitions
        let slowestTransitions = getSlowestTransitions().prefix(5)
        for (index, transition) in slowestTransitions.enumerated() {
            SessionLogManager.shared.log(.info, category: .session, message: "🐢 Slow transition #\(index + 1): \(transition.from) → \(transition.to) (\(Int(transition.avgMs))ms)")
        }
    }
    
    // MARK: - Auto-monitoring Setup
    
    private func setupAutoMonitoring() {
        // Auto-start monitoring in DEBUG builds
        #if DEBUG
        // Start after a short delay to avoid startup overhead
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startMonitoring()
        }
        #endif
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 2. FPS TRACKER
// ═══════════════════════════════════════════════════════════════════════════════

final class FPSTracker {
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var accumulatedTime: CFTimeInterval = 0
    private(set) var currentFPS: Double = 60.0
    
    func startTracking() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: self, selector: #selector(frameUpdate))
        displayLink?.add(to: .main, forMode: .common)
        
        lastFrameTimestamp = CACurrentMediaTime()
    }
    
    func stopTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func frameUpdate(displayLink: CADisplayLink) {
        let currentTimestamp = displayLink.timestamp
        
        if lastFrameTimestamp > 0 {
            frameCount += 1
            accumulatedTime += currentTimestamp - lastFrameTimestamp
            
            // Update FPS every 0.5 seconds
            if accumulatedTime >= 0.5 {
                currentFPS = Double(frameCount) / accumulatedTime
                frameCount = 0
                accumulatedTime = 0
            }
        }
        
        lastFrameTimestamp = currentTimestamp
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 3. MEMORY TRACKER
// ═══════════════════════════════════════════════════════════════════════════════

final class MemoryTracker {
    private var timer: Timer?
    private(set) var currentMemoryMB: Double = 0
    
    func startTracking() {
        guard timer == nil else { return }
        
        // Update every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMemory()
        }
        
        updateMemory()
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateMemory() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            currentMemoryMB = Double(info.resident_size) / 1024.0 / 1024.0
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 4. CPU TRACKER
// ═══════════════════════════════════════════════════════════════════════════════

final class CPUTracker {
    private var timer: Timer?
    private(set) var currentCPUPercent: Double = 0
    
    func startTracking() {
        guard timer == nil else { return }
        
        // Update every 2 seconds (CPU measurement is expensive)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateCPU()
        }
        
        updateCPU()
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCPU() {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        
        let kr = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        guard kr == KERN_SUCCESS, let threads = threadsList else {
            return
        }
        
        var totalCPU: Double = 0
        
        for index in 0..<Int(threadsCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            
            let result = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }
            
            if result == KERN_SUCCESS {
                if threadInfo.flags != TH_FLAGS_IDLE {
                    totalCPU += (Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
        }
        
        // Deallocate the threads array
        let size = vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
        _ = vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        
        currentCPUPercent = totalCPU
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 5. VIEW LOAD TRACKER
// ═══════════════════════════════════════════════════════════════════════════════

final class ViewLoadTracker {
    private var viewLoadTimes: [String: [Double]] = [:]
    private(set) var currentViewName: String?
    
    func recordViewLoad(name: String, loadTimeMs: Double) {
        currentViewName = name
        
        if viewLoadTimes[name] == nil {
            viewLoadTimes[name] = []
        }
        
        viewLoadTimes[name]?.append(loadTimeMs)
        
        // Keep only last 10 loads per view
        if let count = viewLoadTimes[name]?.count, count > 10 {
            viewLoadTimes[name] = Array(viewLoadTimes[name]!.suffix(10))
        }
    }
    
    func getSlowestViews() -> [(name: String, avgMs: Double)] {
        return viewLoadTimes.compactMap { name, times in
            guard !times.isEmpty else { return nil }
            let avg = times.reduce(0, +) / Double(times.count)
            return (name, avg)
        }.sorted { $0.avgMs > $1.avgMs }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 6. TRANSITION TRACKER
// ═══════════════════════════════════════════════════════════════════════════════

final class TransitionTracker {
    private var transitionTimes: [String: [Double]] = [:]
    
    func recordTransition(from: String, to: String, durationMs: Double) {
        let key = "\(from) → \(to)"
        
        if transitionTimes[key] == nil {
            transitionTimes[key] = []
        }
        
        transitionTimes[key]?.append(durationMs)
        
        // Keep only last 10 transitions per pair
        if let count = transitionTimes[key]?.count, count > 10 {
            transitionTimes[key] = Array(transitionTimes[key]!.suffix(10))
        }
    }
    
    func getSlowestTransitions() -> [(from: String, to: String, avgMs: Double)] {
        return transitionTimes.compactMap { transition, times in
            guard !times.isEmpty else { return nil }
            let parts = transition.split(separator: "→").map { String($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else { return nil }
            let avg = times.reduce(0, +) / Double(times.count)
            return (parts[0], parts[1], avg)
        }.sorted { $0.avgMs > $1.avgMs }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 7. PERFORMANCE ISSUE
// ═══════════════════════════════════════════════════════════════════════════════

struct PerformanceIssue: Identifiable {
    let id = UUID()
    let type: IssueType
    let severity: Severity
    let message: String
    let timestamp: Date
    let metrics: [String: Any]
    
    enum IssueType: String {
        case lowFPS = "Low FPS"
        case highMemory = "High Memory"
        case highCPU = "High CPU"
        case slowViewLoad = "Slow View Load"
        case jankyTransition = "Janky Transition"
    }
    
    enum Severity: String {
        case warning = "Warning"
        case critical = "Critical"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 8. VIEW PERFORMANCE MODIFIER (Auto-tracking for all views)
// ═══════════════════════════════════════════════════════════════════════════════

struct ViewPerformanceModifier: ViewModifier {
    let viewName: String
    @State private var loadStartTime: CFTimeInterval = 0
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                loadStartTime = CACurrentMediaTime()
            }
            .task {
                // Small delay to measure full view load
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                let loadTime = (CACurrentMediaTime() - loadStartTime) * 1000.0
                await MainActor.run {
                    PerformanceMonitor.shared.trackViewLoad(name: viewName, loadTimeMs: loadTime)
                }
            }
    }
}

extension View {
    /// Automatically track performance of this view
    func trackPerformance(name: String) -> some View {
        self.modifier(ViewPerformanceModifier(viewName: name))
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 9. NAVIGATION PERFORMANCE TRACKER
// ═══════════════════════════════════════════════════════════════════════════════

@MainActor
final class NavigationPerformanceTracker: ObservableObject {
    static let shared = NavigationPerformanceTracker()
    
    private var currentScreen: String = "Dashboard"
    private var transitionStartTime: CFTimeInterval = 0
    
    private init() {}
    
    func willNavigate(to screen: String) {
        transitionStartTime = CACurrentMediaTime()
    }
    
    func didNavigate(to screen: String) {
        let transitionTime = (CACurrentMediaTime() - transitionStartTime) * 1000.0
        
        PerformanceMonitor.shared.trackTransition(
            from: currentScreen,
            to: screen,
            durationMs: transitionTime
        )
        
        currentScreen = screen
    }
}
