//
//  HealthDataService.swift
//  Fit33
//
//  Aggregates health data from Fitbit, Strava, and manual entries
//  Provides unified insights across all data sources
//

import Foundation
import SwiftUI

// MARK: - Health Data Service

@MainActor
final class HealthDataService: ObservableObject {
    static let shared = HealthDataService()
    
    private static let iso8601 = ISO8601DateFormatter()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    // MARK: - Published Properties
    
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    
    // Daily Summary
    @Published var todaySummary: DailyActivitySummary?
    @Published var weeklyActivityData: [DailyActivitySummary] = []
    
    // Sleep Data
    @Published var recentSleepLogs: [SleepLogEntry] = []
    @Published var averageSleepHours: Double = 0
    @Published var sleepTrend: TrendDirection = .stable
    
    // Heart Rate Data
    @Published var todayHeartRate: HeartRateDaily?
    @Published var weeklyHeartRateData: [HeartRateDaily] = []
    @Published var restingHRTrend: TrendDirection = .stable
    
    // Cardio/Workout Aggregates
    @Published var weeklyWorkoutCount: Int = 0
    @Published var weeklyCardioMinutes: Int = 0
    @Published var weeklyCaloriesBurned: Int = 0
    
    // Connected Sources
    @Published var connectedSources: [String] = []
    
    // Throttling
    private static let syncThrottleInterval: TimeInterval = 300 // 5 minutes
    private var isSyncing = false
    
    /// Sprint 3 (Sprint 2026-04-24 Phase 3): in-flight task for coalescing.
    /// Per QP invariant #24c, multiple concurrent callers of `syncAllHealthData`
    /// MUST share one underlying task instead of spawning N parallel health
    /// source syncs. 1.38 (54) logs showed 9× `HealthKit.syncAll` in a single
    /// startup — from BackgroundChallengeSyncService + Dashboard `.task` +
    /// app-foreground handler + Friends `.task` + onChange triggers all firing
    /// within the same 10-second window. The `isSyncing` flag alone was not
    /// enough because `force: true` bypassed it (pull-to-refresh + scenePhase).
    /// Now force-callers also coalesce into the in-flight task.
    private var inFlightSyncTask: Task<Void, Never>?
    
    private init() {
        updateConnectedSources()
    }
    
    // MARK: - Sync All Data
    
    /// Sync health data from all connected sources (throttled + coalesced).
    /// Concurrent callers share the same underlying work.
    func syncAllHealthData(force: Bool = false) async {
        // Coalesce: if a sync is already in-flight, wait for it rather than
        // starting another. Applies even for `force: true` callers — `force`
        // skips the 5-minute throttle, but does NOT skip the single-flight
        // guarantee. Without this gate, pull-to-refresh (force) stacks on top
        // of scenePhase foreground (force) stacks on top of HK observer wake
        // (force) → 9× parallel sync in the waterfall.
        if let existing = inFlightSyncTask {
            AppLogger.debug("Coalescing into in-flight health sync (force: \(force))", category: .health)
            await existing.value
            return
        }
        
        // Throttle: skip if synced recently and not forced.
        if !force {
            if let lastSync = lastSyncDate,
               Date().timeIntervalSince(lastSync) < Self.syncThrottleInterval {
                AppLogger.debug("Skipping full health sync - synced \(Int(Date().timeIntervalSince(lastSync)))s ago", category: .health)
                // Even when throttled, do a quick HealthKit workout sync to catch new external workouts
                // This is lightweight: just re-fetches workouts from HealthKit and persists any new ones
                if HealthKitService.shared.isAuthorized {
                    await syncHealthKitWorkoutsOnly()
                }
                return
            }
        }
        
        // Wrap the real work in a Task so concurrent callers can `await` it.
        // `self` is @MainActor, so the task body runs on main and hops off via
        // `Task.detached` internally (existing pattern preserved below).
        let task = Task { @MainActor in
            await performSyncAllHealthData(force: force)
        }
        inFlightSyncTask = task
        await task.value
        inFlightSyncTask = nil
    }
    
    /// Internal implementation — runs the actual multi-source sync. Always
    /// called through `syncAllHealthData(force:)` which coalesces + throttles.
    /// Split out so the public API can set up the `inFlightSyncTask` lifecycle.
    private func performSyncAllHealthData(force: Bool) async {
        isSyncing = true
        isLoading = true
        
        updateConnectedSources()
        
        // Capture main-actor state before hopping off thread
        let hkAuthorized = HealthKitService.shared.isAuthorized
        let fitbitConnected = FitbitService.shared.isConnected
        let stravaConnected = StravaService.shared.isConnected
        let whoopConnected = WhoopService.shared.isConnected
        let ouraConnected = OuraService.shared.isConnected
        
        // Run health source syncs off main thread to avoid blocking UI.
        // `force` MUST propagate downstream — each wearable service has its own
        // 5-min throttle, so without this, pull-to-refresh and scenePhase force
        // syncs silently no-op for WHOOP/Oura/Fitbit.
        await Task.detached(priority: .userInitiated) { [self] in
            await withTaskGroup(of: Void.self) { group in
                if hkAuthorized {
                    group.addTask { await self.syncHealthKitData() }
                }
                if fitbitConnected {
                    group.addTask { await self.syncFitbitData(force: force) }
                }
                if stravaConnected {
                    group.addTask { await self.syncStravaData(force: force) }
                }
                if whoopConnected {
                    group.addTask { await self.syncWhoopData(force: force) }
                }
                if ouraConnected {
                    group.addTask { await self.syncOuraData(force: force) }
                }
                group.addTask { await self.fetchWeeklyData() }
            }
        }.value
        
        // 🏆 CHALLENGES: Sync all sources to active challenges AFTER data is loaded
        // This ensures challenges get credit from HealthKit, Strava, Fitbit, etc.
        await syncAllSourcesToChallenges()

        // 🧠 READINESS: Recompute the unified Daily Readiness Score from the
        // freshly-synced wearable state and upsert today's row to
        // `daily_readiness_history`. Must run AFTER per-source syncs
        // because it reads the `@Published` state of each wearable
        // service. Force-propagated (Data invariant #4a) so pull-to-refresh
        // from the Dashboard actually re-blends today's score.
        await ReadinessService.shared.recompute(force: force)

        lastSyncDate = Date()
        isLoading = false
        isSyncing = false
        
        AppLogger.info("Full health data sync complete", category: .health)
    }
    
    // MARK: - Challenge Integration
    
    /// Sync all health data sources to active challenges (1v1, community, and private)
    private func syncAllSourcesToChallenges() async {
        let challengeService = ChallengeService.shared
        let communityService = CommunityChallengeService.shared
        let privateService = PrivateChallengeService.shared
        
        let has1v1 = !challengeService.activeChallenges.isEmpty
        let hasCommunity = !communityService.myChallenges.isEmpty
        let hasPrivate = !privateService.myChallenges.isEmpty
        
        // Skip if no active challenges at all
        guard has1v1 || hasCommunity || hasPrivate else {
            AppLogger.debug("No active challenges to sync", category: .health)
            return
        }
        
        AppLogger.debug("Syncing all health sources to \(challengeService.activeChallenges.count) 1v1 + \(communityService.myChallenges.count) community + \(privateService.myChallenges.count) private challenges", category: .health)
        
        // HealthKit already syncs via syncHealthKitData -> HealthKitService.syncAllData
        // But let's ensure comprehensive sync from all sources
        
        // Sync Fitbit workouts to challenges (if connected)
        if FitbitService.shared.isConnected {
            await syncFitbitToChallenges()
        }
        
        // Strava already syncs to challenges in syncStravaData -> syncActivities
        // But let's do a final recalculation to ensure accuracy
        if has1v1 {
            await challengeService.recalculateAllChallengeProgress()
        }
        
        // Push health data to community AND private challenges SEQUENTIALLY
        // ⚡️ SERIALIZED: Running these one-at-a-time prevents iOS from cancelling
        // concurrent Supabase RPC requests during startup (NSURLErrorDomain -999).
        // Each sync internally loops through challenges and fires RPCs; running both
        // in parallel doubles the concurrent connection count and overwhelms URLSession.
        if hasCommunity {
            await communityService.syncAllTrackingToCommunityChallenges()
        }
        if hasPrivate {
            await privateService.syncAllTrackingToPrivateChallenges()
        }
        
        AppLogger.info("All health sources synced to challenges (1v1 + community + private)", category: .health)
    }
    
