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
    
    private let healthStore = HKHealthStore()
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
    func syncAllData(force: Bool = false) async {
        guard isAuthorized else { return }
        
        // Throttle
        if !force {
            if isSyncing {
                AppLogger.debug("Skipping HealthKit sync - already in progress", category: .health)
                return
            }
            
            if let lastSync = lastSyncDate,
               Date().timeIntervalSince(lastSync) < Self.syncThrottleInterval {
                AppLogger.debug("Skipping HealthKit sync - synced \(Int(Date().timeIntervalSince(lastSync)))s ago", category: .health)
                return
            }
        }
        
        isSyncing = true
        isLoading = true
        
        // Sync in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.syncTodayStats() }
            group.addTask { await self.syncRecentWorkouts() }
            group.addTask { await self.syncHeartRate() }
            group.addTask { await self.syncSleep() }
            group.addTask { await self.syncWeeklyData() }
        }
        
        isLoading = false
        isSyncing = false
        
        AppLogger.info("HealthKit full sync complete", category: .health)
        
        // Persist HealthKit workouts & activity to Supabase (cardio_workouts + daily_activity_summary)
        // This ensures "Sync Now" saves data to the database so it appears in Recent Activity
        await HealthDataService.shared.persistHealthKitDataToSupabase()
        
        // Sync HealthKit data to active challenges
        await ChallengeService.shared.syncHealthKitDataToChallenges()
        
        // Update lastSyncDate AFTER persist + challenge sync so UI observers fire with data ready
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "healthkit_last_sync")
    }
    
    // MARK: - Sync Today's Stats
    
    private func syncTodayStats() async {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        // Fetch steps
        if let steps = await fetchSum(for: .stepCount, predicate: predicate) {
            await MainActor.run { todaySteps = Int(steps) }
        }
        
        // Fetch active calories
        if let calories = await fetchSum(for: .activeEnergyBurned, predicate: predicate) {
            await MainActor.run { todayCalories = Int(calories) }
        }
        
        // Fetch distance
        if let distance = await fetchSum(for: .distanceWalkingRunning, predicate: predicate) {
            await MainActor.run { todayDistance = distance }
        }
        
        AppLogger.info("HealthKit today: \(todaySteps) steps, \(todayCalories) cal, \(String(format: "%.1f", todayDistance/1000)) km", category: .health)
    }
    
    // MARK: - Sync Recent Workouts
    
    private func syncRecentWorkouts() async {
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
            
            let workouts = samples.compactMap { sample -> HealthKitWorkout? in
                guard let workout = sample as? HKWorkout else { return nil }
                let hkWorkout = HealthKitWorkout(from: workout)
                // Skip workouts that Fit33 wrote to HealthKit — avoids duplicates
                if hkWorkout.isFromFit33 { return nil }
                return hkWorkout
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
            }
            
            AppLogger.info("HealthKit synced \(workouts.count) workouts", category: .health)
            
        } catch {
            AppLogger.error("Failed to fetch HealthKit workouts: \(error.localizedDescription)", category: .health)
        }
    }
    
    // MARK: - Sync Heart Rate
    
    private func syncHeartRate() async {
        // Fetch resting heart rate
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: oneWeekAgo, end: Date(), options: .strictStartDate)
        
        if let restingHR = await fetchMostRecent(for: .restingHeartRate, predicate: predicate) {
            await MainActor.run { restingHeartRate = Int(restingHR) }
        }
        
        // Fetch average heart rate for today
        let todayPredicate = HKQuery.predicateForSamples(
            withStart: calendar.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )
        
        if let avgHR = await fetchAverage(for: .heartRate, predicate: todayPredicate) {
            await MainActor.run { averageHeartRate = Int(avgHR) }
        }
        
        if let rhr = restingHeartRate {
            AppLogger.info("HealthKit resting HR: \(rhr) bpm", category: .health)
        }
    }
    
    // MARK: - Sync Sleep
    
    private func syncSleep() async {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
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
            AppLogger.error("Failed to fetch HealthKit sleep: \(error.localizedDescription)", category: .health)
        }
    }
    
    // MARK: - Sync Weekly Data
    
    private func syncWeeklyData() async {
        let calendar = Calendar.current
        var stepData: [DailyStepData] = []
        
        // Fetch steps for each of the last 7 days
        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
            
            if let steps = await fetchSum(for: .stepCount, predicate: predicate) {
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
    
    private func fetchSum(for identifier: HKQuantityTypeIdentifier, predicate: NSPredicate) async -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
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
    
    private func fetchMostRecent(for identifier: HKQuantityTypeIdentifier, predicate: NSPredicate) async -> Double? {
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
    
    private func fetchAverage(for identifier: HKQuantityTypeIdentifier, predicate: NSPredicate) async -> Double? {
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
    
    init(id: UUID, workoutType: HKWorkoutActivityType, startDate: Date, endDate: Date, duration: TimeInterval, calories: Double?, distance: Double?, sourceName: String, sourceBundle: String?) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.calories = calories
        self.distance = distance
        self.sourceName = sourceName
        self.sourceBundle = sourceBundle
    }
}
#endif
