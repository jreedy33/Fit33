//
//  RefreshChallengeIntent.swift
//  RunningActivityWidget
//
//  Realtime Widget Server Pull — Phase 4a (2026-04-26).
//
//  Interactive AppIntent bound to the small refresh button in the
//  widget UI (Phase 4b replaces the swords emoji with a Button(intent:)).
//  Runs INSIDE the widget extension process so we can hit Supabase
//  without paying the cost of waking the main app.
//
//  Why `openAppWhenRun = false`:
//
//  iOS 17+ interactive widgets give us two distinct AppIntent flavors:
//   • `openAppWhenRun = true`  — tap launches the host app and the
//     intent runs there. Adds 1-3 seconds of cold-start UX before the
//     refresh actually happens AND yanks the user out of whatever home
//     screen flow they were in.
//   • `openAppWhenRun = false` — intent runs in the widget process,
//     widget reloads on its own, user stays put. Perfect for
//     "refresh this card" where there's nothing to navigate to.
//
//  Trade-off: the widget extension has ~30MB memory + ~30s runtime
//  budget per intent invocation. `WidgetSupabaseFetcher` is one
//  URLSession round-trip with a 5s timeout, well inside that envelope.
//

import AppIntents
import WidgetKit
import OSLog
import AudioToolbox
import Foundation

