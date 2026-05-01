//
//  SilentPushHandler.swift
//  Fit33
//
//  Routes incoming silent APNs pushes (aps.content-available = 1) to the
//  right subsystem. Currently handles:
//    • `challenge_wake` — `wake-challenge-opponents` edge function asking
//      this device to flush HealthKit / meal / hydration data so the
//      opponent sees fresh numbers.
//    • `strava_activity_new` — `strava-webhook` signaling a new Strava
//      activity for this user; we re-sync to update the recap card.
//    • `challenge_reaction` — visible-alert push that ALSO carries
//      `content-available: 1` so the home-screen Active Challenge widget
//      can paint the comic-book "Do better!" shout bubble before the
//      user opens the app. See `SmackTalkWidgetBridge`.
//
//  Silent pushes get ~30s of background execution time — we aim to finish
//  in under ~25s and call the iOS completion handler so the app doesn't
//  get throttled.
//
//  Created 2026-04-20 as part of the Challenge Background Refresh plan.
//

import UIKit

@MainActor
enum SilentPushHandler {

    /// Entry point called from `AppDelegate.application(_:didReceiveRemoteNotification:...)`.
    /// Routes on the top-level `type` key in the APNs payload.
    static func handle(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let type = (userInfo["type"] as? String) ?? ""

        // Diagnostic 2026-04-29 — surface ALL silent push wakes to the
        // session log so the bug-intel CMS / Console.app can confirm
        // iOS actually fired the content-available wake. If we get a
        // sent-status push in the queue but nothing logs here, iOS is
        // dropping the silent half (force-quit / BG refresh off /
        // content-available not in payload).
        SessionLogManager.shared.log(.info, category: .pushNotification, message: "🛎️ [SILENT PUSH] received", metadata: [
            "type": type,
            "app_state": "\(UIApplication.shared.applicationState.rawValue)",
            "challenge_id": (userInfo["challenge_id"] as? String) ?? "—"
        ])
        AppLogger.info("[SILENT PUSH] received type='\(type)' app_state=\(UIApplication.shared.applicationState.rawValue)", category: .network)

        // NUJ telemetry — silent push receipt is a key retention signal (every
        // wake = "the app reached out to this user"). No-op when user is past
        // their 72h window.
        NewUserJourneyTracker.shared.logNotification(
            type: "silent/\(type)",
            action: "received"
        )

        switch type {
        case "challenge_wake":
            handleChallengeWake(completion: completion)
        case "strava_activity_new":
            handleStravaActivityNew(userInfo: userInfo, completion: completion)
        case "challenge_reaction":
            handleChallengeReaction(userInfo: userInfo, completion: completion)
        default:
            AppLogger.debug("[SILENT PUSH] Ignoring unknown silent push type: '\(type)'", category: .network)
            completion(.noData)
        }
    }

    // MARK: - challenge_reaction
    //
    // Lands here because `send-push-notification` adds
    // `content-available: 1` to challenge_reaction APNs payloads
    // alongside the visible alert, so iOS wakes the app for ~30s
    // even when it's been suspended. Whole job: parse the smack
    // out of the push payload, write a single-slot
    // `WidgetSmackTalk` into the App Group so the home-screen
    // Active Challenge widget can yell it out of the icon, and
    // reload the widget timeline.
    //
    // Foreground guard: when the user is actively in the app
    // (`UIApplication.shared.applicationState == .active`), they
    // can already see the smack inside `ChallengeDetailView`'s
    // reaction feed — yelling at them through the widget on top
    // of that is redundant. We skip the App Group write in that
    // case; the foreground willPresent banner + in-app feed
    // carry the message instead.
    private static func handleChallengeReaction(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let challengeId = userInfo["challenge_id"] as? String,
              let emoji = userInfo["reaction_emoji"] as? String,
              let text = userInfo["reaction_text"] as? String else {
            AppLogger.debug("[SILENT PUSH] challenge_reaction missing required fields — skipping widget write", category: .social)
            completion(.noData)
            return
        }
        let category = (userInfo["reaction_category"] as? String) ?? "trash_talk"
        let senderFullName = (userInfo["from_user_name"] as? String) ?? "Someone"
        let senderFirstName = senderFullName
            .components(separatedBy: " ")
            .first
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Someone"

        // App Group lowercase contract — see
        // `ActiveChallengeWidgetBridge.publish` for the full rationale
        // (PostgREST returns lowercase UUIDs, `Foundation.UUID.uuidString`
        // returns uppercase; everything escaping into the App Group
        // container MUST be lowercased so the widget's match-by-id
        // lookup stays honest).
        let payload = SmackTalkWidgetBridge.WidgetSmackTalk(
            challengeId: challengeId.lowercased(),
            senderFirstName: senderFirstName,
            reactionEmoji: emoji,
            reactionText: text,
            reactionCategory: category,
            receivedAt: Date()
        )
        SmackTalkWidgetBridge.publish(payload, shouldWrite: {
            UIApplication.shared.applicationState != .active
        })
        completion(.newData)
    }

