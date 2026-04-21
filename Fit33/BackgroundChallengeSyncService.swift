//
//  BackgroundChallengeSyncService.swift
//  Fit33
//
//  Background Challenge Sync — Keeps challenge progress up-to-date even when
//  the user doesn't open the app. Uses two mechanisms:
//
//  1. HealthKit Background Delivery: iOS wakes the app when new health data
//     arrives (steps from Apple Watch, workouts from Strava/Nike Run Club, etc.)
//     → Syncs the new data to all active challenges immediately.
//
//  2. BGTaskScheduler Periodic Refresh: iOS periodically wakes the app (~every
//     15-30 min based on usage patterns) to do a full challenge data sync.
//     → Catches anything HealthKit background delivery missed.
//
//  CHALLENGES THAT BENEFIT (data from external sources):
//    ✅ Steps       — Apple Watch, phone pedometer
//    ✅ Walk/Run    — Strava, Nike Run Club, Apple Watch workouts
//    ✅ Lift        — Apple Watch strength workouts
//    ✅ Active Min  — Any HealthKit active energy source
//    ✅ Workout Streak — Any workout logged to Apple Health
//
//  CHALLENGES THAT DON'T NEED THIS (manual in-app input):
//    ❌ Hydration   — Logged manually in Fit33
//    ❌ Protein     — Logged manually via meals
//    ❌ Calories    — Logged manually via meals (HealthKit calories could be added later)
//
//  Created by Infrastructure Team - 2026-02-25
//

import Foundation
import HealthKit
import BackgroundTasks
import UIKit

// MARK: - Background Challenge Sync Service

class BackgroundChallengeSyncService {
    static let shared = BackgroundChallengeSyncService()
    
    private let healthStore = HKHealthStore()
    
    /// BGAppRefreshTask identifier — short-quota periodic refresh (~15-30 min windows).
    /// Must match Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let bgTaskIdentifier = "com.gofit.app.challengeSync"
    
    /// BGProcessingTask identifier — longer-quota (~5 min) opportunistic sync.
    /// iOS typically runs these overnight while charging, giving us a near-free
    /// daily sync for users who leave the app closed for long stretches.
    /// Must match Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let bgProcessingTaskIdentifier = "com.gofit.app.challengeSyncProcessing"
    
    /// Per-source throttle window. One noisy source (steps) no longer starves
    /// the others (e.g. active energy / distance) because each has its own timer.
    /// Workouts are flagged high-priority and bypass the throttle entirely.
    private let perSourceThrottleInterval: TimeInterval = 600 // 10 minutes per source
    
    /// UserDefaults key prefix for per-source last-sync timestamps.
    /// Key form: `bg_challenge_last_sync_<source>` (e.g. `bg_challenge_last_sync_steps`).
    private let lastSyncKeyPrefix = "bg_challenge_last_sync_"

    /// Currently-running `performChallengeSyncInBackground` invocation, if
    /// any. Concurrent callers (e.g. three HealthKit observers firing in the
    /// same millisecond) await this shared Task instead of spawning their
    /// own. Without this the main-actor pipeline backs up by N× the per-run
    /// cost — which is how a ~800ms sync turned into a 2.4s main-thread hang
    /// on workout completions (3 HK observers wake at once).
    /// Accessed only from `@MainActor` (see `performChallengeSyncInBackground`).
    @MainActor
    private var inFlightSyncTask: Task<Void, Never>?

    private init() {}
    
    /// Last-sync UserDefaults key for a given source.
    private func lastSyncKey(for source: String) -> String {
        return "\(lastSyncKeyPrefix)\(source)"
    }
    
    // ═══════════════════════════════════════════════════════════
    // MARK: - Setup (Call once at app launch)
    // ═══════════════════════════════════════════════════════════
    
    /// Call this from Fit33App.swift init or .task on first launch.
    /// Enables HealthKit background delivery and registers the BGTask.
    func setup() {
        enableHealthKitBackgroundDelivery()
        registerBackgroundTask()
        registerBackgroundProcessingTask()
        scheduleNextBackgroundSync()
        scheduleNextProcessingSync()
        
        AppLogger.debug("🔄 [BG SYNC] BackgroundChallengeSyncService initialized", category: .social)
        AppLogger.debug("   └─ HealthKit background delivery: enabled for steps, workouts, active energy", category: .health)
        AppLogger.debug("   └─ BGAppRefreshTask: registered (~15 min windows)", category: .social)
        AppLogger.debug("   └─ BGProcessingTask: registered (~5 min, typically overnight)", category: .social)
    }
    