/// Tap target for the small refresh control on the active challenge
/// widget. Pulls fresh data from Supabase, writes the App Group, and
/// asks WidgetCenter to redraw THIS widget kind only (not the daily
/// goals widget which has its own refresh path).
struct RefreshChallengeIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh challenge"
    static var description: IntentDescription = IntentDescription("Pull the latest challenge progress from Fit33's servers.")
    /// Critical — `false` keeps execution inside the widget extension
    /// so the refresh feels instant. Setting this to `true` would
    /// launch the main app on every tap, which is the opposite of the
    /// "scroll past widget → tap → see fresh data" UX we're optimizing.
    static var openAppWhenRun: Bool = false
    /// We never surface this intent in the system Shortcuts app — it
    /// only makes sense as a widget tap target.
    static var isDiscoverable: Bool = false

    private static let log = Logger(subsystem: "com.fit33.app.RunningActivityWidget", category: "challenge-refresh-intent")

    /// User-tappable refresh budget. Per `PRODUCT_ENGINEER_AGENT.md`
    /// invariant 31 ("Throttle min 5s between fires"). We still always
    /// ask WidgetCenter to reload because that surfaces the spinner-
    /// stop UI feedback even when we throttle the network.
    private static let minPullInterval: TimeInterval = 5.0
    /// Tracked across intent invocations within the same widget process
    /// lifetime. iOS may kill the extension between taps which resets
    /// this — that's fine, the throttle is best-effort UX, not a
    /// correctness primitive.
    nonisolated(unsafe) private static var lastPullAt: Date?
    nonisolated(unsafe) private static let pullLock = NSLock()

    func perform() async throws -> some IntentResult {
        // Diagnostic logging trail (2026-04-27): logged at `.notice`
        // level so it shows up in Console without enabling debug
        // filtering, AND mirrored to App Group UserDefaults via
        // `WidgetTapLog` so the main app can read recent tap activity
        // even when the user can't easily attach Console. Pair this
        // with `WidgetTapLog.summary()` from the main app to surface
        // a "last 10 widget taps" debug card.
        let tapNumber = WidgetTapLog.recordTapReceived()
        Self.log.notice("🔔 [Widget tap #\(tapNumber, privacy: .public)] Refresh button pressed")

        // Immediate tactile confirmation that the tap registered. Fired
        // BEFORE any await so the haptic lands on the same frame the
        // user lifted their finger — waiting until after the network
        // pull would feel disconnected from the tap.
        Self.fireTapHaptic()

        // Capture environmental state up front — knowing which leg
        // failed is half the diagnostic battle (App Group missing →
        // entitlement bug; JWT missing → main-app refresh required;
        // both present + pull still failed → transport / 5xx).
        let env = WidgetTapLog.captureEnvironment()
        Self.log.notice("[Widget tap #\(tapNumber, privacy: .public)] env appGroup=\(env.appGroupAvailable, privacy: .public) hasJWT=\(env.hasJWT, privacy: .public) cachedChallenges=\(env.cachedChallengeCount, privacy: .public) lastWriteAge=\(env.lastWriteAgeDescription, privacy: .public)")

        // Short-circuit if the user is mashing the button — the
        // upstream throttle keeps us under PostgREST's connection
        // budget and prevents the App Group write loop from causing
        // the main app to thrash on Darwin notifications (Phase 5).
        let shouldPull = Self.claimPullSlot()
        if shouldPull {
            // 5s timeout (vs. the timeline path's 3s) — when the user
            // explicitly asked for fresh data we owe them a slightly
            // longer wait before falling back to cache. Still well
            // under iOS's per-intent runtime cap.
            //
            // Bug fix 2026-04-27: branch haptics + logs on the actual
            // pull outcome. The previous version always fired the
            // success haptic — including on JWT-expiry / transport
            // failure — so users got happy confirmation without any
            // data refresh. Now success/warning/error map to real
            // states the user can feel and (when investigating) read
            // in Console.app.
            Self.log.notice("[Widget tap #\(tapNumber, privacy: .public)] pull start (timeout=5s)")
            let pullStart = Date()
            let outcome = await ActiveChallengeProvider.pullAndMergeIfPossible(timeoutSeconds: 5.0)
            let pullMs = Int(Date().timeIntervalSince(pullStart) * 1000)

            switch outcome {
            case .fetched(let wroteFreshData):
                if wroteFreshData {
                    Self.log.notice("✅ [Widget tap #\(tapNumber, privacy: .public)] pull OK in \(pullMs, privacy: .public)ms — fresh bytes written, widget will update")
                    WidgetTapLog.recordOutcome(tapNumber: tapNumber, outcome: .successFresh, durationMs: pullMs, error: nil)
                    Self.fireSuccessHaptic()
                } else {
                    // Pull succeeded but the bytes matched what the
                    // App Group already had (no opponent activity
                    // since the last tick, etc.). Still a successful
                    // refresh — just nothing to celebrate.
                    Self.log.notice("✅ [Widget tap #\(tapNumber, privacy: .public)] pull OK in \(pullMs, privacy: .public)ms — bytes unchanged (no new data on server)")
                    WidgetTapLog.recordOutcome(tapNumber: tapNumber, outcome: .successUnchanged, durationMs: pullMs, error: nil)
                    Self.fireSuccessHaptic()
                }
            case .skippedNoAuth:
                Self.log.warning("⚠️ [Widget tap #\(tapNumber, privacy: .public)] pull skipped in \(pullMs, privacy: .public)ms — JWT expired (foreground main app to refresh)")
                WidgetTapLog.recordOutcome(tapNumber: tapNumber, outcome: .skippedNoAuth, durationMs: pullMs, error: nil)
                Self.fireThrottledHaptic()
            case .skippedNoAppGroup:
                Self.log.error("❌ [Widget tap #\(tapNumber, privacy: .public)] pull skipped — App Group unavailable (entitlement bug)")
                WidgetTapLog.recordOutcome(tapNumber: tapNumber, outcome: .skippedNoAppGroup, durationMs: pullMs, error: nil)
                Self.fireErrorHaptic()
            case .failed(let error):
                Self.log.error("❌ [Widget tap #\(tapNumber, privacy: .public)] pull failed in \(pullMs, privacy: .public)ms — \(String(describing: error), privacy: .public)")
                WidgetTapLog.recordOutcome(tapNumber: tapNumber, outcome: .failed, durationMs: pullMs, error: String(describing: error))
                Self.fireErrorHaptic()
            }
        } else {
            // Bumped from .debug → .notice so we can see throttle
            // events in Console without enabling debug filtering.
            Self.log.notice("⏱️ [Widget tap #\(tapNumber, privacy: .public)] throttled (< \(Self.minPullInterval, privacy: .public)s since last pull)")
            WidgetTapLog.recordOutcome(tapNumber: tapNumber, outcome: .throttled, durationMs: 0, error: nil)
            Self.fireThrottledHaptic()
        }

        // Always reload — gives the user a visible "tap registered"
        // beat even when the network call was a no-op. We scope the
        // reload to JUST our widget kind so the daily goals widget
        // doesn't get caught in the splash damage.
        Self.log.notice("🔄 [Widget tap #\(tapNumber, privacy: .public)] reloadTimelines(ofKind: ActiveChallengeWidget)")
        WidgetCenter.shared.reloadTimelines(ofKind: "ActiveChallengeWidget")
        return .result()
    }

    // MARK: - Haptics
    //
    // Bug fix 2026-04-27: switched off `UIImpactFeedbackGenerator` /
    // `UINotificationFeedbackGenerator` because those APIs silently
    // drop their haptic in widget extension processes — they require
    // full audio-session access that the extension sandbox doesn't
    // grant. The community-standard workaround is
    // `AudioServicesPlaySystemSound` with the four reserved haptic
    // sound IDs (1519/1520/1521), which routes through the system
    // audio service and DOES fire the Taptic engine from extensions.
    //   • 1519 — peek (light, single tap)
    //   • 1520 — pop (medium, single thump)
    //   • 1521 — cancelled (three quick pulses, "warning")
    // No `@MainActor` hop required — `AudioServicesPlaySystemSound` is
    // safe from any thread, unlike UIKit's feedback generators which
    // had to be initialized on main.

    /// Light tap on button press — confirms the intent fired even when
    /// the rest of the perform chain (network, etc.) is still running.
    private static func fireTapHaptic() {
        AudioServicesPlaySystemSound(1519)
    }

    /// Medium "pop" on a successful refresh — fresh bytes landed OR
    /// a successful pull confirmed nothing changed.
    private static func fireSuccessHaptic() {
        AudioServicesPlaySystemSound(1520)
    }

    /// Triple-pulse "cancelled" cue when the user mashed the button
    /// inside `minPullInterval` OR the JWT is expired (transient auth
    /// state — recovers the next time the main app foregrounds). Distinct
    /// from `fireErrorHaptic` so users can feel "I heard you, nothing to
    /// do right now" vs. "something is broken".
    private static func fireThrottledHaptic() {
        AudioServicesPlaySystemSound(1521)
    }

    /// Same triple-pulse pattern as throttled — iOS only exposes three
    /// reserved haptic sound IDs to extensions, so we reuse 1521 for
    /// genuine failures (App Group config bug, transport failure, 5xx,
    /// decode error). The accompanying `error`-level log line in
    /// Console differentiates the two for postmortem.
    private static func fireErrorHaptic() {
        AudioServicesPlaySystemSound(1521)
    }

    /// Returns `true` if the caller is free to do a network pull, or
    /// `false` if a pull happened too recently. Updates the timestamp
    /// only on `true`.
    private static func claimPullSlot() -> Bool {
        pullLock.lock(); defer { pullLock.unlock() }
        let now = Date()
        if let last = lastPullAt, now.timeIntervalSince(last) < minPullInterval {
            return false
        }
        lastPullAt = now
        return true
    }
}

