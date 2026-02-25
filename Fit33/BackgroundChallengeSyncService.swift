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
    
    /// BGTask identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers
    static let bgTaskIdentifier = "com.gofit.app.challengeSync"
    
    /// Minimum interval between background syncs (prevents excessive syncing)
    private let minimumSyncInterval: TimeInterval = 600 // 10 minutes
    private let lastSyncKey = "bg_challenge_last_sync"
    
    private init() {}
    
    // ═══════════════════════════════════════════════════════════
    // MARK: - Setup (Call once at app launch)
    // ═══════════════════════════════════════════════════════════
    
    /// Call this from Fit33App.swift init or .task on first launch.
    /// Enables HealthKit background delivery and registers the BGTask.
    func setup() {
        enableHealthKitBackgroundDelivery()
        registerBackgroundTask()
        scheduleNextBackgroundSync()
        
        print("🔄 [BG SYNC] BackgroundChallengeSyncService initialized")
        print("   └─ HealthKit background delivery: enabled for steps, workouts, active energy")
        print("   └─ BGTask periodic sync: registered")
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
        let challengeRelevantTypes: [(HKQuantityType, HKUpdateFrequency)] = [
            // Steps — updates frequently from Apple Watch/phone pedometer
            (HKQuantityType.quantityType(forIdentifier: .stepCount)!, .immediate),
            
            // Active energy — tracks active minutes / calorie burn
            (HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!, .hourly),
            
            // Walking/running distance — for walk/run challenges
            (HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!, .hourly),
            
            // Exercise time — for active minutes challenges
            (HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!, .hourly),
        ]
        
        // Workout type — for lift/workout streak challenges (Strava, Nike RC, etc.)
        let workoutType = HKObjectType.workoutType()
        
        // Enable background delivery for each type
        for (quantityType, frequency) in challengeRelevantTypes {
            healthStore.enableBackgroundDelivery(for: quantityType, frequency: frequency) { success, error in
                if success {
                    print("✅ [BG SYNC] Background delivery enabled: \(quantityType.identifier)")
                } else if let error = error {
                    print("❌ [BG SYNC] Failed to enable background delivery for \(quantityType.identifier): \(error.localizedDescription)")
                }
            }
        }
        
        // Enable for workout type separately (different API)
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if success {
                print("✅ [BG SYNC] Background delivery enabled: workouts")
            } else if let error = error {
                print("❌ [BG SYNC] Failed to enable background delivery for workouts: \(error.localizedDescription)")
            }
        }
        
        // Set up observer queries that fire in the background
        setupBackgroundObserverQueries()
    }
    
    /// Observer queries that iOS will wake the app for.
    /// These are separate from the foreground observers in HealthKitManager.
    private func setupBackgroundObserverQueries() {
        // Steps observer — syncs step challenges
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let stepObserver = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, _, error in
            guard error == nil else { return }
            self?.handleBackgroundHealthUpdate(source: "steps")
        }
        healthStore.execute(stepObserver)
        
        // Workout observer — syncs lift/run/walk/streak challenges
        let workoutObserver = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, _, error in
            guard error == nil else { return }
            self?.handleBackgroundHealthUpdate(source: "workout")
        }
        healthStore.execute(workoutObserver)
        
        // Active energy observer — syncs active minutes/calorie challenges
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let energyObserver = HKObserverQuery(sampleType: energyType, predicate: nil) { [weak self] _, _, error in
            guard error == nil else { return }
            self?.handleBackgroundHealthUpdate(source: "active_energy")
        }
        healthStore.execute(energyObserver)
        
        // Distance observer — syncs walk/run challenges
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distanceObserver = HKObserverQuery(sampleType: distanceType, predicate: nil) { [weak self] _, _, error in
            guard error == nil else { return }
            self?.handleBackgroundHealthUpdate(source: "distance")
        }
        healthStore.execute(distanceObserver)
    }
    
    /// Called when HealthKit delivers new data in the background.
    /// Throttled to prevent excessive syncing (max once per 10 minutes).
    private func handleBackgroundHealthUpdate(source: String) {
        let now = Date()
        let lastSync = UserDefaults.standard.double(forKey: lastSyncKey)
        let lastSyncDate = Date(timeIntervalSince1970: lastSync)
        
        // Throttle: don't sync more often than every 10 minutes
        guard now.timeIntervalSince(lastSyncDate) >= minimumSyncInterval else {
            print("⏭️ [BG SYNC] Skipping \(source) — synced \(Int(now.timeIntervalSince(lastSyncDate)))s ago")
            return
        }
        
        print("🔄 [BG SYNC] HealthKit background update: \(source)")
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastSyncKey)
        
        // Perform the sync on a background task
        Task {
            await performChallengeSyncInBackground()
        }
    }
    
    // ═══════════════════════════════════════════════════════════
    // MARK: - BGTaskScheduler Periodic Refresh
    // ═══════════════════════════════════════════════════════════
    
    /// Register the background task with iOS.
    /// Must be called before the app finishes launching.
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task as! BGAppRefreshTask)
        }
        
        print("✅ [BG SYNC] BGTask registered: \(Self.bgTaskIdentifier)")
    }
    
    /// Schedule the next background refresh.
    /// iOS will wake the app approximately every 15-30 minutes (depends on user patterns).
    func scheduleNextBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        // Ask iOS to run this no earlier than 15 minutes from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 [BG SYNC] Next background sync scheduled (earliest: ~15 min)")
        } catch {
            print("❌ [BG SYNC] Failed to schedule background task: \(error.localizedDescription)")
        }
    }
    
    /// Handle the BGTask when iOS wakes the app.
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        print("🔄 [BG SYNC] BGTask fired — syncing challenge data...")
        
        // Schedule the NEXT background sync immediately (so it keeps repeating)
        scheduleNextBackgroundSync()
        
        // Set up expiration handler
        task.expirationHandler = {
            print("⏰ [BG SYNC] BGTask expired before completion")
        }
        
        // Perform the sync
        Task {
            await performChallengeSyncInBackground()
            task.setTaskCompleted(success: true)
            print("✅ [BG SYNC] BGTask completed successfully")
        }
    }
    
    // ═══════════════════════════════════════════════════════════
    // MARK: - Core Sync Logic
    // ═══════════════════════════════════════════════════════════
    
    /// The actual sync: fetches latest HealthKit data and pushes to all active challenges.
    /// This runs both from HealthKit background delivery and BGTask periodic refresh.
    /// Also callable from the simulator for testing.
    @MainActor
    func performChallengeSyncInBackground() async {
        guard SupabaseManager.shared.isAuthenticated else {
            print("⏭️ [BG SYNC] Not authenticated — skipping")
            return
        }
        
        let start = Date()
        print("🔄 [BG SYNC] Starting background challenge sync...")
        
        // Step 1: Refresh HealthKit data (steps, workouts, active minutes, distance)
        await HealthKitService.shared.syncAllData(force: true)
        print("   └─ HealthKit data refreshed: \(HealthKitService.shared.todaySteps) steps, \(HealthKitService.shared.todayActiveMinutes) active min")
        
        // Step 2: Refresh the list of active challenges (need to know what to sync to)
        await ChallengeService.shared.fetchActiveChallenges()
        await ChallengeService.shared.fetchActiveGroupChallenges()
        
        let activeCount = ChallengeService.shared.activeChallenges.count
        let groupCount = ChallengeService.shared.activeGroupChallenges.count
        
        guard activeCount > 0 || groupCount > 0 else {
            print("⏭️ [BG SYNC] No active challenges — skipping sync")
            return
        }
        
        // Step 3: Push HealthKit data to all active challenges
        // This calls log_challenge_progress for each relevant challenge
        await ChallengeService.shared.syncHealthKitDataToChallenges()
        
        let duration = Date().timeIntervalSince(start)
        print("✅ [BG SYNC] Background sync complete in \(String(format: "%.1f", duration))s")
        print("   └─ Synced to \(activeCount) 1v1 + \(groupCount) group challenges")
    }
}