    /// Sync Fitbit activities to challenges
    private func syncFitbitToChallenges() async {
        let fitbit = FitbitService.shared
        guard fitbit.isConnected else { return }
        
        // Sync steps from Fitbit
        if let summary = fitbit.todaySummary {
            // Steps challenge
            if summary.steps > 0 {
                await ChallengeService.shared.logProgressFromSource(
                    challengeType: "steps",
                    progressValue: summary.steps,
                    source: "fitbit"
                )
            }
            
            // Active minutes challenge
            let activeMinutes = (summary.fairlyActiveMinutes ?? 0) + (summary.veryActiveMinutes ?? 0)
            if activeMinutes > 0 {
                await ChallengeService.shared.logProgressFromSource(
                    challengeType: "active_minutes",
                    progressValue: activeMinutes,
                    source: "fitbit"
                )
            }
        }
        
        AppLogger.info("Fitbit activity data synced to challenges", category: .health)
    }
    
    // MARK: - Fitbit Data Sync
    
    private func syncFitbitData(force: Bool = false) async {
        guard FitbitService.shared.isConnected else { return }
        
        // Sync Fitbit's internal data first
        await FitbitService.shared.syncAllData(force: force)
        
        // Save daily summary to our database
        if let summary = FitbitService.shared.todaySummary {
            await saveDailyActivity(from: summary, source: "fitbit")
        }
        
        // Save sleep logs
        for sleep in FitbitService.shared.sleepData {
            await saveSleepLog(from: sleep, source: "fitbit")
        }
        
        // Fetch and save heart rate data
        if let heartRate = await FitbitService.shared.fetchHeartRateData() {
            await saveHeartRateData(from: heartRate, date: Date(), source: "fitbit")
        }
    }
    
    // MARK: - Strava Data Sync
    
    private func syncStravaData(force: Bool = false) async {
        guard StravaService.shared.isConnected else { return }
        
        // 🔄 AUTO-SYNC: Fetch latest activities from Strava API
        // This pulls any new runs/rides since last sync. The `force` flag
        // is forwarded from `syncAllHealthData(force:)` so the explicit
        // foreground sync (Sprint 2026-04-25 widget-not-showing fix)
        // bypasses the 5-min throttle.
        AppLogger.debug("Auto-syncing activities from Strava (force: \(force))", category: .health)
        await StravaService.shared.syncActivities(daysBack: 7, force: force)
        
        // Now aggregate the synced activities for daily summary
        let calendar = Calendar.current
        let today = Date()
        
        // Calculate today's Strava contribution
        let todayActivities = StravaService.shared.recentActivities.filter {
            calendar.isDate($0.startDate, inSameDayAs: today)
        }
        
        if !todayActivities.isEmpty {
            let totalCalories = todayActivities.reduce(0) { $0 + ($1.calories ?? 0) }
            let totalDistance = todayActivities.reduce(0.0) { $0 + $1.distance }
            let totalActiveMinutes = todayActivities.reduce(0) { $0 + ($1.movingTime / 60) }
            
            // Update daily activity with Strava data
            await updateDailyActivityFromStrava(
                date: today,
                calories: totalCalories,
                distance: totalDistance,
                activeMinutes: totalActiveMinutes
            )
            
            AppLogger.info("Strava synced \(todayActivities.count) activities from today", category: .health)
        }
    }
    
    // MARK: - WHOOP Data Sync
    
    private func syncWhoopData(force: Bool = false) async {
        guard WhoopService.shared.isConnected else { return }
        
        await WhoopService.shared.syncAllData(force: force)
        
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return }

        let dateFmt = Self.dayFormatter
        let isoFmt = Self.iso8601Fractional

