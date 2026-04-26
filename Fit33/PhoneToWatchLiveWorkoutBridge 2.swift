//
//  PhoneToWatchLiveWorkoutBridge.swift
//  Fit33
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Sibling to `PhoneToWatchSyncBridge.swift`. That bridge owns the
//  challenge-list slot of the watch's `applicationContext`; this
//  bridge owns the new `liveWorkout` slot — the live state of an
//  active strength workout (current exercise, current set, target
//  weight × reps, rest-timer end-time). The watch consumes the slot
//  to render `WatchLiveWorkoutView` and fire the wrist-tap haptic
//  when the rest timer expires.
//
//  Why two bridges:
//    WCSession only lets you assign ONE delegate. The challenge
//    bridge already owns delegation. This bridge holds STATE only
//    and asks `PhoneToWatchSyncBridge.shared.refreshContext()` to
//    push the merged payload (challenges + liveWorkout) whenever
//    its state changes. Inbound messages from the watch land on
//    the challenge bridge first and are routed here via
//    `applyCompleteCurrentSet(...)`.
//
//  Wire format (KEEP IN SYNC with
//  `Fit33Watch Watch App/WatchLiveWorkoutStore.swift::apply(payload:)`):
//
//      "liveWorkout": {
//        "active": true,
//        "exerciseId": "<uuid>",
//        "exerciseName": "Bench Press",
//        "setIndex": 1,            // 0-based, set the user is ON now
//        "totalSets": 4,
//        "targetWeight": 135.0,    // optional; nil if bodyweight
//        "targetReps": 8,
//        "restEndsAt": "<iso8601>" // optional; nil if not resting
//      }
//
//  Phones-only path stays viable (PE invariant 33): if no watch is
//  paired or the watch app isn't installed, every push is a no-op.
//  The watch never sends "completeCurrentSet" in that case.

import Foundation
import Combine

@MainActor
final class PhoneToWatchLiveWorkoutBridge: ObservableObject {
    static let shared = PhoneToWatchLiveWorkoutBridge()

    // MARK: - State (the slot we own)

    /// Last-pushed live workout snapshot. `nil` means no live workout.
    /// The merged context build in `PhoneToWatchSyncBridge` reads this
    /// directly. Mutation MUST be followed by `refreshContext()` so
    /// the watch sees the change.
    private(set) var currentPayload: [String: AnyHashable]?

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - Push (phone → watch via sync bridge)

    /// Called by `ActiveWorkoutView` when the user starts/changes
    /// exercise OR finishes a set. The setIndex is the NEXT set
    /// the user is about to do (0-based), not the just-completed one.
    func pushExercise(
        exerciseId: String,
        exerciseName: String,
        setIndex: Int,
        totalSets: Int,
        targetWeight: Double?,
        targetReps: Int
    ) {
        var slot: [String: AnyHashable] = [
            "active": true,
            "exerciseId": exerciseId,
            "exerciseName": exerciseName,
            "setIndex": setIndex,
            "totalSets": totalSets,
            "targetReps": targetReps
        ]
        if let weight = targetWeight {
            slot["targetWeight"] = weight
        }
        // Preserve the existing rest-timer slot (so completing a set
        // and pushing the next state doesn't accidentally cancel the
        // rest haptic on the watch).
        if let restISO = currentPayload?["restEndsAt"] as? String {
            slot["restEndsAt"] = restISO
        }
        currentPayload = slot
        PhoneToWatchSyncBridge.shared.refreshContext()
    }

    /// Called by `RestTimer.start(...)` / `RestTimer.stop()`. Pass
    /// `nil` to clear the rest haptic on the watch.
    func pushRestEndsAt(_ endsAt: Date?) {
        guard var payload = currentPayload else { return }
        if let endsAt {
            payload["restEndsAt"] = Self.isoFormatter.string(from: endsAt)
        } else {
            payload.removeValue(forKey: "restEndsAt")
        }
        currentPayload = payload
        PhoneToWatchSyncBridge.shared.refreshContext()
    }

    /// Called when the user dismisses the active workout view. Pushes
    /// `active: false` so the watch tears down its full-screen cover.
    func clearLive() {
        currentPayload = ["active": false]
        PhoneToWatchSyncBridge.shared.refreshContext()
        // Drop the local copy after one push so the next set of pushes
        // starts from a clean slate. Done on a tiny task to ensure the
        // refreshContext call has read the value first.
        Task { @MainActor in
            self.currentPayload = nil
            PhoneToWatchSyncBridge.shared.refreshContext()
        }
    }

    // MARK: - Receive (watch → phone via sync bridge)

    /// Called by `PhoneToWatchSyncBridge.session(_:didReceiveMessage:)`
    /// when the watch sends `{ action: "completeCurrentSet", ... }`.
    /// Uses the existing `WorkoutManager.addSetToExercise` path so PE
    /// invariant 14b is automatically respected (we never touch
    /// `ActiveWorkoutView.exercises` from this path).
    ///
    /// Idempotency: the watch side guards via `lastCompletedKey`, but
    /// we double-check here in case the same message gets redelivered
    /// after a watch process restart. We compare the incoming
    /// (exerciseId, setIndex) against the last-pushed state.
    func applyCompleteCurrentSet(exerciseId: String, setIndex: Int) {
        let manager = WorkoutManager.shared

        // Build a completed set using the last-pushed targets so the
        // weight/reps match what the watch displayed. Defaults are
        // zero so missing targets yield a bodyweight set.
        let weight = (currentPayload?["targetWeight"] as? Double) ?? 0
        let reps = (currentPayload?["targetReps"] as? Int) ?? 0

        let setData = WorkoutSetData()
        setData.weight = weight
        setData.weightKg = weight * WorkoutSetData.lbsToKg
        setData.reps = reps
        setData.isCompleted = true

        // Idempotency: if the existing exerciseSetsData already has
        // a completed set at this index, drop the duplicate.
        let existing = manager.exerciseSetsData[exerciseId] ?? []
        let nextIndex = existing.count
        if setIndex < existing.count && existing[setIndex].isCompleted {
            AppLogger.info("Watch completeCurrentSet idempotent — set \(setIndex) already completed for \(exerciseId)", category: .general)
            return
        }
        // If the watch is ahead of the phone (shouldn't happen, but
        // possible after a force-kill), still apply at the canonical
        // append index.
        _ = nextIndex

        manager.addSetToExercise(id: exerciseId, set: setData)
        AppLogger.info("Applied watch completeCurrentSet exercise=\(exerciseId) set=\(setIndex)", category: .general)

        // The phone side will follow up with its own pushExercise
        // (via ActiveWorkoutView's existing handleSetCompletion path)
        // and the rest timer hook so the watch advances to the next
        // set + countdown UI.
    }
}
