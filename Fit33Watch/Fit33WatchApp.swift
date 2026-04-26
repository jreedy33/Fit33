//
//  Fit33WatchApp.swift
//  Fit33Watch (watchOS App)
//
//  Realtime Widget Server Pull — Phase 8a (2026-04-26).
//
//  Headless-style watchOS companion app whose ONLY job is to keep the
//  iPhone-side challenge widgets fresh by writing HealthKit progress
//  to Supabase from the wrist. The user never has to open this app for
//  it to do its job — we register HKObserverQuery + HKBackgroundDelivery
//  so watchOS wakes us in the background whenever new step / active-
//  energy samples land, and we POST `log_challenge_progress` directly
//  from the watch process.
//
//  Why a watch app at all (recap from PRODUCT_ENGINEER_AGENT.md):
//   - The iPhone home-screen widget can pull from Supabase every ~20m
//     (Phase 3) but it can ONLY display whatever the SERVER has. If
//     the user's phone has been silent for hours, the server has
//     stale data, the widget pulls stale data, and the user sees
//     stale data. The watch fills that gap by being the always-on
//     wrist-mounted writer that ships HK samples to Supabase the
//     moment they arrive.
//   - Apple Watch HealthKit observers fire MANY times per day on
//     "wake" cadence — the watch is the closest thing to "real-time"
//     fitness tracking iOS allows, and we lean on it as our 24h
//     freshness guarantee.
//
//  Optional install (PE invariant — phones-only path stays viable):
//   - The phone app DOES NOT require this watch companion to function.
//     Without it, the existing iPhone HKObserverQuery + foreground
//     refresh path is the only writer; widgets just lean harder on
//     "stale" indicators (Phase 6).
//   - When the user uninstalls the watch app, the phone simply stops
//     receiving WCSession config updates and falls back to its own
//     observers — no broken state, no forced re-authentication.

import SwiftUI
import WatchKit
import Combine
import OSLog

@main
struct Fit33WatchApp: App {
    /// Watch-side logger. AppLogger isn't available in this target
    /// (it lives in `Fit33/Logger.swift` and pulls in CoreData),
    /// so we use os.Logger directly. Surfaces in Console.app
    /// filtered to subsystem `com.fit33.app.watchapp`.
    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "lifecycle")

    /// Lifecycle owner — long-lived state lives here so the App
    /// struct's body re-runs don't churn observers.
    @StateObject private var lifecycle = WatchLifecycle()

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(lifecycle)
                .task {
                    Self.log.info("Fit33Watch foreground task — bootstrap")
                    await lifecycle.bootstrap()
                }
        }
    }
}

/// Owns watch-side singletons. We don't put them in `@main` because the
/// SwiftUI App struct gets initialized in odd contexts (e.g. previews,
/// background refresh) and we want to be explicit about "happens once
/// per process".
@MainActor
final class WatchLifecycle: ObservableObject {
    /// Status string driven from background observer activity. Surfaced
    /// in WatchContentView so the user can verify the app is doing its
    /// job without opening the app every day.
    @Published var lastSyncStatus: String = "Waiting for HealthKit…"
    @Published var lastSyncAt: Date?

    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "lifecycle")
    private var bootstrapDone = false

    func bootstrap() async {
        guard !bootstrapDone else { return }
        bootstrapDone = true

        // Start the WCSession listener FIRST so any incoming challenge
        // config from the phone has somewhere to land while we ask
        // for HK auth.
        WatchConnectivityBridge.shared.activate()

        // Then HealthKit. Auth request is no-op if already granted —
        // user is prompted exactly once.
        do {
            try await WatchHealthKitWriter.shared.requestAuthorization()
            await WatchHealthKitWriter.shared.start()
            lastSyncStatus = "Active — observing HealthKit"
            Self.log.info("HealthKit observers started")
        } catch {
            lastSyncStatus = "HealthKit auth denied"
            Self.log.error("HealthKit setup failed: \(error.localizedDescription, privacy: .public)")
        }

        // Schedule the first opportunistic background refresh so we're
        // re-entered even when no new HK samples land. Cadence is
        // self-rescheduled inside the handler.
        WatchBackgroundRefresh.scheduleNext()
    }

    /// Called from observer / WCSession callbacks to surface "we just
    /// did a thing" UX without piling up logs.
    func recordSync(message: String) {
        lastSyncAt = Date()
        lastSyncStatus = message
    }
}

/// Delegate adaptor handles the watchOS background-task lifecycle that
/// SwiftUI doesn't expose via `.backgroundTask` on every OS version.
/// Forwards `WKApplicationRefreshBackgroundTask` to
/// `WatchBackgroundRefresh.handle(_:)`.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "delegate")

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refresh as WKApplicationRefreshBackgroundTask:
                Self.log.info("Background refresh task fired")
                Task {
                    await WatchBackgroundRefresh.handle(refresh)
                }
            default:
                // Other background task types we don't subscribe to —
                // mark complete immediately so watchOS doesn't penalize
                // our background-time budget for them.
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
