//
//  WatchTodayStore.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Owns the data shown by `WatchTodayView`:
//    • Today's HK totals (steps / active cal / exercise minutes),
//      pulled via `WatchHealthKitWriter.todayTotal(for:)`.
//    • Active 1v1 challenges, pulled via
//      `WatchSupabaseClient.fetchActiveChallenges()`.
//    • Currently-selected challenge index (driven by Digital Crown
//      in the view).
//    • Last refresh timestamp + status string.
//
//  Refresh strategy:
//    Cheap on first show, no auto-poll. The user can pull-to-refresh,
//    and we re-pull whenever the view re-mounts (rare on watchOS —
//    apps stay alive in memory). The widget extension and headless
//    background writer keep server-side state fresh independently.
//
//  Complication snapshot:
//    After a successful Supabase pull, we mirror the top challenge
//    into App Group `UserDefaults` under
//    `fit33.watch.today_snapshot.v1` so the GraphicCircular
//    complication can render without making its own RPC.

import Foundation
import Combine
import HealthKit
import OSLog

@MainActor
final class WatchTodayStore: ObservableObject {

    // MARK: - HK totals

    @Published var stepsToday: Int = 0
    @Published var activeCaloriesToday: Int = 0
    @Published var exerciseMinutesToday: Int = 0

    // MARK: - Challenges

    @Published var challenges: [WatchActiveChallenge] = []
    @Published var selectedChallengeIndex: Double = 0

    // MARK: - Refresh status

    @Published var isRefreshing: Bool = false
    @Published var lastRefreshAt: Date?
    @Published var lastError: String?

    // MARK: - Convenience

    var streakDays: Int {
        challenges.first?.myCurrentStreak ?? 0
    }

    var selectedChallenge: WatchActiveChallenge? {
        let count = challenges.count
        guard count > 0 else { return nil }
        let idx = max(0, min(count - 1, Int(selectedChallengeIndex.rounded())))
        return challenges[idx]
    }

    // MARK: - Snapshot for complication

    private static let appGroupID = "group.com.fit33.app"
    private static let snapshotKey = "fit33.watch.today_snapshot.v1"

    /// Wire shape for the complication's App Group read.
    struct Snapshot: Codable {
        let updatedAt: Date
        let topChallengeId: String?
        let topChallengeTitle: String?
        let topChallengeMyProgress: Int
        let topChallengeDailyTarget: Int?
        let topChallengeDaysRemaining: Int
        let myCurrentStreak: Int
        let stepsToday: Int
    }

    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "today-store")

    // MARK: - Refresh

    /// Pull HK totals + Supabase challenges in parallel.
    /// Best-effort — failures surface via `lastError` but don't clear
    /// the previous values. Pull-to-refresh re-runs this.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let hk: Void = refreshHealthKit()
        async let challenges: Void = refreshChallenges()
        _ = await (hk, challenges)

        lastRefreshAt = Date()
        writeSnapshot()
    }

    private func refreshHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        async let s = WatchHealthKitWriter.shared.todayTotal(for: HKQuantityType(.stepCount))
        async let c = WatchHealthKitWriter.shared.todayTotal(for: HKQuantityType(.activeEnergyBurned))
        async let m = WatchHealthKitWriter.shared.todayTotal(for: HKQuantityType(.appleExerciseTime))
        let (steps, cals, mins) = await (s, c, m)
        self.stepsToday = steps
        self.activeCaloriesToday = cals
        self.exerciseMinutesToday = mins
    }

    private func refreshChallenges() async {
        do {
            let rows = try await WatchSupabaseClient.fetchActiveChallenges()
            self.challenges = rows
            // Clamp the crown-driven index in case the list shrank.
            if !rows.isEmpty {
                let maxIdx = Double(rows.count - 1)
                if selectedChallengeIndex > maxIdx { selectedChallengeIndex = maxIdx }
            } else {
                selectedChallengeIndex = 0
            }
            self.lastError = nil
        } catch WatchSupabaseError.notAuthenticated {
            self.lastError = "Sign in on iPhone"
            Self.log.info("fetchActiveChallenges: notAuthenticated — phone hasn't published a session")
        } catch {
            self.lastError = "Couldn't refresh"
            Self.log.error("fetchActiveChallenges failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Snapshot mirror

    private func writeSnapshot() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        let top = challenges.first
        let snapshot = Snapshot(
            updatedAt: Date(),
            topChallengeId: top?.id,
            topChallengeTitle: top?.displayTitle,
            topChallengeMyProgress: top?.myTodayProgress ?? 0,
            topChallengeDailyTarget: top?.dailyTarget,
            topChallengeDaysRemaining: top?.daysRemaining ?? 0,
            myCurrentStreak: top?.myCurrentStreak ?? 0,
            stepsToday: stepsToday
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    // MARK: - Snapshot reader (used by the complication target)

    /// Static reader for the complication target's `TimelineProvider`.
    /// Returns `nil` if the App Group entitlement is missing or the
    /// watch has never refreshed.
    static func readSnapshot() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }
}
