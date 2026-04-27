import Foundation
import HealthKit
import SwiftUI
import UIKit
import WidgetKit

// MARK: - HealthKit Manager
/// Manages all HealthKit interactions including step tracking with cloud sync.
/// Responsible for HealthKit authorization, data observation, and Supabase cloud sync.
/// HealthKitService.swift handles local data reading/caching for UI display.
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    private let supabaseManager = SupabaseManager.shared
    
    // Published properties for real-time UI updates
    @Published var isAuthorized = false
    @Published var todaySteps: Int = 0
    @Published var weeklySteps: [DailySteps] = []
    @Published var monthlyAverage: Int = 0
    @Published var stepGoal: Int = 10000
    @Published var isLoading = false

    // Bug-intel 80234a6b (2026-04-27): user shake at 4:12 AM — "my steps in
    // app did not immediately reset to 0 at the start of the new day."
    // `todaySteps` had no day-boundary tracking; once set at e.g. 11:30 PM
    // yesterday, the @Published value persisted across midnight until the
    // next `fetchTodaySteps()` ran. ChallengeProgressResolver.resolveProgress
    // (.steps) reads HealthKitManager.shared.todaySteps and would happily
    // return yesterday's count.
    //
    // Fix: stamp the local-day component every time we update todaySteps,
    // and expose `effectiveTodaySteps` which returns 0 when the cached value
    // isn't from today's local day. ChallengeProgressResolver reads the
    // effective accessor; the raw `todaySteps` stays public for compat.
    /// Local day-of-year + year of the last successful `fetchTodaySteps()`.
    /// nil = never fetched. Compared against the current calendar day on
    /// every read of `effectiveTodaySteps` so a stale post-midnight cache
    /// returns 0 instead of yesterday's count.
    private var todayStepsFetchedDay: (year: Int, month: Int, day: Int)?

    /// `todaySteps` gated on day freshness. Returns 0 if the cached value
    /// is from a previous local day. Use this in challenge / quest progress
    /// resolvers; the raw `todaySteps` is kept for backward compat where
    /// callers explicitly want "last known fetched value."
    ///
    /// We stamp `(year, month, day)` rather than `(year, dayOfYear)` because
    /// `Calendar.Component.dayOfYear` is iOS 18+; the year + month + day
    /// triple is equivalent for a "same local calendar day?" comparison and
    /// keeps the deployment target unconstrained.
    var effectiveTodaySteps: Int {
        guard let stamp = todayStepsFetchedDay else { return 0 }
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        if stamp.year == comps.year && stamp.month == comps.month && stamp.day == comps.day {
            return todaySteps
        }
        return 0
    }
    
    /// Whether to save workouts to Apple Health (user preference)
    @Published var saveWorkoutsToHealth: Bool {
        didSet {
            UserDefaults.standard.set(saveWorkoutsToHealth, forKey: "saveWorkoutsToHealth")
            AppLogger.debug("Save workouts to Health: \(saveWorkoutsToHealth)", category: .health)
        }
    }
    
    /// Last workout saved to Health (for confirmation UI)
    @Published var lastSavedWorkoutName: String?
    @Published var showHealthSaveConfirmation: Bool = false
    
    // ⚡️ PERFORMANCE: Debounce mechanism for cloud sync to prevent rapid consecutive syncs
    private var lastStepSyncTime: Date?
    private let stepSyncDebounceInterval: TimeInterval = 30 // Only sync every 30 seconds max
    private var isSyncingSteps = false // Prevent concurrent syncs
    
    
    // Step data structure
    struct DailySteps: Identifiable {
        let id = UUID()
        let date: Date
        let steps: Int
        var isToday: Bool {
            Calendar.current.isDateInToday(date)
        }
    }
    
    private init() {
        // Load user preference for saving workouts to Health (default: true)
        self.saveWorkoutsToHealth = UserDefaults.standard.object(forKey: "saveWorkoutsToHealth") as? Bool ?? true
        checkAuthorization()
        registerDayBoundaryObservers()
    }

    // MARK: - Day Boundary Reset (bug-intel 80234a6b — 2026-04-27)

    /// Register OS-driven observers that fire when the local calendar
    /// rolls over (midnight in the user's current timezone) OR when the
    /// system clock / timezone changes. On fire, we:
    ///   1. Zero out `todaySteps` immediately so any synchronous reader
    ///      (e.g. ChallengeProgressResolver) sees the correct value.
    ///   2. Clear `todayStepsFetchedDay` so `effectiveTodaySteps` is also
    ///      gated to zero until the next fetch lands.
    ///   3. Trigger a fresh `fetchTodaySteps()` — at 00:00:01 the HK
    ///      query for `startOfDay…now` returns 0, which matches reality.
    ///   4. Reload all WidgetKit timelines so the Active Challenge widget
    ///      (which reads HealthKit directly via Phase 7c) re-renders with
    ///      0 steps without waiting for its next 20-min tick.
    ///
    /// Both observers are registered for the singleton's lifetime; no
    /// teardown needed because `HealthKitManager.shared` is a process
    /// singleton (matches how the rest of the app uses it).
    private func registerDayBoundaryObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleDayBoundaryRollover),
            name: .NSCalendarDayChanged,
            object: nil
        )
        // `significantTimeChange` fires for: timezone shift, daylight
        // saving transition, manual clock changes — all of which can
        // also invalidate the cached "today's steps" assumption.
        center.addObserver(
            self,
            selector: #selector(handleDayBoundaryRollover),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )
    }

    @objc private func handleDayBoundaryRollover() {
        AppLogger.info("📅 [HK] Day boundary detected — resetting todaySteps + reloading widget timelines", category: .health)

        Task { @MainActor in
            // Step 1+2: zero the cache. effectiveTodaySteps now returns 0
            // until the next fetch stamps the new local day.
            self.todaySteps = 0
            self.todayStepsFetchedDay = nil
        }

        // Step 3: re-fetch from HealthKit. At 00:00:01 this returns 0
        // (HK query range is `startOfDay(for: now)` → `now`). If the user
        // happens to be walking right at midnight, we'll catch the first
        // few steps of the new day and the widget will reflect it on the
        // next tick.
        Task { await self.fetchTodaySteps() }

        // Step 4: force WidgetKit to regenerate timelines. The Active
        // Challenge widget's timeline provider reads HK directly via
        // `WidgetHealthKitReader` (Phase 7c), so the next render cycle
        // will see 0 from HK + 0 from the server's new-day row (or no
        // row yet for today, which the widget handles). Without this
        // call the widget would stay on yesterday's snapshot until its
        // next 20-min `.policy(.after(...))` tick.
        //
        // Route through `DailyGoalsWidgetBridge.requestMidnightReset()`
        // (audit 2026-04-27 #14): this path is the singular midnight
        // reset for both widgets, so we go through the bridge which
        // applies a 60s coalescing window across back-to-back
        // day-changed / significantTimeChange ticks instead of issuing
        // an unguarded `reloadAllTimelines()` for each.
        DailyGoalsWidgetBridge.requestMidnightReset()
    }
    
    // MARK: - Authorization
    
    /// Request HealthKit authorization for steps and workouts
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        // Types to READ from HealthKit
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let workoutType = HKObjectType.workoutType()
        
        // Body metrics for accurate calorie calculation
        let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
        let biologicalSexType = HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        let dateOfBirthType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        
        let typesToRead: Set<HKObjectType> = [
            stepType, activeEnergyType, workoutType,
            bodyMassType, heightType, biologicalSexType, dateOfBirthType
        ]
        
        // Types to WRITE to HealthKit (workouts + calories)
        let typesToWrite: Set<HKSampleType> = [workoutType, activeEnergyType]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            await MainActor.run {
                self.isAuthorized = true
                // Sync with HealthKitService so Settings shows "Connected" ✅
                UserDefaults.standard.set(true, forKey: "healthkit_authorized")
                HealthKitService.shared.isAuthorized = true
            }
            AppLogger.info("HealthKit authorized for steps + workout writing", category: .health)
            
            // Update integration status in database
            await SupabaseManager.shared.updateIntegrationStatus(integration: "apple_health", isConnected: true)
            
            // Sprint 3 Q2-28: HK observer ownership lives in
            // BackgroundChallengeSyncService. We subscribe to its notifications
            // instead of running our own HKObserverQuery.
            subscribeToSyncNotifications()
            
            // Initial data fetch
            await fetchTodaySteps()
            await fetchWeeklySteps()
            await fetchMonthlyAverage()
            
            // Also sync HealthKitService data
            await HealthKitService.shared.syncAllData(force: true)
        } catch {
            AppLogger.error("HealthKit authorization error: \(error.localizedDescription)", category: .health)
            throw error
        }
    }
    
    // MARK: - 🏋️ Save Workout to Apple Health
    
    /// Save a completed workout to Apple Health
    /// This fills the Exercise ring and shows in Apple Fitness!
    func saveWorkoutToHealth(
        workoutName: String,
        startDate: Date,
        endDate: Date,
        durationSeconds: TimeInterval,
        caloriesBurned: Double,
        exerciseCount: Int,
        workoutType: WorkoutActivityType = .strengthTraining
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        // Map our workout type to HealthKit activity type
        let activityType = workoutType.hkWorkoutActivityType
        
        // Create the workout
        let workout = HKWorkout(
            activityType: activityType,
            start: startDate,
            end: endDate,
            duration: durationSeconds,
            totalEnergyBurned: caloriesBurned > 0 ? HKQuantity(unit: .kilocalorie(), doubleValue: caloriesBurned) : nil,
            totalDistance: nil,
            metadata: [
                HKMetadataKeyWorkoutBrandName: "Fit33",
                "WorkoutName": workoutName,
                "ExerciseCount": exerciseCount
            ]
        )
        
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await healthStore.save(workout)
                AppLogger.info("Workout saved to Apple Health: \(workoutName), \(Int(durationSeconds / 60))min, \(Int(caloriesBurned))kcal, \(exerciseCount) exercises, type: \(activityType.name)", category: .health)
                
                await MainActor.run {
                    self.lastSavedWorkoutName = workoutName
                    self.showHealthSaveConfirmation = true
                    
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        self.showHealthSaveConfirmation = false
                    }

                    NotificationCenter.default.post(name: NSNotification.Name("WorkoutSavedToHealth"), object: nil)
                }
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
                let isTimedOutMessage = error.localizedDescription.lowercased().contains("timed out")
                
                if (isTimeout || isTimedOutMessage) && attempt < 2 {
                    let delay = UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000
                    AppLogger.warning("HealthKit workout save timed out (attempt \(attempt + 1)/3) — retrying in \(Int(pow(2.0, Double(attempt + 1))))s", category: .health)
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                break
            }
        }
        
        AppLogger.error("Failed to save workout after retries: \(lastError?.localizedDescription ?? "unknown")", category: .health)
        throw HealthKitError.saveFailed(lastError ?? NSError(domain: "HealthKit", code: -1))
    }
    
    /// Save a running workout to Apple Health with distance
    func saveRunningWorkoutToHealth(
        startDate: Date,
        endDate: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Double,
        caloriesBurned: Double
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        // Create the running workout with distance
        let workout = HKWorkout(
            activityType: .running,
            start: startDate,
            end: endDate,
            duration: durationSeconds,
            totalEnergyBurned: caloriesBurned > 0 ? HKQuantity(unit: .kilocalorie(), doubleValue: caloriesBurned) : nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
            metadata: [
                HKMetadataKeyWorkoutBrandName: "Fit33",
                HKMetadataKeyIndoorWorkout: false
            ]
        )
        
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await healthStore.save(workout)
                
                let distanceKm = distanceMeters / 1000.0
                var paceString = "--:--"
                if distanceKm > 0.01 {
                    let paceSecondsPerKm = durationSeconds / distanceKm
                    if paceSecondsPerKm.isFinite && paceSecondsPerKm > 0 && paceSecondsPerKm < 3600 {
                        let paceMin = Int(paceSecondsPerKm) / 60
                        let paceSec = Int(paceSecondsPerKm) % 60
                        paceString = "\(paceMin):\(String(format: "%02d", paceSec))"
                    }
                }
                
                AppLogger.info("Running workout saved to Apple Health: \(String(format: "%.2f", distanceKm))km, \(Int(durationSeconds / 60))min, pace \(paceString)/km, \(Int(caloriesBurned))kcal", category: .health)
                
                await MainActor.run {
                    self.lastSavedWorkoutName = "Outdoor Run"
                    self.showHealthSaveConfirmation = true
                    
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        self.showHealthSaveConfirmation = false
                    }

                    NotificationCenter.default.post(name: NSNotification.Name("WorkoutSavedToHealth"), object: nil)
                }
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
                let isTimedOutMessage = error.localizedDescription.lowercased().contains("timed out")
                
                if (isTimeout || isTimedOutMessage) && attempt < 2 {
                    let delay = UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000
                    AppLogger.warning("HealthKit running workout save timed out (attempt \(attempt + 1)/3) — retrying in \(Int(pow(2.0, Double(attempt + 1))))s", category: .health)
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                break
            }
        }
        
        AppLogger.error("Failed to save running workout after retries: \(lastError?.localizedDescription ?? "unknown")", category: .health)
        throw HealthKitError.saveFailed(lastError ?? NSError(domain: "HealthKit", code: -1))
    }
    
    /// Estimate calories burned for a strength training workout (simplified method)
    /// For accurate calculation, use calculateDetailedCalories with exercise data
    func estimateCaloriesBurned(
        durationMinutes: Double,
        exerciseCount: Int,
        intensity: WorkoutIntensity = .moderate
    ) async -> Double {
        // Fetch user biometrics for accurate calculation
        let user = await WorkoutCalorieCalculator.fetchUserBiometrics()
        
        // Map our intensity to calculator intensity
        let calcIntensity: WorkoutCalorieCalculator.WorkoutIntensity
        switch intensity {
        case .light: calcIntensity = .light
        case .moderate: calcIntensity = .moderate
        case .vigorous: calcIntensity = .vigorous
        }
        
        return WorkoutCalorieCalculator.calculateCaloriesSimplified(
            durationMinutes: durationMinutes,
            exerciseCount: exerciseCount,
            estimatedIntensity: calcIntensity,
            user: user
        )
    }
    
    /// Calculate detailed calories with full exercise data (Apple Fitness-quality accuracy)
    /// This uses the comprehensive WorkoutCalorieCalculator
    func calculateDetailedCalories(
        exercises: [ExerciseCalorieData],
        totalDurationSeconds: TimeInterval
    ) async -> CalorieResult {
        let user = await WorkoutCalorieCalculator.fetchUserBiometrics()
        
        let result = WorkoutCalorieCalculator.calculateCalories(
            exercises: exercises,
            totalDurationSeconds: totalDurationSeconds,
            user: user
        )
        
        // Log the detailed breakdown
        AppLogger.debug("Calorie calculation: \(result.summary)", category: .health)
        
        return result
    }
    
    // MARK: - Workout Type Mapping
    
    /// Workout activity types supported by the app
    enum WorkoutActivityType {
        case strengthTraining    // Traditional strength/weight training
        case functionalTraining  // Functional/CrossFit style
        case hiit                // High intensity interval
        case coreTraining        // Core/abs focused
        case flexibility         // Stretching/yoga
        case cardio              // General cardio
        case mixedCardio         // Mixed workout
        
        var hkWorkoutActivityType: HKWorkoutActivityType {
            switch self {
            case .strengthTraining:
                return .traditionalStrengthTraining
            case .functionalTraining:
                return .functionalStrengthTraining
            case .hiit:
                return .highIntensityIntervalTraining
            case .coreTraining:
                return .coreTraining
            case .flexibility:
                return .flexibility
            case .cardio:
                return .running
            case .mixedCardio:
                return .mixedCardio
            }
        }
    }
    
    /// Workout intensity levels for calorie estimation
    enum WorkoutIntensity {
        case light      // Easy pace, lots of rest
        case moderate   // Normal workout pace
        case vigorous   // High intensity, minimal rest
    }
    
    func checkAuthorizationStatus() {
        checkAuthorization()
    }
    
    private func checkAuthorization() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let status = healthStore.authorizationStatus(for: stepType)
        
        // Check both the write authorization status AND the UserDefaults flag
        // UserDefaults is set when user approves via ANY authorization request
        let hasWriteAuth = (status == .sharingAuthorized)
        let hasStoredAuth = UserDefaults.standard.bool(forKey: "healthkit_authorized")
        
        isAuthorized = hasWriteAuth || hasStoredAuth
        
        // Keep UserDefaults and HealthKitService in sync
        if isAuthorized && !hasStoredAuth {
            UserDefaults.standard.set(true, forKey: "healthkit_authorized")
        }
        if isAuthorized {
            // HealthKitService is @MainActor, so we need to update it on main thread
            Task { @MainActor in
                HealthKitService.shared.isAuthorized = true
            }
        }
        
        if isAuthorized {
            subscribeToSyncNotifications()
            Task {
                await fetchTodaySteps()
                await fetchWeeklySteps()
                await fetchMonthlyAverage()
            }
        }
    }

    // MARK: - HK Observer (Unified — Sprint 3 Q2-28)
    //
    // Before Sprint 3, `HealthKitManager` ran its own foreground `HKObserverQuery`
    // for `stepCount` and `workoutType`, AND `BackgroundChallengeSyncService`
    // registered another pair (plus energy/distance/exerciseTime) with immediate
    // background delivery. Both fired in the foreground, so every HK delivery
    // triggered duplicate fetches and duplicate cloud syncs.
    //
    // Single owner now: `BackgroundChallengeSyncService` runs all HK observers.
    // When it finishes a sync it posts `.healthStepsDidUpdate` (step/energy/
    // distance/exerciseTime) and/or `.externalWorkoutSynced` (workouts) on the
    // main thread. We refresh our `@Published` UI state off those notifications.

    private var syncNotificationObservers: [NSObjectProtocol] = []

    private func subscribeToSyncNotifications() {
        guard syncNotificationObservers.isEmpty else { return }

        let stepsObserver = NotificationCenter.default.addObserver(
            forName: .healthStepsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.fetchTodaySteps()
                await self.syncTodayStepsToCloud()
            }
        }
        syncNotificationObservers.append(stepsObserver)

        let workoutObserver = NotificationCenter.default.addObserver(
            forName: .externalWorkoutSynced,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `BackgroundChallengeSyncService` has already persisted the new
            // workout to `cardio_workouts`. We just refresh our local caches so
            // any view observing HealthKitManager sees the updated counts.
            Task { [weak self] in
                guard let self else { return }
                await self.fetchTodaySteps()
                await self.fetchWeeklySteps()
            }
        }
        syncNotificationObservers.append(workoutObserver)

        AppLogger.info("HealthKitManager subscribed to unified HK sync notifications", category: .health)
    }

    deinit {
        for observer in syncNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Fetch Step Data
    
    /// Fetch today's step count from HealthKit
    func fetchTodaySteps() async {
        guard isAuthorized else { return }
        await MainActor.run { isLoading = true }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            guard let self = self else { return }
            
            if let error = error {
                let desc = error.localizedDescription.lowercased()
                let isExpectedHKError = desc.contains("protected health data")
                    || desc.contains("no data available")
                    || desc.contains("authorization not determined")
                    || desc.contains("no samples")
                
                if isExpectedHKError {
                    // Silent — expected on simulator and when no data exists
                } else {
                    let nsErr = error as NSError
                    AppLogger.error("[STEPS] Unexpected HealthKit error (domain: \(nsErr.domain), code: \(nsErr.code)): \(error.localizedDescription)", category: .health)
                }
                Task { await MainActor.run { self.isLoading = false } }
                return
            }
            
            let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)

            // Stamp the local day so `effectiveTodaySteps` can detect a
            // stale cache after a midnight rollover (bug-intel 80234a6b).
            // Year + month + day (not dayOfYear, which is iOS 18+).
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: Date())
            let stamp = (year: comps.year ?? 0,
                         month: comps.month ?? 0,
                         day: comps.day ?? 0)

            Task {
                await MainActor.run {
                    self.todaySteps = steps
                    self.todayStepsFetchedDay = stamp
                    self.isLoading = false
                    // Optimistic widget patch — `ChallengeProgressResolver`
                    // reads `HealthKitManager.todaySteps` first, so this
                    // surface needs the same fast-path as `HealthKitService`.
                    ActiveChallengeWidgetBridge.publishOptimisticLocalProgress()
                }
                
                // Update daily quest progress with latest step count
                await DailyQuestService.shared.onStepsUpdated(todaySteps: steps)
                
                // Sync to cloud
                await self.syncTodayStepsToCloud()
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Fetch weekly step data for the chart
    func fetchWeeklySteps() async {
        guard isAuthorized else { return }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        
        var interval = DateComponents()
        interval.day = 1
        
        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: nil,
            options: .cumulativeSum,
            anchorDate: startOfWeek,
            intervalComponents: interval
        )
        
        query.initialResultsHandler = { [weak self] query, results, error in
            guard let self = self, let results = results else {
                if let error = error {
                    let desc = error.localizedDescription
                    if desc.contains("Protected health data") || desc.contains("No data available") {
                        AppLogger.debug("Weekly steps unavailable: \(desc)", category: .health)
                    } else {
                        AppLogger.error("Error fetching weekly steps: \(desc)", category: .health)
                    }
                }
                return
            }
            
            var dailyData: [DailySteps] = []
            
            results.enumerateStatistics(from: startOfWeek, to: now) { statistics, stop in
                let steps = Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                dailyData.append(DailySteps(date: statistics.startDate, steps: steps))
            }
            
            Task {
                await MainActor.run {
                    self.weeklySteps = dailyData
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Fetch monthly average steps
    func fetchMonthlyAverage() async {
        guard isAuthorized else { return }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfMonth, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            guard let self = self else { return }
            
            if let error = error {
                let desc = error.localizedDescription
                if desc.contains("Protected health data") || desc.contains("No data available") {
                    // Silent — expected on simulator and when no data exists
                } else {
                    AppLogger.error("Error fetching monthly steps: \(desc)", category: .health)
                }
                return
            }
            
            let totalSteps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            let daysInMonth = calendar.dateComponents([.day], from: startOfMonth, to: now).day ?? 1
            let average = daysInMonth > 0 ? totalSteps / daysInMonth : 0
            
            Task {
                await MainActor.run {
                    self.monthlyAverage = average
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Cloud Sync
    
    /// Sync today's steps to Supabase cloud (with debounce to prevent rapid consecutive syncs)
    private func syncTodayStepsToCloud() async {
        guard supabaseManager.isAuthenticated else {
            return
        }
        
        // ⚡️ PERFORMANCE: Prevent concurrent syncs AND enforce cooldown
        guard !isSyncingSteps else { return } // Already syncing
        
        // Debounce: Skip if we synced recently
        if let lastSync = lastStepSyncTime,
           Date().timeIntervalSince(lastSync) < stepSyncDebounceInterval {
            return // Silently skip - don't spam logs
        }
        
        // Mark as syncing BEFORE async work to prevent race conditions
        isSyncingSteps = true
        lastStepSyncTime = Date() // Set time immediately to block concurrent calls
        defer { isSyncingSteps = false }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        do {
            var succeeded = false
            var lastError: Error?
            for attempt in 0...1 {
                do {
                    try await supabaseManager.saveStepData(
                        date: today,
                        steps: todaySteps,
                        goal: stepGoal
                    )
                    succeeded = true
                    break
                } catch {
                    lastError = error
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut && attempt < 1 {
                        AppLogger.warning("Steps sync timed out — retrying once in 2s...", category: .health)
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    throw error
                }
            }
            if succeeded {
                AppLogger.info("Synced \(todaySteps) steps to cloud", category: .health)
                if let userId = supabaseManager.currentUser?.id {
                    await AdvancedIntelligenceService.shared.trackActivityForRecovery(
                        userId: userId,
                        date: today,
                        steps: todaySteps
                    )
                }
            }
        } catch {
            NetworkErrorClassifier.log(error, context: "Syncing steps to cloud", category: .health)
        }
    }
    
    /// Sync weekly steps to cloud (batch operation)
    func syncWeeklyStepsToCloud() async {
        guard supabaseManager.isAuthenticated else { return }
        
        // ⚡️ PERFORMANCE: Batch all steps into a single upsert instead of individual calls
        do {
            try await supabaseManager.batchSaveStepData(weeklySteps, goal: stepGoal)
            AppLogger.info("Synced \(weeklySteps.count) days of steps to cloud in single batch", category: .health)
        } catch {
            NetworkErrorClassifier.log(error, context: "Batch syncing weekly steps", category: .health)
        }
    }
    
    /// Fetch step data from cloud (for syncing across devices)
    func fetchStepsFromCloud() async throws -> [DailySteps] {
        guard supabaseManager.isAuthenticated else { return [] }
        
        let cloudSteps = try await supabaseManager.fetchRecentSteps(days: 30)
        
        return cloudSteps.map { cloudStep in
            DailySteps(
                date: ISO8601DateFormatter().date(from: cloudStep.date) ?? Date(),
                steps: cloudStep.steps
            )
        }
    }
    
    // MARK: - Step Goal Management
    
    /// Update daily step goal and sync to cloud
    func updateStepGoal(_ newGoal: Int) async {
        await MainActor.run {
            self.stepGoal = newGoal
        }
        
        // Save goal to UserDefaults for local persistence
        UserDefaults.standard.set(newGoal, forKey: "dailyStepGoal")
        
        // Sync to cloud
        if supabaseManager.isAuthenticated {
            do {
                try await supabaseManager.updateStepGoal(newGoal)
                AppLogger.info("Step goal updated to \(newGoal)", category: .health)
            } catch {
                NetworkErrorClassifier.log(error, context: "Updating step goal", category: .health)
            }
        }
    }
    
    /// Load step goal from local storage or cloud
    func loadStepGoal() async {
        // First try local
        let localGoal = UserDefaults.standard.integer(forKey: "dailyStepGoal")
        if localGoal > 0 {
            await MainActor.run {
                self.stepGoal = localGoal
            }
        }
        
        // Then sync from cloud if authenticated
        if supabaseManager.isAuthenticated {
            do {
                if let cloudGoal = try await supabaseManager.fetchStepGoal() {
                    await MainActor.run {
                        self.stepGoal = cloudGoal
                    }
                    UserDefaults.standard.set(cloudGoal, forKey: "dailyStepGoal")
                }
            } catch {
                NetworkErrorClassifier.log(
                    error,
                    context: "Loading step goal from cloud",
                    category: .health,
                    transientLevel: .debug   // cold-start cancels are noisy; keep them silent
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculate progress percentage towards goal
    func progressPercentage() -> Double {
        guard stepGoal > 0 else { return 0 }
        return min(Double(todaySteps) / Double(stepGoal), 1.0)
    }
    
    /// Get step goal achievement status
    func isGoalAchieved() -> Bool {
        return todaySteps >= stepGoal
    }
    
    /// Format steps with commas
    func formattedSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
    
    /// Get motivational message based on progress
    func getMotivationalMessage() -> String {
        let progress = progressPercentage()
        
        if progress >= 1.0 {
            return "🎉 Goal crushed! Amazing work!"
        } else if progress >= 0.75 {
            return "🔥 Almost there! Keep moving!"
        } else if progress >= 0.5 {
            return "💪 Halfway to your goal!"
        } else if progress >= 0.25 {
            return "👟 Great start! Keep it up!"
        } else {
            return "🚶 Let's get moving today!"
        }
    }
}

// MARK: - HealthKit Error
enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .saveFailed(let error):
            return "Failed to save to HealthKit: \(error.localizedDescription)"
        }
    }
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .traditionalStrengthTraining:
            return "Strength Training"
        case .functionalStrengthTraining:
            return "Functional Training"
        case .highIntensityIntervalTraining:
            return "HIIT"
        case .coreTraining:
            return "Core Training"
        case .flexibility:
            return "Flexibility"
        case .running:
            return "Cardio"
        case .mixedCardio:
            return "Mixed Cardio"
        default:
            return "Workout"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when an external workout (Apple Watch, Nike Run Club, Strava, etc.)
    /// is detected via HealthKit and synced to cardio_workouts in Supabase.
    /// Dashboard should reload cardio workouts when this fires.
    static let externalWorkoutSynced = Notification.Name("externalWorkoutSynced")

    /// Posted by `BackgroundChallengeSyncService` when HealthKit delivers new
    /// step / activeEnergy / distance / exerciseTime data AND the throttle has
    /// allowed a sync to run. Observed by `HealthKitManager` to refresh its
    /// `@Published todaySteps` / `weeklySteps` / `monthlyAverage` state.
    ///
    /// Sprint 3 (Q2-28) unified HK observer ownership under
    /// `BackgroundChallengeSyncService`; `HealthKitManager` no longer runs its
    /// own `HKObserverQuery` for steps or workouts.
    static let healthStepsDidUpdate = Notification.Name("healthStepsDidUpdate")
}