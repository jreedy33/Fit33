import Foundation

// MARK: - Diagnostic Context
//
// Structured diagnostic payload attached to errors + performance logs so the
// Bug Intelligence rollup can fingerprint by `pg_code` / `http_status` / `op`
// instead of lossy error strings.
//
// Every cluster fix in the "mega-sweep" attaches one of these at every catch
// block that previously logged `AppLogger.error(...)`. When the next
// occurrence happens, `dev_session_logs.entries[].extra` tells the full
// story:
//   • op           = "weight.log" / "dashboard.social_fanout"
//   • endpoint     = "rpc/get_daily_quests" / "weight_logs"
//   • elapsed_ms   = wall-clock from operation start to failure
//   • pg_code      = PostgrestError.code ("42501" RLS / "42883" UUID / "23505" dup)
//   • http_status  = URL response code (401 / 502 / 504)
//   • user_id_short = first 8 chars of UUID (PII minimization)
//   • retry_attempt = 0 for first-try, 1+ for retries
//
// Usage:
//   } catch {
//       let ctx = DiagnosticContext.from(
//           error: error,
//           op: "weight.log",
//           endpoint: "weight_logs",
//           startedAt: startedAt,
//           userId: currentUser?.id
//       )
//       AppLogger.error("Failed to log weight", category: .health, context: ctx)
//   }

struct DiagnosticContext {
    let op: String
    let endpoint: String?
    let elapsedMs: Int?
    let pgCode: String?
    let httpStatus: Int?
    let userIdShort: String?
    let retryAttempt: Int?

    init(op: String,
         endpoint: String? = nil,
         elapsedMs: Int? = nil,
         pgCode: String? = nil,
         httpStatus: Int? = nil,
         userIdShort: String? = nil,
         retryAttempt: Int? = nil) {
        self.op = op
        self.endpoint = endpoint
        self.elapsedMs = elapsedMs
        self.pgCode = pgCode
        self.httpStatus = httpStatus
        self.userIdShort = userIdShort
        self.retryAttempt = retryAttempt
    }

    /// Compact one-line summary appended to log messages.
    /// Example: "[op=weight.log ep=weight_logs pg=42883 ms=1240 u=a1b2c3d4]"
    var compactSummary: String {
        var parts: [String] = ["op=\(op)"]
        if let endpoint { parts.append("ep=\(endpoint)") }
        if let pgCode { parts.append("pg=\(pgCode)") }
        if let httpStatus { parts.append("http=\(httpStatus)") }
        if let elapsedMs { parts.append("ms=\(elapsedMs)") }
        if let retryAttempt, retryAttempt > 0 { parts.append("try=\(retryAttempt)") }
        if let userIdShort { parts.append("u=\(userIdShort)") }
        return "[\(parts.joined(separator: " "))]"
    }

    /// Flat String->String dict for `CrashReportingService.additionalContext`
    /// (flat keeps compat with the existing JSONB column shape).
    var asStringDict: [String: String] {
        var d: [String: String] = ["op": op]
        if let endpoint { d["endpoint"] = endpoint }
        if let pgCode { d["pg_code"] = pgCode }
        if let httpStatus { d["http_status"] = String(httpStatus) }
        if let elapsedMs { d["elapsed_ms"] = String(elapsedMs) }
        if let retryAttempt { d["retry_attempt"] = String(retryAttempt) }
        if let userIdShort { d["user_id_short"] = userIdShort }
        return d
    }

    /// Untyped dict for `AdvancedSessionLogger.log(extra:)` parameter.
    var asAnyDict: [String: Any] {
        asStringDict as [String: Any]
    }
}

// MARK: - Factories

extension DiagnosticContext {
    /// Build a context from an error surfaced by PostgREST / Foundation URL.
    /// Extracts PostgrestError.code + HTTP status when available.
    static func from(
        error: Error,
        op: String,
        endpoint: String? = nil,
        startedAt: Date? = nil,
        userId: UUID? = nil,
        retryAttempt: Int? = nil
    ) -> DiagnosticContext {
        let elapsedMs = startedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
        let pg = PgErrorExtractor.code(from: error)
        let http = PgErrorExtractor.httpStatus(from: error)
        let uShort = userId.map { String($0.uuidString.prefix(8).lowercased()) }
        return DiagnosticContext(
            op: op,
            endpoint: endpoint,
            elapsedMs: elapsedMs,
            pgCode: pg,
            httpStatus: http,
            userIdShort: uShort,
            retryAttempt: retryAttempt
        )
    }

    /// Build a timing-only context (no error). Used for signpost ends.
    static func timing(
        op: String,
        elapsedMs: Int,
        endpoint: String? = nil,
        userId: UUID? = nil
    ) -> DiagnosticContext {
        let uShort = userId.map { String($0.uuidString.prefix(8).lowercased()) }
        return DiagnosticContext(
            op: op,
            endpoint: endpoint,
            elapsedMs: elapsedMs,
            pgCode: nil,
            httpStatus: nil,
            userIdShort: uShort,
            retryAttempt: nil
        )
    }
}

// MARK: - PostgREST / NSError extraction
//
// Supabase-swift `PostgrestError` exposes `.code` as a stored property.
// Foundation `NSURLErrorDomain` errors sometimes carry
// `userInfo["HTTPStatusCode"]`. We also parse common patterns out of
// `.localizedDescription` as a best-effort fallback so older Supabase
// SDK versions still yield a fingerprintable code.

enum PgErrorExtractor {
    static func code(from error: Error) -> String? {
        // Walk stored properties via Mirror — works for PostgrestError without
        // importing Supabase types here (avoids adding a compile dep on the
        // Supabase module from a utility file).
        let mirror = Mirror(reflecting: error)
        for child in mirror.children {
            guard child.label == "code" else { continue }
            if let v = child.value as? String { return v }
            // .code may be wrapped in Optional<String>; unwrap via another Mirror.
            let inner = Mirror(reflecting: child.value)
            if inner.displayStyle == .optional, let some = inner.children.first?.value as? String {
                return some
            }
        }
        let desc = (error as NSError).localizedDescription
        if let match = desc.range(of: #"\b(\d{5})\b"#, options: .regularExpression) {
            return String(desc[match])
        }
        if let match = desc.range(of: #"\bPGRST\d+\b"#, options: .regularExpression) {
            return String(desc[match])
        }
        return nil
    }

    static func httpStatus(from error: Error) -> Int? {
        let ns = error as NSError
        if let status = ns.userInfo["HTTPStatusCode"] as? Int { return status }
        if let status = ns.userInfo["status"] as? Int { return status }
        let desc = ns.localizedDescription
        if let match = desc.range(of: #"\b(40[0-9]|50[0-9])\b"#, options: .regularExpression) {
            return Int(desc[match])
        }
        return nil
    }
}