// MARK: - Tap diagnostics
//
// Persistent tap trail mirrored to App Group `UserDefaults` so we can
// confirm widget refresh button behavior even when Console.app isn't
// readily attached (the most common reason "no haptic, no update"
// reports come in without supporting evidence).
//
// Storage layout (App Group `group.com.fit33.app`):
//   • `fit33.widget.refresh.tapCount`    — Int, monotonic all-time tap counter
//   • `fit33.widget.refresh.lastTapAt`   — Date, most recent tap timestamp
//   • `fit33.widget.refresh.lastOutcome` — String, raw outcome code
//   • `fit33.widget.refresh.lastDurationMs` — Int, network duration of last pull
//   • `fit33.widget.refresh.lastError`   — String?, error description if any
//   • `fit33.widget.refresh.recentEvents` — JSON-encoded `[Event]`, ring buffer
//     of the last 10 taps so a future debug surface can render a timeline.
//
// All writes are best-effort — if the App Group is unavailable we log
// to OSLog and silently no-op. We never let logging failures bubble up
// and break the actual refresh flow.
enum WidgetTapLog {
    private static let appGroupID = "group.com.fit33.app"
    private static let log = Logger(subsystem: "com.fit33.app.RunningActivityWidget", category: "widget-tap-log")

    private static let tapCountKey = "fit33.widget.refresh.tapCount"
    private static let lastTapAtKey = "fit33.widget.refresh.lastTapAt"
    private static let lastOutcomeKey = "fit33.widget.refresh.lastOutcome"
    private static let lastDurationMsKey = "fit33.widget.refresh.lastDurationMs"
    private static let lastErrorKey = "fit33.widget.refresh.lastError"
    private static let recentEventsKey = "fit33.widget.refresh.recentEvents"
    /// Cap the ring buffer at 10 — small enough to render in a debug
    /// card, large enough to spot patterns ("3 throttles in a row →
    /// user is mashing", "5 noAuth in a row → JWT refresh broken").
    private static let recentEventsMax = 10

    /// Outcome shape — kept stringly-typed in the on-disk JSON so
    /// adding a new case in a future build doesn't break decode of
    /// older payloads written to the App Group.
    enum Outcome: String, Codable {
        case tapReceived       // Logged at the moment the intent fires; no pull yet
        case successFresh      // Pull OK, fresh bytes written
        case successUnchanged  // Pull OK, but bytes matched cache
        case throttled         // Inside `minPullInterval` window
        case skippedNoAuth     // JWT expired
        case skippedNoAppGroup // App Group entitlement bug
        case failed            // Transport / 5xx / decode
    }

    /// One row in the persistent tap trail. Decoded by the main app's
    /// debug surfaces (when wired up) to render a recent-history list.
    struct Event: Codable {
        let tapNumber: Int
        let timestamp: Date
        let outcome: String
        let durationMs: Int?
        let error: String?
    }

