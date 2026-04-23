//
//  ReadinessService.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 0 (Foundation)
//
//  Single source of truth for "how ready is this user to train?" —
//  computes a unified 0-100 readiness score + band by blending
//  whichever wearable is connected, in priority order:
//      1. WHOOP `recovery_score`     (already 0-100)
//      2. Oura  `readiness_score`    (already 0-100)
//      3. Fitbit-derived             (RHR deviation + sleep + activity)
//      4. HealthKit-derived          (RHR + sleep hours + steps)
//
//  Downstream readers (auto-gen, adaptive goals, XP multipliers,
//  daily quests, challenges, insights, Dashboard welcome card) ONLY
//  see `todayReadiness` + `readinessHistory` and never touch raw
//  WHOOP / Oura / Fitbit DTOs directly. Add a new wearable = add one
//  case to `ReadinessSource` + one branch in `computeReadiness(...)`.
//
//  Threading:
//    * `@MainActor` because every published property is read from
//      SwiftUI and every wearable service we read from is also
//      `@MainActor`.
//    * `recompute(force:)` is fast (computes in-memory from already
//      synced wearable state) — do NOT call wearable `.syncAllData()`
//      from here; `HealthDataService.syncAllHealthData(force:)` is the
//      single upstream sync orchestrator (Data invariant #4a: force
//      propagates through HDS → per-wearable services).
//
//  Persistence:
//    * On every recompute, upserts today's snapshot to
//      `daily_readiness_history` via
//      `SupabaseManager.upsertReadinessSnapshot(...)`.
//    * Last-known snapshot mirrored to `UserDefaults` for cold-start
//      reads before the first network sync — mirrors WhoopService /
//      OuraService pattern.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ReadinessService: ObservableObject {
    static let shared = ReadinessService()

    // MARK: - Published state

    /// Today's snapshot. Starts as `.placeholder()` and flips to a real
    /// value on first `recompute()`. Never `nil` so downstream readers
    /// don't need optional dances — instead check
    /// `snapshot.hasWearableSignal` to branch on "has the user connected
    /// anything yet".
    @Published var todayReadiness: DailyReadinessSnapshot

    /// Rolling window of recent snapshots (local cache, server-authoritative).
    /// Sorted newest-first. Capped at 30 days to match the
    /// `v_user_readiness_30d` view.
    @Published var readinessHistory: [DailyReadinessSnapshot] = []

    /// True while the service is recomputing / upserting. Used by the
    /// Dashboard readiness pill to show a subtle loading state.
    @Published var isComputing: Bool = false

    /// Last successful recompute. Used by `MainTabView` to decide
    /// whether returning to the Dashboard should trigger a refresh
    /// (mirrors Data invariant #4b: wearable widget staleness).
    @Published var lastComputedAt: Date?

    // MARK: - Private state

    private let historyCap = 30

    /// User-defaults key for cold-start cache. Single JSON blob keeps
    /// the cache coherent (don't drift `score` and `band`).
    private static let cacheKey = "readiness_snapshot_cache_v1"

    /// 60-second in-process throttle so a burst of dashboard refreshes
    /// doesn't re-upsert the same day-of row. Wearable sync throttles
    /// are already 5-minute; this is just the lightweight blend on top.
    private static let computeThrottleInterval: TimeInterval = 60

    // MARK: - Init

    private init() {
        // Cold-start: hydrate from UserDefaults so the Dashboard shows a
        // real readiness pill immediately on launch, even before the
        // first wearable sync lands. Falls through to placeholder
        // otherwise (yellow / no-wearable — safe default).
        if let cached = Self.loadCachedSnapshot() {
            self.todayReadiness = cached
        } else {
            self.todayReadiness = DailyReadinessSnapshot.placeholder()
        }

        // Register for the bug-report state snapshot so shake reports
        // include last-known readiness + wearable-connection states.
        BugReportSnapshotter.shared.register(self)
    }

    // MARK: - Public API

    /// Recompute `todayReadiness` from the current in-memory state of
    /// WHOOP / Oura / Fitbit / HealthKit services. Throttled to once
    /// per minute unless `force` is true.
    ///
    /// Call sites:
    ///   - `HealthDataService.syncAllHealthData(force:)` at the tail
    ///     (already propagates force — Data invariant #4a)
    ///   - Pull-to-refresh from the Dashboard readiness pill
    ///   - Tab-return staleness check in `MainTabView`
    ///
    /// MUST NOT trigger additional wearable syncs — upstream is HDS.
    func recompute(force: Bool = false) async {
        if !force, let last = lastComputedAt,
           Date().timeIntervalSince(last) < Self.computeThrottleInterval {
            AppLogger.debug(
                "[Readiness] Skipping recompute — ran \(Int(Date().timeIntervalSince(last)))s ago",
                category: .health
            )
            return
        }

        isComputing = true
        defer { isComputing = false }

        let snapshot = computeReadiness(for: Date())
        todayReadiness = snapshot
        Self.saveCachedSnapshot(snapshot)

        // Fire-and-forget persist to Supabase. Auth + network errors
        // are logged inside the manager — don't block recompute on
        // them (dashboard readiness pill must not depend on cloud).
        await persistSnapshotToSupabase(snapshot)

        // Refresh local history window so the chart updates post-sync.
        await loadHistoryFromServer(days: historyCap)

        lastComputedAt = Date()

        AppLogger.info(
            "[Readiness] Computed score=\(snapshot.score) band=\(snapshot.band.rawValue) source=\(snapshot.primarySource.rawValue) signals=\(snapshot.signals.count)",
            category: .health
        )
    }

    /// Hydrate `readinessHistory` from Supabase. Idempotent — safe to
    /// call on tab-enter and after sync.
    func loadHistoryFromServer(days: Int) async {
        guard SupabaseManager.shared.isAuthenticated,
              SupabaseManager.shared.currentUser?.id != nil else {
            return
        }
        let history = await SupabaseManager.shared.fetchReadinessHistory(daysBack: days)
        self.readinessHistory = history
    }

    // MARK: - Blend: the core algorithm

    /// Compute today's snapshot by picking the highest-priority
    /// wearable source with a signal and blending its numbers in.
    private func computeReadiness(for date: Date) -> DailyReadinessSnapshot {
        // Snapshot all wearable state up-front so the blend is
        // consistent even if a background sync writes mid-compute.
        let whoop = WhoopService.shared
        let oura = OuraService.shared
        let fitbit = FitbitService.shared
        let healthKit = HealthKitService.shared
        let healthData = HealthDataService.shared

        // Priority 1 — WHOOP recovery ------------------------------------
        if whoop.isConnected,
           let recovery = whoop.todayRecovery,
           let score = recovery.recoveryScore {
            return buildSnapshotFromWhoop(date: date, score: score, recovery: recovery,
                                          strain: whoop.todayStrain, sleep: whoop.lastSleep,
                                          baselineHRV: whoop.baselineHRV,
                                          baselineRHR: whoop.baselineRHR)
        }

        // Priority 2 — Oura readiness ------------------------------------
        if oura.isConnected,
           let readiness = oura.todayReadiness,
           let score = readiness.score {
            return buildSnapshotFromOura(date: date, score: score, readiness: readiness,
                                         activity: oura.todayActivity, sleep: oura.lastSleep,
                                         baselineRHR: oura.baselineRHR)
        }

        // Priority 3 — Fitbit-derived ------------------------------------
        if fitbit.isConnected {
            let sleepHours = fitbit.sleepData.first?.minutesAsleep.map { Double($0) / 60.0 }
            let restingHR = fitbit.todaySummary?.restingHeartRate
            if sleepHours != nil || restingHR != nil {
                return buildDerivedSnapshot(
                    date: date,
                    source: .fitbit,
                    sleepHours: sleepHours,
                    restingHR: restingHR,
                    baselineRHR: healthData.avgRestingHeartRate.map(Double.init),
                    hrvDeltaPct: nil,
                    strainPrev: nil,
                    activeMinutes: (fitbit.todaySummary?.fairlyActiveMinutes ?? 0) + (fitbit.todaySummary?.veryActiveMinutes ?? 0)
                )
            }
        }

        // Priority 4 — HealthKit-derived ---------------------------------
        if healthKit.isAuthorized {
            let sleepHours = healthKit.lastNightSleep
            let restingHR = healthKit.restingHeartRate
            if sleepHours != nil || restingHR != nil {
                return buildDerivedSnapshot(
                    date: date,
                    source: .healthkit,
                    sleepHours: sleepHours,
                    restingHR: restingHR,
                    baselineRHR: healthData.avgRestingHeartRate.map(Double.init),
                    hrvDeltaPct: nil,
                    strainPrev: nil,
                    activeMinutes: nil
                )
            }
        }

        // No wearable with data — return placeholder.
        return DailyReadinessSnapshot.placeholder(on: date)
    }

    // MARK: - Builders (one per source)

    private func buildSnapshotFromWhoop(
        date: Date,
        score: Int,
        recovery: WhoopRecoveryScore,
        strain: WhoopCycleScore?,
        sleep: WhoopSleepScore?,
        baselineHRV: Double?,
        baselineRHR: Double?
    ) -> DailyReadinessSnapshot {
        let hrv = recovery.hrvRmssdMilli
        let rhr = recovery.restingHeartRate.map(Double.init)

        let hrvDeltaPct: Double? = {
            guard let hrv, let base = baselineHRV, base > 0 else { return nil }
            return ((hrv - base) / base) * 100.0
        }()

        let rhrTrend: Double? = {
            guard let rhr, let base = baselineRHR, base > 0 else { return nil }
            return rhr - base
        }()

        // Sleep hours from WHOOP stage summary (light + deep + rem).
        let sleepHours: Double? = {
            guard let stages = sleep?.stageSummary else { return nil }
            let totalMilli = (stages.totalLightSleepTimeMilli ?? 0)
                + (stages.totalSlowWaveSleepTimeMilli ?? 0)
                + (stages.totalRemSleepTimeMilli ?? 0)
            guard totalMilli > 0 else { return nil }
            return Double(totalMilli) / 3_600_000.0
        }()

        let sleepDebt: Int? = {
            guard let hours = sleepHours else { return nil }
            return max(0, Int(((7.0 - hours) * 60).rounded()))
        }()

        var signals: [ReadinessSignal] = []
        if let hrvDelta = hrvDeltaPct {
            signals.append(buildHrvSignal(hrvDelta: hrvDelta))
        }
        if let sleepHours = sleepHours {
            signals.append(buildSleepSignal(hours: sleepHours))
        }
        if let rhrTrend = rhrTrend {
            signals.append(buildRhrSignal(delta: rhrTrend))
        }
        if let strainVal = strain?.strain {
            signals.append(ReadinessSignal(
                kind: "strain_prev",
                label: "Yesterday's strain",
                value: strainVal,
                severity: strainVal > 15 ? .warning : .neutral
            ))
        }

        return DailyReadinessSnapshot(
            date: date,
            score: clamp(score),
            band: ReadinessBand(score: score),
            primarySource: .whoop,
            hrvDeltaPct: hrvDeltaPct,
            sleepHours: sleepHours,
            sleepDebtMin: sleepDebt,
            rhrTrendBpm: rhrTrend,
            strainPrev: strain?.strain,
            signals: signals
        )
    }

    private func buildSnapshotFromOura(
        date: Date,
        score: Int,
        readiness: OuraReadinessRecord,
        activity: OuraActivityRecord?,
        sleep: OuraSleepRecord?,
        baselineRHR: Double?
    ) -> DailyReadinessSnapshot {
        // Oura's HRV "balance" is already a 0-100 contributor score, not
        // raw RMSSD. We map it to an approximate delta pct relative to
        // 50 (Oura's "balanced" midpoint) so downstream readers see the
        // same shape as WHOOP's absolute delta. 100 → +20% (strong),
        // 0 → -20% (fatigued). Imperfect but coherent.
        let hrvDeltaPct: Double? = readiness.contributors?.hrvBalance.map { contributor in
            (Double(contributor) - 50.0) / 50.0 * 20.0
        }

        // Oura's RHR contributor is also 0-100 (100 = better/lower vs
        // baseline). Map to a bpm trend using the user's 28-day avg
        // RHR if available; otherwise approximate as 0 when contributor
        // is 50, ±5bpm at the extremes.
        let rhrTrend: Double? = {
            if let rhr = readiness.contributors?.restingHeartRate, let base = baselineRHR, base > 0 {
                // Oura-contributor 100 → RHR at/below baseline (0 delta),
                // Oura-contributor 0 → RHR ~5bpm above baseline.
                return (1.0 - Double(rhr) / 100.0) * 5.0
            }
            return nil
        }()

        let sleepHours: Double? = sleep?.totalSleepDuration.map { Double($0) / 3600.0 }
        let sleepDebt: Int? = sleepHours.map { max(0, Int(((7.0 - $0) * 60).rounded())) }

        var signals: [ReadinessSignal] = []
        if let hrvDelta = hrvDeltaPct {
            signals.append(buildHrvSignal(hrvDelta: hrvDelta))
        }
        if let sleepHours = sleepHours {
            signals.append(buildSleepSignal(hours: sleepHours))
        }
        if let rhrTrend = rhrTrend {
            signals.append(buildRhrSignal(delta: rhrTrend))
        }
        if let temp = readiness.temperatureDeviation {
            signals.append(ReadinessSignal(
                kind: "body_temp",
                label: "Body temperature",
                value: temp,
                severity: abs(temp) > 0.5 ? .warning : .neutral
            ))
        }
        if let activityScore = activity?.score {
            signals.append(ReadinessSignal(
                kind: "activity_score",
                label: "Yesterday's activity",
                value: Double(activityScore),
                severity: activityScore < 50 ? .warning : .neutral
            ))
        }

        return DailyReadinessSnapshot(
            date: date,
            score: clamp(score),
            band: ReadinessBand(score: score),
            primarySource: .oura,
            hrvDeltaPct: hrvDeltaPct,
            sleepHours: sleepHours,
            sleepDebtMin: sleepDebt,
            rhrTrendBpm: rhrTrend,
            strainPrev: nil,
            signals: signals
        )
    }

    /// Blend for Fitbit or HealthKit — neither supplies a native
    /// readiness score, so we derive one from RHR deviation + sleep
    /// + activity minutes.
    ///
    /// Formula (all components 0-100, missing parts drop to a neutral 50):
    ///   * sleep_component  = clamp((sleep_hours / 7.5) * 100, 0, 100)
    ///   * rhr_component    = clamp(100 - (rhr_delta * 5), 0, 100)
    ///     (every +5bpm above baseline ≈ 25 points worse; empirical)
    ///   * active_component = clamp(active_minutes * 2 + 50, 0, 100)
    ///     (30 active minutes yesterday ≈ 110 capped to 100; 0 = 50)
    ///
    ///   score = 0.4 * sleep + 0.4 * rhr + 0.2 * active
    ///
    /// Matches the plan's Phase-0 blend priority formula.
    private func buildDerivedSnapshot(
        date: Date,
        source: ReadinessSource,
        sleepHours: Double?,
        restingHR: Int?,
        baselineRHR: Double?,
        hrvDeltaPct: Double?,
        strainPrev: Double?,
        activeMinutes: Int?
    ) -> DailyReadinessSnapshot {
        let sleepComponent: Double = {
            guard let hours = sleepHours else { return 50 }
            return clampD((hours / 7.5) * 100.0, lower: 0, upper: 100)
        }()

        let rhrTrend: Double? = {
            guard let rhr = restingHR, let base = baselineRHR, base > 0 else { return nil }
            return Double(rhr) - base
        }()

        let rhrComponent: Double = {
            guard let trend = rhrTrend else { return 50 }
            // Higher-than-baseline RHR is worse; 5 points off per bpm above.
            return clampD(100.0 - (trend * 5.0), lower: 0, upper: 100)
        }()

        let activeComponent: Double = {
            guard let mins = activeMinutes else { return 50 }
            return clampD(Double(mins) * 2.0 + 50.0, lower: 0, upper: 100)
        }()

        let blended = 0.4 * sleepComponent + 0.4 * rhrComponent + 0.2 * activeComponent
        let score = Int(blended.rounded())

        var signals: [ReadinessSignal] = []
        if let hours = sleepHours {
            signals.append(buildSleepSignal(hours: hours))
        }
        if let trend = rhrTrend {
            signals.append(buildRhrSignal(delta: trend))
        }
        if let mins = activeMinutes, mins > 0 {
            signals.append(ReadinessSignal(
                kind: "active_minutes",
                label: "Yesterday's active minutes",
                value: Double(mins),
                severity: mins > 30 ? .positive : .neutral
            ))
        }

        let sleepDebt: Int? = sleepHours.map { max(0, Int(((7.0 - $0) * 60).rounded())) }

        return DailyReadinessSnapshot(
            date: date,
            score: clamp(score),
            band: ReadinessBand(score: score),
            primarySource: source,
            hrvDeltaPct: hrvDeltaPct,
            sleepHours: sleepHours,
            sleepDebtMin: sleepDebt,
            rhrTrendBpm: rhrTrend,
            strainPrev: strainPrev,
            signals: signals
        )
    }

    // MARK: - Signal builders

    private func buildHrvSignal(hrvDelta: Double) -> ReadinessSignal {
        let severity: ReadinessSignal.Severity
        let label: String
        if hrvDelta > 10 {
            severity = .positive
            label = "HRV above baseline"
        } else if hrvDelta < -10 {
            severity = .negative
            label = "HRV below baseline"
        } else if hrvDelta < -5 {
            severity = .warning
            label = "HRV slightly low"
        } else {
            severity = .neutral
            label = "HRV at baseline"
        }
        return ReadinessSignal(kind: "hrv_delta", label: label, value: hrvDelta, severity: severity)
    }

    private func buildSleepSignal(hours: Double) -> ReadinessSignal {
        let severity: ReadinessSignal.Severity
        let label: String
        if hours >= 8 {
            severity = .positive
            label = "Great sleep"
        } else if hours >= 7 {
            severity = .neutral
            label = "Solid sleep"
        } else if hours >= 6 {
            severity = .warning
            label = "Short sleep"
        } else {
            severity = .negative
            label = "Insufficient sleep"
        }
        return ReadinessSignal(kind: "sleep_hours", label: label, value: hours, severity: severity)
    }

    private func buildRhrSignal(delta: Double) -> ReadinessSignal {
        let severity: ReadinessSignal.Severity
        let label: String
        if delta > 5 {
            severity = .negative
            label = "RHR elevated"
        } else if delta > 2 {
            severity = .warning
            label = "RHR slightly high"
        } else if delta < -2 {
            severity = .positive
            label = "RHR below baseline"
        } else {
            severity = .neutral
            label = "RHR at baseline"
        }
        return ReadinessSignal(kind: "rhr_trend", label: label, value: delta, severity: severity)
    }

    // MARK: - Persistence

    private func persistSnapshotToSupabase(_ snapshot: DailyReadinessSnapshot) async {
        guard snapshot.hasWearableSignal else {
            // Don't bother writing a "no wearable" placeholder — server
            // nightly rollup would just overwrite with the same thing.
            return
        }
        await SupabaseManager.shared.upsertReadinessSnapshot(snapshot)
    }

    private static func loadCachedSnapshot() -> DailyReadinessSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder.fit33.decode(DailyReadinessSnapshot.self, from: data)
    }

    private static func saveCachedSnapshot(_ snapshot: DailyReadinessSnapshot) {
        guard let data = try? JSONEncoder.fit33.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    // MARK: - Helpers

    private func clamp(_ v: Int) -> Int {
        return max(0, min(100, v))
    }

    private func clampD(_ v: Double, lower: Double, upper: Double) -> Double {
        return max(lower, min(upper, v))
    }
}

