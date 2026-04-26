//
//  WatchBackgroundRefresh.swift
//  Fit33Watch
//
//  Realtime Widget Server Pull — Phase 8d (2026-04-26).
//
//  watchOS background-task scheduling. HKObserverQuery is the primary
//  wake source — but observers don't fire on bone-dry days (user
//  takes off the watch, watch is dead, simulator). Background refresh
//  gives us a belt-and-suspenders heartbeat: a low-frequency
//  `WKApplicationRefreshBackgroundTask` that we self-reschedule on
//  every fire, so even on a quiet day the watch wakes once per
//  preferred-window and re-attempts a Supabase write of the current
//  HealthKit totals.
//
//  Cadence:
//    Schedule the next task `60 minutes` from now. iOS may delay
//    it (battery, low-power mode, deferred to bundling); we accept
//    that latency since the observer path is the one that drives
//    "live" cadence and this is purely fallback.
//
//  Budget discipline:
//    We finish each task within 4–5 seconds — even with the 30-second
//    watchOS hard ceiling, finishing fast preserves our future
//    background-refresh budget allocation.

import Foundation
import HealthKit
import WatchKit
import os

enum WatchBackgroundRefresh {
    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "background-refresh")

    /// Schedule the next background refresh. Idempotent — calling
    /// multiple times before the previous task fires REPLACES the
    /// previously scheduled wake (matches WatchKit's documented
    /// semantics for `scheduleBackgroundRefresh`).
    static func scheduleNext() {
        let preferredDate = Date().addingTimeInterval(60 * 60) // ~1 hour
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error = error {
                log.error("scheduleBackgroundRefresh failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("scheduled background refresh at \(preferredDate)")
            }
        }
    }

    /// Handle a delivered `WKApplicationRefreshBackgroundTask`. Caller
    /// (`WatchAppDelegate.handle(_:)`) is responsible for routing here
    /// and we MUST call `setTaskCompletedWithSnapshot(_:)` before we
    /// return — otherwise watchOS thinks we're hung and revokes
    /// future budget.
    @MainActor
    static func handle(_ task: WKApplicationRefreshBackgroundTask) async {
        log.info("Background refresh handler entered")
        // Re-arm IMMEDIATELY so we don't accidentally drop the heartbeat
        // if the body below throws.
        scheduleNext()

        // Pump each registered HK family through the writer so a quiet
        // day still ships today's totals to Supabase. We bypass the
        // observer debounce — background refreshes only fire hourly,
        // so coalescing would be pointless.
        let pairs: [(HKQuantityType, String)] = [
            (HKQuantityType(.stepCount), "steps"),
            (HKQuantityType(.activeEnergyBurned), "calories"),
            (HKQuantityType(.appleExerciseTime), "active_minutes")
        ]
        for (type, family) in pairs {
            await WatchHealthKitWriter.shared.flush(family: family, hkType: type)
        }

        task.setTaskCompletedWithSnapshot(false)
        log.info("Background refresh handler completed")
    }
}
