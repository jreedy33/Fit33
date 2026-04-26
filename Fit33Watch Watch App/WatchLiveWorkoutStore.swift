//
//  WatchLiveWorkoutStore.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Holds the live strength-workout state pushed from the iPhone via
//  WCSession `applicationContext`. Drives `WatchLiveWorkoutView` —
//  when `isLive == true`, the Today screen presents the live workout
//  full-screen cover.
//
//  Wire format owned by `Fit33/PhoneToWatchLiveWorkoutBridge.swift`:
//
//      {
//        v: 1,
//        liveWorkout: {
//          active: true,
//          exerciseId: "<uuid>",
//          exerciseName: "Bench Press",
//          setIndex: 1,        // 0-based, the set the user is ON now
//          totalSets: 4,
//          targetWeight: 135,  // optional; nil if bodyweight
//          targetReps: 8,
//          restEndsAt: "<iso8601>" | null
//        }
//      }
//
//  Local rest-timer behaviour:
//    The phone's `restEndsAt` is a hard end-of-rest timestamp. When
//    the store sees a fresh `restEndsAt > now`, it spins up a local
//    `Task` that sleeps until expiry and fires
//    `WKInterfaceDevice.current().play(.notification)` — that's the
//    "wrist tap when my rest timer expires" feature. The tap is a
//    no-op when the watch is off-wrist (correct behaviour).
//

import Foundation
import Combine
import OSLog
#if canImport(WatchKit)
import WatchKit
#endif

@MainActor
final class WatchLiveWorkoutStore: ObservableObject {

    // MARK: - Published live-workout state

    @Published var isLive: Bool = false
    @Published var exerciseId: String?
    @Published var exerciseName: String = ""
    @Published var setIndex: Int = 0
    @Published var totalSets: Int = 0
    @Published var targetWeight: Double?
    @Published var targetReps: Int = 0

    /// Timestamp at which the rest timer expires. `nil` means we are
    /// not currently resting.
    @Published var restEndsAt: Date?

    /// Live-ticking countdown derived from `restEndsAt`. Non-nil only
    /// while we're resting, in seconds.
    @Published var restRemainingSec: Int = 0

    // MARK: - Internal

    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "live-workout")

    /// One-shot task that fires the wrist haptic when `restEndsAt` is
    /// reached. Cancelled + replaced whenever the phone pushes a new
    /// `restEndsAt`.
    private var hapticTask: Task<Void, Never>?

    /// Live tick task — updates `restRemainingSec` once per second
    /// while resting so the countdown UI animates without the view
    /// having to maintain its own timer.
    private var tickTask: Task<Void, Never>?

    /// Idempotency guard for watch→phone "completeCurrentSet" sends:
    /// we keep the (exerciseId, setIndex) of the last set the user
    /// pressed Done on so a flaky WCSession redelivery doesn't double-
    /// add a set.
    private(set) var lastCompletedKey: String?

    init() {}

    // MARK: - Phone → Watch state ingestion

    /// Apply the `liveWorkout` slot pushed from the iPhone. Called
    /// from `WatchConnectivityBridge.consume(applicationContext:)`.
    func apply(payload: [String: Any]) {
        // `active: false` (or no `active` key) = no live workout.
        let active = (payload["active"] as? Bool) ?? false
        guard active else {
            clearLive()
            return
        }

        let newExerciseId = payload["exerciseId"] as? String
        let newSetIndex = (payload["setIndex"] as? Int) ?? 0
        // If the phone moved on past the set we last completed, clear
        // the idempotency guard.
        if newExerciseId != exerciseId || newSetIndex != setIndex {
            lastCompletedKey = nil
        }

        isLive = true
        exerciseId = newExerciseId
        exerciseName = (payload["exerciseName"] as? String) ?? ""
        setIndex = newSetIndex
        totalSets = (payload["totalSets"] as? Int) ?? 0
        targetWeight = payload["targetWeight"] as? Double
        targetReps = (payload["targetReps"] as? Int) ?? 0

        let newRestEndsAt = parseISO8601(payload["restEndsAt"])
        applyRestEndsAt(newRestEndsAt)
    }

    private func clearLive() {
        isLive = false
        exerciseId = nil
        exerciseName = ""
        setIndex = 0
        totalSets = 0
        targetWeight = nil
        targetReps = 0
        applyRestEndsAt(nil)
        lastCompletedKey = nil
    }

    // MARK: - Rest timer

    private func applyRestEndsAt(_ newValue: Date?) {
        // Skip churn if unchanged.
        if newValue == restEndsAt {
            return
        }
        restEndsAt = newValue

        hapticTask?.cancel()
        tickTask?.cancel()
        hapticTask = nil
        tickTask = nil

        guard let endsAt = newValue else {
            restRemainingSec = 0
            return
        }

        let remaining = endsAt.timeIntervalSinceNow
        if remaining <= 0 {
            // Already expired — fire haptic immediately (phone push
            // arrived late) and clear.
            playRestExpiredHaptic()
            restRemainingSec = 0
            return
        }

        restRemainingSec = Int(remaining.rounded())

        hapticTask = Task { [weak self] in
            let sleepSec = endsAt.timeIntervalSinceNow
            if sleepSec > 0 {
                try? await Task.sleep(nanoseconds: UInt64(sleepSec * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.handleRestExpired()
        }

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = await self.tickRemainingFromMain(endsAt: endsAt)
                if remaining <= 0 { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tickRemainingFromMain(endsAt: Date) async -> Int {
        let remaining = max(0, Int(endsAt.timeIntervalSinceNow.rounded()))
        self.restRemainingSec = remaining
        return remaining
    }

    private func handleRestExpired() {
        playRestExpiredHaptic()
        restEndsAt = nil
        restRemainingSec = 0
    }

    private func playRestExpiredHaptic() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.notification)
        #endif
        Self.log.info("Rest timer expired — fired wrist tap haptic")
    }

    // MARK: - Watch → Phone action

    /// Called from `WatchLiveWorkoutView` when the user taps Mark Done.
    /// Sends `completeCurrentSet` over WCSession; the phone side
    /// applies it through the existing `WorkoutManager.addSetToExercise`
    /// path so PE invariant 14b is automatically respected.
    func completeCurrentSet() {
        guard let exerciseId else {
            Self.log.warning("completeCurrentSet called with no live exercise")
            return
        }
        let key = "\(exerciseId):\(setIndex)"
        if lastCompletedKey == key {
            Self.log.info("completeCurrentSet idempotency guard — already sent for \(key, privacy: .public)")
            return
        }
        lastCompletedKey = key

        WatchConnectivityBridge.shared.sendMessage([
            "action": "completeCurrentSet",
            "exerciseId": exerciseId,
            "setIndex": setIndex
        ])

        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
        Self.log.info("Sent completeCurrentSet exercise=\(exerciseId, privacy: .public) set=\(self.setIndex)")
    }

    // MARK: - Helpers

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseISO8601(_ raw: Any?) -> Date? {
        guard let s = raw as? String, !s.isEmpty else { return nil }
        if let d = Self.isoFractionalFormatter.date(from: s) { return d }
        return Self.isoFormatter.date(from: s)
    }
}
