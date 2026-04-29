//
//  HealthKitService.swift
//  Fit33
//
//  Apple HealthKit Integration - Syncs workouts, steps, heart rate, and more
//  from Apple Health (which aggregates data from Nike Run Club, Apple Watch,
//  Strava, Fitbit, and any other connected fitness apps)
//

import Foundation
import HealthKit
import SwiftUI

// MARK: - HealthKit Service

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    
    // MARK: - Published Properties
    
    @Published var isAuthorized: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastSyncDate: Date?
    
    // Today's Summary
    @Published var todaySteps: Int = 0
    @Published var todayCalories: Int = 0
    @Published var todayActiveMinutes: Int = 0
    @Published var todayDistance: Double = 0 // meters
    
    // Workouts
    @Published var recentWorkouts: [HealthKitWorkout] = []
    
    // Heart Rate
    @Published var restingHeartRate: Int?
    @Published var averageHeartRate: Int?
    
    // Sleep
    @Published var lastNightSleep: Double? // hours
    
    // Weekly Data
    @Published var weeklySteps: [DailyStepData] = []
    @Published var weeklyWorkouts: [HealthKitWorkout] = []
    
    // MARK: - Private Properties
    
    nonisolated(unsafe) private let healthStore = HKHealthStore()
    private static let syncThrottleInterval: TimeInterval = 300 // 5 minutes
    private var isSyncing = false
    
    // Types we want to read from HealthKit
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned, .distanceWalkingRunning,
            .heartRate, .restingHeartRate
        ]
        for id in quantityIdentifiers {
            if let qt = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(qt)
            }
        }
        
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        
        return types
    }
    
    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energyType)
        }
        return types
    }
    
    // MARK: - Initialization
    
    private init() {
        // Check if already authorized
        checkAuthorizationStatus()
        
        // Load last sync date
        if let date = UserDefaults.standard.object(forKey: "healthkit_last_sync") as? Date {
            lastSyncDate = date
        }
    }
    
    // MARK: - Authorization
    
    /// Check if HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() {
        guard isHealthKitAvailable else {
            isAuthorized = false
            return
        }
        
        // Check if we have any authorization (we can only check individual types)
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let status = healthStore.authorizationStatus(for: stepType)
        
        // Check both write authorization status AND UserDefaults flag
        let hasWriteAuth = (status == .sharingAuthorized)
        let hasStoredAuth = UserDefaults.standard.bool(forKey: "healthkit_authorized")
        
        isAuthorized = hasWriteAuth || hasStoredAuth
        
        // Keep UserDefaults synced if write auth was granted externally
        if hasWriteAuth && !hasStoredAuth {
            UserDefaults.standard.set(true, forKey: "healthkit_authorized")
        }
        
        // Sync with HealthKitManager
        if isAuthorized {
            HealthKitManager.shared.isAuthorized = true
        }
    }
    
    /// Request HealthKit authorization
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitServiceError.notAvailable
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            
            await MainActor.run {
                isAuthorized = true
                UserDefaults.standard.set(true, forKey: "healthkit_authorized")
                // Sync with HealthKitManager so step tracking also knows we're authorized
                HealthKitManager.shared.isAuthorized = true
            }
            
            AppLogger.info("HealthKit authorization granted", category: .health)
            
            // Sync data after authorization
            await syncAllData(force: true)
            
        } catch {
            AppLogger.error("HealthKit authorization failed: \(error.localizedDescription)", category: .health)
            throw HealthKitServiceError.authorizationFailed(error)
        }
    }
    
    /// Disconnect HealthKit (revoke local authorization flag)
    func disconnect() {
        isAuthorized = false
        UserDefaults.standard.set(false, forKey: "healthkit_authorized")
        
        // Clear cached data
        todaySteps = 0
        todayCalories = 0
        todayActiveMinutes = 0
        todayDistance = 0
        recentWorkouts = []
        restingHeartRate = nil
        averageHeartRate = nil
        lastNightSleep = nil
        weeklySteps = []
        weeklyWorkouts = []
        lastSyncDate = nil
        
        UserDefaults.standard.removeObject(forKey: "healthkit_last_sync")
        
        AppLogger.info("HealthKit disconnected", category: .health)
    }
    
    // MARK: - Sync All Data
    
    /// Sync all health data from HealthKit (throttled)
    nonisolated func syncAllData(force: Bool = false) async {
        // Sprint 5 M-8: two paths can call this in the same second — dashboard
        // `.task`, `BackgroundChallengeSyncService` tick, and the foreground
        // resume handler. The legacy `isSyncing` guard causes the second
        // caller to BAIL immediately, so its `await` returns before data is
        // actually fresh. Coalescing makes the second caller **wait** for the
        // first sync to finish, which is the semantics every caller assumes.
        // Keyed by force flag so a non-force caller doesn't wait for a forced
        // sync it didn't ask for (different throttle semantics).
        await RequestCoalescer.shared.coalesceVoid(key: "HealthKit.syncAllData.force=\(force)") {
            await self._syncAllDataBody(force: force)
        }
    }

    nonisolated private func _syncAllDataBody(force: Bool) async {
        let (shouldProceed, authorized) = await MainActor.run {
            guard isAuthorized else { return (false, false) }
            if isSyncing {
                AppLogger.debug("Skipping HealthKit sync - already in progress", category: .health)
                return (false, false)
            }
            if !force, let lastSync = lastSyncDate,
               Date().timeIntervalSince(lastSync) < Self.syncThrottleInterval {
                AppLogger.debug("Skipping HealthKit sync - synced \(Int(Date().timeIntervalSince(lastSync)))s ago", category: .health)
                return (false, false)
            }
            isSyncing = true
            isLoading = true
            return (true, isAuthorized)
        }
        guard shouldProceed else { return }

        StartupWaterfall.shared.mark("HealthKit.syncAll")

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.syncTodayStats(authorized: authorized) }
            group.addTask { await self.syncRecentWorkouts() }
            group.addTask { await self.syncHeartRate() }
            group.addTask { await self.syncSleep() }
            group.addTask { await self.syncWeeklyData(authorized: authorized) }
        }

        await MainActor.run {
            isLoading = false
            isSyncing = false
        }

        AppLogger.info("HealthKit full sync complete", category: .health)

        await HealthDataService.shared.persistHealthKitDataToSupabase()

        StartupWaterfall.shared.end("HealthKit.syncAll")

        await ChallengeService.shared.syncHealthKitDataToChallenges()

        await MainActor.run {
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "healthkit_last_sync")
        }
    }
    
    // MARK: - Refresh Today's Stats Only
    //
    // Lightweight refresh of TODAY's HK counters (steps, active energy,
    // distance). Does NOT run the full `syncAllData` TaskGroup, does NOT
    // chain into `ChallengeService.syncHealthKitDataToChallenges()`, does
    // NOT touch `RequestCoalescer`.
    //
    // This MUST exist as a separate entry point because
    // `syncAllData(force:)` chains into
    // `ChallengeService.syncHealthKitDataToChallenges()` which itself
    // calls `syncAllData(force: true)`. With `RequestCoalescer.coalesceVoid`
    // keyed by `"HealthKit.syncAllData.force=true"`, the inner call JOINS
    // the outer (still-in-flight) Task and DEADLOCKS — the outer awaits
    // the inner, the inner awaits the outer's `.value`. The Task system
    // does not detect this; the chain hangs until the parent Task is
    // cancelled (e.g. the user navigates away). Canonical incident
    // 2026-04-28 — `ChallengeService.backfillTodayProgressForChallenge`
    // (challenge accept backfill) called `syncAllData(force: true)` from
    // both the `respondToChallenge` accept path and the
    // `RealtimeService.handleAllParticipantUpdates` "opponent accepted"
    // branch (Paul's side). Both deadlocked, both eventually unwound when
    // Joe navigated away from the challenge detail view, so Paul's progress
    // appeared but with a multi-second delay instead of instantly.
    nonisolated func refreshTodayStats() async {
        let authorized = await MainActor.run { isAuthorized }
        guard authorized else { return }
        await syncTodayStats(authorized: true)
    }

    // MARK: - Sync Today's Stats
    
    nonisolated private func syncTodayStats(authorized: Bool) async {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let steps = await fetchSum(for: .stepCount, predicate: predicate, authorized: authorized)
        let calories = await fetchSum(for: .activeEnergyBurned, predicate: predicate, authorized: authorized)
        let distance = await fetchSum(for: .distanceWalkingRunning, predicate: predicate, authorized: authorized)
        
        let stepsInt = steps.map { Int($0) } ?? 0
        let calsInt = calories.map { Int($0) } ?? 0
        let distVal = distance ?? 0
        
        await MainActor.run {
            todaySteps = stepsInt
            todayCalories = calsInt
            todayDistance = distVal
            // Optimistic widget patch: as soon as the @Published values
            // commit, push fresh local progress into the active-challenge
            // widget snapshot. The bridge hash-gates so this is a no-op
            // when nothing changed.
            ActiveChallengeWidgetBridge.publishOptimisticLocalProgress()
        }
        
        AppLogger.info("HealthKit today: \(stepsInt) steps, \(calsInt) cal, \(String(format: "%.1f", distVal/1000)) km", category: .health)
        
        if calsInt > 0 {
            await DailyQuestService.shared.onCaloriesBurned(kcal: calsInt)
        }
    }
    
    // MARK: - Sync Recent Workouts
    
    nonisolated private func syncRecentWorkouts() async {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: predicate,
                    limit: 50,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            let rawWorkouts = samples.compactMap { sample -> HealthKitWorkout? in
                guard let workout = sample as? HKWorkout else { return nil }
                let hkWorkout = HealthKitWorkout(from: workout)
                // Skip workouts that Fit33 wrote to HealthKit — avoids duplicates
                if hkWorkout.isFromFit33 { return nil }
                return hkWorkout
            }

            // Enrich with per-workout HR stats in parallel. Each workout
            // fires two HKStatisticsQuery reads bounded by its own
            // start/end, so the `cardio_workouts` insert downstream can
            // persist `average_heart_rate` / `max_heart_rate` for
            // wearable-imported strength sessions (WHOOP / Apple Watch).
            // Without this enrichment the detail-view WHOOP Insights card
            // would show `--` for both HR metrics — see
            // `WorkoutHistoryDetailView.wearableInsightsCard`.
            let workouts: [HealthKitWorkout] = await withTaskGroup(
                of: (Int, Int?, Int?).self,
                returning: [HealthKitWorkout].self
            ) { group in
                for (idx, workout) in rawWorkouts.enumerated() {
                    group.addTask { [self] in
                        let stats = await self.fetchHeartRateStats(
                            start: workout.startDate,
                            end: workout.endDate
                        )
                        return (idx, stats.avg, stats.max)
                    }
                }
                var enriched = rawWorkouts
                for await (idx, avg, peak) in group {
                    enriched[idx].averageHeartRate = avg
                    enriched[idx].maxHeartRate = peak
                }
                return enriched
            }

            await MainActor.run {
                recentWorkouts = workouts
                
                // Calculate weekly totals
                let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
                let weekWorkouts = workouts.filter { $0.startDate >= oneWeekAgo }
                weeklyWorkouts = weekWorkouts
                let todayStart = calendar.startOfDay(for: Date())
                let todayWorkouts = weekWorkouts.filter { $0.startDate >= todayStart }
                todayActiveMinutes = todayWorkouts.reduce(0) { $0 + $1.durationMinutes }
                // Optimistic widget patch — see `syncTodayStats` for the
                // rationale. `active_minutes` / `walk` / `run` challenges
                // pick this up before the Supabase round-trip lands.
                ActiveChallengeWidgetBridge.publishOptimisticLocalProgress()
            }
            
            AppLogger.info("HealthKit synced \(workouts.count) workouts", category: .health)
            
        } catch {
            let desc = error.localizedDescription.lowercased()
            let isExpectedHKError = desc.contains("protected health data")
                || desc.contains("no data available")
                || desc.contains("authorization not determined")
                || desc.contains("not available")
            
            if isExpectedHKError {
                AppLogger.debug("[WORKOUTS] HealthKit unavailable (device locked or permissions revoked): \(error.localizedDescription)", category: .health)
            } else {
                let nsErr = error as NSError
                AppLogger.error("[WORKOUTS] Unexpected HealthKit error (domain: \(nsErr.domain), code: \(nsErr.code)): \(error.localizedDescription)", category: .health)
            }
        }
    }
    
    // MARK: - Sync Heart Rate
    
    nonisolated private func syncHeartRate() async {
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: oneWeekAgo, end: Date(), options: .strictStartDate)
        
        let restingHR = await fetchMostRecent(for: .restingHeartRate, predicate: predicate)
        if let rhr = restingHR {
            await MainActor.run { restingHeartRate = Int(rhr) }
            AppLogger.info("HealthKit resting HR: \(Int(rhr)) bpm", category: .health)
        }
        
        let todayPredicate = HKQuery.predicateForSamples(
            withStart: calendar.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )
        
        if let avgHR = await fetchAverage(for: .heartRate, predicate: todayPredicate) {
            await MainActor.run { averageHeartRate = Int(avgHR) }
        }
    }
    
    // MARK: - Sync Sleep
    
    nonisolated private func syncSleep() async {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        let authStatus = healthStore.authorizationStatus(for: sleepType)
        guard authStatus != .notDetermined else {
            return
        }
        
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: endOfToday, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            // Calculate total sleep (in-bed or asleep states)
            var totalSleepSeconds: TimeInterval = 0
            for sample in samples {
                guard let categorySample = sample as? HKCategorySample else { continue }
                
                // Only count actual sleep (not in-bed time)
                if categorySample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                   categorySample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                   categorySample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                   categorySample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                    totalSleepSeconds += categorySample.endDate.timeIntervalSince(categorySample.startDate)
                }
            }
            
            let sleepHours = totalSleepSeconds / 3600.0
            
            await MainActor.run {
                lastNightSleep = sleepHours > 0 ? sleepHours : nil
            }
            
            if sleepHours > 0 {
                AppLogger.info("HealthKit last night sleep: \(String(format: "%.1f", sleepHours)) hours", category: .health)
            }
            
        } catch {
            let desc = error.localizedDescription
            if desc.contains("Protected health data") {
                AppLogger.debug("HealthKit sleep unavailable (device locked or permissions revoked)", category: .health)
            } else {
                AppLogger.error("Failed to fetch HealthKit sleep: \(desc)", category: .health)
            }
        }
    }
    
    // MARK: - Sync Weekly Data
    
    nonisolated private func syncWeeklyData(authorized: Bool) async {
        let calendar = Calendar.current
        var stepData: [DailyStepData] = []
        
        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
            
            if let steps = await fetchSum(for: .stepCount, predicate: predicate, authorized: authorized) {
                stepData.append(DailyStepData(date: startOfDay, steps: Int(steps)))
            } else {
                stepData.append(DailyStepData(date: startOfDay, steps: 0))
            }
        }
        
        await MainActor.run {
            weeklySteps = stepData.reversed() // Oldest first
        }
    }
    
    // MARK: - Helper Methods
    
    nonisolated private func fetchSum(for identifier: HKQuantityTypeIdentifier, predicate: NSPredicate, authorized: Bool) async -> Double? {
        guard authorized else { return nil }
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    let desc = error.localizedDescription.lowercased()
                    let isExpected = desc.contains("no data available") || desc.contains("protected health data") || desc.contains("authorization not determined")
                    if !isExpected {
                        AppLogger.warning("[HK] fetchSum(\(identifier.rawValue)) failed: \(error.localizedDescription)", category: .health)
                    }
                    continuation.resume(returning: nil)
                    return
                }
                guard let result = result, let sum = result.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let unit: HKUnit
                switch identifier {
                case .stepCount:
                    unit = .count()
                case .activeEnergyBurned:
                    unit = .kilocalorie()
                case .distanceWalkingRunning:
                    unit = .meter()
                default:
                    unit = .count()
                }
                
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    nonisolated private func fetchMostRecent(for identifier: HKQuantityTypeIdentifier, predicate: NSPredicate) async -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let unit: HKUnit
                switch identifier {
                case .heartRate, .restingHeartRate:
                    unit = HKUnit.count().unitDivided(by: .minute())
                default:
                    unit = .count()
                }
                
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    nonisolated private func fetchAverage(for identifier: HKQuantityTypeIdentifier, predicate: NSPredicate) async -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                guard let result = result, let avg = result.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let unit: HKUnit
                switch identifier {
                case .heartRate, .restingHeartRate:
                    unit = HKUnit.count().unitDivided(by: .minute())
                default:
                    unit = .count()
                }
                
                continuation.resume(returning: avg.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    /// Discrete maximum value for a quantity type over `predicate`. Mirrors
    /// `fetchAverage` but runs `HKStatisticsQuery` with `.discreteMax` so
    /// per-workout peak HR imports cleanly into `cardio_workouts.max_heart_rate`.
    nonisolated private func fetchMax(for identifier: HKQuantityTypeIdentifier, predicate: NSPredicate) async -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteMax
            ) { _, result, error in
                guard let result = result, let peak = result.maximumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }

                let unit: HKUnit
                switch identifier {
                case .heartRate, .restingHeartRate:
                    unit = HKUnit.count().unitDivided(by: .minute())
                default:
                    unit = .count()
                }

                continuation.resume(returning: peak.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    /// Average + peak bpm for `start...end`. Used to enrich `HealthKitWorkout`
    /// rows after they're pulled by `syncRecentWorkouts` so the
    /// `cardio_workouts` insert has HR stats — which then drives the
    /// wearable insights card (see `WorkoutWearableMerger` +
    /// `WorkoutHistoryDetailView.wearableInsightsCard`). Returns `(nil, nil)`
    /// when HealthKit has no HR samples in the range or authorization is
    /// missing; both conditions are silent-failures so we don't spam logs
    /// for every manually-logged strength session.
    nonisolated func fetchHeartRateStats(start: Date, end: Date) async -> (avg: Int?, max: Int?) {
        guard end > start else { return (nil, nil) }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        async let avgBpm = fetchAverage(for: .heartRate, predicate: predicate)
        async let maxBpm = fetchMax(for: .heartRate, predicate: predicate)
        let (avg, peak) = await (avgBpm, maxBpm)
        return (
            avg.map { Int($0.rounded()) },
            peak.map { Int($0.rounded()) }
        )
    }
    
    // MARK: - Write Workout to HealthKit
    
    /// Save a completed workout to HealthKit
    func saveWorkout(
        type: HKWorkoutActivityType,
        start: Date,
        end: Date,
        calories: Double?,
        distance: Double? // in meters
    ) async throws {
        guard isAuthorized else {
            throw HealthKitServiceError.notAuthorized
        }
        
        var samples: [HKSample] = []
        
        // Create energy burned sample if provided
        if let calories = calories, calories > 0 {
            let calorieType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
            let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
            let calorieSample = HKQuantitySample(
                type: calorieType,
                quantity: calorieQuantity,
                start: start,
                end: end
            )
            samples.append(calorieSample)
        }
        
        // Create distance sample if provided
        if let distance = distance, distance > 0 {
            let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distance)
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: distanceQuantity,
                start: start,
                end: end
            )
            samples.append(distanceSample)
        }
        
        // Create workout
        let workout = HKWorkout(
            activityType: type,
            start: start,
            end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: calories.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
            totalDistance: distance.map { HKQuantity(unit: .meter(), doubleValue: $0) },
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        
        try await healthStore.save(workout)
        
        // Associate samples with workout
        if !samples.isEmpty {
            try await healthStore.addSamples(samples, to: workout)
        }
        
        AppLogger.info("Saved workout to HealthKit", category: .health)
    }
}

