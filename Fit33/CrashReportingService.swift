import Foundation
import UIKit
import CommonCrypto
import MachO // Q2-97 Phase 5 — dyld APIs for binary_uuid + ASLR slide capture

// ═══════════════════════════════════════════════════════════════
// MARK: - Crash Report Model (Supabase DTO)
// ═══════════════════════════════════════════════════════════════

struct CrashReportInsert: Codable {
    let user_id: String?
    let user_email: String?
    let user_name: String?
    let report_type: String       // crash, error, critical, warning, fatal_signal
    let severity: String          // low, medium, high, critical, fatal
    let error_message: String
    let error_domain: String?
    let error_code: String?
    let stack_trace: String?
    let fingerprint: String
    let breadcrumbs: [[String: String]]?
    let device_model: String
    let os_version: String
    let app_version: String
    let build_number: String
    let current_screen: String?
    let memory_usage_mb: Double?
    let free_memory_mb: Double?
    let battery_level: Double?
    let is_low_power_mode: Bool
    let network_type: String?
    let session_id: String?
    let session_duration_seconds: Int?
    let actions_before_crash: Int?
    let additional_context: [String: String]?
    let session_log_snippet: String?
    let status: String
    let occurred_at: String
    // Q2-97 Phase 5 · dSYM symbolication scaffolding — captured at crash time,
    // consumed by the symbolicate-crashes GitHub Actions runner. Both are nil
    // on devices where dyld lookup fails (never observed in practice but we
    // stay defensive — the runner treats nil binary_uuid as `no_dsym`).
    let binary_uuid: String?
    let binary_slide: String?
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Crash Reporting Service
// ═══════════════════════════════════════════════════════════════

/// Production-grade crash and error reporting service.
///
/// **Architecture** (inspired by Meta's crash reporting pipeline):
///
/// 1. **Signal Handlers**: Catch fatal signals (SIGSEGV, SIGABRT, etc.)
///    → Persist crash data to disk immediately (can't use network during crash)
///    → Upload on next app launch
///
/// 2. **Exception Handler**: Catch uncaught NSExceptions
///    → Same persist-to-disk-then-upload flow
///
/// 3. **Error Interceptor**: Hook into AppLogger.error() / .critical()
///    → Upload in real-time (app is still running)
///    → Rate-limited to prevent flooding
///
/// 4. **Breadcrumb Trail**: Track last N user actions for crash context
///    → Stored in circular buffer, included with every report
///
/// 5. **Fingerprinting**: Hash (error + domain + top stack frames)
///    → Groups identical crashes in the admin dashboard
///    → Prevents duplicate noise
///
/// 6. **Rate Limiting**: Max reports per session/per fingerprint
///    → Prevents one broken loop from generating thousands of reports
final class CrashReportingService {
    static let shared = CrashReportingService()
    
    // MARK: - Configuration
    private struct Config {
        static let maxBreadcrumbs = 50              // Keep last 50 actions
        static let maxReportsPerSession = 30        // Don't flood the DB
        static let maxReportsPerFingerprint = 3     // Same crash only reported 3x per session
        static let maxSessionLogSnippetLines = 50   // Last 50 lines of session log
        static let pendingReportsFile = "pending_crash_reports.json"
        static let breadcrumbsFile = "crash_breadcrumbs.json"
        static let uploadRetryDelay: TimeInterval = 5.0
        static let maxPendingReports = 100          // Disk limit
    }
    
    // MARK: - State
    private var breadcrumbs: [(action: String, screen: String, timestamp: Date)] = []
    private let breadcrumbLock = NSLock()
    
    private var reportsThisSession = 0
    private var fingerprintCounts: [String: Int] = [:]
    private let reportLock = NSLock()
    
    private var sessionStartTime: Date?
    private var isInitialized = false

    // Q2-97 Phase 5 — captured once at initialize(). Both values are fixed for
    // the process lifetime (UUID is baked into the binary by the linker, slide
    // is picked once by ASLR at exec time) so there's no point re-reading them
    // per crash. Matches Apple's advice in CrashReporting.pdf §Address Slides.
    private var mainBinaryUUID: String?
    private var mainBinarySlide: String?
    
