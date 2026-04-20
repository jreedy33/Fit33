//
//  ChallengeOpponentWakeService.swift
//  Fit33
//
//  Client side of the silent-push opponent-wake system. Invokes the
//  `wake-challenge-opponents` edge function so our opponents' devices get
//  a content-available: 1 push and sync their HealthKit / meal / hydration
//  data to Supabase — meaning we see fresh numbers as close to realtime as
//  iOS allows.
//
//  Triggered from three places:
//    1. Fit33App.swift scenePhase `.active`      (user opens app)
//    2. BackgroundChallengeSyncService            (our own BG sync finished)
//    3. Challenge detail views                    (optional future addition)
//
//  Server-side throttle: 15 min per recipient (via silent_push_wake_log).
//  Device-side debounce: 60s, so scenePhase toggles or rapid back-and-forth
//  between views don't fire the function repeatedly.
//
//  Created 2026-04-20 as part of the Challenge Background Refresh plan.
//

import Foundation
import Supabase

/// Trigger reason for a wake request. Matches the
/// `silent_push_wake_log.triggered_by` CHECK constraint.
enum ChallengeWakeTrigger: String {
    case foreground
    case backgroundSync = "background_sync"
}

actor ChallengeOpponentWakeService {
    static let shared = ChallengeOpponentWakeService()

    /// Device-side debounce — the server also throttles per recipient, but
    /// we don't want to spam the function with identical invocations from
    /// scenePhase flapping or a user rapidly navigating.
    private let deviceDebounceInterval: TimeInterval = 60

    private var lastRequestAt: Date?

    private init() {}

    /// Fire-and-forget silent-push wake. Safe to call from anywhere on any
    /// thread; all network work is isolated to this actor. Failures are
    /// logged and swallowed.
    func requestWake(trigger: ChallengeWakeTrigger) async {
        // Auth guard — no point invoking the function without a session
        let isAuthenticated = await MainActor.run { SupabaseManager.shared.isAuthenticated }
        guard isAuthenticated else {
            AppLogger.debug("[OPPONENT WAKE] Skipping — not authenticated", category: .social)
            return
        }

        // Device debounce
        if let last = lastRequestAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < deviceDebounceInterval {
                AppLogger.debug("[OPPONENT WAKE] Skipping — last request \(Int(elapsed))s ago (device debounce)", category: .social)
                return
            }
        }

        // Only call the edge function when the user actually has active
        // challenges — otherwise we're burning a function invocation for
        // nothing.
        let hasChallenges = await MainActor.run { () -> Bool in
            let a = ChallengeService.shared.activeChallenges.count
            let g = ChallengeService.shared.activeGroupChallenges.count
            let p = PrivateChallengeService.shared.myChallenges.count
            return (a + g + p) > 0
        }
        guard hasChallenges else {
            AppLogger.debug("[OPPONENT WAKE] Skipping — no active challenges", category: .social)
            return
        }

        lastRequestAt = Date()

        let start = CFAbsoluteTimeGetCurrent()
        do {
            struct WakeResponse: Decodable {
                let sent: Int?
                let throttled: Int?
                let candidates: Int?
                let eligible: Int?
                let apns_failed: Int?
                let message: String?
            }

            let response: WakeResponse = try await SupabaseManager.shared.supabaseClient
                .functions
                .invoke(
                    "wake-challenge-opponents",
                    options: FunctionInvokeOptions(
                        body: ["source": trigger.rawValue]
                    )
                )

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            AppLogger.info(
                "[OPPONENT WAKE] \(trigger.rawValue) completed in \(elapsedMs)ms — sent=\(response.sent ?? 0) throttled=\(response.throttled ?? 0) eligible=\(response.eligible ?? 0)",
                category: .social
            )
        } catch {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            // Fire-and-forget — downgrade to warning so a flaky network
            // doesn't flood the error log. Background refresh degrades
            // gracefully to BGTask + HK observers.
            AppLogger.warning(
                "[OPPONENT WAKE] \(trigger.rawValue) failed after \(elapsedMs)ms: \(error.localizedDescription)",
                category: .social
            )
        }
    }
}
