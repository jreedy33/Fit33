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
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }

        let text = message()

        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        Swift.print("\(level.emoji) [\(category.rawValue)] [\(filename):\(line)] \(text)")
        #else
        // Production: route through os_log for error+ only
        if level >= .error {
            let log = OSLog(subsystem: subsystem, category: category.rawValue)
            os_log("%{public}@", log: log, type: level.osLogType, text)
        }
        #endif
        
        // Forward to advanced session logger when active
        if AdvancedSessionLogger.shared.isEnabled {
            let logType = level >= .error ? "error" : (level >= .warning ? "warning" : "log")
            AdvancedSessionLogger.shared.log(
                type: logType,
                detail: "[\(category.rawValue)] \(text)",
                screen: nil
            )
        }
        
        // 🛡️ Auto-report errors and critical issues to crash reporting service
        if level >= .error {
            let severity: CrashReportingService.ErrorSeverity = level >= .critical ? .critical : .high
            CrashReportingService.shared.reportError(
                message: text,
                domain: category.rawValue,
                severity: severity,
                file: file,
                function: function,
                line: line
            )
        }
    }

    // MARK: - Convenience

    static func verbose(_ msg: @autoclosure () -> String, category: Category = .general) {
        log(msg(), level: .verbose, category: category)
    }
    static func debug(_ msg: @autoclosure () -> String, category: Category = .general) {
        log(msg(), level: .debug, category: category)
    }
    static func info(_ msg: @autoclosure () -> String, category: Category = .general) {
        log(msg(), level: .info, category: category)
    }
    static func warning(_ msg: @autoclosure () -> String, category: Category = .general) {
        log(msg(), level: .warning, category: category)
    }
    static func error(_ msg: @autoclosure () -> String, category: Category = .general) {
        log(msg(), level: .error, category: category)
    }
    static func critical(_ msg: @autoclosure () -> String, category: Category = .general) {
        log(msg(), level: .critical, category: category)
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