        // Save recovery + strain data to whoop_recovery_data
        for recovery in WhoopService.shared.recentRecoveries {
            guard recovery.scoreState == "SCORED", let score = recovery.score else { continue }
            
            let matchingCycle = WhoopService.shared.recentCycles.first { $0.id == recovery.cycleId }
            let cycleScore = matchingCycle?.score
            
            let dateStr: String
            if let cycleStart = matchingCycle?.start, let parsed = isoFmt.date(from: cycleStart) {
                dateStr = dateFmt.string(from: parsed)
            } else {
                dateStr = dateFmt.string(from: Date())
            }
            
            let insert = WhoopRecoveryInsert(
                userId: userId.uuidString,
                date: dateStr,
                cycleId: Int(recovery.cycleId),
                recoveryScore: score.recoveryScore,
                hrvRmssdMilli: score.hrvRmssdMilli,
                restingHeartRate: score.restingHeartRate,
                spo2Percentage: score.spo2Percentage,
                skinTempCelsius: score.skinTempCelsius,
                strain: cycleScore?.strain,
                kilojoules: cycleScore?.kilojoule,
                avgHeartRate: cycleScore?.averageHeartRate,
                maxHeartRate: cycleScore?.maxHeartRate
            )
            
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("whoop_recovery_data")
                    .upsert(insert, onConflict: "user_id,date")
                    .execute()
            } catch {
                AppLogger.warning("[WHOOP] Failed to save recovery for \(dateStr): \(error)", category: .health)
            }
        }
        
        // Save WHOOP sleep data to sleep_logs with enhanced fields
        for sleep in WhoopService.shared.recentSleeps {
            guard !sleep.nap, sleep.scoreState == "SCORED", let score = sleep.score else { continue }
            
            guard let startStr = sleep.start, let parsed = isoFmt.date(from: startStr) else { continue }
            let sleepDate = dateFmt.string(from: parsed)
            
            let totalSleepMilli = (score.stageSummary?.totalLightSleepTimeMilli ?? 0)
                + (score.stageSummary?.totalSlowWaveSleepTimeMilli ?? 0)
                + (score.stageSummary?.totalRemSleepTimeMilli ?? 0)
            let totalSleepHours = Double(totalSleepMilli) / 3_600_000.0
            
            let insert = WhoopSleepInsert(
                userId: userId.uuidString,
                date: sleepDate,
                totalSleepHours: totalSleepHours,
                source: "whoop",
                externalId: sleep.id,
                sleepPerformancePct: score.sleepPerformancePercentage,
                sleepConsistencyPct: score.sleepConsistencyPercentage,
                sleepEfficiencyPct: score.sleepEfficiencyPercentage,
                respiratoryRate: score.respiratoryRate,
                disturbanceCount: score.stageSummary?.disturbanceCount,
                sleepDebtMilli: score.sleepNeeded?.needFromSleepDebtMilli ?? 0,
                lightSleepMilli: score.stageSummary?.totalLightSleepTimeMilli ?? 0,
                deepSleepMilli: score.stageSummary?.totalSlowWaveSleepTimeMilli ?? 0,
                remSleepMilli: score.stageSummary?.totalRemSleepTimeMilli ?? 0,
                awakeMilli: score.stageSummary?.totalAwakeTimeMilli ?? 0
            )
            
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("sleep_logs")
                    .upsert(insert, onConflict: "user_id,date,source")
                    .execute()
            } catch {
                AppLogger.warning("[WHOOP] Failed to save sleep for \(sleepDate): \(error)", category: .health)
            }
        }
        
        // Save WHOOP workouts to cardio_workouts (using existing FitbitCardioWorkoutInsert).
        //
        // Dedup policy (see Support doc "WHOOP duplicate workout rows"):
        //   WHOOP's API can return multiple `workout` records for a single
        //   physical session (e.g. an auto-detected generic "Activity" with
        //   sport_name=nil alongside the user-logged specific sport). Our
        //   legacy guard only deduped on `(source='whoop', external_id)`,
        //   so each returned id produced its own row. We now also reject any
        //   incoming WHOOP workout whose time window overlaps ≥50% with an
        //   existing WHOOP-origin row, keeping the higher-quality row.
        var savedWorkouts = 0
        var skippedAsDuplicate = 0
        for workout in WhoopService.shared.recentWorkouts {
            guard workout.scoreState == "SCORED" else { continue }
            
            let startDate = workout.start.flatMap { isoFmt.date(from: $0) } ?? Date()
            let endDate = workout.end.flatMap { isoFmt.date(from: $0) } ?? startDate
            let durationSeconds = Int(endDate.timeIntervalSince(startDate))
            
            let kilojoules = workout.score?.kilojoule ?? 0
            let calories = kilojoules / 4.184
            
            let activityType = mapWhoopSportToActivityType(sportId: workout.sportId, sportName: workout.sportName)
            let insert = FitbitCardioWorkoutInsert(
                userId: userId.uuidString,
                activityType: activityType,
                workoutName: workout.sportName ?? "WHOOP Workout",
                goalType: "open_goal",
                goalAchieved: true,
                durationSeconds: durationSeconds,
                distanceMeters: workout.score?.distanceMeter ?? 0,
                caloriesBurned: calories,
                averageSpeed: nil,
                maxSpeed: nil,
                averageHeartRate: workout.score?.averageHeartRate,
                maxHeartRate: workout.score?.maxHeartRate,
                totalElevationGain: workout.score?.altitudeGainMeter,
                startedAt: Self.iso8601.string(from: startDate),
                completedAt: Self.iso8601.string(from: endDate),
                source: "whoop",
                externalId: workout.id,
                externalUrl: nil
            )
            
            do {
                // 1. Exact external_id match (same WHOOP workout, already synced).
                let exact: [CardioWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                    .from("cardio_workouts")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .eq("source", value: "whoop")
                    .eq("external_id", value: workout.id)
                    .execute()
                    .value
                if !exact.isEmpty { continue }

                // 2. Time-overlap match against any WHOOP-origin row (either
                //    from a prior OAuth insert with a different external_id,
                //    or an HK-imported row with origin_app='whoop'). We pull
                //    candidates by fetching rows that START anywhere in a
                //    ±2h window around the incoming workout — overlap is
                //    computed in Swift because Supabase doesn't expose a
                //    range-overlap operator through the REST client.
                let windowStart = startDate.addingTimeInterval(-2 * 3600)
                let windowEnd = endDate.addingTimeInterval(2 * 3600)
                let candidates: [CardioWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                    .from("cardio_workouts")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .gte("started_at", value: Self.iso8601.string(from: windowStart))
                    .lte("started_at", value: Self.iso8601.string(from: windowEnd))
                    .execute()
                    .value

                let incomingQuality = cardioQualityScore(
                    activityType: activityType,
                    durationSeconds: durationSeconds,
                    caloriesBurned: calories,
                    distanceMeters: workout.score?.distanceMeter ?? 0,
                    averageHeartRate: workout.score?.averageHeartRate
                )

                var overlapLoserIds: [String] = []
                var shouldSkip = false
                for candidate in candidates where candidate.resolvedOrigin == .whoop {
                    guard let candidateStart = isoFmt.date(from: candidate.startedAt),
                          let candidateEnd = isoFmt.date(from: candidate.completedAt) else { continue }
                    let overlap = timeRangeOverlapFraction(
                        aStart: startDate, aEnd: endDate,
                        bStart: candidateStart, bEnd: candidateEnd
                    )
                    if overlap < 0.5 { continue }

                    let candidateQuality = cardioQualityScore(
                        activityType: candidate.activityType,
                        durationSeconds: candidate.durationSeconds,
                        caloriesBurned: candidate.caloriesBurned,
                        distanceMeters: candidate.distanceMeters,
                        averageHeartRate: candidate.averageHeartRate
                    )
                    if candidateQuality >= incomingQuality {
                        shouldSkip = true
                    } else {
                        overlapLoserIds.append(candidate.id)
                    }
                }

                if shouldSkip {
                    skippedAsDuplicate += 1
                    continue
                }

                // Delete any lower-quality overlapping rows before inserting
                // the richer incoming one, so the history list only shows a
                // single row for this physical session.
                for loserId in overlapLoserIds {
                    do {
                        try await SupabaseManager.shared.supabaseClient
                            .from("cardio_workouts")
                            .delete()
                            .eq("id", value: loserId)
                            .execute()
                        AppLogger.info("[WHOOP] Replaced lower-quality duplicate row \(loserId) with WHOOP id=\(workout.id)", category: .health)
                    } catch {
                        AppLogger.warning("[WHOOP] Failed to delete duplicate row \(loserId): \(error.localizedDescription)", category: .health)
                    }
                }

                try await SupabaseManager.shared.supabaseClient
                    .from("cardio_workouts")
                    .insert(insert)
                    .execute()
                savedWorkouts += 1
            } catch {
                AppLogger.warning("[WHOOP] Failed to save workout \(workout.id): \(error)", category: .health)
            }
        }
        
        if savedWorkouts > 0 {
            await MainActor.run {
                NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
            }
        }
        
        if skippedAsDuplicate > 0 {
            AppLogger.info("[WHOOP] Skipped \(skippedAsDuplicate) overlapping duplicate workout records", category: .health)
        }
        AppLogger.info("[WHOOP] HealthDataService sync complete", category: .health)
    }

    // MARK: - Cardio dedup helpers

    /// Fraction of the shorter of [aStart,aEnd] and [bStart,bEnd] that is
    /// covered by the other range. Returns 0 when the ranges are disjoint.
    /// Using the shorter-side denominator means a fully-contained short
    /// workout inside a longer one still scores 1.0 and is treated as a
    /// duplicate of the longer record.
    private func timeRangeOverlapFraction(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Double {
        let overlapStart = max(aStart, bStart)
        let overlapEnd = min(aEnd, bEnd)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        if overlap <= 0 { return 0 }
        let aLen = max(1, aEnd.timeIntervalSince(aStart))
        let bLen = max(1, bEnd.timeIntervalSince(bStart))
        let shorter = min(aLen, bLen)
        return overlap / shorter
    }

    /// Rough "richness" score used to decide which of two overlapping cardio
    /// rows should win. Higher = more descriptive / more data.
    private func cardioQualityScore(activityType: String, durationSeconds: Int, caloriesBurned: Double, distanceMeters: Double, averageHeartRate: Int?) -> Int {
        var score = 0
        let generic: Set<String> = ["other", "workout", "unknown", ""]
        if !generic.contains(activityType.lowercased()) { score += 10 }
        if let hr = averageHeartRate, hr > 0 { score += 3 }
        if distanceMeters > 0 { score += 2 }
        if caloriesBurned > 0 { score += 1 }
        if durationSeconds > 0 { score += 1 }
        return score
    }
    
    // MARK: - WHOOP Insert Models

    private struct WhoopRecoveryInsert: Codable {
        let userId: String
        let date: String
        let cycleId: Int?
        let recoveryScore: Int?
        let hrvRmssdMilli: Double?
        let restingHeartRate: Int?
        let spo2Percentage: Double?
        let skinTempCelsius: Double?
        let strain: Double?
        let kilojoules: Double?
        let avgHeartRate: Int?
        let maxHeartRate: Int?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case date
            case cycleId = "cycle_id"
            case recoveryScore = "recovery_score"
            case hrvRmssdMilli = "hrv_rmssd_milli"
            case restingHeartRate = "resting_heart_rate"
            case spo2Percentage = "spo2_percentage"
            case skinTempCelsius = "skin_temp_celsius"
            case strain, kilojoules
            case avgHeartRate = "avg_heart_rate"
            case maxHeartRate = "max_heart_rate"
        }
    }

    private struct WhoopSleepInsert: Codable {
        let userId: String
        let date: String
        let totalSleepHours: Double
        let source: String
        let externalId: String
        let sleepPerformancePct: Double?
        let sleepConsistencyPct: Double?
        let sleepEfficiencyPct: Double?
        let respiratoryRate: Double?
        let disturbanceCount: Int?
        let sleepDebtMilli: Int
        let lightSleepMilli: Int
        let deepSleepMilli: Int
        let remSleepMilli: Int
        let awakeMilli: Int

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case date
            case totalSleepHours = "total_sleep_hours"
            case source
            case externalId = "external_id"
            case sleepPerformancePct = "sleep_performance_pct"
            case sleepConsistencyPct = "sleep_consistency_pct"
            case sleepEfficiencyPct = "sleep_efficiency_pct"
            case respiratoryRate = "respiratory_rate"
            case disturbanceCount = "disturbance_count"
            case sleepDebtMilli = "sleep_debt_milli"
            case lightSleepMilli = "light_sleep_milli"
            case deepSleepMilli = "deep_sleep_milli"
            case remSleepMilli = "rem_sleep_milli"
            case awakeMilli = "awake_milli"
        }
    }

    /// Map a WHOOP workout to one of our canonical `activity_type` keys.
    ///
    /// Prefers the numeric `sport_id` (stable across locales) and falls back
    /// to fuzzy matching on `sport_name`. Covers the common WHOOP sport ids
    /// published at https://developer.whoop.com/docs/developing/sport-ids —
    /// any unmapped id still resolves to "other" but the richer auto-detected
    /// workout will usually take precedence over the generic record via the
    /// time-overlap dedup in `syncWhoopData`.
    private func mapWhoopSportToActivityType(sportId: Int?, sportName: String?) -> String {
        // 1. Sport-id first (deterministic). The ids below are stable
        //    across WHOOP API versions for the sports we already display.
        if let id = sportId {
            switch id {
            case 0:   return "outdoor_run"             // Running
            case 1:   return "outdoor_cycle"            // Cycling
            case 16:  return "swimming"                 // Swim
            case 28:  return "hiit"                     // HIIT / Functional fitness
            case 43:  return "outdoor_cycle"            // Mountain Biking
            case 44:  return "walk"                     // Hiking / Rucking
            case 45:  return "strength_training"        // Weightlifting
            case 48:  return "walk"                     // Walking
            case 59:  return "rowing"                   // Rowing
            case 63:  return "elliptical"               // Elliptical
            case 65:  return "treadmill"                // Treadmill (WHOOP sport_id)
            case 66:  return "yoga"                     // Yoga
            case 71:  return "yoga"                     // Pilates (grouped with yoga)
            case 123: return "hiit"                     // HIIT
            case 125: return "yoga"                     // Meditation — grouped for display
            case 126: return "strength_training"        // Powerlifting
            case 127: return "hiit"                     // Rock Climbing — default to hiit bucket
            case 228: return "strength_training"        // Strength Trainer
            case 230: return "yoga"                     // Pilates
            default: break
            }
        }

        // 2. Fallback: fuzzy match on sport_name.
        guard let sport = sportName?.lowercased() else { return "other" }
        if sport.contains("run") { return sport.contains("treadmill") ? "treadmill" : "outdoor_run" }
        if sport.contains("treadmill") { return "treadmill" }
        if sport.contains("cycling") || sport.contains("bike") || sport.contains("cycle") { return "outdoor_cycle" }
        if sport.contains("swim") { return "swimming" }
        if sport.contains("walk") || sport.contains("hike") || sport.contains("ruck") { return "walk" }
        if sport.contains("yoga") || sport.contains("pilates") || sport.contains("meditation") { return "yoga" }
        if sport.contains("row") { return "rowing" }
        if sport.contains("strength") || sport.contains("weight") || sport.contains("lift") || sport.contains("powerlifting") { return "strength_training" }
        if sport.contains("hiit") || sport.contains("crossfit") || sport.contains("functional") || sport.contains("circuit") { return "hiit" }
        if sport.contains("elliptical") { return "elliptical" }
        if sport.contains("stair") { return "stair_climber" }
        return "other"
    }
    
    // MARK: - Oura Data Sync

    private func syncOuraData(force: Bool = false) async {
        guard OuraService.shared.isConnected else { return }

        await OuraService.shared.syncAllData(force: force)

        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return }

        let dateFmt = Self.dayFormatter

        // Save readiness + activity data to oura_readiness_data
        for readiness in OuraService.shared.recentReadiness {
            let matchingActivity = OuraService.shared.recentActivity.first { $0.day == readiness.day }
            let matchingSpo2 = OuraService.shared.recentSleeps.last(where: { $0.day == readiness.day })

            let insert = OuraReadinessInsert(
                userId: userId.uuidString,
                date: readiness.day,
                readinessScore: readiness.score,
                temperatureDeviation: readiness.temperatureDeviation,
                temperatureTrendDeviation: readiness.temperatureTrendDeviation,
                hrvBalance: readiness.contributors?.hrvBalance,
                restingHeartRate: readiness.contributors?.restingHeartRate,
                activityScore: matchingActivity?.score,
                steps: matchingActivity?.steps,
                activeCalories: matchingActivity?.activeCalories,
                totalCalories: matchingActivity?.totalCalories,
                equivalentWalkingDistance: matchingActivity?.equivalentWalkingDistance,
                spo2Percentage: nil,
                breathingDisturbanceIndex: nil
            )

            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("oura_readiness_data")
                    .upsert(insert, onConflict: "user_id,date")
                    .execute()
            } catch {
                AppLogger.warning("[OURA] Failed to save readiness for \(readiness.day): \(error)", category: .health)
            }
        }

        // Backfill SpO2 into oura_readiness_data where available
        if let spo2 = OuraService.shared.todaySpo2,
           let avg = spo2.spo2Percentage?.average {
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("oura_readiness_data")
                    .update(["spo2_percentage": avg, "breathing_disturbance_index": spo2.breathingDisturbanceIndex ?? 0.0])
                    .eq("user_id", value: userId.uuidString)
                    .eq("date", value: spo2.day)
                    .execute()
            } catch {
                AppLogger.debug("[OURA] SpO2 backfill skipped: \(error)", category: .health)
            }
        }

        // Save Oura sleep data to sleep_logs (reuses WHOOP sleep insert shape)
        for sleep in OuraService.shared.recentSleeps {
            guard sleep.type == "long_sleep" else { continue }

            let totalSleepSeconds = sleep.totalSleepDuration ?? 0
            let totalSleepHours = Double(totalSleepSeconds) / 3600.0

            let insert = WhoopSleepInsert(
                userId: userId.uuidString,
                date: sleep.day,
                totalSleepHours: totalSleepHours,
                source: "oura",
                externalId: sleep.id ?? UUID().uuidString,
                sleepPerformancePct: nil,
                sleepConsistencyPct: nil,
                sleepEfficiencyPct: sleep.efficiency.map { Double($0) },
                respiratoryRate: sleep.averageBreath,
                disturbanceCount: sleep.restlessPeriods,
                sleepDebtMilli: 0,
                lightSleepMilli: (sleep.lightSleepDuration ?? 0) * 1000,
                deepSleepMilli: (sleep.deepSleepDuration ?? 0) * 1000,
                remSleepMilli: (sleep.remSleepDuration ?? 0) * 1000,
                awakeMilli: (sleep.awakeTime ?? 0) * 1000
            )

            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("sleep_logs")
                    .upsert(insert, onConflict: "user_id,date,source")
                    .execute()
            } catch {
                AppLogger.warning("[OURA] Failed to save sleep for \(sleep.day): \(error)", category: .health)
            }
        }

        // Save Oura workouts to cardio_workouts
        var savedWorkouts = 0
        for workout in OuraService.shared.recentWorkouts {
            guard let workoutId = workout.id else { continue }

            let startDate: Date
            if let startStr = workout.startDatetime {
                startDate = Self.iso8601.date(from: startStr) ?? Date()
            } else {
                startDate = Date()
            }
            let endDate: Date
            if let endStr = workout.endDatetime {
                endDate = Self.iso8601.date(from: endStr) ?? startDate
            } else {
                endDate = startDate
            }
            let durationSeconds = Int(endDate.timeIntervalSince(startDate))

            let insert = FitbitCardioWorkoutInsert(
                userId: userId.uuidString,
                activityType: mapOuraActivityToType(workout.activity),
                workoutName: workout.label ?? workout.activity ?? "Oura Workout",
                goalType: "open_goal",
                goalAchieved: true,
                durationSeconds: durationSeconds,
                distanceMeters: workout.distance ?? 0,
                caloriesBurned: workout.calories ?? 0,
                averageSpeed: nil,
                maxSpeed: nil,
                averageHeartRate: nil,
                maxHeartRate: nil,
                totalElevationGain: nil,
                startedAt: Self.iso8601.string(from: startDate),
                completedAt: Self.iso8601.string(from: endDate),
                source: "oura",
                externalId: workoutId,
                externalUrl: nil
            )

            do {
                let existing: [CardioWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                    .from("cardio_workouts")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .eq("source", value: "oura")
                    .eq("external_id", value: workoutId)
                    .execute()
                    .value

                if existing.isEmpty {
                    try await SupabaseManager.shared.supabaseClient
                        .from("cardio_workouts")
                        .insert(insert)
                        .execute()
                    savedWorkouts += 1
                }
            } catch {
                AppLogger.warning("[OURA] Failed to save workout \(workoutId): \(error)", category: .health)
            }
        }

        if savedWorkouts > 0 {
            await MainActor.run {
                NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
            }
        }

        AppLogger.info("[OURA] HealthDataService sync complete", category: .health)
    }

    // MARK: - Oura Insert Models

    private struct OuraReadinessInsert: Codable {
        let userId: String
        let date: String
        let readinessScore: Int?
        let temperatureDeviation: Double?
        let temperatureTrendDeviation: Double?
        let hrvBalance: Int?
        let restingHeartRate: Int?
        let activityScore: Int?
        let steps: Int?
        let activeCalories: Int?
        let totalCalories: Int?
        let equivalentWalkingDistance: Int?
        let spo2Percentage: Double?
        let breathingDisturbanceIndex: Double?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case date
            case readinessScore = "readiness_score"
            case temperatureDeviation = "temperature_deviation"
            case temperatureTrendDeviation = "temperature_trend_deviation"
            case hrvBalance = "hrv_balance"
            case restingHeartRate = "resting_heart_rate"
            case activityScore = "activity_score"
            case steps
            case activeCalories = "active_calories"
            case totalCalories = "total_calories"
            case equivalentWalkingDistance = "equivalent_walking_distance"
            case spo2Percentage = "spo2_percentage"
            case breathingDisturbanceIndex = "breathing_disturbance_index"
        }
    }

    private func mapOuraActivityToType(_ activity: String?) -> String {
        guard let activity = activity?.lowercased() else { return "other" }
        if activity.contains("run") { return activity.contains("treadmill") ? "treadmill" : "outdoor_run" }
        if activity.contains("cycling") || activity.contains("bike") { return "outdoor_cycle" }
        if activity.contains("swim") { return "swimming" }
        if activity.contains("walk") || activity.contains("hike") { return "walk" }
        if activity.contains("yoga") || activity.contains("pilates") { return "yoga" }
        if activity.contains("rowing") { return "rowing" }
        if activity.contains("strength") || activity.contains("weight") { return "strength_training" }
        if activity.contains("hiit") || activity.contains("crossfit") { return "hiit" }
        if activity.contains("elliptical") { return "elliptical" }
        return "other"
    }

    // MARK: - HealthKit Data Sync (Nike Run Club, Apple Watch, etc.)
    
    private func syncHealthKitData() async {
        guard HealthKitService.shared.isAuthorized else { return }
        
        // Sync HealthKit's internal data
        await HealthKitService.shared.syncAllData()
        
        // Persist the in-memory HealthKit data to Supabase
        await persistHealthKitDataToSupabase()
    }
    
    /// Lightweight sync: only re-fetch HealthKit workouts and persist new ones.
    /// Called when the full sync is throttled but we still want to catch new external workouts
    /// (e.g., user just completed a walk on Apple Watch and opens the app).
    private func syncHealthKitWorkoutsOnly() async {
        guard HealthKitService.shared.isAuthorized else { return }
        
        AppLogger.debug("Quick workout-only sync (full sync throttled)", category: .health)
        
        // Force HealthKit to re-fetch recent workouts (bypasses HealthKitService throttle)
        await HealthKitService.shared.syncAllData(force: true)
        
        // Persist any new workouts to Supabase
        await persistHealthKitDataToSupabase()
    }
    
    private var lastPersistDate: Date?
    private static let persistThrottleInterval: TimeInterval = 30
    
    /// Persist current in-memory HealthKit data to Supabase.
    /// Call this after HealthKitService has synced from the HK API.
    /// Safe to call from anywhere – does NOT re-fetch from HealthKit.
    /// Throttled to once per 30s to prevent redundant writes during startup.
    func persistHealthKitDataToSupabase() async {
        let healthKit = HealthKitService.shared
        guard healthKit.isAuthorized else { return }
        
        if let last = lastPersistDate,
           Date().timeIntervalSince(last) < Self.persistThrottleInterval {
            AppLogger.debug("Skipping HealthKit persistence — persisted \(Int(Date().timeIntervalSince(last)))s ago", category: .health)
            return
        }
        lastPersistDate = Date()
        
        let calendar = Calendar.current
        let today = Date()
        
        // Save today's activity from HealthKit
        await saveDailyActivityFromHealthKit(
            date: today,
            steps: healthKit.todaySteps,
            calories: healthKit.todayCalories,
            distance: healthKit.todayDistance,
            restingHR: healthKit.restingHeartRate
        )
        
        // Save workouts from every third-party app that wrote to HealthKit
        // (Strava, Nike Run Club, Peloton, Garmin, Zwift, Apple Watch, ...).
        //
        // Priority rules:
        //   - Fit33's own round-trip writes are always skipped.
        //   - If the user has a first-party OAuth integration connected for
        //     the app that authored this workout (Strava/Fitbit/WHOOP/Oura),
        //     SKIP the HealthKit copy — that integration will write a richer
        //     row directly, and saving both would produce duplicates.
        var savedCount = 0
        var skippedByOAuth = 0
        for workout in healthKit.recentWorkouts {
            let origin = workout.origin
            if origin == .fit33 { continue }
            if isOAuthConnected(for: origin) {
                skippedByOAuth += 1
                continue
            }

            // Only save workouts from today/recent (7 days)
            if calendar.isDate(workout.startDate, inSameDayAs: today) ||
               workout.startDate > calendar.date(byAdding: .day, value: -7, to: today)! {
                await saveHealthKitWorkout(workout)
                savedCount += 1
            }
        }
        if skippedByOAuth > 0 {
            AppLogger.debug("Skipped \(skippedByOAuth) HealthKit workouts owned by connected OAuth integrations", category: .health)
        }
        
        // Save sleep data if available
        if let sleepHours = healthKit.lastNightSleep, sleepHours > 0 {
            await saveSleepFromHealthKit(hours: sleepHours)
        }
        
        AppLogger.info("HealthKit data persisted to Supabase (steps: \(healthKit.todaySteps), workouts saved: \(savedCount)/\(healthKit.recentWorkouts.count))", category: .health)
        
        // Notify dashboard to reload cardio workouts so external workouts appear in Recent Activity
        if savedCount > 0 {
            NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
        }
    }
    
    private func saveDailyActivityFromHealthKit(date: Date, steps: Int, calories: Int, distance: Double, restingHR: Int?) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        let insert = DailyActivityInsert(
            userId: userId.uuidString,
            date: Self.iso8601.string(from: date),
            steps: steps,
            caloriesBurned: calories,
            caloriesActive: calories,
            distanceMeters: distance,
            restingHeartRate: restingHR,
            sources: ["healthkit"]
        )
        
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("daily_activity_summary")
                    .upsert(insert, onConflict: "user_id,date")
                    .execute()
                
                AppLogger.info("Saved daily activity from HealthKit", category: .health)
                return
            } catch {
                guard !Task.isCancelled else { return }
                if NetworkErrorClassifier.isTransient(error) && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    AppLogger.warning("saveDailyActivityFromHealthKit transient failure (attempt \(attempt)/\(maxRetries)), retrying...", category: .health)
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    NetworkErrorClassifier.log(error, context: "Failed to save HealthKit activity", category: .health)
                    return
                }
            }
        }
    }
    
    private func saveHealthKitWorkout(_ workout: HealthKitWorkout) async {
        // Data Invariant #26: every Supabase write guarded by isAuthenticated.
        // Previously only guarded by `currentUser?.id` — that survives into a
        // stale-JWT state and fires 42501 RLS errors that land in
        // bug_intelligence_fingerprints.
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.info(
                "[HEALTH] Skipping saveHealthKitWorkout — not authenticated",
                category: .health,
                context: DiagnosticContext(op: "cardio.save", endpoint: "cardio_workouts")
            )
            return
        }

        let workoutType: String
        switch workout.workoutType {
        case .running: workoutType = "Run"
        case .cycling: workoutType = "Cycling"
        case .walking: workoutType = "Walk"
        case .swimming: workoutType = "Swimming"
        case .hiking: workoutType = "Hike"
        case .elliptical: workoutType = "Elliptical"
        case .rowing: workoutType = "Rowing"
        case .yoga: workoutType = "Yoga"
        case .dance: workoutType = "Dance"
        case .highIntensityIntervalTraining: workoutType = "HIIT"
        case .coreTraining: workoutType = "Core Training"
        case .pilates: workoutType = "Pilates"
        case .stairClimbing: workoutType = "Stair Climbing"
        case .crossTraining: workoutType = "Cross Training"
        case .functionalStrengthTraining, .traditionalStrengthTraining: workoutType = "Strength Training"
        case .flexibility: workoutType = "Flexibility"
        case .cooldown: workoutType = "Cooldown"
        default: workoutType = workout.workoutName
        }
        
        // Resolve canonical origin (Strava / Nike / Peloton / Garmin / ...)
        // from the HKWorkout's sourceBundle + sourceName. This is what
        // drives both the persisted `origin_app` column and the display
        // name prepended to `workout_name`.
        let origin = workout.origin
        let displayName: String = (origin == .unknown) ? workout.sourceName : origin.displayName

        let insert = HealthKitWorkoutInsert(
            userId: userId.uuidString,
            activityType: workoutType,
            workoutName: "\(displayName) \(workoutType)",
            goalType: "open_goal",
            goalAchieved: true,
            durationSeconds: Int(workout.duration),
            distanceMeters: workout.distance ?? 0,
            caloriesBurned: Int(workout.calories ?? 0),
            averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.maxHeartRate,
            startedAt: Self.iso8601.string(from: workout.startDate),
            completedAt: Self.iso8601.string(from: workout.endDate),
            source: "healthkit",
            externalId: workout.id.uuidString,
            originApp: (origin == .unknown) ? nil : origin.rawValue
        )
        
        // One-shot retry on transient failures (timeout / network / 5xx).
        // Dev-session logs observed `The request timed out` drop an entire
        // WHOOP strength import, which then hides the wearable-insights card
        // on the matching Fit33 workout (see `WorkoutWearableMerger`). A
        // single 2s-delay retry recovers the common iOS background-sync
        // network blip without impacting duplicate/conflict behaviour (that
        // short-circuits before the retry).
        await upsertCardioWorkoutWithRetry(
            insert: insert,
            displayName: displayName,
            workoutType: workoutType,
            origin: origin,
            durationMinutes: Int(workout.duration / 60)
        )
    }

    /// Retries `cardio_workouts` upsert once on transient failure. Duplicate
    /// / conflict errors are swallowed silently (same contract as the
    /// pre-retry implementation — ON CONFLICT is expected when the row
    /// already exists from a prior sync).
    private func upsertCardioWorkoutWithRetry(
        insert: HealthKitWorkoutInsert,
        displayName: String,
        workoutType: String,
        origin: WorkoutOrigin,
        durationMinutes: Int
    ) async {
        let label = "\(displayName) \(workoutType)"
        let originTag = "[\(origin.rawValue)]"

        for attempt in 1...2 {
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("cardio_workouts")
                    .upsert(insert, onConflict: "user_id,source,external_id")
                    .execute()
                if attempt == 1 {
                    AppLogger.info("Saved HealthKit workout: \(label) \(originTag) (\(durationMinutes)m)", category: .health)
                } else {
                    AppLogger.info("Saved HealthKit workout on retry: \(label) \(originTag) (\(durationMinutes)m)", category: .health)
                }
                return
            } catch {
                let message = error.localizedDescription.lowercased()

                // Duplicate row — already stored, no retry needed.
                if message.contains("duplicate") || message.contains("conflict") {
                    return
                }

                // Transient conditions worth a single retry. Anything else
                // (auth, RLS, 4xx) will keep failing — log and bail.
                let isTransient = message.contains("timed out")
                    || message.contains("timeout")
                    || message.contains("network connection")
                    || message.contains("offline")
                    || message.contains("temporarily")
                    || message.contains("503")
                    || message.contains("502")
                    || message.contains("500")

                if attempt == 1 && isTransient {
                    AppLogger.warning("HealthKit workout save transient failure, retrying: \(label): \(error.localizedDescription)", category: .health)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }

                NetworkErrorClassifier.log(
                    error,
                    context: "Failed to save HealthKit workout (\(label))",
                    category: .health
                )
                return
            }
        }
    }

    // MARK: - Origin/OAuth helpers

    /// Returns true when the user has a first-party OAuth integration
    /// connected that owns workouts from this origin. Used by the HealthKit
    /// sync loop to avoid saving a duplicate HealthKit-imported copy when
    /// the richer OAuth feed is already writing the row.
    private func isOAuthConnected(for origin: WorkoutOrigin) -> Bool {
        switch origin {
        case .strava: return StravaService.shared.isConnected
        case .fitbit: return FitbitService.shared.isConnected
        case .whoop:  return WhoopService.shared.isConnected
        case .oura:   return OuraService.shared.isConnected
        default:      return false
        }
    }

    /// Remove any HealthKit-imported cardio_workouts rows whose true origin
    /// matches the given key. Called by OAuth services (Strava/Fitbit/
    /// WHOOP/Oura) the moment the user connects, so the cleaner OAuth feed
    /// becomes the single source of truth and we never display a duplicate.
    ///
    /// Generic by design: pass any WorkoutOrigin rawValue — the function
    /// just deletes `source='healthkit' AND origin_app=<key>` for the
    /// current user. Adding OAuth for Garmin/Peloton/etc. later needs no
    /// changes here.
    func removeHealthKitDuplicates(for origin: WorkoutOrigin) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        guard SupabaseManager.shared.isAuthenticated else { return }

        do {
            try await SupabaseManager.shared.supabaseClient
                .from("cardio_workouts")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("source", value: "healthkit")
                .eq("origin_app", value: origin.rawValue)
                .execute()
            AppLogger.info("[ORIGIN] Removed HealthKit-imported \(origin.rawValue) rows after OAuth connect", category: .health)
            NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
        } catch {
            AppLogger.warning("[ORIGIN] Failed to remove HealthKit \(origin.rawValue) duplicates: \(error.localizedDescription)", category: .health)
        }
    }
    
    private func saveSleepFromHealthKit(hours: Double) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.info(
                "[HEALTH] Skipping saveSleepFromHealthKit — not authenticated",
                category: .health,
                context: DiagnosticContext(op: "healthkit.sleep_save", endpoint: "sleep_logs")
            )
            return
        }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dateStr = Self.iso8601.string(from: yesterday)
        
        let insert = HealthKitSleepInsert(
            userId: userId.uuidString,
            dateOfSleep: dateStr,
            durationMs: Int(hours * 3600 * 1000),
            minutesAsleep: Int(hours * 60),
            source: "healthkit"
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("sleep_logs")
                .upsert(insert)
                .execute()
        } catch {
            NetworkErrorClassifier.log(error, context: "Failed to save HealthKit sleep", category: .health)
        }
    }
    
    // MARK: - Database Operations
    
    private func saveDailyActivity(from fitbitSummary: FitbitDailySummary, source: String) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.info(
                "[HEALTH] Skipping saveDailyActivity(fitbit) — not authenticated",
                category: .health,
                context: DiagnosticContext(op: "daily_activity.save", endpoint: "daily_activity_summary")
            )
            return
        }

        let insert = DailyActivityInsert(
            userId: userId.uuidString,
            date: Self.iso8601.string(from: Date()),
            steps: fitbitSummary.steps,
            caloriesBurned: fitbitSummary.caloriesOut,
            caloriesActive: fitbitSummary.activityCalories ?? 0,
            sedentaryMinutes: fitbitSummary.sedentaryMinutes ?? 0,
            lightlyActiveMinutes: fitbitSummary.lightlyActiveMinutes ?? 0,
            fairlyActiveMinutes: fitbitSummary.fairlyActiveMinutes ?? 0,
            veryActiveMinutes: fitbitSummary.veryActiveMinutes ?? 0,
            floorsClimbed: fitbitSummary.floors ?? 0,
            restingHeartRate: fitbitSummary.restingHeartRate,
            sources: [source]
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("daily_activity_summary")
                .upsert(insert, onConflict: "user_id,date")
                .execute()
            
            AppLogger.info("Saved daily activity from \(source)", category: .health)
        } catch {
            NetworkErrorClassifier.log(error, context: "Failed to save daily activity", category: .health)
        }
    }
    
    private func updateDailyActivityFromStrava(date: Date, calories: Int, distance: Double, activeMinutes: Int) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let dateStr = Self.dayFormatter.string(from: date)
        
        // First, try to get existing record
        do {
            let existing: [DailyActivitySummary] = try await SupabaseManager.shared.supabaseClient
                .from("daily_activity_summary")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("date", value: dateStr)
                .execute()
                .value
            
            if let current = existing.first {
                // Update with Strava data (add to existing)
                let update: [String: AnyEncodable] = [
                    "calories_burned": AnyEncodable(max(current.caloriesBurned, calories)),
                    "distance_meters": AnyEncodable(max(current.distanceMeters, distance)),
                    "very_active_minutes": AnyEncodable(max(current.veryActiveMinutes, activeMinutes)),
                    "sources": AnyEncodable(Array(Set(current.sources + ["strava"]))),
                    "updated_at": AnyEncodable(Self.iso8601.string(from: Date()))
                ]
                
                try await SupabaseManager.shared.supabaseClient
                    .from("daily_activity_summary")
                    .update(update)
                    .eq("id", value: current.id.uuidString)
                    .execute()
            } else {
                // Create new record with Strava data
                let insert = DailyActivityInsert(
                    userId: userId.uuidString,
                    date: dateStr,
                    steps: 0,
                    caloriesBurned: calories,
                    caloriesActive: calories,
                    distanceMeters: distance,
                    veryActiveMinutes: activeMinutes,
                    sources: ["strava"]
                )
                
                try await SupabaseManager.shared.supabaseClient
                    .from("daily_activity_summary")
                    .insert(insert)
                    .execute()
            }
            
            AppLogger.info("Updated daily activity with Strava data", category: .health)
        } catch {
            NetworkErrorClassifier.log(error, context: "Failed to update Strava activity", category: .health)
        }
    }
    
    private func saveSleepLog(from fitbitSleep: FitbitSleepLog, source: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let insert = SleepLogInsert(
            userId: userId.uuidString,
            dateOfSleep: fitbitSleep.dateOfSleep,
            startTime: fitbitSleep.startTime,
            endTime: fitbitSleep.endTime,
            durationMs: fitbitSleep.duration,
            timeInBedMs: fitbitSleep.timeInBed,
            efficiency: fitbitSleep.efficiency,
            minutesAsleep: fitbitSleep.minutesAsleep,
            minutesAwake: fitbitSleep.minutesAwake,
            isMainSleep: fitbitSleep.mainSleep ?? true,
            sleepType: fitbitSleep.type,
            source: source,
            externalId: String(fitbitSleep.logId)
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("sleep_logs")
                .upsert(insert, onConflict: "user_id,source,external_id")
                .execute()
            
            AppLogger.info("Saved sleep log from \(source)", category: .health)
        } catch {
            NetworkErrorClassifier.log(error, context: "Failed to save sleep log", category: .health)
        }
    }
    
    private func saveHeartRateData(from heartRate: FitbitHeartRateData, date: Date, source: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let dateStr = Self.dayFormatter.string(from: date)
        
        // Extract zone data
        var outOfRangeMinutes = 0, fatBurnMinutes = 0, cardioMinutes = 0, peakMinutes = 0
        var outOfRangeCalories = 0.0, fatBurnCalories = 0.0, cardioCalories = 0.0, peakCalories = 0.0
        var fatBurnMin = 0, fatBurnMax = 0, cardioMin = 0, cardioMax = 0, peakMin = 0
        
        if let zones = heartRate.heartRateZones {
            for zone in zones {
                switch zone.name.lowercased() {
                case "out of range":
                    outOfRangeMinutes = zone.minutes ?? 0
                    outOfRangeCalories = zone.caloriesOut ?? 0
                case "fat burn":
                    fatBurnMinutes = zone.minutes ?? 0
                    fatBurnCalories = zone.caloriesOut ?? 0
                    fatBurnMin = zone.min
                    fatBurnMax = zone.max
                case "cardio":
                    cardioMinutes = zone.minutes ?? 0
                    cardioCalories = zone.caloriesOut ?? 0
                    cardioMin = zone.min
                    cardioMax = zone.max
                case "peak":
                    peakMinutes = zone.minutes ?? 0
                    peakCalories = zone.caloriesOut ?? 0
                    peakMin = zone.min
                default:
                    break
                }
            }
        }
        
        let insert = HeartRateDailyInsert(
            userId: userId.uuidString,
            date: dateStr,
            restingHeartRate: heartRate.restingHeartRate,
            outOfRangeMinutes: outOfRangeMinutes,
            fatBurnMinutes: fatBurnMinutes,
            cardioMinutes: cardioMinutes,
            peakMinutes: peakMinutes,
            outOfRangeCalories: outOfRangeCalories,
            fatBurnCalories: fatBurnCalories,
            cardioCalories: cardioCalories,
            peakCalories: peakCalories,
            fatBurnMin: fatBurnMin,
            fatBurnMax: fatBurnMax,
            cardioMin: cardioMin,
            cardioMax: cardioMax,
            peakMin: peakMin,
            source: source
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("heart_rate_daily")
                .upsert(insert, onConflict: "user_id,date,source")
                .execute()
            
            AppLogger.info("Saved heart rate data from \(source)", category: .health)
        } catch {
            NetworkErrorClassifier.log(error, context: "Failed to save heart rate", category: .health)
        }
    }
    
    // MARK: - Fetch Aggregated Data
    
    func fetchWeeklyData() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        // ⚡️ Sequential with 150ms gaps to avoid flooding URLSession during startup.
        // These are display-only queries — not critical for challenge sync.
        
        // Fetch weekly activity data
        do {
            let activities: [DailyActivitySummary] = try await SupabaseManager.shared.supabaseClient
                .from("daily_activity_summary")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date", value: Self.dayFormatter.string(from: weekAgo))
                .order("date", ascending: false)
                .execute()
                .value
            
            weeklyActivityData = activities
            todaySummary = activities.first { calendar.isDateInToday(Self.dayFormatter.date(from: $0.date) ?? Date()) }
            
            AppLogger.info("Fetched \(activities.count) days of activity data", category: .health)
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch activity data",
                category: .health,
                transientLevel: .debug   // startup flood = cancels; refetches next cycle
            )
        }
        
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms throttle
        
        // Fetch sleep logs
        do {
            let sleepLogs: [SleepLogEntry] = try await SupabaseManager.shared.supabaseClient
                .from("sleep_logs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date_of_sleep", value: Self.dayFormatter.string(from: weekAgo))
                .order("date_of_sleep", ascending: false)
                .execute()
                .value
            
            recentSleepLogs = sleepLogs
            calculateSleepStats()
            
            AppLogger.info("Fetched \(sleepLogs.count) sleep logs", category: .health)
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch sleep data",
                category: .health,
                transientLevel: .debug
            )
        }
        
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms throttle
        
        // Fetch heart rate data
        do {
            let heartRates: [HeartRateDaily] = try await SupabaseManager.shared.supabaseClient
                .from("heart_rate_daily")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date", value: Self.dayFormatter.string(from: weekAgo))
                .order("date", ascending: false)
                .execute()
                .value
            
            weeklyHeartRateData = heartRates
            todayHeartRate = heartRates.first { calendar.isDateInToday(Self.dayFormatter.date(from: $0.date) ?? Date()) }
            calculateHeartRateTrend()
            
            AppLogger.info("Fetched \(heartRates.count) days of heart rate data", category: .health)
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch heart rate data",
                category: .health,
                transientLevel: .debug
            )
        }
        
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms throttle
        
        // Fetch workout aggregates from cardio_workouts
        await fetchWorkoutAggregates()
    }
    
    private func fetchWorkoutAggregates() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        
        do {
            let workouts: [CardioWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                .from("cardio_workouts")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("completed_at", value: Self.iso8601.string(from: startOfWeek))
                .execute()
                .value
            
            weeklyWorkoutCount = workouts.count
            weeklyCardioMinutes = workouts.reduce(0) { $0 + (($1.durationSeconds ?? 0) / 60) }
            weeklyCaloriesBurned = workouts.reduce(0) { $0 + Int($1.caloriesBurned ?? 0) }
            
            AppLogger.info("Weekly workouts: \(weeklyWorkoutCount), minutes: \(weeklyCardioMinutes)", category: .health)
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch workout aggregates",
                category: .health,
                transientLevel: .debug
            )
        }
    }
    
    // MARK: - Stats Calculations
    
    private func calculateSleepStats() {
        guard !recentSleepLogs.isEmpty else { return }
        
        let mainSleepLogs = recentSleepLogs.filter { $0.isMainSleep }
        
        if !mainSleepLogs.isEmpty {
            let totalHours = mainSleepLogs.reduce(0.0) { $0 + (Double($1.durationMs) / 3600000.0) }
            averageSleepHours = totalHours / Double(mainSleepLogs.count)
            
            // Calculate trend (compare first half to second half of week)
            if mainSleepLogs.count >= 4 {
                let midpoint = mainSleepLogs.count / 2
                let recentAvg = mainSleepLogs.prefix(midpoint).reduce(0.0) { $0 + Double($1.durationMs) } / Double(midpoint)
                let olderAvg = mainSleepLogs.suffix(midpoint).reduce(0.0) { $0 + Double($1.durationMs) } / Double(midpoint)
                
                let diff = (recentAvg - olderAvg) / olderAvg
                if diff > 0.05 {
                    sleepTrend = .improving
                } else if diff < -0.05 {
                    sleepTrend = .declining
                } else {
                    sleepTrend = .stable
                }
            }
        }
    }
    
    private func calculateHeartRateTrend() {
        let validHRs = weeklyHeartRateData.compactMap { $0.restingHeartRate }
        guard validHRs.count >= 4 else { return }
        
        let midpoint = validHRs.count / 2
        let recentAvg = Double(validHRs.prefix(midpoint).reduce(0, +)) / Double(midpoint)
        let olderAvg = Double(validHRs.suffix(midpoint).reduce(0, +)) / Double(midpoint)
        
        // Lower HR is better
        let diff = (recentAvg - olderAvg) / olderAvg
        if diff < -0.02 {
            restingHRTrend = .improving
        } else if diff > 0.02 {
            restingHRTrend = .declining
        } else {
            restingHRTrend = .stable
        }
    }
    
    // MARK: - Helpers
    
    private func updateConnectedSources() {
        var sources: [String] = []
        if HealthKitService.shared.isAuthorized { sources.append("healthkit") }
        if FitbitService.shared.isConnected { sources.append("fitbit") }
        if StravaService.shared.isConnected { sources.append("strava") }
        if WhoopService.shared.isConnected { sources.append("whoop") }
        if OuraService.shared.isConnected { sources.append("oura") }
        connectedSources = sources
    }
    
    // MARK: - Computed Properties
    
    var totalActiveMinutesToday: Int {
        guard let summary = todaySummary else { return 0 }
        return summary.fairlyActiveMinutes + summary.veryActiveMinutes
    }
    
    var weeklyStepsTotal: Int {
        weeklyActivityData.reduce(0) { $0 + $1.steps }
    }
    
    var weeklyStepsAverage: Int {
        guard !weeklyActivityData.isEmpty else { return 0 }
        return weeklyStepsTotal / weeklyActivityData.count
    }
    
    var avgRestingHeartRate: Int? {
        let validHRs = weeklyHeartRateData.compactMap { $0.restingHeartRate }
        guard !validHRs.isEmpty else { return nil }
        return validHRs.reduce(0, +) / validHRs.count
    }
}