    // ═══════════════════════════════════════════════════════════
    // MARK: - HealthKit Background Delivery
    // ═══════════════════════════════════════════════════════════
    
    /// Enable background delivery for health data types that affect challenges.
    /// When Apple Watch logs steps, or Strava syncs a run, iOS wakes the app
    /// and calls our observer query — even if the app is suspended.
    private func enableHealthKitBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        // Types that affect challenge progress
        let identifiersAndFreqs: [(HKQuantityTypeIdentifier, HKUpdateFrequency)] = [
            (.stepCount, .immediate),
            (.activeEnergyBurned, .hourly),
            (.distanceWalkingRunning, .hourly),
            (.appleExerciseTime, .hourly),
        ]
        let challengeRelevantTypes: [(HKQuantityType, HKUpdateFrequency)] = identifiersAndFreqs.compactMap { id, freq in
            guard let qt = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
            return (qt, freq)
        }
        
        // Workout type — for lift/workout streak challenges (Strava, Nike RC, etc.)
        let workoutType = HKObjectType.workoutType()
        
        // Enable background delivery for each type
        for (quantityType, frequency) in challengeRelevantTypes {
            healthStore.enableBackgroundDelivery(for: quantityType, frequency: frequency) { success, error in
                if success {
                    AppLogger.info("✅ [BG SYNC] Background delivery enabled: \(quantityType.identifier)", category: .social)
                } else if let error = error {
                    AppLogger.error("❌ [BG SYNC] Failed to enable background delivery for \(quantityType.identifier): \(error.localizedDescription)", category: .social)
                }
            }
        }
        
