//
//  OAuthAuditLog.swift
//  Fit33
//
//  Persistent breadcrumb trail of OAuth wearable connect / disconnect /
//  token-refresh events so we can investigate "WHOOP just disconnected
//  again" reports AFTER THE FACT — without relying on dev_session_logs
//  being flushed at the right moment, the user re-running the app, or the
//  raw NSLog buffer surviving a process exit.
//
//  Why this exists (2026-04-28):
//  We've shipped:
//   • single-flight refresh (`4d-singleflight`)
//   • additive integration-status push (`4c-supabase-integration-additive`)
//   • locked-keychain disambiguation (`4d-recover`)
//   • conditional refresh-token rotation (`4d`)
//  …and Joe still reports recurring WHOOP disconnects between sessions.
//  The current `[WHOOP] Disconnected` log line tells us the symptom but
//  not the cause: which call site invoked `disconnect()`, what the
//  keychain probe returned at the moment, or whether the disconnect
//  fired in this process or a prior BGTask wake. This log answers all
//  three so the next reproduction is diagnosed in one read.
//

import Foundation

/// Append-only ring buffer (capped at `maxEntries`) of OAuth lifecycle
/// events for `WhoopService`, `OuraService`, `StravaService`,
/// `FitbitService`. Persisted in `UserDefaults` so the trail survives
/// process exits (the keychain itself isn't appropriate here — these are
/// non-sensitive breadcrumbs and we want them readable from the app
/// without unlocking the keychain).
///
/// Read with `OAuthAuditLog.dump(service:)` (returns most-recent-first
/// printable list) at app launch when investigating reports.
enum OAuthAuditLog {

    // MARK: - Configuration

    /// Maximum entries retained per service. Exceeded entries drop oldest
    /// first. 50 covers ~a week of normal usage at 5–8 events/day.
    private static let maxEntries: Int = 50

    /// `UserDefaults` key prefix per service. Keys live in the standard
    /// suite (NOT the App Group suite) — these are app-only diagnostics
    /// and should NEVER show in any widget.
    private static let keyPrefix: String = "oauth_audit_log."

    // MARK: - Event Type

    enum Event: String, Codable {
        case connect            // user-initiated OAuth callback success
        case disconnect         // any path that cleared tokens
        case refreshSuccess     // token rotation succeeded
        case refreshFailure     // 4xx/5xx/timeout on /oauth/token
        case keychainProbe      // init / scenePhase / BGTask wake snapshot
        case stateTransition    // `isConnected` flipped (without a connect/disconnect)
    }

    // MARK: - Entry

    struct Entry: Codable {
        let ts: Date
        let event: String
        let service: String
        let reason: String              // short human label: "user_tap", "http_400", "rt_wiped", "init_probe"
        let details: [String: String]   // free-form: keychain status, http code, refresh window, etc.
        let stackHead: [String]?        // for `disconnect` only — top 8 stack frames

        /// Compact, human-readable line — used in console dumps.
        var formatted: String {
            let dateStr = ISO8601DateFormatter().string(from: ts)
            let detailStr = details.isEmpty ? "" :
                " [" + details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ") + "]"
            return "\(dateStr) \(service) \(event) reason=\(reason)\(detailStr)"
        }
    }

    // MARK: - Public API

    /// Append a breadcrumb. Safe to call from any thread; uses
    /// `UserDefaults`'s thread-safe writes. Failures (encoding, etc.)
    /// are silent — we never want a log path to throw.
    static func record(
        service: String,
        event: Event,
        reason: String,
        details: [String: String] = [:],
        captureStack: Bool = false
    ) {
        let stackHead: [String]? = captureStack
            ? Array(Thread.callStackSymbols.prefix(8))
            : nil

        let entry = Entry(
            ts: Date(),
            event: event.rawValue,
            service: service,
            reason: reason,
            details: details,
            stackHead: stackHead
        )

        let key = keyPrefix + service
        var existing: [Entry] = []
        if let raw = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Entry].self, from: raw) {
            existing = decoded
        }
        existing.append(entry)
        if existing.count > maxEntries {
            existing = Array(existing.suffix(maxEntries))
        }
        if let encoded = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    /// Returns most-recent-first printable list. Pass `nil` for all
    /// services interleaved by timestamp.
    static func dump(service: String? = nil) -> [String] {
        let services: [String] = service.map { [$0] } ?? ["whoop", "oura", "strava", "fitbit"]
        var all: [Entry] = []
        for s in services {
            let key = keyPrefix + s
            guard let raw = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Entry].self, from: raw) else {
                continue
            }
            all.append(contentsOf: decoded)
        }
        all.sort { $0.ts > $1.ts }
        return all.map { $0.formatted }
    }

    /// Erase the breadcrumb trail for a service (or all services).
    /// Used after a clean reconnect so old failure events don't pollute
    /// the next diagnostic.
    static func clear(service: String? = nil) {
        let services: [String] = service.map { [$0] } ?? ["whoop", "oura", "strava", "fitbit"]
        for s in services {
            UserDefaults.standard.removeObject(forKey: keyPrefix + s)
        }
    }

    // MARK: - Cloud Forwarding
    //
    // 2026-04-29 — bug-intel "WHOOP card disappeared with no disconnect
    // log line on the cloud side". The audit trail above is local-only
    // (UserDefaults), so debugging "why is WHOOP suddenly disconnected
    // again?" required a remote device pull. This forwards the trail
    // through `AppLogger` once per foreground (gated by a watermark so
    // we don't ship the same breadcrumbs every launch). When dev
    // logging is enabled for the user, the entries land in
    // `dev_session_logs.entries[]` and become queryable for post-mortem
    // — same surface used to investigate this incident in the first
    // place. Cheap (≤4 services × ≤50 entries × one log line) and
    // best-effort: we never want a logging path to throw.

    private static let watermarkKey: String = "oauth_audit_log.last_flushed_ts"

    /// Forward newly-recorded entries (since the last flush) into
    /// `AppLogger` so they land in `dev_session_logs.entries[]` when
    /// dev logging is enabled. Idempotent — re-runs are a no-op until
    /// new entries arrive. Call once per foreground.
    static func flushToDevLog() {
        let lastFlushed = UserDefaults.standard.double(forKey: watermarkKey)
        var newWatermark = lastFlushed
        var flushed = 0
        let services = ["whoop", "oura", "strava", "fitbit"]
        for s in services {
            let key = keyPrefix + s
            guard let raw = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Entry].self, from: raw) else {
                continue
            }
            for entry in decoded {
                let ts = entry.ts.timeIntervalSince1970
                guard ts > lastFlushed else { continue }
                if ts > newWatermark { newWatermark = ts }
                // Use `.info` (NOT `.warning`) for the .keychainProbe
                // breadcrumbs — they're informational, not bug-class.
                // Real failure events (.refreshFailure / .disconnect)
                // ride the same level so they don't inflate severity
                // scores in the bug-intel pipeline; the `event=` token
                // in the message lets the dashboard filter them.
                AppLogger.info(
                    "[OAUTH-AUDIT] \(entry.formatted)",
                    category: .auth
                )
                flushed += 1
            }
        }
        if flushed > 0 {
            UserDefaults.standard.set(newWatermark, forKey: watermarkKey)
            AppLogger.info("[OAUTH-AUDIT] Flushed \(flushed) breadcrumbs to dev log (watermark=\(newWatermark))", category: .auth)
        }
    }
}