    // Previous signal handlers (to chain)
    private var previousSIGABRT: (@convention(c) (Int32) -> Void)?
    private var previousSIGSEGV: (@convention(c) (Int32) -> Void)?
    private var previousSIGBUS: (@convention(c) (Int32) -> Void)?
    private var previousSIGFPE: (@convention(c) (Int32) -> Void)?
    private var previousSIGILL: (@convention(c) (Int32) -> Void)?
    private var previousSIGTRAP: (@convention(c) (Int32) -> Void)?
    
    // File paths
    private var pendingReportsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Config.pendingReportsFile)
    }
    
    private var breadcrumbsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Config.breadcrumbsFile)
    }
    
    private init() {}
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Initialization
    // ═══════════════════════════════════════════════════════════════
    
    /// Call this ONCE at app launch, before anything else.
    /// Sets up signal handlers and exception handlers.
    func initialize() {
        guard !isInitialized else { return }
        isInitialized = true
        sessionStartTime = Date()

        // Q2-97 Phase 5.1 — capture the main binary's UUID + ASLR slide once
        // at launch. These get written into every crash_reports insert so the
        // symbolicate-crashes GitHub Actions workflow (5.5) can pick the
        // matching .dSYM out of the `dsyms` storage bucket and feed it +
        // the slide to `atos`.
        mainBinaryUUID = computeMainBinaryUUID()
        mainBinarySlide = computeMainBinarySlide()

        // 1. Restore breadcrumbs from disk (in case app was killed)
        restoreBreadcrumbs()
        
        // 2. Install signal handlers for fatal crashes
        installSignalHandlers()
        
        // 3. Install uncaught exception handler
        installExceptionHandler()
        
        // 4. Upload any crash reports from previous session
        uploadPendingReports()

        AppLogger.debug("🛡️ [CrashReporter] Initialized — signal handlers, exception handler, pending upload · uuid=\(mainBinaryUUID ?? "nil") slide=\(mainBinarySlide ?? "nil")", category: .general)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Signal Handlers (Fatal Crashes)
    // ═══════════════════════════════════════════════════════════════
    
    private func installSignalHandlers() {
        // Store shared instance reference for C callback
        _crashReportingServiceInstance = self
        
        // Install handlers, preserving previous ones
        previousSIGABRT = signal(SIGABRT, _signalHandler)
        previousSIGSEGV = signal(SIGSEGV, _signalHandler)
        previousSIGBUS  = signal(SIGBUS,  _signalHandler)
        previousSIGFPE  = signal(SIGFPE,  _signalHandler)
        previousSIGILL  = signal(SIGILL,  _signalHandler)
        previousSIGTRAP = signal(SIGTRAP, _signalHandler)
    }
    
    /// Called from C signal handler — MUST be async-signal-safe.
    /// Only writes to disk (no network, no allocations if possible).
    fileprivate func handleSignal(_ signal: Int32) {
        let signalName: String
        switch signal {
        case SIGABRT: signalName = "SIGABRT"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGBUS:  signalName = "SIGBUS"
        case SIGFPE:  signalName = "SIGFPE"
        case SIGILL:  signalName = "SIGILL"
        case SIGTRAP: signalName = "SIGTRAP"
        default:      signalName = "SIGNAL(\(signal))"
        }
        
        // Build crash report and persist to disk synchronously
        let report = buildReport(
            type: "fatal_signal",
            severity: "fatal",
            message: "Fatal signal: \(signalName)",
            domain: "System",
            code: "\(signal)",
            stackTrace: Thread.callStackSymbols.joined(separator: "\n")
        )
        
        persistReportToDisk(report)
        
        // Also log to session log if possible
        SessionLogManager.shared.logCrash(
            type: signalName,
            name: "Fatal Signal",
            reason: "Process received \(signalName)",
            stackTrace: Thread.callStackSymbols.joined(separator: "\n")
        )
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Exception Handler
    // ═══════════════════════════════════════════════════════════════
    
    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let service = CrashReportingService.shared
            
            let report = service.buildReport(
                type: "crash",
                severity: "fatal",
                message: "\(exception.name.rawValue): \(exception.reason ?? "No reason")",
                domain: "Exception",
                code: exception.name.rawValue,
                stackTrace: exception.callStackSymbols.joined(separator: "\n")
            )
            
            service.persistReportToDisk(report)
            
            // Chain to SessionLogManager's handler
            SessionLogManager.shared.logCrash(
                type: "UncaughtException",
                name: exception.name.rawValue,
                reason: exception.reason,
                stackTrace: exception.callStackSymbols.joined(separator: "\n")
            )
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Real-time Error Reporting (for non-fatal errors)
    // ═══════════════════════════════════════════════════════════════
    
    /// Called by AppLogger when an error or critical log is emitted.
    /// Uploads in real-time since the app is still running.
    func reportError(
        message: String,
        domain: String? = nil,
        code: String? = nil,
        error: Error? = nil,
        severity: ErrorSeverity = .high,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        additionalContext: [String: String]? = nil
    ) {
        if let error = error {
            if error is CancellationError { return }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNetworkConnectionLost { return }
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet { return }
            if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1000 { return }
            if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001 { return }
        }
        if message.hasSuffix(": cancelled") || message.contains("NSURLErrorDomain error -999") { return }
        if message.contains("network connection was lost") || message.contains("not connected to the Internet") { return }
        if message.contains("[APPLE AUTH]") && message.contains("1000") { return }
        
        reportLock.lock()
        defer { reportLock.unlock() }
        
        guard reportsThisSession < Config.maxReportsPerSession else { return }
        
        let fullMessage: String
        if let error = error {
            fullMessage = "\(message): \(error.localizedDescription)"
        } else {
            fullMessage = message
        }
        
        let fileName = (file as NSString).lastPathComponent
        let errorDomain = domain ?? categorizeFile(fileName)
        
        let fingerprint = generateFingerprint(
            message: fullMessage,
            domain: errorDomain,
            file: fileName,
            line: line
        )
        
        // Check per-fingerprint rate limit
        let fpCount = fingerprintCounts[fingerprint] ?? 0
        guard fpCount < Config.maxReportsPerFingerprint else { return }
        fingerprintCounts[fingerprint] = fpCount + 1
        reportsThisSession += 1
        
        // Build the report
        var context = additionalContext ?? [:]
        context["file"] = fileName
        context["function"] = function
        context["line"] = "\(line)"
        if let error = error {
            context["error_type"] = String(describing: type(of: error))
            context["error_detail"] = String(describing: error)
        }
        
        let thermalState: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "nominal"
        case .fair: thermalState = "fair"
        case .serious: thermalState = "serious"
        case .critical: thermalState = "critical"
        @unknown default: thermalState = "unknown"
        }
        context["thermal_state"] = thermalState
        
        let stackTrace = Thread.callStackSymbols.joined(separator: "\n")
        
        let report = buildReport(
            type: severity == .critical ? "critical" : "error",
            severity: severity.rawValue,
            message: fullMessage,
            domain: errorDomain,
            code: code,
            stackTrace: stackTrace,
            additionalContext: context
        )
        
        // Upload in background (app is still running)
        Task.detached(priority: .utility) {
            await self.uploadReport(report)
        }
    }
    
    /// Severity levels for non-fatal errors
    enum ErrorSeverity: String {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Breadcrumbs (User Action Trail)
    // ═══════════════════════════════════════════════════════════════
    
    /// Add a breadcrumb — call this on every significant user action.
    func addBreadcrumb(_ action: String, screen: String? = nil) {
        breadcrumbLock.lock()
        
        let currentScreen = screen ?? getCurrentScreen()
        breadcrumbs.append((action: action, screen: currentScreen, timestamp: Date()))
        
        // Trim to max size (circular buffer)
        if breadcrumbs.count > Config.maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - Config.maxBreadcrumbs)
        }
        
        // Persist breadcrumbs to disk periodically (every 10 actions)
        // Take snapshot while holding lock, then release before disk I/O
        var snapshotForPersist: [[String: String]]? = nil
        if breadcrumbs.count % 10 == 0 {
            snapshotForPersist = _breadcrumbsSnapshotUnsafe()
        }
        
        breadcrumbLock.unlock()
        
        // Disk write happens OUTSIDE the lock on a background queue
        // to avoid blocking the main thread and prevent deadlocks
        if let snapshot = snapshotForPersist {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.persistBreadcrumbsSnapshot(snapshot)
            }
        }
    }
    
    private func getCurrentScreen() -> String {
        // Try to get from SessionLogManager
        return "Unknown"
    }
    
    /// Thread-safe snapshot — acquires lock internally. Safe to call from any context.
    private func getBreadcrumbsSnapshot() -> [[String: String]] {
        breadcrumbLock.lock()
        let snapshot = _breadcrumbsSnapshotUnsafe()
        breadcrumbLock.unlock()
        return snapshot
    }
    
    /// Unsafe snapshot — caller MUST already hold breadcrumbLock.
    private func _breadcrumbsSnapshotUnsafe() -> [[String: String]] {
        let formatter = ISO8601DateFormatter()
        return breadcrumbs.map { crumb in
            [
                "action": crumb.action,
                "screen": crumb.screen,
                "timestamp": formatter.string(from: crumb.timestamp)
            ]
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Report Building
    // ═══════════════════════════════════════════════════════════════
    
    private func buildReport(
        type: String,
        severity: String,
        message: String,
        domain: String?,
        code: String? = nil,
        stackTrace: String? = nil,
        additionalContext: [String: String]? = nil
    ) -> CrashReportInsert {
        let device = UIDevice.current
        
        // Memory info
        let memoryUsage = getMemoryUsageMB()
        let freeMemory = getFreeMemoryMB()
        
        // Battery
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = Double(device.batteryLevel)
        
        // Session context
        let sessionDuration: Int?
        if let start = sessionStartTime {
            sessionDuration = Int(Date().timeIntervalSince(start))
        } else {
            sessionDuration = nil
        }
        
        // Session log snippet (last N lines)
        let sessionLogSnippet = getSessionLogSnippet()
        
        // User context
        let userId = SupabaseManager.shared.currentUser?.id.uuidString
        let userEmail = SupabaseManager.shared.currentUser?.email
        let userName: String? = UserManager.shared.currentUser?.name
        
        let fingerprint = generateFingerprint(
            message: message,
            domain: domain,
            file: nil,
            line: nil
        )
        
        let formatter = ISO8601DateFormatter()
        
        return CrashReportInsert(
            user_id: userId,
            user_email: userEmail,
            user_name: userName,
            report_type: type,
            severity: severity,
            error_message: String(message.prefix(2000)),
            error_domain: domain,
            error_code: code,
            stack_trace: stackTrace.map { String($0.prefix(8000)) },
            fingerprint: fingerprint,
            breadcrumbs: getBreadcrumbsSnapshot(),
            device_model: getDeviceModel(),
            os_version: "\(device.systemName) \(device.systemVersion)",
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            build_number: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
            current_screen: breadcrumbs.last?.screen,
            memory_usage_mb: memoryUsage,
            free_memory_mb: freeMemory,
            battery_level: batteryLevel >= 0 ? batteryLevel : nil,
            is_low_power_mode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            network_type: getNetworkType(),
            session_id: nil, // Could link to SessionLogManager.sessionId
            session_duration_seconds: sessionDuration,
            actions_before_crash: breadcrumbs.count,
            additional_context: additionalContext,
            session_log_snippet: sessionLogSnippet,
            status: "new",
            occurred_at: formatter.string(from: Date()),
            // Phase 5.1 — both fields are cached from initialize(), never
            // re-read here (dyld APIs aren't async-signal-safe and we call
            // buildReport from the signal handler).
            binary_uuid: mainBinaryUUID,
            binary_slide: mainBinarySlide
        )
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Q2-97 Phase 5 — Binary UUID + ASLR slide capture
    // ═══════════════════════════════════════════════════════════════

    /// Reads the LC_UUID load command from the main executable's Mach-O
    /// header. This is the same UUID that ships inside the `.dSYM` bundle
    /// Apple produces at Archive time, so the GitHub Actions symbolicator
    /// can use it as a primary key to locate the right dSYM in our
    /// `dsyms` Supabase Storage bucket.
    ///
    /// Safe to call from any queue; returns nil only if the header / load
    /// commands are malformed (never observed on real devices).
    private func computeMainBinaryUUID() -> String? {
        // Image at index 0 is always the main executable per dyld docs.
        guard let headerPtr = _dyld_get_image_header(0) else { return nil }

        // Walk load commands — start offset depends on 32 vs 64-bit header.
        let is64 = (headerPtr.pointee.magic == MH_MAGIC_64 || headerPtr.pointee.magic == MH_CIGAM_64)
        let headerSize = is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        var cmdPtr = UnsafeRawPointer(headerPtr).advanced(by: headerSize)
        let ncmds = Int(headerPtr.pointee.ncmds)

        for _ in 0..<ncmds {
            let cmd = cmdPtr.assumingMemoryBound(to: load_command.self).pointee
            if cmd.cmd == LC_UUID {
                let uuidCmd = cmdPtr.assumingMemoryBound(to: uuid_command.self).pointee
                // uuid_t is a homogeneous tuple of 16 UInt8s. Copy into a
                // Foundation UUID for a stable uppercase string.
                let u = uuidCmd.uuid
                let foundationUUID = UUID(uuid: (
                    u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                    u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15
                ))
                return foundationUUID.uuidString
            }
            // cmdsize of 0 would loop forever; defensive guard.
            guard cmd.cmdsize > 0 else { return nil }
            cmdPtr = cmdPtr.advanced(by: Int(cmd.cmdsize))
        }
        return nil
    }

    /// ASLR slide for the main image, formatted as a 0x-prefixed hex string
    /// compatible with `atos -l <slide>`. intptr_t → UInt64 via bit pattern
    /// so negative slides (never observed but legal) round-trip correctly.
    private func computeMainBinarySlide() -> String? {
        let slide = _dyld_get_image_vmaddr_slide(0)
        return String(format: "0x%llx", UInt64(bitPattern: Int64(slide)))
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Fingerprinting (Deduplication)
    // ═══════════════════════════════════════════════════════════════
    
    private func generateFingerprint(
        message: String,
        domain: String?,
        file: String?,
        line: Int?
    ) -> String {
        // Normalize the message: strip numbers, UUIDs, specific values
        let normalized = normalizeErrorMessage(message)
        
        // Build fingerprint input
        var input = normalized
        if let domain = domain { input += "|\(domain)" }
        if let file = file { input += "|\(file)" }
        if let line = line { input += "|\(line)" }
        
        // SHA256 hash
        return sha256(input)
    }
    
    private func normalizeErrorMessage(_ message: String) -> String {
        var result = message
        
        // Strip UUIDs
        result = result.replacingOccurrences(
            of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            with: "<UUID>",
            options: .regularExpression
        )
        
        // Strip specific numbers (error codes, counts, etc.)
        result = result.replacingOccurrences(
            of: "\\b\\d{4,}\\b",
            with: "<NUM>",
            options: .regularExpression
        )
        
        // Strip URLs
        result = result.replacingOccurrences(
            of: "https?://[^\\s]+",
            with: "<URL>",
            options: .regularExpression
        )
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "unknown" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - File Categorization (auto-detect domain from filename)
    // ═══════════════════════════════════════════════════════════════
    
    private func categorizeFile(_ filename: String) -> String {
        let lower = filename.lowercased()
        if lower.contains("workout") || lower.contains("exercise") { return "Workout" }
        if lower.contains("supabase") || lower.contains("network") || lower.contains("api") { return "Network" }
        if lower.contains("auth") || lower.contains("login") || lower.contains("signup") { return "Auth" }
        if lower.contains("challenge") { return "Social" }
        if lower.contains("friend") || lower.contains("social") || lower.contains("realtime") { return "Social" }
        if lower.contains("food") || lower.contains("nutrition") || lower.contains("meal") || lower.contains("recipe") { return "Nutrition" }
        if lower.contains("health") || lower.contains("step") || lower.contains("heart") || lower.contains("sleep") { return "Health" }
        if lower.contains("weight") || lower.contains("hydration") { return "Health" }
        if lower.contains("core") || lower.contains("persistence") || lower.contains("data") { return "CoreData" }
        if lower.contains("notification") || lower.contains("push") { return "Notifications" }
        if lower.contains("video") || lower.contains("thumbnail") { return "Media" }
        if lower.contains("premium") || lower.contains("purchase") || lower.contains("ad") { return "Monetization" }
        if lower.contains("onboarding") { return "Onboarding" }
        if lower.contains("view") || lower.contains("ui") || lower.contains("screen") { return "UI" }
        return "General"
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Disk Persistence (for fatal crashes)
    // ═══════════════════════════════════════════════════════════════
    
    private func persistReportToDisk(_ report: CrashReportInsert) {
        do {
            var pending = loadPendingReports()
            pending.append(report)
            
            // Trim to max
            if pending.count > Config.maxPendingReports {
                pending = Array(pending.suffix(Config.maxPendingReports))
            }
            
            let data = try JSONEncoder().encode(pending)
            try data.write(to: pendingReportsURL, options: .atomic)
        } catch {
            // Can't do much if disk write fails during a crash
        }
    }
    
    private func loadPendingReports() -> [CrashReportInsert] {
        guard FileManager.default.fileExists(atPath: pendingReportsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: pendingReportsURL)
            return try JSONDecoder().decode([CrashReportInsert].self, from: data)
        } catch {
            return []
        }
    }
    
    private func clearPendingReports() {
        try? FileManager.default.removeItem(at: pendingReportsURL)
    }
    
    /// Persist a pre-built snapshot to disk. Does NOT acquire any locks.
    private func persistBreadcrumbsSnapshot(_ snapshot: [[String: String]]) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: breadcrumbsURL, options: .atomic)
        } catch {
            // Non-critical
        }
    }
    
    /// Thread-safe persist — acquires lock, snapshots, then writes to disk.
    /// Only call this from contexts that do NOT already hold breadcrumbLock.
    private func persistBreadcrumbsToDisk() {
        let snapshot = getBreadcrumbsSnapshot()
        persistBreadcrumbsSnapshot(snapshot)
    }
    
    private func restoreBreadcrumbs() {
        guard FileManager.default.fileExists(atPath: breadcrumbsURL.path) else { return }
        // Clear disk breadcrumbs - they're from a previous session
        try? FileManager.default.removeItem(at: breadcrumbsURL)
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Upload
    // ═══════════════════════════════════════════════════════════════
    
    /// Upload pending crash reports from disk (from previous crash)
    private func uploadPendingReports() {
        let pending = loadPendingReports()
        guard !pending.isEmpty else { return }
        
        AppLogger.debug("🛡️ [CrashReporter] Found \(pending.count) pending crash reports from previous session", category: .general)
        
        Task.detached(priority: .utility) {
            var uploaded = 0
            for report in pending {
                let success = await self.uploadReport(report)
                if success { uploaded += 1 }
            }
            
            if uploaded > 0 {
                AppLogger.debug("🛡️ [CrashReporter] Uploaded \(uploaded)/\(pending.count) pending crash reports", category: .general)
                self.clearPendingReports()
            }
        }
    }
    
    /// Upload a single crash report to Supabase
    @discardableResult
    private func uploadReport(_ report: CrashReportInsert) async -> Bool {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("🛡️ [CrashReporter] Skipping upload — not authenticated (will retry later)", category: .general)
            return false
        }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("crash_reports")
                .insert(report)
                .execute()
            
            return true
        } catch {
            // Classifier keeps transient / auth-expired / RLS rejections at .warning.
            // Without this, every offline queue flush produced a fresh
            // bug_intelligence fingerprint (the #1 source of noise pre-Phase 5).
            NetworkErrorClassifier.log(
                error,
                context: "🛡️ [CrashReporter] Upload failed",
                category: .general
            )
            return false
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Device Info Helpers
    // ═══════════════════════════════════════════════════════════════
    
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Map to human-readable names
        let modelMap: [String: String] = [
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
        ]
        
        return modelMap[identifier] ?? identifier
    }
    
    private func getMemoryUsageMB() -> Double? {
        let mb = SystemMetrics.getMemoryUsageMB()
        return mb > 0 ? mb : nil
    }
    
    private func getFreeMemoryMB() -> Double? {
        let pageSize = vm_kernel_page_size
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(vmStats.free_count) * Double(pageSize) / 1_048_576.0
    }
    
    private func getNetworkType() -> String {
        // Basic network check - could enhance with NWPathMonitor
        return "unknown"
    }
    
    private func getSessionLogSnippet() -> String? {
        let fullLog = SessionLogManager.shared.exportLogsAsText()
        guard !fullLog.isEmpty else { return nil }
        
        let lines = fullLog.components(separatedBy: "\n")
        let snippetLines = Array(lines.suffix(Config.maxSessionLogSnippetLines))
        let snippet = snippetLines.joined(separator: "\n")
        
        // Cap at 10KB to avoid oversized payloads
        return String(snippet.prefix(10_000))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - C Signal Handler (must be a free function)
// ═══════════════════════════════════════════════════════════════

/// Global reference for the C signal handler callback
private var _crashReportingServiceInstance: CrashReportingService?

/// C-compatible signal handler function
private func _signalHandler(_ signal: Int32) {
    _crashReportingServiceInstance?.handleSignal(signal)
    
    // Re-raise the signal with default handler so the OS can handle it
    Darwin.signal(signal, SIG_DFL)
    Darwin.raise(signal)
}