// MARK: - Trend Direction

enum TrendDirection {
    case improving
    case stable
    case declining
    
    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }
    
    var color: Color {
        switch self {
        case .improving: return .green
        case .stable: return .secondary
        case .declining: return .red
        }
    }
}

// MARK: - Database Models

struct DailyActivitySummary: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: String
    let steps: Int
    let stepsGoal: Int
    let distanceMeters: Double
    let caloriesBurned: Int
    let caloriesBmr: Int
    let caloriesActive: Int
    let sedentaryMinutes: Int
    let lightlyActiveMinutes: Int
    let fairlyActiveMinutes: Int
    let veryActiveMinutes: Int
    let floorsClimbed: Int
    let elevationMeters: Double
    let restingHeartRate: Int?
    let sources: [String]
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case steps
        case stepsGoal = "steps_goal"
        case distanceMeters = "distance_meters"
        case caloriesBurned = "calories_burned"
        case caloriesBmr = "calories_bmr"
        case caloriesActive = "calories_active"
        case sedentaryMinutes = "sedentary_minutes"
        case lightlyActiveMinutes = "lightly_active_minutes"
        case fairlyActiveMinutes = "fairly_active_minutes"
        case veryActiveMinutes = "very_active_minutes"
        case floorsClimbed = "floors_climbed"
        case elevationMeters = "elevation_meters"
        case restingHeartRate = "resting_heart_rate"
        case sources
    }
}

