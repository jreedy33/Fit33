//
//  WatchWorkoutSessionManager.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  HKWorkoutSession + HKLiveWorkoutBuilder owner. Owns the live
//  cardio workout state shown by `WatchActiveWorkoutView`:
//    • Duration ticker (driven by the session start date).
//    • Heart-rate sample feed via `HKLiveWorkoutDataSource`.
//    • Finish path: `endActivity` → `endCollection` → `finishWorkout`.
//
//  The resulting `HKWorkout` sample is written to HealthKit by the
//  builder; the iPhone's HK observer imports it automatically (see
//  `Fit33/HealthKitService.swift`'s observer chain). No watch-side
//  Supabase write is needed for cardio sessions.
//

import Foundation
import Combine
import HealthKit
import OSLog
#if canImport(WatchKit)
import WatchKit
#endif

@MainActor
final class WatchWorkoutSessionManager: NSObject, ObservableObject {

    enum State: Equatable {
        case picker
        case running
        case ending
        case finished
    }

    enum WorkoutKind: CaseIterable {
        case run, walk, other

        var label: String {
            switch self {
            case .run:   return "Run"
            case .walk:  return "Outdoor Walk"
            case .other: return "Other"
            }
        }

        var symbol: String {
            switch self {
            case .run:   return "figure.run"
            case .walk:  return "figure.walk"
            case .other: return "figure.mixed.cardio"
            }
        }

        var hkType: HKWorkoutActivityType {
            switch self {
            case .run:   return .running
            case .walk:  return .walking
            case .other: return .other
            }
        }

        var location: HKWorkoutSessionLocationType {
            switch self {
            case .run, .walk: return .outdoor
            case .other:      return .unknown
            }
        }
    }

    // MARK: - Published state

    @Published var state: State = .picker
    @Published var heartRateBPM: Int = 0
    @Published var durationSec: Int = 0

    var kindLabel: String { kind?.label ?? "" }

    var formattedDuration: String {
        let s = max(0, durationSec)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    var heartRateString: String {
        heartRateBPM > 0 ? "\(heartRateBPM)" : "—"
    }

    // MARK: - HK plumbing

    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "workout-session")
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var tickTask: Task<Void, Never>?
    private(set) var kind: WorkoutKind?

    deinit {
        tickTask?.cancel()
    }

    // MARK: - Lifecycle

    func start(kind: WorkoutKind) {
        guard state == .picker else { return }
        self.kind = kind

        let writeShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning)
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        Task { @MainActor in
            do {
                try await store.requestAuthorization(toShare: writeShare, read: read)
            } catch {
                Self.log.error("HK auth for workout session failed: \(error.localizedDescription, privacy: .public)")
            }
            self.beginSession(kind: kind)
        }
    }

    private func beginSession(kind: WorkoutKind) {
        let config = HKWorkoutConfiguration()
        config.activityType = kind.hkType
        config.locationType = kind.location

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            let now = Date()
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { [weak self] success, error in
                if let error = error {
                    Self.log.error("beginCollection failed: \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in
                    if success {
                        self?.state = .running
                    }
                }
            }

            self.session = session
            self.builder = builder
            self.startedAt = now

            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.start)
            #endif

            startDurationTicker()
        } catch {
            Self.log.error("HKWorkoutSession init failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startDurationTicker() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tick() async {
        guard let startedAt else { return }
        durationSec = Int(Date().timeIntervalSince(startedAt).rounded())
    }

    func finish() async {
        guard state == .running, let session, let builder else {
            // If the user mashes Finish before the session actually
            // started, just dismiss back to picker.
            state = .finished
            return
        }
        state = .ending
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
            Self.log.info("Workout finished + saved to HealthKit")
        } catch {
            Self.log.error("finishWorkout failed: \(error.localizedDescription, privacy: .public)")
        }
        tickTask?.cancel()
        tickTask = nil
        state = .finished
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        // No-op — UI state is driven by `start` / `finish` paths.
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            Self.log.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
            self.state = .finished
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Events (markers, lap, etc.) aren't surfaced in v1.
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType) else { return }
        guard let stats = workoutBuilder.statistics(for: hrType),
              let mostRecent = stats.mostRecentQuantity()
        else { return }
        let bpm = mostRecent.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in
            self.heartRateBPM = Int(bpm.rounded())
        }
    }
}
