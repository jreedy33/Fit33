//
//  WatchConnectivityBridge.swift
//  Fit33Watch
//
//  Realtime Widget Server Pull — Phase 8e (2026-04-26).
//
//  WCSession listener for "what challenges should I be writing to?"
//  config sync from the iPhone. The phone is the source of truth for
//  the user's active challenge list (it owns ChallengeService); the
//  watch needs that list to know which challenge IDs to log against
//  when HealthKit fires.
//
//  Wire format (mirror this in `Fit33/PhoneToWatchSyncBridge.swift`
//  on the iPhone side — task #wcsession-phone in Phase 8e):
//
//      {
//        "v": 1,
//        "challenges": [
//          { "id": "<uuid>", "type": "steps" },
//          { "id": "<uuid>", "type": "calories" },
//          ...
//        ]
//      }
//
//  Persistence:
//    The most recent applicationContext is mirrored into App Group
//    `UserDefaults` so background-launched watch processes (no
//    foreground UI yet, no in-memory state) can still read the
//    challenge list synchronously inside the HK observer callback.
//
//  Failure mode:
//    If WCSession isn't supported (no paired iPhone yet, or the
//    iPhone Fit33 build is older than this sprint), we hold the empty
//    list. The watch HK observer fires, finds no challenges, and
//    silently no-ops. That's the correct degradation — the iPhone
//    HK observer path remains the writer of last resort.

import Foundation
import WatchConnectivity
import OSLog

/// Sendable shape of the per-challenge config the phone sends down.
struct WatchChallengeConfig: Codable, Equatable, Sendable {
    /// UUID string of the challenge (1v1 / group).
    let id: String
    /// One of "steps" / "calories" / "active_minutes" — matches the
    /// `family` strings in `WatchHealthKitWriter`.
    let type: String
}

@MainActor
final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()

    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "wcsession")

    private static let appGroupID = "group.com.fit33.app"
    private static let userDefaultsKey = "fit33.watch.challenge_config.v1"

    /// In-memory mirror of the latest config. Backed by App Group
    /// UserDefaults so a fresh background-launched watch process
    /// gets the same list without waiting on WCSession.
    private(set) var challenges: [WatchChallengeConfig] = []

    /// Set by `Fit33WatchApp` once the foreground stores are
    /// instantiated. Optional because the bridge is a singleton that
    /// pre-exists the first SwiftUI render — when the live workout
    /// payload lands before the store is wired, we drop it (the
    /// phone re-pushes regularly while a workout is live).
    weak var liveWorkoutStore: WatchLiveWorkoutStore?

    private var activated = false

    override private init() {
        super.init()
        // Hydrate from disk so background-launches see the last-known
        // list immediately, before WCSession has had a chance to push
        // a fresher applicationContext.
        rehydrate()
    }

    // MARK: - Public API

    func activate() {
        guard !activated, WCSession.isSupported() else { return }
        activated = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        Self.log.info("WCSession activate requested")
    }

    /// Returns the active challenges that should receive writes for
    /// the given HK family ("steps" / "calories" / "active_minutes").
    func activeChallenges(matching family: String) -> [WatchChallengeConfig]? {
        let matches = challenges.filter { $0.type == family }
        return matches.isEmpty ? nil : matches
    }

    /// Watch → iPhone fire-and-forget message. Used by
    /// `WatchLiveWorkoutStore.completeCurrentSet` to send the
    /// "completeCurrentSet" action. We do NOT use a reply handler:
    /// the phone is expected to apply the action through the
    /// existing WorkoutManager path, and the watch UI updates
    /// optimistically (the phone's next applicationContext push
    /// confirms the new set state).
    func sendMessage(_ message: [String: Any]) {
        guard activated, WCSession.isSupported() else {
            Self.log.info("sendMessage skipped — WCSession not active")
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            Self.log.info("sendMessage skipped — session not yet activated")
            return
        }
        // Reachability differs from activation: `isReachable` requires
        // the iPhone Fit33 app to be in foreground OR background-eligible.
        // If unreachable, we still try — WatchConnectivity queues
        // small messages briefly. If it fails, the watch UI will
        // re-attempt on the next user tap (idempotency-guarded by
        // `WatchLiveWorkoutStore.lastCompletedKey`).
        if !session.isReachable {
            Self.log.info("sendMessage: phone not reachable — best effort")
        }
        session.sendMessage(message, replyHandler: nil) { error in
            Self.log.error("sendMessage failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Persistence

    private func rehydrate() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = defaults.data(forKey: Self.userDefaultsKey),
              let list = try? JSONDecoder().decode([WatchChallengeConfig].self, from: data)
        else { return }
        self.challenges = list
        Self.log.info("Rehydrated \(list.count) challenge config rows from App Group")
    }

    private func persist(_ list: [WatchChallengeConfig]) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(list)
        else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            Self.log.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        Self.log.info("WCSession activated state=\(activationState.rawValue)")
        // Pull the most recent applicationContext synchronously — it
        // may already be populated when the watch app cold-starts.
        let ctx = session.receivedApplicationContext
        Task { @MainActor in self.consume(applicationContext: ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.consume(applicationContext: applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.consume(applicationContext: message) }
    }

    private func consume(applicationContext ctx: [String: Any]) {
        guard !ctx.isEmpty else { return }

        // Slot A: active-challenge config (steps/calories/minutes for
        // the headless writer).
        if let raw = ctx["challenges"] as? [[String: Any]] {
            let parsed: [WatchChallengeConfig] = raw.compactMap { dict in
                guard let id = dict["id"] as? String,
                      let type = dict["type"] as? String
                else { return nil }
                return WatchChallengeConfig(id: id, type: type)
            }
            if parsed != challenges {
                challenges = parsed
                persist(parsed)
                Self.log.info("WCSession applied config: \(parsed.count) challenge(s)")
            }
        }

        // Slot B: live strength-workout state (drives the
        // WatchLiveWorkoutView fullScreenCover + rest-timer haptic).
        // Format owned by `Fit33/PhoneToWatchLiveWorkoutBridge.swift`.
        if let liveWorkout = ctx["liveWorkout"] as? [String: Any] {
            if let store = liveWorkoutStore {
                store.apply(payload: liveWorkout)
                Self.log.debug("WCSession applied liveWorkout payload")
            } else {
                Self.log.info("liveWorkout payload arrived before store was wired — dropping")
            }
        }
    }
}