    // MARK: - strava_activity_new
    //
    // Pushed by the `strava-webhook` edge function when Strava reports a
    // new activity for this user. The payload carries `activity_id`
    // (the numeric Strava ID, as a string). We don't need to do the
    // network round-trip the webhook already did — we just refresh the
    // local Strava activity list so the dashboard recap card and the
    // notification carousel pick up the new row immediately.
    //
    // Budget: tight (~25s self-cap). We only do a 1-day Strava sync.
    private static func handleStravaActivityNew(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("[SILENT PUSH] strava_activity_new skipped — not authenticated", category: .network)
            completion(.noData)
            return
        }

        let activityId = (userInfo["activity_id"] as? String) ?? "?"
        AppLogger.info("[SILENT PUSH] strava_activity_new received (activity=\(activityId))", category: .network)
        let start = CFAbsoluteTimeGetCurrent()

        let workTask = Task { @MainActor in
            // Webhook signaled a brand-new activity — force-sync to bypass
            // the 5-minute throttle so the dashboard widget updates instantly.
            await StravaService.shared.syncActivities(daysBack: 1, force: true)
            UserManager.shared.updateStreak()
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            if !Task.isCancelled {
                AppLogger.warning("[SILENT PUSH] strava_activity_new timed out at 25s — cancelling", category: .network)
                workTask.cancel()
            }
        }

        Task { @MainActor in
            _ = await workTask.value
            timeoutTask.cancel()
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            AppLogger.info("[SILENT PUSH] strava_activity_new completed in \(elapsedMs)ms", category: .network)
            completion(workTask.isCancelled ? .failed : .newData)
        }
    }

    // MARK: - challenge_wake

    /// Pushed by the `wake-challenge-opponents` edge function. Our device
    /// reads the latest HealthKit data and logs it to the challenge progress
    /// tables (1v1 / group / private / community) so opponents see our most
    /// up-to-date numbers via realtime.
    ///
    /// **Lite path**: this handler ONLY runs the wake-essential subset of
    /// `BackgroundChallengeSyncService.performLiteWakeSync()` (HealthKit +
    /// active-challenge fetch + per-service sync). Strava / Fitbit / WHOOP /
    /// Oura / Readiness / meals / hydration / quest / intelligence work all
    /// stays on the foreground + BGAppRefresh + BGProcessing paths — none of
    /// them affect the opponent's view of step / active-energy / distance /
    /// calorie progress, and bundling them in here was the dominant cause
    /// of timeouts (and the ensuing iOS budget penalty) for users with
    /// multiple wearables connected.
    ///
    /// Self-cap: 15s. Lite path runs in ~3-7s in the field; 15s leaves
    /// generous headroom while staying well under iOS's ~30s ceiling. A
    /// timeout here is treated as `.failed` and counts against future
    /// silent-push budget — so we keep the timeout snug to surface real
    /// regressions early instead of masking them.
    private static func handleChallengeWake(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("[SILENT PUSH] challenge_wake skipped — not authenticated", category: .network)
            completion(.noData)
            return
        }

        let start = CFAbsoluteTimeGetCurrent()
        AppLogger.info("[SILENT PUSH] challenge_wake received — running lite wake sync...", category: .network)

        let workTask = Task { @MainActor in
            await BackgroundChallengeSyncService.shared.performLiteWakeSync()
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled {
                AppLogger.warning("[SILENT PUSH] challenge_wake timed out at 15s — cancelling lite path", category: .network)
                workTask.cancel()
            }
        }

        Task { @MainActor in
            _ = await workTask.value
            timeoutTask.cancel()

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            AppLogger.info("[SILENT PUSH] challenge_wake completed in \(elapsedMs)ms", category: .network)
            completion(workTask.isCancelled ? .failed : .newData)
        }
    }
}