        // Enable for workout type separately (different API)
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if success {
                AppLogger.info("✅ [BG SYNC] Background delivery enabled: workouts", category: .social)
            } else if let error = error {
                AppLogger.error("❌ [BG SYNC] Failed to enable background delivery for workouts: \(error.localizedDescription)", category: .social)
            }
        }
        
        // Set up observer queries that fire in the background
        setupBackgroundObserverQueries()
    }
    
    /// Observer queries that iOS will wake the app for.
    /// These are separate from the foreground observers in HealthKitManager.
    ///
    /// CRITICAL: The HKObserverQuery completionHandler MUST be called when
    /// processing is finished. If you don't call it, iOS assumes the app hung
    /// and will eventually STOP delivering background updates entirely.
    private func setupBackgroundObserverQueries() {
        // Steps observer — syncs step challenges (throttled — high frequency)
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let stepObserver = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            self?.handleBackgroundHealthUpdate(source: "steps", isHighPriority: false) {
                completionHandler()
            }
        }
        healthStore.execute(stepObserver)
        
        // Workout observer — syncs lift/run/walk/streak challenges
        // HIGH PRIORITY: Workouts sync IMMEDIATELY (no throttle) because the user
        // just finished a Dance, Walk, Run, etc. in another app and expects to see it.
        let workoutObserver = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            self?.handleBackgroundHealthUpdate(source: "workout", isHighPriority: true) {
                completionHandler()
            }
        }
        healthStore.execute(workoutObserver)
        
        // Active energy observer — syncs active minutes/calorie challenges (throttled)
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let energyObserver = HKObserverQuery(sampleType: energyType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            self?.handleBackgroundHealthUpdate(source: "active_energy", isHighPriority: false) {
                completionHandler()
            }
        }
        healthStore.execute(energyObserver)
        
        // Distance observer — syncs walk/run challenges (throttled)
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distanceObserver = HKObserverQuery(sampleType: distanceType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            self?.handleBackgroundHealthUpdate(source: "distance", isHighPriority: false) {
                completionHandler()
            }
        }
        healthStore.execute(distanceObserver)
        
        // Exercise time observer — syncs active minutes challenges (throttled)
        if let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            let exerciseObserver = HKObserverQuery(sampleType: exerciseType, predicate: nil) { [weak self] _, completionHandler, error in
                guard error == nil else { completionHandler(); return }
                self?.handleBackgroundHealthUpdate(source: "exercise_time", isHighPriority: false) {
                    completionHandler()
                }
            }
            healthStore.execute(exerciseObserver)
        }
    }
    
    /// Called when HealthKit delivers new data in the background.
    ///
    /// - `isHighPriority`: Workout completions sync immediately (no throttle).
    ///   Continuous data (steps, energy) is throttled to prevent excessive syncing.
    /// - `onComplete`: MUST be called when processing is finished — this is the
    ///   HKObserverQuery completionHandler. If not called, iOS stops delivering.
    private func handleBackgroundHealthUpdate(source: String, isHighPriority: Bool, onComplete: @escaping () -> Void) {
        let now = Date()
        let sourceKey = lastSyncKey(for: source)
        let lastSync = UserDefaults.standard.double(forKey: sourceKey)
        let lastSyncDate = Date(timeIntervalSince1970: lastSync)
        let elapsed = now.timeIntervalSince(lastSyncDate)
        
        // High-priority events (workout completions) always sync immediately.
        // Low-priority events (steps, energy, distance, exercise_time) throttle
        // independently per source — a step flood no longer suppresses an
        // active-energy or distance event fired in the same window.
        if !isHighPriority && elapsed < perSourceThrottleInterval {
            AppLogger.debug("⏭️ [BG SYNC] Skipping \(source) — synced \(Int(elapsed))s ago (per-source throttle)", category: .social)
            onComplete()
            return
        }
        
        AppLogger.debug("🔄 [BG SYNC] HealthKit background update: \(source)\(isHighPriority ? " ⚡️ IMMEDIATE" : "")", category: .health)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: sourceKey)

        // Perform the sync and call the completion handler when done
        Task {
            await performChallengeSyncInBackground()

            // Sprint 3 Q2-28: Notify HealthKitManager so it can refresh its
            // @Published UI state. This replaces the duplicate foreground
            // `HKObserverQuery` we used to run inside HealthKitManager.
            //
            // NOTE: `performChallengeSyncInBackground` already calls
            // `HealthKitService.syncAllData(force: true)` as Step 1, so the
            // `cardio_workouts` row is written before we post here. A
            // previous implementation did a SECOND `syncAllData(force: true)`
            // on the workout path — that was a double sync and is removed.
            await MainActor.run {
                switch source {
                case "workout":
                    NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
                case "steps", "active_energy", "distance", "exercise_time":
                    NotificationCenter.default.post(name: .healthStepsDidUpdate, object: nil)
                default:
                    break
                }
            }

            onComplete()
        }
    }
    
    // ═══════════════════════════════════════════════════════════
    // MARK: - BGTaskScheduler Periodic Refresh
    // ═══════════════════════════════════════════════════════════
    
    /// Register the BGAppRefreshTask handler with iOS.
    /// Must be called before the app finishes launching.
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                AppLogger.error("❌ [BG SYNC] Unexpected task type: \(type(of: task))", category: .social)
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(refreshTask)
        }
        
        AppLogger.info("✅ [BG SYNC] BGAppRefreshTask registered: \(Self.bgTaskIdentifier)", category: .social)
    }
    
    /// Register the BGProcessingTask handler with iOS.
    /// Processing tasks get ~5-minute budgets and run opportunistically when
    /// the device is idle — most commonly overnight while charging. This gives
    /// us a near-free daily sync even when the app hasn't been opened all day.
    private func registerBackgroundProcessingTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgProcessingTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                AppLogger.error("❌ [BG SYNC] Unexpected processing task type: \(type(of: task))", category: .social)
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundProcessingTask(processingTask)
        }
        
        AppLogger.info("✅ [BG SYNC] BGProcessingTask registered: \(Self.bgProcessingTaskIdentifier)", category: .social)
    }
    
    /// Schedule the next BGAppRefreshTask.
    /// iOS decides when to actually run it (typically every 15-30 min based on
    /// usage patterns — sometimes zero times a day for dormant users, which is
    /// why the BGProcessingTask + silent-push layers exist as safety nets).
    func scheduleNextBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLogger.debug("📅 [BG SYNC] Next BGAppRefresh scheduled (earliest: ~15 min)", category: .social)
        } catch {
            AppLogger.error("❌ [BG SYNC] Failed to schedule BGAppRefreshTask: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Schedule the next BGProcessingTask.
    /// Targets the overnight/idle window. `requiresExternalPower = false` keeps
    /// us eligible even when not charging (better coverage); network is required
    /// since we need to hit Supabase.
    func scheduleNextProcessingSync() {
        let request = BGProcessingTaskRequest(identifier: Self.bgProcessingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60) // 2h
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLogger.debug("📅 [BG SYNC] Next BGProcessing scheduled (earliest: ~2h)", category: .social)
        } catch {
            AppLogger.error("❌ [BG SYNC] Failed to schedule BGProcessingTask: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Handle the BGAppRefreshTask when iOS wakes the app.
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        AppLogger.debug("🔄 [BG SYNC] BGAppRefresh fired — syncing challenge data...", category: .social)
        
        // Reschedule the NEXT refresh immediately so the chain never breaks,
        // even if this run crashes or expires below.
        scheduleNextBackgroundSync()
        
        let syncTask = Task {
            await performChallengeSyncInBackground()
            task.setTaskCompleted(success: true)
            AppLogger.info("✅ [BG SYNC] BGAppRefresh completed successfully", category: .social)
        }
        
        // If iOS cuts us off, cancel the in-flight work, mark the task complete
        // as failed, and ensure the next cycle is still scheduled.
        task.expirationHandler = {
            AppLogger.warning("⏰ [BG SYNC] BGAppRefresh expired before completion — cancelling sync", category: .social)
            syncTask.cancel()
            self.scheduleNextBackgroundSync()
            task.setTaskCompleted(success: false)
        }
    }
    
    /// Handle the BGProcessingTask when iOS wakes the app.
    /// Same sync logic as BGAppRefresh — the only difference is the longer
    /// execution budget and typical overnight scheduling.
    private func handleBackgroundProcessingTask(_ task: BGProcessingTask) {
        AppLogger.debug("🔄 [BG SYNC] BGProcessing fired — syncing challenge data...", category: .social)
        
        // Reschedule the NEXT processing run immediately so the chain never breaks.
        scheduleNextProcessingSync()
        
        let syncTask = Task {
            await performChallengeSyncInBackground()
            task.setTaskCompleted(success: true)
            AppLogger.info("✅ [BG SYNC] BGProcessing completed successfully", category: .social)
        }
        
        task.expirationHandler = {
            AppLogger.warning("⏰ [BG SYNC] BGProcessing expired before completion — cancelling sync", category: .social)
            syncTask.cancel()
            self.scheduleNextProcessingSync()
            task.setTaskCompleted(success: false)
        }
    }
    
    // ═══════════════════════════════════════════════════════════
    // MARK: - Core Sync Logic
    // ═══════════════════════════════════════════════════════════
    
    /// The actual sync: fetches latest health data from ALL connected sources
    /// (HealthKit, Strava, Fitbit) and pushes to Supabase + active challenges.
    ///
    /// Runs from:
    /// - HealthKit background delivery (workout/step/energy observer)
    /// - BGTask periodic refresh (~15 min)
    /// - Simulator testing
    ///
    /// After this completes, the Dashboard's `.onChange(of: healthKitService.lastSyncDate)`
    /// will fire to refresh the UI (recent activity cards + stats).
    ///
    /// Concurrent callers coalesce to a single in-flight run (see
    /// `inFlightSyncTask`). HealthKit wakes the app with multiple observer
    /// types at once (workout + steps + active_energy), so without this
    /// coalescing the main-actor pipeline runs the same work 3× back-to-back.
    @MainActor
    func performChallengeSyncInBackground() async {
        if let existing = inFlightSyncTask {
            AppLogger.debug("🔁 [BG SYNC] Coalescing into in-flight sync", category: .social)
            await existing.value
            return
        }
        let task = Task { @MainActor [weak self] in
            await self?.performSyncBody()
            self?.inFlightSyncTask = nil
        }
        inFlightSyncTask = task
        await task.value
    }

    @MainActor
    private func performSyncBody() async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("⏭️ [BG SYNC] Not authenticated — skipping", category: .social)
            return
        }

        let start = Date()
        AppLogger.debug("🔄 [BG SYNC] Starting background sync (all sources)...", category: .social)
        
        // ── Step 1: Refresh HealthKit data ──
        // syncAllData now also persists workouts to Supabase (`cardio_workouts`)
        // and updates `lastSyncDate` which triggers Dashboard UI refresh
        await HealthKitService.shared.syncAllData(force: true)
        AppLogger.debug("   └─ HealthKit: \(HealthKitService.shared.todaySteps) steps, \(HealthKitService.shared.recentWorkouts.count) workouts", category: .health)
        
        // ── Step 2: Refresh Strava data (if connected) ──
        // Strava workouts also write to HealthKit, but fetching from Strava API
        // gives us richer data (route, splits, elevation) for the cardio_workouts table
        if StravaService.shared.isConnected {
            await StravaService.shared.syncActivities(daysBack: 7)
            AppLogger.debug("   └─ Strava: synced recent activities", category: .social)
        }
        
        // ── Step 3: Refresh Fitbit data (if connected) ──
        // Fitbit does NOT write to HealthKit, so we must pull from their API
        if FitbitService.shared.isConnected {
            await FitbitService.shared.syncAllData(force: true)
            AppLogger.debug("   └─ Fitbit: synced recent data", category: .social)
        }
        
        // ── Step 4: Refresh active challenges ──
        await ChallengeService.shared.fetchActiveChallenges()
        await ChallengeService.shared.fetchActiveGroupChallenges()
        
        let activeCount = ChallengeService.shared.activeChallenges.count
        let groupCount = ChallengeService.shared.activeGroupChallenges.count
        
        guard activeCount > 0 || groupCount > 0 else {
            let duration = Date().timeIntervalSince(start)
            AppLogger.info("✅ [BG SYNC] Sync complete in \(String(format: "%.1f", duration))s (no active challenges)", category: .social)
            return
        }
        
        // ── Step 4b: Refresh meal & hydration data for today ──
        // Without this, stale yesterday data would be synced as today's progress.
        MealService.shared.ensureFreshForToday()
        await HydrationService.shared.loadTodayData()
        
        // ── Step 5: Push ALL health data to challenges ──
        // This calls log_challenge_progress for each relevant challenge type
        await ChallengeService.shared.syncAllTrackingToChallenges()
        
        // ── Step 6: Sync private & community challenges ──
        // These have their own daily progress tables and need the same sync
        await PrivateChallengeService.shared.syncAllTrackingToPrivateChallenges()
        await CommunityChallengeService.shared.syncAllTrackingToCommunityChallenges()
        
        let privateChallengeCount = PrivateChallengeService.shared.myChallenges.count
        let communityChallengeCount = CommunityChallengeService.shared.myChallenges.count
        
        let duration = Date().timeIntervalSince(start)
        AppLogger.info("✅ [BG SYNC] Background sync complete in \(String(format: "%.1f", duration))s", category: .social)
        AppLogger.debug("   └─ Synced to \(activeCount) 1v1 + \(groupCount) group + \(privateChallengeCount) private + \(communityChallengeCount) community challenges", category: .social)

        // ── Step 6b: Refresh the dashboard welcome-card recommendation cache ──
        // Quests + health are already fresh by this point (Steps 1 & 4b), so
        // this run picks up today's "close the gap" nudge with live data.
        // Caching it to disk means the next cold launch can hydrate the
        // welcome card instantly — no blank state, no flicker before the
        // real message appears. Also ensures daily-quests fetched above are
        // reflected before we compute the recommendation.
        await DailyQuestService.shared.fetchDailyQuests()
        await AdvancedIntelligenceService.shared.refreshCachedRecommendation()

        // ── Step 7: Nudge opponents so their stats show up fresh for US next time.
        // Fire-and-forget silent push wake to every opponent in our active
        // challenges. Server-side throttle (15 min/recipient) prevents abuse
        // regardless of how often this path runs. Safe no-op when edge function
        // is unavailable.
        Task.detached(priority: .background) {
            await ChallengeOpponentWakeService.shared.requestWake(trigger: .backgroundSync)
        }
    }
}
