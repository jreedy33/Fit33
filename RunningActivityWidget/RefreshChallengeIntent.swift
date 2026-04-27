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
import UIKit

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
        // Immediate tactile confirmation that the tap registered. Fired
        // BEFORE any await so the haptic lands on the same frame the
        // user lifted their finger — waiting until after the network
        // pull would feel disconnected from the tap. Medium impact
        // mirrors the in-app `HapticManager.impact(.medium)` used for
        // primary action buttons.
        await Self.fireTapHaptic()

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
            let outcome = await ActiveChallengeProvider.pullAndMergeIfPossible(timeoutSeconds: 5.0)
            switch outcome {
            case .fetched(let wroteFreshData):
                if wroteFreshData {
                    Self.log.info("Refresh intent: pulled fresh data — widget will update")
                    await Self.fireSuccessHaptic()
                } else {
                    // Pull succeeded but the bytes matched what the
                    // App Group already had (no opponent activity
                    // since the last tick, etc.). Still a successful
                    // refresh — just nothing to celebrate.
                    Self.log.info("Refresh intent: pulled, no changes since last tick")
                    await Self.fireSuccessHaptic()
                }
            case .skippedNoAuth:
                Self.log.warning("Refresh intent: JWT expired — main app must foreground to refresh")
                await Self.fireThrottledHaptic()
            case .skippedNoAppGroup:
                Self.log.error("Refresh intent: App Group unavailable — entitlement misconfigured")
                await Self.fireErrorHaptic()
            case .failed(let error):
                Self.log.error("Refresh intent: pull failed — \(String(describing: error), privacy: .public)")
                await Self.fireErrorHaptic()
            }
        } else {
            Self.log.debug("Refresh intent: throttled (last pull < \(Self.minPullInterval, privacy: .public)s ago)")
            await Self.fireThrottledHaptic()
        }

        // Always reload — gives the user a visible "tap registered"
        // beat even when the network call was a no-op. We scope the
        // reload to JUST our widget kind so the daily goals widget
        // doesn't get caught in the splash damage.
        WidgetCenter.shared.reloadTimelines(ofKind: "ActiveChallengeWidget")
        return .result()
    }

    // MARK: - Haptics
    //
    // The widget extension links UIKit on iOS, so the standard
    // UIImpactFeedbackGenerator / UINotificationFeedbackGenerator APIs
    // work here the same way they do in the main app. Generators must
    // be created and fired on the main thread; `@MainActor` hops handle
    // that. We allocate fresh generators each time rather than keeping
    // a static one alive — extension memory budget is tight (~30MB)
    // and keeping a feedback generator warm across intent invocations
    // doesn't measurably reduce latency for a once-per-tap impact.

    @MainActor
    private static func fireTapHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    @MainActor
    private static func fireSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Soft warning haptic when the user mashed the button inside the
    /// `minPullInterval` window OR when the JWT is expired (transient
    /// auth state, recovers next time the main app foregrounds).
    /// Less assertive than `.error`; communicates "I heard you, just
    /// nothing to do right now."
    @MainActor
    private static func fireThrottledHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Hard error haptic for genuine failures — App Group config bug,
    /// transport failure, decode error, 5xx. Distinguishes "real
    /// failure that should be investigated" from the soft warning
    /// case (throttled / auth expired). Pairs with an `error`-level
    /// log line so the underlying cause shows up in Console.app.
    @MainActor
    private static func fireErrorHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
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