// MARK: - JSONCoder helpers

/// Shared encoder / decoder using ISO-8601 with fractional seconds.
/// Private to this file so `Date` round-trips the UserDefaults cache
/// without drifting from Supabase row encoding.
private extension JSONDecoder {
    static let fit33: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let fit33: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

// MARK: - Baseline helpers on wearable services
//
// Small extensions that expose "personal 28-day baseline" computed
// from the service's already-fetched record cache. Declared here so
// ReadinessService never writes to the underlying service — it just
// reads derived values.

extension WhoopService {
    /// 28-day baseline HRV (RMSSD, ms). Falls back to the 7 records
    /// currently in cache if that's all we have; returns nil if the
    /// user has fewer than 3 scored recoveries.
    var baselineHRV: Double? {
        let scores = recentRecoveries.compactMap { $0.score?.hrvRmssdMilli }
        guard scores.count >= 3 else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// 28-day baseline RHR (bpm).
    var baselineRHR: Double? {
        let rhrs = recentRecoveries.compactMap { $0.score?.restingHeartRate }
        guard rhrs.count >= 3 else { return nil }
        return Double(rhrs.reduce(0, +)) / Double(rhrs.count)
    }
}

extension OuraService {
    /// Oura doesn't expose raw HRV on daily_readiness — we'd need the
    /// separate `/v2/usercollection/heartrate` endpoint. For now, use
    /// the 7-day mean of sleep.averageHrv as a proxy baseline.
    var baselineHRV: Double? {
        let hrvs = recentSleeps.compactMap { $0.averageHrv }
        guard hrvs.count >= 3 else { return nil }
        return hrvs.reduce(0, +) / Double(hrvs.count)
    }

