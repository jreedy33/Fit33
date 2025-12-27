import Foundation

// MARK: - Production Print Override
// In Release builds, this completely silences print() statements
// This is more efficient than wrapping every print in #if DEBUG
#if !DEBUG
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // Silent in production - no-op
}
#endif

/// Production-safe logging utility
/// Only prints in DEBUG builds - completely silent in Release
enum Logger {
    
    /// Log levels for categorization
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
    
    /// Main logging function - only active in DEBUG builds
    static func log(_ message: String, level: Level = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        print("\(level.rawValue) [\(filename):\(line)] \(message)")
        #endif
    }
    
    /// Convenience methods
    static func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    static func info(_ message: String) {
        log(message, level: .info)
    }
    
    static func success(_ message: String) {
        log(message, level: .success)
    }
    
    static func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    static func error(_ message: String) {
        log(message, level: .error)
    }
    
    static func network(_ message: String) {
        log(message, level: .network)
    }
    
    static func data(_ message: String) {
        log(message, level: .data)
    }
    
    static func performance(_ message: String) {
        log(message, level: .performance)
    }
}

/// Global debug print function - only active in DEBUG builds
/// Use this as a drop-in replacement for print() statements
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    print(output, terminator: terminator)
    #endif
}