struct DailyActivityInsert: Codable {
    let userId: String
    let date: String
    var steps: Int = 0
    var caloriesBurned: Int = 0
    var caloriesActive: Int = 0
    var distanceMeters: Double = 0
    var sedentaryMinutes: Int = 0
    var lightlyActiveMinutes: Int = 0
    var fairlyActiveMinutes: Int = 0
    var veryActiveMinutes: Int = 0
    var floorsClimbed: Int = 0
    var restingHeartRate: Int?
    var sources: [String] = []
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date, steps
        case caloriesBurned = "calories_burned"
        case caloriesActive = "calories_active"
        case distanceMeters = "distance_meters"
        case sedentaryMinutes = "sedentary_minutes"
        case lightlyActiveMinutes = "lightly_active_minutes"
        case fairlyActiveMinutes = "fairly_active_minutes"
        case veryActiveMinutes = "very_active_minutes"
        case floorsClimbed = "floors_climbed"
        case restingHeartRate = "resting_heart_rate"
        case sources
    }
}

struct SleepLogEntry: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let dateOfSleep: String
    let startTime: String
    let endTime: String
    let durationMs: Int
    let timeInBedMs: Int?
    let efficiency: Int?
    let minutesAsleep: Int?
    let minutesAwake: Int?
    let deepSleepMinutes: Int?
    let lightSleepMinutes: Int?
    let remSleepMinutes: Int?
    let wakeSleepMinutes: Int?
    let isMainSleep: Bool
    let sleepType: String?
    let source: String
    let externalId: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case dateOfSleep = "date_of_sleep"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMs = "duration_ms"
        case timeInBedMs = "time_in_bed_ms"
        case efficiency
        case minutesAsleep = "minutes_asleep"
        case minutesAwake = "minutes_awake"
        case deepSleepMinutes = "deep_sleep_minutes"
        case lightSleepMinutes = "light_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case wakeSleepMinutes = "wake_minutes"
        case isMainSleep = "is_main_sleep"
        case sleepType = "sleep_type"
        case source
        case externalId = "external_id"
    }
    
    var sleepHours: Double {
        Double(durationMs) / 3600000.0
    }
}

