import Foundation
import UIKit
import CoreData
import Supabase
import Network

/// High-resolution behavioral tracker for the **first 72 hours** of every new
/// user's journey.
///
/// Auto-enrolled by tenure (server-side `enroll_new_user_journey()` RPC sets
/// `journey_ends_at = now() + 72h` on first auth). The iOS singleton checks
/// `is_in_new_user_journey()` on cold start; when active, every screen view,
/// tap, funnel transition, error, and integration attempt is captured and
/// batch-flushed to Supabase every 10 s (or 50 events, whichever first).
///
/// Sibling to `AdvancedSessionLogger`:
///   - `AdvancedSessionLogger` is opt-in by EMAIL (dogfooding). Manual toggle.
///   - `NewUserJourneyTracker` is opt-in by TENURE (every new user, 72h TTL).
///   - Both forward from `AppLogger` via the `isActive` flag.
///   - Both batch-upload but to different tables (`dev_session_logs` vs
///     `new_user_journey_events`).
///
/// Privacy: NO email/phone/full-name in payloads. Only `auth.uid()` plus
/// product-search terms (food names, exercise names — those are domain data,
/// not PII). Free-text bug-report bodies stay in `bug_reports`, not here.
@MainActor
final class NewUserJourneyTracker: ObservableObject {
    static let shared = NewUserJourneyTracker()

    /// Thread-safe flag readable from any context (mirror of
    /// `AdvancedSessionLogger.isActive`). Logger.swift checks this on the
    /// hot path so we avoid actor-isolated reads on every log call.
    nonisolated(unsafe) static var isActive: Bool = false

    @Published private(set) var isEnrolled = false
    @Published private(set) var journeyEndsAt: Date?
    @Published private(set) var bufferedEventCount = 0

    private var sessionId: String = ""
    private var sessionStartedAt: Date?
    private var pendingEvents: [[String: Any]] = []
    private var flushTimer: Timer?
    private let maxEventsPerBatch = 50
    private let flushIntervalSeconds: TimeInterval = 10.0

    // Per-session counters (uploaded on session end)
    private var sessionScreenViewCount = 0
    private var sessionTapCount = 0
    private var sessionErrorCount = 0
    private var sessionCrashCount = 0
    private var lastScreen: String?

    // Network type observer (cellular vs wifi vs offline) for session metadata
    private let netMonitor = NWPathMonitor()
    private var lastNetworkType: String = "unknown"

    private init() {
        // NWPathMonitor.pathUpdateHandler is invoked on the queue passed to
        // start(queue:) — a background queue. Hop to MainActor before
        // mutating `lastNetworkType` (the property is part of this @MainActor
        // class). The closure itself is @Sendable so we can only capture
        // Sendable values into the Task.
        netMonitor.pathUpdateHandler = { [weak self] path in
            let type: String
            if path.status != .satisfied {
                type = "offline"
            } else if path.usesInterfaceType(.wifi) {
                type = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                type = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = "ethernet"
            } else {
                type = "unknown"
            }
            Task { @MainActor [weak self] in
                self?.lastNetworkType = type
            }
        }
        netMonitor.start(queue: DispatchQueue(label: "com.fit33.nuj.netmon"))
    }

    // MARK: - Lifecycle

    /// Call once per cold start, AFTER auth resolves. Idempotent — safely
    /// re-callable on every scenePhase .active or post-OAuth.
    /// Performs:
    ///   1. Server-side enrollment (idempotent; returns existing window if any)
    ///   2. Activates batched ingestion if `journey_ends_at > now()`
    func checkEnrollmentAndActivate() async {
        guard SupabaseManager.shared.isAuthenticated,
              SupabaseManager.shared.currentUser != nil else { return }

        do {
            struct EnrollResponse: Decodable {
                let success: Bool
                let newly_enrolled: Bool?
                let journey_started_at: String?
                let journey_ends_at: String?
                let is_active: Bool?
            }

            let response: EnrollResponse = try await SupabaseManager.shared.supabaseClient
                .rpc("enroll_new_user_journey", params: enrollmentParams())
                .execute()
                .value

            guard response.success else {
                AppLogger.debug("[NUJ] enroll returned success=false", category: .general)
                return
            }

            isEnrolled = true
            if let endsAt = response.journey_ends_at {
                journeyEndsAt = Self.iso8601.date(from: endsAt) ?? Self.iso8601Frac.date(from: endsAt)
            }
            let active = response.is_active ?? false

            if active {
                activate(newlyEnrolled: response.newly_enrolled ?? false)
            } else {
                AppLogger.debug("[NUJ] not active (journey expired)", category: .general)
            }
        } catch {
            AppLogger.debug("[NUJ] enrollment check failed: \(error.localizedDescription)", category: .network)
        }
    }

