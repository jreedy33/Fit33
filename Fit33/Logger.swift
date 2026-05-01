import Foundation
import os.log

// MARK: - Production Print Override
// In Release builds, this completely silences print() statements
// This is more efficient than wrapping every print in #if DEBUG
#if !DEBUG
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // Silent in production — no-op.
    // All 3,000+ print() calls are automatically suppressed in App Store builds.
}
#endif

// MARK: - Structured Logger

/// Production-safe, level-gated logging utility.
///
/// **Debug builds**: All levels print to console via `Swift.print`.
/// **Release builds**: Only `.error` and `.critical` emit via `os_log`
/// so they appear in Console.app / crash reports without noise.
///
/// Usage:
///   AppLogger.debug("loading exercises")
///   AppLogger.error("failed to save: \(error)")
enum AppLogger {

    // os.log subsystem (bundle ID) — used for production-important logs
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.fit33"

    /// Log categories matching major app domains
    enum Category: String {
        case auth        = "Auth"
        case workout     = "Workout"
        case social      = "Social"
        case nutrition   = "Nutrition"
        case health      = "Health"
        case network     = "Network"
        case ui          = "UI"
        case data        = "Data"
        case performance = "Performance"
        case general     = "General"
    }

    /// Severity levels
    enum Level: Int, Comparable {
        case verbose = 0   // Only in debug, very chatty
        case debug   = 1   // Debug-only detail
        case info    = 2   // Notable runtime event
        case warning = 3   // Unexpected but handled
        case error   = 4   // Something failed
        case critical = 5  // Crash-imminent

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var emoji: String {
            switch self {
            case .verbose:  return "🔍"
            case .debug:    return "🐛"
            case .info:     return "ℹ️"
            case .warning:  return "⚠️"
            case .error:    return "❌"
            case .critical: return "🔥"
            }
        }

        var osLogType: OSLogType {
            switch self {
            case .verbose, .debug: return .debug
            case .info:            return .info
            case .warning:         return .default
            case .error:           return .error
            case .critical:        return .fault
            }
        }
    }

    // MARK: - Core

    /// Minimum level that actually emits. Change per-build if needed.
    #if DEBUG
    private static let minimumLevel: Level = .verbose
    #else
    private static let minimumLevel: Level = .error
    #endif

    static func log(
        _ message: @autoclosure () -> String,
        level: Level = .debug,
        category: Category = .general,
        context: DiagnosticContext? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Build message (append DiagnosticContext compact summary if present)
        let rawText = message()
        let text = context.map { "\(rawText) \($0.compactSummary)" } ?? rawText

        // Forward to NewUserJourneyTracker when active (parallel pipeline,
        // 72h-TTL per-user behavioral telemetry — see NewUserJourneyTracker.swift).
        // Only ship .warning+ here so the per-user payload stays bounded; product
        // funnel events come through the tracker's explicit logFunnelStep / logTap
        // surface, not via free-form AppLogger calls.
        if NewUserJourneyTracker.isActive && level >= .warning {
            let capturedLevel = level
            let capturedCategory = category.rawValue
            let capturedText = text
            let capturedFile = (file as NSString).lastPathComponent
            let capturedLine = line
            let capturedFunction = function
            Task { @MainActor in
                let severityString: String = {
                    switch capturedLevel {
                    case .critical: return "critical"
                    case .error:    return "error"
                    case .warning:  return "warning"
                    default:        return "info"
                    }
                }()
                NewUserJourneyTracker.shared.logError(
                    message: "[\(capturedCategory)] \(capturedText)",
                    severity: severityString,
                    file: capturedFile,
                    line: capturedLine,
                    function: capturedFunction
                )
            }
        }

        // Forward ALL levels to advanced session logger when active (before minimum level gate)
        if AdvancedSessionLogger.isActive {
            let capturedCategory = category.rawValue
            let capturedLevel = level
            let capturedCtx = context
            // Bug-Intel Phase 12 (2026-04-25 — Tier 0 #1): always ship the
            // call-site (`file:line:function`) into `dev_session_logs.entries[].x_*`
            // so the rollup pipeline can pivot fingerprints by source location
            // — not just by message string. Pre-Phase-12, only `crash_reports`
            // carried this via `CrashReportingService.additionalContext`; logs
            // dropped it entirely. Now every `AppLogger.error/.warning/.critical`
            // line in the codebase auto-attaches its source location for free
            // (the compiler fills `#file/#line/#function` at the call site that
            // invoked the convenience wrapper, then this base method threads them
            // through). Keys are prefixed `x_` by `AdvancedSessionLogger.log` →
            // `entry->>'x_file' / 'x_line' / 'x_function'` in SQL.
            let fileName = (file as NSString).lastPathComponent
            var baseExtra: [String: Any] = [
                "file": fileName,
                "line": line,
                "function": function
            ]
            if let ctxDict = capturedCtx?.asAnyDict {
                for (k, v) in ctxDict { baseExtra[k] = v }
            }
            Task { @MainActor in
                let logType = capturedLevel >= .error ? "error" : (capturedLevel >= .warning ? "warning" : "log")
                AdvancedSessionLogger.shared.log(
                    type: logType,
                    detail: "[\(capturedCategory)] \(text)",
                    screen: nil,
                    apiEndpoint: capturedCtx?.endpoint,
                    apiStatus: capturedCtx?.httpStatus,
                    durationMs: capturedCtx?.elapsedMs,
                    error: capturedCtx?.pgCode,
                    extra: baseExtra
                )
            }
        }

        guard level >= minimumLevel else { return }

        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        Swift.print("\(level.emoji) [\(category.rawValue)] [\(filename):\(line)] \(text)")
        #else
        if level >= .error {
            let log = OSLog(subsystem: subsystem, category: category.rawValue)
            os_log("%{public}@", log: log, type: level.osLogType, text)
        }
        #endif
        
        // 🛡️ Auto-report errors and critical issues to crash reporting service
        if level >= .error {
            let severity: CrashReportingService.ErrorSeverity = level >= .critical ? .critical : .high
            CrashReportingService.shared.reportError(
                message: text,
                domain: category.rawValue,
                code: context?.pgCode,
                severity: severity,
                file: file,
                function: function,
                line: line,
                additionalContext: context?.asStringDict
            )
        }
    }