struct SleepLogInsert: Codable {
    let userId: String
    let dateOfSleep: String
    let startTime: String
    let endTime: String
    let durationMs: Int
    let timeInBedMs: Int?
    let efficiency: Int?
    let minutesAsleep: Int?
    let minutesAwake: Int?
    let isMainSleep: Bool
    let sleepType: String?
    let source: String
    let externalId: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dateOfSleep = "date_of_sleep"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMs = "duration_ms"
        case timeInBedMs = "time_in_bed_ms"
        case efficiency
        case minutesAsleep = "minutes_asleep"
        case minutesAwake = "minutes_awake"
        case isMainSleep = "is_main_sleep"
        case sleepType = "sleep_type"
        case source
        case externalId = "external_id"
    }
}

struct HeartRateDaily: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: String
    let restingHeartRate: Int?
    let outOfRangeMinutes: Int
    let fatBurnMinutes: Int
    let cardioMinutes: Int
    let peakMinutes: Int
    let outOfRangeCalories: Double
    let fatBurnCalories: Double
    let cardioCalories: Double
    let peakCalories: Double
    let source: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case restingHeartRate = "resting_heart_rate"
        case outOfRangeMinutes = "out_of_range_minutes"
        case fatBurnMinutes = "fat_burn_minutes"
        case cardioMinutes = "cardio_minutes"
        case peakMinutes = "peak_minutes"
        case outOfRangeCalories = "out_of_range_calories"
        case fatBurnCalories = "fat_burn_calories"
        case cardioCalories = "cardio_calories"
        case peakCalories = "peak_calories"
        case source
    }
    
    var totalZoneMinutes: Int {
        fatBurnMinutes + cardioMinutes + peakMinutes
    }
}