// MARK: - HealthKit Workout Model

struct HealthKitWorkout: Identifiable {
    let id: UUID
    let workoutType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let calories: Double?
    let distance: Double? // meters
    let sourceName: String
    let sourceBundle: String?
    /// Average bpm over `startDate...endDate`, computed from the heart-rate
    /// samples HealthKit stored during the workout. `nil` when the source
    /// app didn't write HR samples (e.g. a manually-logged workout) or
    /// when authorization is missing. Populated by
    /// `HealthKitService.enrichHeartRate(for:)` before the workout reaches
    /// `cardio_workouts`. Required so the detail view's "WHOOP Insights"
    /// card can show Avg HR for HealthKit-imported strength sessions.
    var averageHeartRate: Int?
    /// Peak bpm over `startDate...endDate`. Same source + nil semantics as
    /// `averageHeartRate`.
    var maxHeartRate: Int?
    
    var durationMinutes: Int {
        Int(duration / 60)
    }
    
    var distanceKm: Double {
        (distance ?? 0) / 1000
    }
    
    var distanceMiles: Double {
        (distance ?? 0) / 1609.344
    }
    
    var workoutName: String {
        switch workoutType {
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hike"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "Cross Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .coreTraining: return "Core Training"
        case .flexibility: return "Flexibility"
        default: return "Workout"
        }
    }
    
