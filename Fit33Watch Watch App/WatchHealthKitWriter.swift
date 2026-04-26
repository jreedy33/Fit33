//
//  WatchHealthKitWriter.swift
//  Fit33Watch
//
//  Realtime Widget Server Pull — Phase 8c (2026-04-26).
//
//  HKObserverQuery + HKAnchoredObjectQuery layer that wakes the watch
//  app whenever new step / active-energy samples land, computes
//  today's local-midnight totals, and POSTs them to Supabase via
//  `WatchSupabaseClient.logChallengeProgress`.
//
//  Why both observer + anchored queries:
//    • HKObserverQuery is the wake source. iOS+watchOS will deliver
//      a callback to a foreground OR background watch app whenever
//      new samples land for a registered type. We MUST call
//      `enableBackgroundDelivery(for:frequency:)` after auth — that's
//      the difference between "fires when I have the watch face up"
//      and "fires at the OS-determined cadence regardless of UI
//      state".
//    • HKAnchoredObjectQuery is how we read the actual values. The
//      anchor lets us avoid a full re-aggregation on every callback;
//      we only ever sum samples newer than what we last wrote.
//    • HKStatisticsCollectionQuery would have been simpler but doesn't
//      get scheduled for background delivery on its own — observer
//      is required regardless. Using the anchored query keeps the
//      whole pipeline observer-driven.
//
//  Throttling:
//    HK observer fires can be bursty (e.g. when an Apple Watch
//    workout ends and dumps 30 minutes of samples in one go). We
//    coalesce by debouncing for 30 seconds — multiple observer
//    callbacks within the window collapse to ONE Supabase write.
//
//  Multi-challenge fanout:
//    The phone owns the canonical list of active challenges + their
//    type (steps / active_minutes / calories). We get that list via
//    `WatchConnectivityBridge` and write it to App Group
//    `UserDefaults` so the observer callback can fan-out one RPC
//    per challenge that maps to the HK type that just changed.

import Foundation
import HealthKit
import OSLog

@MainActor
final class WatchHealthKitWriter {
    static let shared = WatchHealthKitWriter()

    private let store = HKHealthStore()
    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "healthkit")

    /// Currently-registered observer queries. Held strong so they
    /// stay running for the process lifetime; an HKObserverQuery
    /// goes silent the moment its retain count hits zero.
    private var observers: [HKObserverQuery] = []

    /// Last-written progress value per (challengeId, hkType) so we
    /// don't repeatedly re-send the same "8,432 steps" row when the
    /// observer fires on a non-changing day. Memory only — fine for
    /// a process whose watchdog cycle is "every observer fire wakes
    /// us, we re-read".
    private var lastWritten: [String: Int] = [:]

    /// Coalescer task — replaced on every observer fire so only the
    /// most recent burst's task survives.
    private var coalesceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            // Simulator / non-HK device — just return; observers
            // will be no-ops because they need HK data anyway.
            Self.log.info("HealthKit unavailable on this device")
            return
        }
        let read: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime)
        ]
        try await store.requestAuthorization(toShare: [], read: read)
    }

    // MARK: - Observer wiring

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Tear down any prior observers so `start()` is idempotent.
        for q in observers { store.stop(q) }
        observers.removeAll()

        let types: [(HKQuantityType, String)] = [
            (HKQuantityType(.stepCount), "steps"),
            (HKQuantityType(.activeEnergyBurned), "calories"),
            (HKQuantityType(.appleExerciseTime), "active_minutes")
        ]

        for (type, family) in types {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
                if let error = error {
                    Self.log.error("Observer error \(family, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return
                }
                Task { @MainActor in
                    await self?.handleObserverFire(family: family, hkType: type)
                }
            }
            store.execute(q)
            observers.append(q)

            // hourly background delivery is enough — we'll over-deliver
            // if the user's wrist is active anyway. Lower frequency
            // also keeps battery impact predictable.
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: .hourly)
                Self.log.info("Background delivery enabled for \(family, privacy: .public)")
            } catch {
                Self.log.error("enableBackgroundDelivery \(family, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Observer handler (with debounce)

    private func handleObserverFire(family: String, hkType: HKQuantityType) async {
        // Cancel any pending coalesce — we want the LAST fire in a
        // burst to be the one that triggers the write.
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.flush(family: family, hkType: hkType)
        }
    }

    /// Internal so `WatchBackgroundRefresh` can drive the same path
    /// without a trampoline. Not private because the background-task
    /// handler is a separate file in the same module.
    func flush(family: String, hkType: HKQuantityType) async {
        guard let challenges = WatchConnectivityBridge.shared.activeChallenges(matching: family),
              !challenges.isEmpty
        else {
            Self.log.debug("No active \(family, privacy: .public) challenges — skipping write")
            return
        }

        // Sum today's samples for this HK type — local midnight to now.
        let total = await todayTotal(for: hkType)
        guard total > 0 else { return }

        for ch in challenges {
            // Dedup against last-write so we don't spam server-side.
            let key = "\(ch.id):\(family)"
            if let prior = lastWritten[key], prior == total { continue }
            do {
                try await WatchSupabaseClient.logChallengeProgress(
                    challengeId: ch.id,
                    progress: total
                )
                lastWritten[key] = total
                Self.log.info("Wrote \(family, privacy: .public)=\(total) → challenge \(ch.id, privacy: .public)")
            } catch {
                Self.log.error("Watch RPC failed \(family, privacy: .public) ch=\(ch.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - HK aggregation

    /// Sum today's samples (local midnight → now) for the given type.
    /// Uses HKStatisticsQuery rather than anchored — anchored gives us
    /// deltas, but we want absolute totals to match the iPhone's
    /// `log_challenge_progress` semantics (which always sends the
    /// running daily total, not the delta).
    ///
    /// Internal (not private) so the foreground `WatchTodayStore`
    /// can reuse the same aggregation path the background writer
    /// uses — no need to duplicate the HK query plumbing.
    func todayTotal(for type: HKQuantityType) async -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [.strictStartDate])
        let unit: HKUnit
        switch type {
        case HKQuantityType(.stepCount): unit = .count()
        case HKQuantityType(.activeEnergyBurned): unit = .kilocalorie()
        case HKQuantityType(.appleExerciseTime): unit = .minute()
        default: unit = .count()
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                cont.resume(returning: Int(value.rounded()))
            }
            store.execute(q)
        }
    }
}
