import Foundation
import HealthKit
import SwiftUI

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
            
            // Start observing steps and workouts after authorization
            startObservingSteps()
            startObservingWorkouts()
            
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
        
        do {
            try await healthStore.save(workout)
            AppLogger.info("Workout saved to Apple Health: \(workoutName), \(Int(durationSeconds / 60))min, \(Int(caloriesBurned))kcal, \(exerciseCount) exercises, type: \(activityType.name)", category: .health)
            
            // Update UI for confirmation
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
        } catch {
            AppLogger.error("Failed to save workout: \(error.localizedDescription)", category: .health)
            throw HealthKitError.saveFailed(error)
        }
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
        
        do {
            try await healthStore.save(workout)
            
            let distanceKm = distanceMeters / 1000.0
            
            // Safely calculate pace - avoid division by zero
            var paceString = "--:--"
            if distanceKm > 0.01 { // At least 10 meters
                let paceSecondsPerKm = durationSeconds / distanceKm
                if paceSecondsPerKm.isFinite && paceSecondsPerKm > 0 && paceSecondsPerKm < 3600 {
                    let paceMin = Int(paceSecondsPerKm) / 60
                    let paceSec = Int(paceSecondsPerKm) % 60
                    paceString = "\(paceMin):\(String(format: "%02d", paceSec))"
                }
            }
            
            AppLogger.info("Running workout saved to Apple Health: \(String(format: "%.2f", distanceKm))km, \(Int(durationSeconds / 60))min, pace \(paceString)/km, \(Int(caloriesBurned))kcal", category: .health)
            
            // Update UI for confirmation
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
        } catch {
            AppLogger.error("Failed to save running workout: \(error.localizedDescription)", category: .health)
            throw HealthKitError.saveFailed(error)
        }
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
            startObservingSteps()
            startObservingWorkouts()
            Task {
                await fetchTodaySteps()
                await fetchWeeklySteps()
                await fetchMonthlyAverage()
            }
        }
    }
    
    // MARK: - Real-time Step Observation
    
    /// Observe step changes in real-time
    private func startObservingSteps() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        // Create an observer query that fires whenever new step data is available
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] query, completionHandler, error in
            if let error = error {
                AppLogger.error("Observer query error: \(error.localizedDescription)", category: .health)
                completionHandler()
                return
            }
            
            // Fetch updated step count
            Task {
                await self?.fetchTodaySteps()
                await self?.syncTodayStepsToCloud()
            }
            
            completionHandler()
        }
        
        healthStore.execute(query)
        AppLogger.info("Started observing step changes", category: .health)
        
        // Note: Background delivery requires special entitlements
        // The observer query above already provides real-time updates when app is active
    }
    
    // MARK: - Real-time Workout Observation
    
    /// Observe new workouts in real-time (Apple Watch, Nike Run Club, Strava, etc.)
    /// When a new workout is recorded in any connected app and synced to Apple Health,
    /// this observer fires and triggers a sync to create a Recent Activity card.
    private func startObservingWorkouts() {
        let workoutType = HKObjectType.workoutType()
        
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error = error {
                AppLogger.error("Workout observer error: \(error.localizedDescription)", category: .health)
                completionHandler()
                return
            }
            
            AppLogger.info("New workout detected in Apple Health — syncing to Recent Activity", category: .health)
            
            Task {
                // Sync HealthKit workouts and persist to Supabase (creates cardio_workouts records)
                await HealthKitService.shared.syncAllData(force: true)
                
                // Post notification so Dashboard reloads cardio workouts immediately
                await MainActor.run {
                    NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
                }
            }
            
            completionHandler()
        }
        
        healthStore.execute(query)
        AppLogger.info("Started observing workout changes (external apps)", category: .health)
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
                AppLogger.error("Error fetching today's steps: \(error.localizedDescription)", category: .health)
                Task { await MainActor.run { self.isLoading = false } }
                return
            }
            
            let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            
            Task {
                await MainActor.run {
                    self.todaySteps = steps
                    self.isLoading = false
                }
                
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
                    AppLogger.error("Error fetching weekly steps: \(error.localizedDescription)", category: .health)
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
                AppLogger.error("Error fetching monthly steps: \(error.localizedDescription)", category: .health)
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
            AppLogger.debug("Not authenticated, skipping step sync to cloud", category: .health)
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
            try await supabaseManager.saveStepData(
                date: today,
                steps: todaySteps,
                goal: stepGoal
            )
            AppLogger.info("Synced \(todaySteps) steps to cloud", category: .health)
            
            // 🧠 ADVANCED INTELLIGENCE: Track activity for recovery correlation
            // This helps recommend workouts based on previous day's activity
            if let userId = supabaseManager.currentUser?.id {
                await AdvancedIntelligenceService.shared.trackActivityForRecovery(
                    userId: userId,
                    date: today,
                    steps: todaySteps
                )
            }
        } catch {
            AppLogger.error("Error syncing steps to cloud: \(error.localizedDescription)", category: .health)
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
            AppLogger.error("Error batch syncing weekly steps: \(error.localizedDescription)", category: .health)
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
                AppLogger.error("Error updating step goal: \(error.localizedDescription)", category: .health)
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
                AppLogger.error("Error loading step goal from cloud: \(error.localizedDescription)", category: .health)
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
}