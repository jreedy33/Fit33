//
//  PhoneToWatchSyncBridge.swift
//  Fit33
//
//  Realtime Widget Server Pull — Phase 8e (2026-04-26).
//
//  iPhone-side companion to `Fit33Watch/WatchConnectivityBridge.swift`.
//  Sends the user's active challenge list to the paired Apple Watch
//  via WCSession `applicationContext` so the watch knows which
//  challenge IDs to log against when its HealthKit observers fire.
//
//  This file is OPTIONAL — if the user hasn't installed the watch
//  companion, `WCSession.isSupported() == true` but
//  `isWatchAppInstalled == false`, and we silently skip every send.
//  The phone-side HK observer path remains the writer of last resort
//  in that case.
//
//  Wire format (KEEP IN SYNC with `WatchConnectivityBridge.consume`):
//
//      ["v": 1,
//       "challenges": [
//         ["id": "<uuid>", "type": "steps"],
//         ...
//       ]]
//
//  Send cadence:
//   - On every `ChallengeService.activeChallenges` change (publisher
//     observer in `Fit33App.swift::task`).
//   - On every cold-start once `ChallengeService.fetchActiveChallenges`
//     completes for the first time.
//   - On `WCSessionDelegate.sessionReachabilityDidChange` if the watch
//     comes back into range without a new active-challenge update —
//     ensures we re-push the latest config when the Bluetooth link
//     wakes back up.
//
//  Failure mode:
//   `updateApplicationContext(_:)` is the right WCSession primitive
//   here — it's "latest write wins, persisted on the watch even if
//   it's asleep, delivered the moment the watch comes back". We
//   deliberately don't use `sendMessage(_:)` (requires the watch app
//   to be running) or `transferUserInfo(_:)` (queue, FIFO, can build
//   up if we send aggressively). One context, last-known config.

import Foundation
import Combine
import WatchConnectivity
import os

@MainActor
final class PhoneToWatchSyncBridge: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = PhoneToWatchSyncBridge()

    private static let log = AppLogger.self
    private static let category: AppLogger.Category = .general

    private var activated = false
    private var lastSentPayload: [String: AnyHashable]?
    private var lastChallengesSlot: [[String: String]] = []
    private var cancellables: Set<AnyCancellable> = []

    override private init() {
        super.init()
    }

    // MARK: - Public API

    /// Activate the WCSession and subscribe to delegate events. Safe to
    /// call multiple times; idempotent.
    func activate() {
        guard !activated, WCSession.isSupported() else { return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
        AppLogger.debug("PhoneToWatchSyncBridge activated", category: .general)

        // Subscribe to active-challenge changes so we keep the watch
        // in lockstep without each call site having to push manually.
        // `removeDuplicates` collapses purely-cosmetic re-emissions
        // (same IDs + types). Debounce 250ms coalesces the bursty
        // post-fetch chain (fetchActiveChallenges → publish → friend
        // metadata enrich → publish again).
        ChallengeService.shared.$activeChallenges
            .removeDuplicates(by: { lhs, rhs in
                guard lhs.count == rhs.count else { return false }
                for (l, r) in zip(lhs, rhs) where l.challengeId != r.challengeId
                    || l.targetUnit != r.targetUnit { return false }
                return true
            })
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] list in
                self?.sendActiveChallenges(list)
            }
            .store(in: &cancellables)
    }

    /// Pushes the current active-challenge list to the watch. Called
    /// from `Fit33App.swift::task` whenever `ChallengeService.shared
    /// .activeChallenges` changes (Combine publisher observer). The
    /// `type` field maps the iPhone's `ActiveChallenge.targetUnit` into
    /// the wire-format strings the watch's HK writer expects.
    func sendActiveChallenges(_ list: [ActiveChallenge]) {
        let challenges: [[String: String]] = list.compactMap { ch in
            guard let mapped = wireType(for: ch.targetUnit) else { return nil }
            return ["id": ch.challengeId.uuidString, "type": mapped]
        }
        lastChallengesSlot = challenges
        refreshContext()
    }

    /// Rebuilds the merged applicationContext payload from the two
    /// slots we own (`challenges` from `sendActiveChallenges`, and
    /// `liveWorkout` from `PhoneToWatchLiveWorkoutBridge.shared
    /// .currentPayload`) and pushes it to the watch. Called whenever
    /// either slot changes. Idempotent — no-op if the merged payload
    /// is byte-identical to the last send.
    func refreshContext() {
        guard activated, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isPaired, session.isWatchAppInstalled else {
            // No watch companion — there's nothing to sync. The
            // iPhone HK observer path remains the only writer. Don't
            // log every call to keep this quiet.
            return
        }

        var payload: [String: AnyHashable] = [
            "v": 1,
            "challenges": lastChallengesSlot as AnyHashable
        ]
        if let liveSlot = PhoneToWatchLiveWorkoutBridge.shared.currentPayload {
            payload["liveWorkout"] = liveSlot as AnyHashable
        }

        // Skip if unchanged — `updateApplicationContext` is debounced
        // by watchOS but we still avoid the dict comparison cost.
        if let last = lastSentPayload, last == payload { return }
        lastSentPayload = payload

        do {
            try session.updateApplicationContext(payload)
            AppLogger.debug("Pushed context to watch challenges=\(lastChallengesSlot.count) liveWorkout=\(payload["liveWorkout"] != nil)", category: .general)
        } catch {
            AppLogger.warning("WCSession updateApplicationContext failed: \(error.localizedDescription)", category: .general)
        }
    }

    /// Maps a 1v1 / group challenge `target_unit` (matches the
    /// `challenge_type` column on `group_challenges`) to the
    /// HealthKit "family" string the watch's `WatchHealthKitWriter`
    /// understands. Anything outside this list (e.g. hydration,
    /// protein) is intentionally NOT synced — the watch only writes
    /// passive auto-tracked HK data, never user-input nutrition.
    private func wireType(for targetUnit: String) -> String? {
        switch targetUnit.lowercased() {
        case "steps": return "steps"
        case "calories", "kcal", "active_calories": return "calories"
        case "active_minutes", "minutes", "exercise_minutes": return "active_minutes"
        default: return nil
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            AppLogger.warning("WCSession activation failed: \(error.localizedDescription)", category: .general)
        } else {
            AppLogger.debug("WCSession activated state=\(activationState.rawValue)", category: .general)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Per Apple docs, must reactivate after a multi-watch switch.
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            guard session.isReachable, WCSession.default.isWatchAppInstalled else { return }
            // Watch came back into range — re-push the latest list.
            self.sendActiveChallenges(ChallengeService.shared.activeChallenges)
        }
    }

    /// Watch → phone fire-and-forget messages. The only currently-
    /// supported action is `completeCurrentSet` (sent from
    /// `WatchLiveWorkoutStore.completeCurrentSet()`); future actions
    /// must be added to this switch and to PE invariant 33's wire-
    /// format documentation.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        switch action {
        case "completeCurrentSet":
            let exerciseId = message["exerciseId"] as? String ?? ""
            let setIndex = message["setIndex"] as? Int ?? 0
            Task { @MainActor in
                guard !exerciseId.isEmpty else { return }
                PhoneToWatchLiveWorkoutBridge.shared.applyCompleteCurrentSet(
                    exerciseId: exerciseId,
                    setIndex: setIndex
                )
            }
        default:
            AppLogger.debug("Unknown WCSession action: \(action)", category: .general)
        }
    }
}
