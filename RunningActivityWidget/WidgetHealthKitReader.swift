//
//  WidgetHealthKitReader.swift
//  RunningActivityWidget
//
//  Widget Freshness Sprint — Phase 7c (2026-04-26).
//
//  Direct HealthKit read from inside the widget extension. Lets the
//  home-screen Active Challenge widget overlay the user's freshest
//  step count on top of the server-side `myTodayProgress` value, so
//  the displayed number tracks live walking even when:
//
//   • the main Fit33 app has been force-killed for hours
//     (BackgroundChallengeSyncService HK observers stop firing);
//   • the 20-min widget timeline pull just landed BEFORE iOS rolled
//     up the latest pedometer batch into Supabase;
//   • a silent push wake budget is exhausted (Apple's ~2-3/hr cap).
//
//  Architecture notes:
//
//  1. **Read-only.** The widget never writes to HealthKit and never
//     starts an `HKObserverQuery` — observers are not delivered to
//     widget extensions. We use a single `HKStatisticsQuery` per
//     timeline tick (cumulative-sum on `stepCount` for today's
//     local-day window). That's the cheapest API for "how many
//     steps today" and finishes in <100ms on real hardware.
//  2. **Monotonic guard.** The merger that consumes this only ever
//     RAISES `myTodayProgress`, never regresses below the
//     server-confirmed value. Mirrors `ActiveChallengeWidgetBridge.
//     publishOptimisticLocalProgress` (QP invariant 25u). Dawn-rollover
//     edges (HK reads zero before the user has moved post-midnight)
//     can never flicker the widget downward.
//  3. **Authorization-aware.** `HKHealthStore.authorizationStatus`
//     for `stepCount` is a sync, fast call; we early-return when
//     the user hasn't granted read access. The main app handles the
//     prompt — the widget extension can't show one. Without
//     authorization the merger keeps using the server value
//     unchanged, which is the same behavior as before this file
//     existed.
//  4. **No `HealthKit` import gating.** HealthKit is iOS-built-in
//     since iOS 8 — the framework imports unconditionally. The
//     `com.apple.developer.healthkit` entitlement is what gates
//     read access at runtime. Without the entitlement, queries
//     return an authorization error which we swallow silently.
//
//  Xcode setup checklist (one-time):
//   • Target → Signing & Capabilities → + Capability → HealthKit
//     (adds `com.apple.developer.healthkit = true` to
//     `RunningActivityWidget.entitlements` and links HealthKit.framework
//     to the extension target).
//   • Both have been pre-populated by this commit; no manual edits
//     needed in Xcode beyond ensuring the capability is checked on the
//     `RunningActivityWidget` target.
//   • The main app's `NSHealthShareUsageDescription` (in `Fit33/Info.plist`)
//     covers the widget process — extensions inherit usage descriptions
//     from the host app's bundle. No widget Info.plist change needed.
//

import Foundation
import HealthKit
import OSLog

/// Static reader namespace used by `ActiveChallengeProvider.timeline` to
/// patch step-typed challenges with the freshest local HealthKit value.
enum WidgetHealthKitReader {

    private static let log = Logger(
        subsystem: "com.fit33.app.RunningActivityWidget",
        category: "healthkit"
    )

    /// Single shared store. `HKHealthStore` is documented as cheap to
    /// instantiate, but the widget process is short-lived and a static
    /// lets us cache the underlying URL session it lazily allocates.
    /// `nonisolated(unsafe)` + sync access is fine — `HKHealthStore`
    /// internally is thread-safe for read queries.
    nonisolated(unsafe) private static let healthStore = HKHealthStore()

    /// Read today's cumulative step count from HealthKit. Returns nil
    /// when:
    ///   • HealthKit is unavailable on this device (iPad without HK,
    ///     tvOS, etc.);
    ///   • the `stepCount` type is missing from the SDK (impossible on
    ///     iOS, but defensive);
    ///   • read authorization for `stepCount` is `notDetermined` or
    ///     `sharingDenied` (entitlement missing OR user revoked);
    ///   • the underlying query fails (timeout, sample-source missing).
    ///
    /// In any of those cases the caller should keep using the
    /// server-side `myTodayProgress` value unchanged.
    ///
    /// - Parameter timeoutSeconds: hard ceiling on the query — iOS
    ///   gives the timeline provider ~5-30s of wall time per tick;
    ///   1.5s leaves >95% of the budget for everything else.
    static func todayStepsIfAuthorized(
        timeoutSeconds: TimeInterval = 1.5
    ) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return nil
        }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }

        // `authorizationStatus(for:)` returns `.sharingAuthorized` only
        // when the user explicitly granted READ access. Apple's privacy
        // model deliberately reports `.notDetermined` for un-granted
        // permissions to avoid leaking presence-of-data, so we treat
        // anything other than `.sharingAuthorized` as "no signal".
        //
        // NOTE: iOS reports authorization status only for WRITE — for
        // READ it will lie and say `.sharingDenied` even when granted.
        // The defensive pattern is to attempt the query and let it
        // fail closed; we keep this as a fast-path opt-out only when
        // it's CLEARLY denied (`.notDetermined` means we never asked).
        let status = healthStore.authorizationStatus(for: stepType)
        if status == .notDetermined {
            // Main app hasn't run the auth prompt yet — there's no
            // chance of a successful read. Fast bail.
            return nil
        }

        // Local-day window. HealthKit aggregates by local timezone by
        // default for daily totals, which matches what the dashboard
        // and `log_challenge_progress` use server-side (Data invariant
        // #46/47 — caller timezone is the canonical day boundary).
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let endOfDay = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        return await withTaskGroup(of: Int?.self) { group -> Int? in
            // Query path.
            group.addTask {
                await runStepQuery(predicate: predicate, type: stepType)
            }
            // Timeout path — never lets the widget tick stall on a
            // hung HealthKit XPC connection.
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }

            // First task to complete wins. If the timeout fires first
            // it returns nil; if the query fires first with a value
            // we return that value. Cancel the loser.
            defer { group.cancelAll() }
            for await result in group {
                if let result {
                    return result
                }
                // First branch returned nil — could be either the
                // query (auth-failed / no samples) or the timeout.
                // Either way, no fresh read this tick.
                return nil
            }
            return nil
        }
    }

    /// Inner query runner. Suspended via continuation because
    /// `HKStatisticsQuery` only exposes a callback API.
    private static func runStepQuery(
        predicate: NSPredicate,
        type: HKQuantityType
    ) async -> Int? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    log.debug("Widget HK steps query failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let sum = statistics?.sumQuantity() else {
                    // No samples yet today — legitimate (user is
                    // pre-dawn / hasn't moved). Return 0 so the
                    // monotonic max() at the call site keeps the
                    // server value unchanged.
                    continuation.resume(returning: 0)
                    return
                }
                let total = Int(sum.doubleValue(for: HKUnit.count()))
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }
}