    // MARK: - Convenience

    // Bug-Intel Phase 12 (2026-04-25): convenience wrappers MUST forward
    // `#file/#function/#line` so the call site (not Logger.swift) shows up in
    // `dev_session_logs.entries[].x_file:x_line` and `crash_reports.additional_context.file:line`.
    static func verbose(_ msg: @autoclosure () -> String, category: Category = .general, context: DiagnosticContext? = nil,
                        file: String = #file, function: String = #function, line: Int = #line) {
        log(msg(), level: .verbose, category: category, context: context, file: file, function: function, line: line)
    }
    static func debug(_ msg: @autoclosure () -> String, category: Category = .general, context: DiagnosticContext? = nil,
                      file: String = #file, function: String = #function, line: Int = #line) {
        log(msg(), level: .debug, category: category, context: context, file: file, function: function, line: line)
    }
    static func info(_ msg: @autoclosure () -> String, category: Category = .general, context: DiagnosticContext? = nil,
                     file: String = #file, function: String = #function, line: Int = #line) {
        log(msg(), level: .info, category: category, context: context, file: file, function: function, line: line)
    }
    static func warning(_ msg: @autoclosure () -> String, category: Category = .general, context: DiagnosticContext? = nil,
                        file: String = #file, function: String = #function, line: Int = #line) {
        log(msg(), level: .warning, category: category, context: context, file: file, function: function, line: line)
    }
    static func error(_ msg: @autoclosure () -> String, category: Category = .general, context: DiagnosticContext? = nil,
                      file: String = #file, function: String = #function, line: Int = #line) {
        log(msg(), level: .error, category: category, context: context, file: file, function: function, line: line)
    }
    static func critical(_ msg: @autoclosure () -> String, category: Category = .general, context: DiagnosticContext? = nil,
                         file: String = #file, function: String = #function, line: Int = #line) {
        log(msg(), level: .critical, category: category, context: context, file: file, function: function, line: line)
    }
}

// MARK: - Legacy Logger (preserved for backward compatibility)

/// Legacy convenience logger — delegates to AppLogger.
enum Logger {
    enum Level: String {
        case debug = "🔍"
        case info = "ℹ️"
        case success = "✅"
        case warning = "⚠️"
        case error = "❌"
        case network = "🌐"
        case data = "📦"
        case performance = "⚡"
    }

    static func log(_ message: String, level: Level = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        print("\(level.rawValue) [\(filename):\(line)] \(message)")
        #endif
    }

    static func debug(_ message: String) { log(message, level: .debug) }
    static func info(_ message: String) { log(message, level: .info) }
    static func success(_ message: String) { log(message, level: .success) }
    static func warning(_ message: String) { log(message, level: .warning) }
    static func error(_ message: String) { log(message, level: .error) }
    static func network(_ message: String) { log(message, level: .network) }
    static func data(_ message: String) { log(message, level: .data) }
    static func performance(_ message: String) { log(message, level: .performance) }
}

/// Global debug print function - only active in DEBUG builds
/// Use this as a drop-in replacement for print() statements
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    print(output, terminator: terminator)
    #endif
}