    var workoutIcon: String {
        switch workoutType {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .hiking: return "figure.hiking"
        case .yoga: return "figure.yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "dumbbell.fill"
        case .highIntensityIntervalTraining: return "flame.fill"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rower"
        case .stairClimbing: return "figure.stairs"
        case .dance: return "figure.dance"
        default: return "figure.mixed.cardio"
        }
    }
    
    /// Check if this workout is from Nike Run Club
    var isFromNikeRunClub: Bool {
        sourceName.lowercased().contains("nike") || sourceBundle?.contains("nike") == true
    }
    
    /// Check if this workout is from Strava
    var isFromStrava: Bool {
        sourceName.lowercased().contains("strava") || sourceBundle?.contains("strava") == true
    }
    
    /// Check if this workout is from Apple Watch/Fitness
    var isFromApple: Bool {
        sourceName.lowercased().contains("apple") ||
        sourceBundle?.contains("com.apple") == true ||
        sourceName == "Watch"
    }
    
    /// Check if this workout originated from Fit33 itself (written to HealthKit, then read back)
    var isFromFit33: Bool {
        sourceBundle?.contains("com.fit33") == true ||
        sourceName.lowercased().contains("fit33")
    }
    
    init(from hkWorkout: HKWorkout) {
        self.id = hkWorkout.uuid
        self.workoutType = hkWorkout.workoutActivityType
        self.startDate = hkWorkout.startDate
        self.endDate = hkWorkout.endDate
        self.duration = hkWorkout.duration
        self.calories = hkWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        self.distance = hkWorkout.totalDistance?.doubleValue(for: .meter())
        self.sourceName = hkWorkout.sourceRevision.source.name
        self.sourceBundle = hkWorkout.sourceRevision.source.bundleIdentifier
        self.averageHeartRate = nil
        self.maxHeartRate = nil
    }
}

// MARK: - Daily Step Data

struct DailyStepData: Identifiable {
    let id = UUID()
    let date: Date
    let steps: Int
    
    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - HealthKit Service Errors

enum HealthKitServiceError: LocalizedError {
    case notAvailable
    case notAuthorized
    case authorizationFailed(Error)
    case fetchFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .authorizationFailed(let error):
            return "Authorization failed: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension HealthKitWorkout {
    static var preview: HealthKitWorkout {
        HealthKitWorkout(
            id: UUID(),
            workoutType: .running,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            duration: 3600,
            calories: 450,
            distance: 8000,
            sourceName: "Nike Run Club",
            sourceBundle: "com.nike.nikeplus-gps"
        )
    }
    
    init(id: UUID, workoutType: HKWorkoutActivityType, startDate: Date, endDate: Date, duration: TimeInterval, calories: Double?, distance: Double?, sourceName: String, sourceBundle: String?, averageHeartRate: Int? = nil, maxHeartRate: Int? = nil) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.calories = calories
        self.distance = distance
        self.sourceName = sourceName
        self.sourceBundle = sourceBundle
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }
}
#endif
