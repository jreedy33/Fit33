import Foundation

// MARK: - Network Error Classifier
//
// Shared helper for correctly classifying Foundation / NSURLError / Supabase
// errors into log levels that match the QUALITY_PERFORMANCE_AGENT invariants:
//
//   #15 — HealthKit "protected health data" / "no data available" /
//         "authorization not determined" → .debug (EXPECTED, device state).
//   #25 — Normal user actions / transient network / cancelled ops → .debug
//         or .warning; `.error` is reserved for actual malfunctions.
//
// The previous pattern — `AppLogger.error("Save failed: \(error.localizedDescription)")`
// in every Supabase catch block — was responsible for 25+ bug-intelligence
// fingerprints per rollup, because every `AppLogger.error(...)` call:
//   1. writes an `entries[type=error]` row into `dev_session_logs`
//   2. (conditionally) posts a `crash_reports` row via
//      `CrashReportingService.reportError`
// and the `compute_daily_bug_rollup()` pg function captures both as bugs.
//
// The classifier keeps the catch blocks honest: transient / expected errors
// log at `.debug` or `.warning`, real bugs stay at `.error`. Call sites use:
//
//     } catch {
//         NetworkErrorClassifier.log(
//             error,
//             context: "Saving HealthKit activity",
//             category: .health
//         )
//     }
//
// If you need to suppress a specific transient class entirely (e.g. the
// offline retry queue already owns recovery, so surfacing the first failure
// at `.warning` is noise), pass `transientLevel: .debug`.

enum NetworkErrorClassifier {

    // MARK: - Classification
    enum Classification {
        case expectedHealthKit     // HK-permissioning, device-locked, no-data
        case transientNetwork      // timeout, connection lost, not connected, cancelled
        case authExpired           // Supabase session invalid / no auth
        case rlsViolation          // RLS rejected the row (usually auth-expired + user_id set)
        case realError             // anything else
    }

    static func classify(_ error: Error) -> Classification {
        if error is CancellationError { return .transientNetwork }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCancelled,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed:
                return .transientNetwork
            default:
                break
            }
        }

        let lower = nsError.localizedDescription.lowercased()

        // HealthKit expected states — QP invariant #15
        if lower.contains("protected health data")
            || lower.contains("no data available")
            || lower.contains("authorization not determined") {
            return .expectedHealthKit
        }

        // Supabase / PostgREST transient + auth patterns
        if lower.contains("the network connection was lost")
            || lower.contains("not connected to the internet")
            || lower.contains("request timed out")
            || lower.contains("the operation couldn’t be completed. (\(nsError.domain) error -999)")
            || lower.contains("cancelled") {
            return .transientNetwork
        }

        // Cloudflare / edge gateway flaps — the proxy in front of Supabase
        // periodically returns 502/503/504 for a few seconds during rolling
        // restarts. The iOS retry queue recovers these automatically, so
        // surfacing them as .error creates a bug_intelligence_fingerprint
        // every deploy. Treat as transient. (QP invariant #25a, #25b)
        if lower.contains("502 bad gateway")
            || lower.contains("bad gateway")
            || lower.contains("503 service unavailable")
            || lower.contains("service unavailable")
            || lower.contains("504 gateway time-out")
            || lower.contains("gateway timeout")
            || lower.contains("gateway time-out")
            || lower.contains("status code: 502")
            || lower.contains("status code: 503")
            || lower.contains("status code: 504") {
            return .transientNetwork
        }

        if lower.contains("not authenticated")
            || lower.contains("jwt expired")
            || lower.contains("invalid jwt") {
            return .authExpired
        }

        if lower.contains("row-level security policy") || lower.contains("42501") {
            return .rlsViolation
        }

        return .realError
    }

    static func isTransient(_ error: Error) -> Bool {
        switch classify(error) {
        case .transientNetwork, .expectedHealthKit, .authExpired:
            return true
        case .rlsViolation, .realError:
            return false
        }
    }

    // MARK: - Logging
    //
    // `context` should describe the operation (“Saving HealthKit activity”,
    // “Syncing steps to cloud”). The classifier composes:
    //   "<context>: <localizedDescription>"
    // and picks a log level:
    //   transient/expected → `transientLevel` (default `.warning`)
    //   auth-expired       → `.warning`  + category `.auth`
    //   rls-violation      → `.warning`  + category `.auth` (same root cause)
    //   real-error         → `.error`
    //
    // Returns the classification so the caller can decide to retry, queue for
    // offline replay, etc.

    @discardableResult
    static func log(
        _ error: Error,
        context: String,
        category: AppLogger.Category = .general,
        transientLevel: AppLogger.Level = .warning,
        op: String? = nil,
        endpoint: String? = nil,
        startedAt: Date? = nil,
        userId: UUID? = nil,
        retryAttempt: Int? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> Classification {
        let classification = classify(error)
        let msg = "\(context): \(error.localizedDescription)"

        // When any structured context field is supplied, build a
        // DiagnosticContext so downstream fingerprinting can pivot by
        // pg_code / http_status / op. Existing call sites that omit all
        // optional args still work exactly as before (context = nil).
        let diag: DiagnosticContext? = {
            guard op != nil || endpoint != nil || startedAt != nil || userId != nil else {
                return nil
            }
            return DiagnosticContext.from(
                error: error,
                op: op ?? "unknown",
                endpoint: endpoint,
                startedAt: startedAt,
                userId: userId,
                retryAttempt: retryAttempt
            )
        }()

        switch classification {
        case .transientNetwork, .expectedHealthKit:
            AppLogger.log(msg, level: transientLevel, category: category, context: diag, file: file, function: function, line: line)
        case .authExpired, .rlsViolation:
            // Route auth/RLS at .warning with category `.auth` so the catch-all
            // rollup can separate "user needs to re-auth" from "network flapped"
            // without spamming crash_reports.
            AppLogger.log(msg, level: .warning, category: .auth, context: diag, file: file, function: function, line: line)
        case .realError:
            AppLogger.log(msg, level: .error, category: category, context: diag, file: file, function: function, line: line)
        }

        return classification
    }
}