struct HeartRateDailyInsert: Codable {
    let userId: String
    let date: String
    let restingHeartRate: Int?
    var outOfRangeMinutes: Int = 0
    var fatBurnMinutes: Int = 0
    var cardioMinutes: Int = 0
    var peakMinutes: Int = 0
    var outOfRangeCalories: Double = 0
    var fatBurnCalories: Double = 0
    var cardioCalories: Double = 0
    var peakCalories: Double = 0
    var fatBurnMin: Int = 0
    var fatBurnMax: Int = 0
    var cardioMin: Int = 0
    var cardioMax: Int = 0
    var peakMin: Int = 0
    let source: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case restingHeartRate = "resting_heart_rate"
        case outOfRangeMinutes = "out_of_range_minutes"
        case fatBurnMinutes = "fat_burn_minutes"
        case cardioMinutes = "cardio_minutes"
        case peakMinutes = "peak_minutes"
        case outOfRangeCalories = "out_of_range_calories"
        case fatBurnCalories = "fat_burn_calories"
        case cardioCalories = "cardio_calories"
        case peakCalories = "peak_calories"
        case fatBurnMin = "fat_burn_min"
        case fatBurnMax = "fat_burn_max"
        case cardioMin = "cardio_min"
        case cardioMax = "cardio_max"
        case peakMin = "peak_min"
        case source
    }
}