    /// Read by `Fit33App` immediately after a successful auth/OAuth callback.
    /// Persisted in UserDefaults so a process restart between sign-up and
    /// enrollment activation doesn't lose the channel attribution.
    private static let authProviderKey = "fit33.nuj.last_auth_provider"
    private static let referralKey = "fit33.nuj.install_referral"

    /// Set by callers (`OnboardingView`, `SocialAuthService`) on the moment
    /// of successful auth so enrollment captures channel attribution.
    static func recordAuthProvider(_ provider: String) {
        UserDefaults.standard.set(provider, forKey: authProviderKey)
    }

    static func recordInstallReferral(_ source: String) {
        UserDefaults.standard.set(source, forKey: referralKey)
    }

    private func enrollmentParams() -> [String: String?] {
        let bundle = Bundle.main.infoDictionary
        return [
            "p_auth_provider":        UserDefaults.standard.string(forKey: Self.authProviderKey),
            "p_install_app_version":  bundle?["CFBundleShortVersionString"] as? String,
            "p_install_build_number": bundle?["CFBundleVersion"] as? String,
            "p_install_device_model": Self.deviceModelIdentifier,
            "p_install_ios_version":  UIDevice.current.systemVersion,
            "p_install_locale":       Locale.current.identifier,
            "p_install_timezone":     TimeZone.current.identifier,
            "p_referral_source":      UserDefaults.standard.string(forKey: Self.referralKey)
        ]
    }

