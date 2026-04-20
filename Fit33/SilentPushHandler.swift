//
//  SilentPushHandler.swift
//  Fit33
//
//  Routes incoming silent APNs pushes (aps.content-available = 1) to the
//  right subsystem. Today we only handle `type: "challenge_wake"`, which
//  arrives via the `wake-challenge-opponents` edge function and asks our
//  app to read the latest HealthKit / meal / hydration data and push it
//  to Supabase so opponents see fresh numbers.
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

        switch type {
        case "challenge_wake":
            handleChallengeWake(completion: completion)
        default:
            AppLogger.debug("[SILENT PUSH] Ignoring unknown silent push type: '\(type)'", category: .network)
            completion(.noData)
        }
    }

    // MARK: - challenge_wake

    /// Pushed by the `wake-challenge-opponents` edge function. Our device
    /// reads the latest HealthKit data, logs it to the appropriate challenge
    /// progress tables (1v1 / group / private / community), and also retries
    /// meal / hydration syncs — so opponents see our most up-to-date numbers
    /// as close to realtime as iOS allows.
    private static func handleChallengeWake(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("[SILENT PUSH] challenge_wake skipped — not authenticated", category: .network)
            completion(.noData)
            return
        }

        let start = CFAbsoluteTimeGetCurrent()
        AppLogger.info("[SILENT PUSH] challenge_wake received — syncing...", category: .network)

        // Budget: iOS gives us ~30s. We self-cap at 25s so we always
        // manage to call `completion(_:)` before the system force-ends us
        // (which would count against our future background delivery budget).
        let workTask = Task { @MainActor in
            await BackgroundChallengeSyncService.shared.performChallengeSyncInBackground()
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            if !Task.isCancelled {
                AppLogger.warning("[SILENT PUSH] challenge_wake timed out at 25s — cancelling", category: .network)
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