    /// Snapshot of the widget's environment at tap time — what's in
    /// the App Group, whether the cached JWT looks valid, age of the
    /// last successful App Group write. Logged at every tap so when
    /// the user reports "no update" we can immediately tell whether
    /// the widget process even has the inputs it needs to refresh.
    struct EnvironmentSnapshot {
        let appGroupAvailable: Bool
        let hasJWT: Bool
        let cachedChallengeCount: Int
        let lastWriteAt: Date?

        var lastWriteAgeDescription: String {
            guard let lastWriteAt else { return "never" }
            let secs = Int(Date().timeIntervalSince(lastWriteAt))
            if secs < 60 { return "\(secs)s" }
            if secs < 3600 { return "\(secs / 60)m" }
            if secs < 86400 { return "\(secs / 3600)h" }
            return "\(secs / 86400)d"
        }
    }

    /// Increments the all-time tap counter, stamps `lastTapAt`, and
    /// appends a `tapReceived` event to the ring buffer. Returns the
    /// new tap number so the caller can correlate log lines.
    @discardableResult
    static func recordTapReceived() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            log.error("Tap log: App Group unavailable — counter will not advance")
            return -1
        }
        let next = defaults.integer(forKey: tapCountKey) + 1
        defaults.set(next, forKey: tapCountKey)
        defaults.set(Date(), forKey: lastTapAtKey)
        defaults.set(Outcome.tapReceived.rawValue, forKey: lastOutcomeKey)
        defaults.removeObject(forKey: lastErrorKey)
        appendEvent(Event(
            tapNumber: next,
            timestamp: Date(),
            outcome: Outcome.tapReceived.rawValue,
            durationMs: nil,
            error: nil
        ), defaults: defaults)
        return next
    }

    /// Stamps the final outcome of a tap (called after the pull /
    /// throttle decision). Updates the "last" fields AND appends a
    /// second ring-buffer event so the trail captures both the moment
    /// of receipt and the moment of resolution.
    static func recordOutcome(tapNumber: Int, outcome: Outcome, durationMs: Int, error: String?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            log.error("Tap log #\(tapNumber): App Group unavailable — outcome will not be recorded")
            return
        }
        defaults.set(outcome.rawValue, forKey: lastOutcomeKey)
        defaults.set(durationMs, forKey: lastDurationMsKey)
        if let error {
            defaults.set(error, forKey: lastErrorKey)
        } else {
            defaults.removeObject(forKey: lastErrorKey)
        }
        appendEvent(Event(
            tapNumber: tapNumber,
            timestamp: Date(),
            outcome: outcome.rawValue,
            durationMs: durationMs,
            error: error
        ), defaults: defaults)
    }

    /// Reads the current widget-process environment so the intent can
    /// log it on every tap. Pure inspection — no writes here.
    static func captureEnvironment() -> EnvironmentSnapshot {
        let defaults = UserDefaults(suiteName: appGroupID)
        let appGroupAvailable = defaults != nil
        // JWT presence proxy: the main-app Supabase SDK parks the
        // session blob at this exact key (see
        // `WidgetSessionStorage.userDefaultsKey` in the fetcher).
        // Cheap "is the blob there" check — actual expiry detection
        // happens inside the fetcher when it tries to use the token.
        let hasJWT = (defaults?.data(forKey: "supabase.session.fit33.supabase.session.v1") != nil)
        let cachedChallengeCount: Int = {
            guard let defaults,
                  let data = defaults.data(forKey: "fit33.widget.activeChallenges.list.v1"),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
                return 0
            }
            return list.count
        }()
        let lastWriteAt = defaults?.object(forKey: "fit33.widget.activeChallenge.updatedAt") as? Date
        return EnvironmentSnapshot(
            appGroupAvailable: appGroupAvailable,
            hasJWT: hasJWT,
            cachedChallengeCount: cachedChallengeCount,
            lastWriteAt: lastWriteAt
        )
    }

    /// Appends a single event to the persistent ring buffer, trimming
    /// the head so we never keep more than `recentEventsMax` rows.
    /// JSON-encoded so a future main-app surface can decode without
    /// linking the widget extension target.
    private static func appendEvent(_ event: Event, defaults: UserDefaults) {
        var events: [Event] = []
        if let data = defaults.data(forKey: recentEventsKey),
           let decoded = try? JSONDecoder().decode([Event].self, from: data) {
            events = decoded
        }
        events.append(event)
        if events.count > recentEventsMax {
            events.removeFirst(events.count - recentEventsMax)
        }
        if let encoded = try? JSONEncoder().encode(events) {
            defaults.set(encoded, forKey: recentEventsKey)
        }
    }
}