// MARK: - AnyEncodable Helper

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    
    init<T: Encodable>(_ value: T) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }
    
    /// Initialize with Any value - handles dictionaries, arrays, and primitives
    init(_ value: Any?) {
        if let value = value {
            switch value {
            case let str as String:
                _encode = { try str.encode(to: $0) }
            case let int as Int:
                _encode = { try int.encode(to: $0) }
            case let double as Double:
                _encode = { try double.encode(to: $0) }
            case let bool as Bool:
                _encode = { try bool.encode(to: $0) }
            case let dict as [String: Any]:
                let wrapped = dict.mapValues { AnyEncodable($0) }
                _encode = { try wrapped.encode(to: $0) }
            case let array as [Any]:
                let wrapped = array.map { AnyEncodable($0) }
                _encode = { try wrapped.encode(to: $0) }
            default:
                _encode = { encoder in
                    var container = encoder.singleValueContainer()
                    try container.encode(String(describing: value))
                }
            }
        } else {
            _encode = { encoder in
                var container = encoder.singleValueContainer()
                try container.encodeNil()
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// Helper extension to convert [String: Any] to Encodable for RPC calls
extension Dictionary where Key == String, Value == Any {
    func toEncodable() -> [String: AnyEncodable] {
        return self.mapValues { AnyEncodable($0) }
    }
}

// MARK: - HealthKit Insert DTOs

struct HealthKitWorkoutInsert: Codable {
    let userId: String
    let activityType: String
    let workoutName: String?
    let goalType: String
    let goalAchieved: Bool
    let durationSeconds: Int
    let distanceMeters: Double
    let caloriesBurned: Int
    /// Average bpm over the workout's time range. Computed from HealthKit
    /// heart-rate samples by `HealthKitService.fetchHeartRateStats` and
    /// persisted so the detail-view WHOOP Insights card can render Avg HR
    /// for wearable-imported strength sessions (WHOOP / Apple Watch /
    /// Garmin via HealthKit). `nil` when the source app didn't write HR.
    let averageHeartRate: Int?
    /// Peak bpm over the workout's time range. Same source + nil
    /// semantics as `averageHeartRate`.
    let maxHeartRate: Int?
    let startedAt: String
    let completedAt: String
    let source: String
    let externalId: String
    /// Canonical key of the app that originally authored the workout
    /// (e.g. "strava", "nike_run_club", "apple_watch"). Independent of
    /// `source` which tracks the transport (always "healthkit" here).
    let originApp: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case activityType = "activity_type"
        case workoutName = "workout_name"
        case goalType = "goal_type"
        case goalAchieved = "goal_achieved"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case caloriesBurned = "calories_burned"
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case source
        case externalId = "external_id"
        case originApp = "origin_app"
    }
}

struct HealthKitSleepInsert: Codable {
    let userId: String
    let dateOfSleep: String
    let durationMs: Int
    let minutesAsleep: Int
    let source: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dateOfSleep = "date_of_sleep"
        case durationMs = "duration_ms"
        case minutesAsleep = "minutes_asleep"
        case source
    }
}