    /// Oura RHR baseline from recent sleep's `lowestHeartRate`.
    var baselineRHR: Double? {
        let rhrs = recentSleeps.compactMap { $0.lowestHeartRate }
        guard rhrs.count >= 3 else { return nil }
        return Double(rhrs.reduce(0, +)) / Double(rhrs.count)
    }
}

// MARK: - Bug report snapshot

extension ReadinessService: SnapshotProvider {
    var snapshotKey: String { "ReadinessService" }

    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue] {
        var v: [String: SnapshotValue] = [
            "todayScore": .int(todayReadiness.score),
            "todayBand": .string(todayReadiness.band.rawValue),
            "todaySource": .string(todayReadiness.primarySource.rawValue),
            "hasWearableSignal": .bool(todayReadiness.hasWearableSignal),
            "isComputing": .bool(isComputing),
            "history.count": .int(readinessHistory.count),
            "signals.count": .int(todayReadiness.signals.count),
        ]
        if let last = lastComputedAt {
            v["lastComputedAgeSec"] = .double(Date().timeIntervalSince(last))
        }
        if let hrv = todayReadiness.hrvDeltaPct {
            v["hrvDeltaPct"] = .double(hrv)
        }
        if let hrs = todayReadiness.sleepHours {
            v["sleepHours"] = .double(hrs)
        }
        if let rhr = todayReadiness.rhrTrendBpm {
            v["rhrTrendBpm"] = .double(rhr)
        }
        // Wearable-connection state — high-leverage for "readiness
        // pill stuck on Yellow" triage.
        v["whoopConnected"] = .bool(WhoopService.shared.isConnected)
        v["ouraConnected"] = .bool(OuraService.shared.isConnected)
        v["fitbitConnected"] = .bool(FitbitService.shared.isConnected)
        v["healthKitAuthorized"] = .bool(HealthKitService.shared.isAuthorized)

        // Last-sync ages so Claude can distinguish "wearable
        // disconnected" from "connected but data is 6 hours stale".
        if let d = WhoopService.shared.lastSyncDate {
            v["whoopLastSyncAgeSec"] = .double(Date().timeIntervalSince(d))
        }
        if let d = OuraService.shared.lastSyncDate {
            v["ouraLastSyncAgeSec"] = .double(Date().timeIntervalSince(d))
        }
        if let d = FitbitService.shared.lastSyncDate {
            v["fitbitLastSyncAgeSec"] = .double(Date().timeIntervalSince(d))
        }
        return v
    }
}