    private func activate(newlyEnrolled: Bool) {
        guard !Self.isActive else { return }
        Self.isActive = true
        sessionId = "\(UUID().uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970))"
        sessionStartedAt = Date()

        Task { await openSession() }

        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.flush() }
        }

        recordEvent(eventType: "system",
                    screen: nil,
                    detail: newlyEnrolled ? "journey_started" : "journey_resumed",
                    payload: [
                        "session_id": sessionId,
                        "newly_enrolled": newlyEnrolled
                    ])

        AppLogger.info("[NUJ] tracker active (session=\(sessionId))", category: .general)
    }

    /// Call from scenePhase .background. Stops batched ingestion, flushes,
    /// closes the session row.
    func deactivate() {
        guard Self.isActive else { return }
        Self.isActive = false
        recordEvent(eventType: "system",
                    screen: lastScreen,
                    detail: "session_ended",
                    payload: ["session_id": sessionId])
        Task {
            await flush()
            await closeSession()
        }
        flushTimer?.invalidate()
        flushTimer = nil
    }

    // MARK: - Public Recording API
    //
    // These mirror the SessionLogManager / AdvancedSessionLogger shape so any
    // existing instrumentation surface can hand off without re-thinking
    // call sites. All are no-ops when `isActive == false`.

    /// Screen view (the canonical funnel signal).
    func logScreen(_ screenName: String) {
        sessionScreenViewCount += 1
        lastScreen = screenName
        recordEvent(eventType: "screen", screen: screenName, detail: screenName, payload: [:])
    }

    /// User tap on an actionable element (button, row, chip).
    func logTap(action: String, screen: String? = nil) {
        sessionTapCount += 1
        recordEvent(eventType: "tap",
                    screen: screen ?? lastScreen,
                    detail: action,
                    payload: ["action": action])
    }

    /// Funnel step transition (onboarding, first-workout, paywall, etc.).
    /// `step_index` lets the report sort steps without parsing names.
    func logFunnelStep(funnel: String, step: String, stepIndex: Int? = nil, extra: [String: Any] = [:]) {
        var payload: [String: Any] = [
            "funnel": funnel,
            "step": step
        ]
        if let stepIndex { payload["step_index"] = stepIndex }
        for (k, v) in extra { payload[k] = v }
        recordEvent(eventType: "funnel",
                    screen: lastScreen,
                    detail: "\(funnel)/\(step)",
                    payload: payload)
    }

    /// State machine transition (e.g. WorkoutManager state, sync state).
    func logStateTransition(name: String, from: String, to: String) {
        recordEvent(eventType: "state",
                    screen: lastScreen,
                    detail: "\(name): \(from) → \(to)",
                    payload: ["name": name, "from": from, "to": to])
    }

    /// Outbound API call (Supabase RPC, edge function, third-party).
    func logAPI(endpoint: String, status: Int, durationMs: Int, screen: String? = nil) {
        recordEvent(eventType: "api",
                    screen: screen ?? lastScreen,
                    detail: "\(status) \(endpoint)",
                    payload: ["endpoint": endpoint, "status": status, "duration_ms": durationMs])
    }

    /// Non-fatal error. Forwarded automatically by AppLogger.error/.warning/.critical.
    func logError(message: String, severity: String, file: String?, line: Int?, function: String?, screen: String? = nil) {
        if severity == "error" || severity == "critical" {
            sessionErrorCount += 1
        }
        var payload: [String: Any] = ["message": message]
        if let file { payload["file"] = (file as NSString).lastPathComponent }
        if let line { payload["line"] = line }
        if let function { payload["function"] = function }
        recordEvent(eventType: "error",
                    screen: screen ?? lastScreen,
                    detail: message,
                    payload: payload,
                    severity: severity)
    }

    /// Captured crash signal (CrashReportingService entry point).
    func logCrash(reason: String, stackTop: String?) {
        sessionCrashCount += 1
        var payload: [String: Any] = ["reason": reason]
        if let stackTop { payload["stack_top"] = stackTop }
        recordEvent(eventType: "crash",
                    screen: lastScreen,
                    detail: reason,
                    payload: payload,
                    severity: "critical")
    }

    /// Workout lifecycle event.
    func logWorkout(phase: String, workoutId: String? = nil, source: String? = nil, exerciseCount: Int? = nil, durationMin: Int? = nil) {
        var payload: [String: Any] = ["phase": phase]
        if let workoutId { payload["workout_id"] = workoutId }
        if let source { payload["source"] = source }
        if let exerciseCount { payload["exercise_count"] = exerciseCount }
        if let durationMin { payload["duration_min"] = durationMin }
        recordEvent(eventType: "workout",
                    screen: lastScreen,
                    detail: "workout_\(phase)",
                    payload: payload)
    }

    /// Meal logging event.
    func logMeal(phase: String, foodName: String? = nil, source: String? = nil, calories: Double? = nil) {
        var payload: [String: Any] = ["phase": phase]
        if let foodName { payload["food_name"] = foodName }
        if let source { payload["source"] = source }
        if let calories { payload["calories"] = calories }
        recordEvent(eventType: "meal",
                    screen: lastScreen,
                    detail: "meal_\(phase)",
                    payload: payload)
    }

    /// Social action (friend add, request sent, message).
    func logSocial(action: String, targetUserId: String? = nil) {
        var payload: [String: Any] = ["action": action]
        if let targetUserId { payload["target_user_id"] = targetUserId }
        recordEvent(eventType: "social",
                    screen: lastScreen,
                    detail: action,
                    payload: payload)
    }

    /// Paywall surface event. `action` ∈ {view, dismiss, convert, restore}.
    /// - `triggeringFeature` — the `PremiumFeature.rawValue` that fired the
    ///   paywall (most useful trigger-context field; lets Claude rank "which
    ///   features convert vs dismiss")
    /// - `secondsSinceLastEvent` — what was the user doing right before? Lets
    ///   the cohort report identify "users who hit the paywall in their first
    ///   30 seconds dismiss at 95%; users who hit it after a 10-min flow
    ///   convert at 12%."
    func logPaywall(surface: String,
                    action: String,
                    sku: String? = nil,
                    priceUsd: Double? = nil,
                    triggeringFeature: String? = nil,
                    secondsSinceLastEvent: Int? = nil,
                    wasInIntroOffer: Bool? = nil) {
        var payload: [String: Any] = ["surface": surface, "action": action]
        if let sku { payload["sku"] = sku }
        if let priceUsd { payload["price_usd"] = priceUsd }
        if let triggeringFeature { payload["triggering_feature"] = triggeringFeature }
        if let secondsSinceLastEvent { payload["seconds_since_last_event"] = secondsSinceLastEvent }
        if let wasInIntroOffer { payload["was_in_intro_offer"] = wasInIntroOffer }
        recordEvent(eventType: "paywall",
                    screen: lastScreen,
                    detail: "\(surface)/\(action)",
                    payload: payload)
    }

    /// Wearable / HealthKit / OAuth integration attempt.
    /// `action` ∈ {attempt, success, failure, disconnect}.
    func logIntegration(provider: String, action: String, errorMessage: String? = nil) {
        var payload: [String: Any] = ["provider": provider, "action": action]
        if let errorMessage { payload["error"] = errorMessage }
        recordEvent(eventType: "integration",
                    screen: lastScreen,
                    detail: "\(provider)/\(action)",
                    payload: payload)
    }

    /// System permission prompt (notifications, HK, contacts, camera, ATT).
    func logPermission(kind: String, granted: Bool) {
        recordEvent(eventType: "permission",
                    screen: lastScreen,
                    detail: "\(kind)/\(granted ? "granted" : "denied")",
                    payload: ["kind": kind, "granted": granted])
    }

    /// Push notification received or opened.
    func logNotification(type: String, action: String) {
        recordEvent(eventType: "notification",
                    screen: lastScreen,
                    detail: "\(type)/\(action)",
                    payload: ["type": type, "action": action])
    }

    /// Background sync / silent push handled.
    func logBackgroundWork(reason: String, durationMs: Int? = nil, success: Bool = true) {
        var payload: [String: Any] = ["reason": reason, "success": success]
        if let durationMs { payload["duration_ms"] = durationMs }
        recordEvent(eventType: "background",
                    screen: nil,
                    detail: reason,
                    payload: payload)
    }

    /// Performance budget breach (op exceeded its target).
    func logPerformanceBreach(op: String, valueMs: Int, budgetMs: Int) {
        recordEvent(eventType: "performance",
                    screen: lastScreen,
                    detail: "\(op) breach (\(valueMs)ms > \(budgetMs)ms)",
                    payload: ["op": op, "value_ms": valueMs, "budget_ms": budgetMs])
    }

    // MARK: - Internal recording

    private func recordEvent(eventType: String,
                             screen: String?,
                             detail: String,
                             payload: [String: Any],
                             severity: String? = nil) {
        guard Self.isActive else { return }

        // `is_error` is denormalized on the server table for fast filtering
        // (`new_user_journey_events.is_error BOOLEAN NOT NULL DEFAULT FALSE`).
        // The server-side RPC historically computed this value itself, but a
        // three-valued-logic bug (`FALSE OR NULL = NULL` when severity was
        // omitted) was causing every flush to fail with a 23502 / not-null
        // violation, re-queueing the entire batch indefinitely. We now stamp
        // the flag client-side so the value is always a concrete bool by the
        // time the row reaches PostgreSQL — see migration
        // `20260823_nuj_is_error_default.sql`. Only the canonical error /
        // crash event types and explicitly-severe entries flag TRUE; every
        // other event (`screen`, `tap`, `funnel`, `state`, `api`, `workout`,
        // `meal`, `social`, `paywall`, `integration`, `permission`,
        // `notification`, `background`, `performance`) is FALSE.
        let isError = (eventType == "error" || eventType == "crash")
            || (severity == "error" || severity == "critical")

        var entry: [String: Any] = [
            "event_type": eventType,
            "session_id": sessionId,
            "occurred_at_ms": Int(Date().timeIntervalSince1970 * 1000),
            "payload": JSONSerialization.isValidJSONObject(payload) ? payload : [:],
            "is_error": isError
        ]
        if let screen { entry["screen"] = screen }
        entry["detail"] = detail
        if let severity { entry["severity"] = severity }

        pendingEvents.append(entry)
        bufferedEventCount = pendingEvents.count

        if pendingEvents.count >= maxEventsPerBatch {
            Task { await flush() }
        }
    }

    // MARK: - Session lifecycle (server-side rows)

    private func openSession() async {
        let bundle = Bundle.main.infoDictionary
        let params: [String: String?] = [
            "p_session_id":   sessionId,
            "p_app_version":  bundle?["CFBundleShortVersionString"] as? String,
            "p_build_number": bundle?["CFBundleVersion"] as? String,
            "p_device_model": Self.deviceModelIdentifier,
            "p_ios_version":  UIDevice.current.systemVersion,
            "p_network_type": lastNetworkType,
            "p_entry_screen": lastScreen
        ]
        do {
            try await SupabaseManager.shared.supabaseClient
                .rpc("record_new_user_session_start", params: params)
                .execute()
        } catch {
            AppLogger.debug("[NUJ] session open failed: \(error.localizedDescription)", category: .network)
        }
    }

    private func closeSession() async {
        struct Params: Encodable {
            let p_session_id: String
            let p_last_screen: String?
            let p_error_count: Int
            let p_crash_count: Int
            let p_screen_view_count: Int
            let p_tap_count: Int
        }
        let params = Params(
            p_session_id: sessionId,
            p_last_screen: lastScreen,
            p_error_count: sessionErrorCount,
            p_crash_count: sessionCrashCount,
            p_screen_view_count: sessionScreenViewCount,
            p_tap_count: sessionTapCount
        )
        do {
            try await SupabaseManager.shared.supabaseClient
                .rpc("record_new_user_session_end", params: params)
                .execute()
        } catch {
            AppLogger.debug("[NUJ] session close failed: \(error.localizedDescription)", category: .network)
        }
        sessionScreenViewCount = 0
        sessionTapCount = 0
        sessionErrorCount = 0
        sessionCrashCount = 0
    }

    // MARK: - Batched flush

    private func flush() async {
        guard !pendingEvents.isEmpty,
              SupabaseManager.shared.isAuthenticated else { return }

        let batch = pendingEvents
        pendingEvents = []
        bufferedEventCount = 0

        guard JSONSerialization.isValidJSONObject(batch) else {
            AppLogger.warning("[NUJ] batch not valid JSON; dropping \(batch.count) events", category: .performance)
            return
        }

        do {
            struct BatchParams: Encodable { let p_events: [JSONValue] }
            let jsonData = try JSONSerialization.data(withJSONObject: batch)
            let decoded = try JSONDecoder().decode([JSONValue].self, from: jsonData)
            try await SupabaseManager.shared.supabaseClient
                .rpc("record_new_user_events_batch", params: BatchParams(p_events: decoded))
                .execute()
        } catch {
            // Re-buffer on transient failure; drop the head if we drift too far.
            AppLogger.debug("[NUJ] flush failed: \(error.localizedDescription) — re-queueing", category: .network)
            pendingEvents.insert(contentsOf: batch, at: 0)
            if pendingEvents.count > maxEventsPerBatch * 4 {
                pendingEvents = Array(pendingEvents.suffix(maxEventsPerBatch * 2))
            }
            bufferedEventCount = pendingEvents.count
        }
    }

    // MARK: - Helpers

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let iso8601Frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Hardware identifier (e.g. "iPhone17,2"), more useful than UIDevice.model
    /// (which only returns "iPhone").
    private static var deviceModelIdentifier: String = {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        return mirror.children.reduce(into: "") { acc, ch in
            if let val = ch.value as? Int8, val != 0 {
                acc.append(String(UnicodeScalar(UInt8(val))))
            }
        }
    }()
}

// MARK: - JSON helper for typed Supabase RPC params

/// Supabase-Swift requires `Encodable` types for RPC params. JSONSerialization
/// produces `Any` which isn't `Encodable`; this minimal wrapper bridges the gap
/// without dragging in a full Codable model for every event shape.
private enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .int(let v):     try c.encode(v)
        case .double(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }
}
