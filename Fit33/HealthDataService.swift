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
    
    private init() {
        updateConnectedSources()
    }
    
    // MARK: - Sync All Data
    
    /// Sync health data from all connected sources (throttled)
    func syncAllHealthData(force: Bool = false) async {
        // Throttle: Skip if already syncing or synced recently
        if !force {
            if isSyncing {
                print("⏭️ [HEALTH] Skipping sync - already in progress")
                return
            }
            
            if let lastSync = lastSyncDate,
               Date().timeIntervalSince(lastSync) < Self.syncThrottleInterval {
                print("⏭️ [HEALTH] Skipping full sync - synced \(Int(Date().timeIntervalSince(lastSync)))s ago")
                // Even when throttled, do a quick HealthKit workout sync to catch new external workouts
                // This is lightweight: just re-fetches workouts from HealthKit and persists any new ones
                if HealthKitService.shared.isAuthorized {
                    await syncHealthKitWorkoutsOnly()
                }
                return
            }
        }
        
        isSyncing = true
        isLoading = true
        
        updateConnectedSources()
        
        // Sync from connected sources in parallel
        await withTaskGroup(of: Void.self) { group in
            // Apple HealthKit data (Nike Run Club, Apple Watch, etc.)
            if HealthKitService.shared.isAuthorized {
                group.addTask {
                    await self.syncHealthKitData()
                }
            }
            
            // Fitbit data
            if FitbitService.shared.isConnected {
                group.addTask {
                    await self.syncFitbitData()
                }
            }
            
            // Strava data
            if StravaService.shared.isConnected {
                group.addTask {
                    await self.syncStravaData()
                }
            }
            
            // Fetch aggregated data from database
            group.addTask {
                await self.fetchWeeklyData()
            }
        }
        
        // 🏆 CHALLENGES: Sync all sources to active challenges AFTER data is loaded
        // This ensures challenges get credit from HealthKit, Strava, Fitbit, etc.
        await syncAllSourcesToChallenges()
        
        lastSyncDate = Date()
        isLoading = false
        isSyncing = false
        
        print("✅ [HEALTH] Full health data sync complete")
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
            print("📊 [CHALLENGES] No active challenges to sync")
            return
        }
        
        print("🏆 [CHALLENGES] Syncing all health sources to \(challengeService.activeChallenges.count) 1v1 + \(communityService.myChallenges.count) community + \(privateService.myChallenges.count) private challenges...")
        
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
        
        print("✅ [CHALLENGES] All health sources synced to challenges (1v1 + community + private)")
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
        
        print("✅ [FITBIT] Synced activity data to challenges")
    }
    
    // MARK: - Fitbit Data Sync
    
    private func syncFitbitData() async {
        guard FitbitService.shared.isConnected else { return }
        
        // Sync Fitbit's internal data first
        await FitbitService.shared.syncAllData()
        
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
    
    private func syncStravaData() async {
        guard StravaService.shared.isConnected else { return }
        
        // 🔄 AUTO-SYNC: Fetch latest activities from Strava API
        // This pulls any new runs/rides since last sync
        print("🔄 [STRAVA] Auto-syncing activities from Strava...")
        await StravaService.shared.syncActivities(daysBack: 7) // Last 7 days for efficiency
        
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
            
            print("✅ [STRAVA] Synced \(todayActivities.count) activities from today")
        }
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
        
        print("🏃 [HEALTH] Quick workout-only sync (full sync throttled)...")
        
        // Force HealthKit to re-fetch recent workouts (bypasses HealthKitService throttle)
        await HealthKitService.shared.syncAllData(force: true)
        
        // Persist any new workouts to Supabase
        await persistHealthKitDataToSupabase()
    }
    
    /// Persist current in-memory HealthKit data to Supabase.
    /// Call this after HealthKitService has synced from the HK API.
    /// Safe to call from anywhere – does NOT re-fetch from HealthKit.
    func persistHealthKitDataToSupabase() async {
        let healthKit = HealthKitService.shared
        guard healthKit.isAuthorized else { return }
        
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
        
        // Save workouts (Nike Run Club runs, Apple Watch workouts, etc.)
        var savedCount = 0
        for workout in healthKit.recentWorkouts {
            // Only save workouts from today/recent (7 days)
            if calendar.isDate(workout.startDate, inSameDayAs: today) ||
               workout.startDate > calendar.date(byAdding: .day, value: -7, to: today)! {
                await saveHealthKitWorkout(workout)
                savedCount += 1
            }
        }
        
        // Save sleep data if available
        if let sleepHours = healthKit.lastNightSleep, sleepHours > 0 {
            await saveSleepFromHealthKit(hours: sleepHours)
        }
        
        print("✅ [HEALTH] HealthKit data persisted to Supabase (steps: \(healthKit.todaySteps), workouts saved: \(savedCount)/\(healthKit.recentWorkouts.count))")
        
        // Notify dashboard to reload cardio workouts so external workouts appear in Recent Activity
        if savedCount > 0 {
            NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
        }
    }
    
    private func saveDailyActivityFromHealthKit(date: Date, steps: Int, calories: Int, distance: Double, restingHR: Int?) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        var insert = DailyActivityInsert(
            userId: userId.uuidString,
            date: ISO8601DateFormatter().string(from: date),
            steps: steps,
            caloriesBurned: calories,
            caloriesActive: calories,
            distanceMeters: distance,
            restingHeartRate: restingHR,
            sources: ["healthkit"]
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("daily_activity_summary")
                .upsert(insert, onConflict: "user_id,date")
                .execute()
            
            print("✅ [HEALTH] Saved daily activity from HealthKit")
        } catch {
            print("❌ [HEALTH] Failed to save HealthKit activity: \(error)")
        }
    }
    
    private func saveHealthKitWorkout(_ workout: HealthKitWorkout) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Map workout type to cardio type
        let workoutType: String
        switch workout.workoutType {
        case .running: workoutType = "Run"
        case .cycling: workoutType = "Cycling"
        case .walking: workoutType = "Walk"
        case .swimming: workoutType = "Swimming"
        case .hiking: workoutType = "Hike"
        case .elliptical: workoutType = "Elliptical"
        case .rowing: workoutType = "Rowing"
        default: workoutType = "Other"
        }
        
        // Determine source name for display
        let sourceName: String
        if workout.isFromNikeRunClub {
            sourceName = "Nike Run Club"
        } else if workout.isFromStrava {
            sourceName = "Strava"
        } else if workout.isFromApple {
            sourceName = "Apple Watch"
        } else {
            sourceName = workout.sourceName
        }
        
        let insert = HealthKitWorkoutInsert(
            userId: userId.uuidString,
            activityType: workoutType,
            workoutName: "\(sourceName) \(workoutType)",
            goalType: "open_goal",
            goalAchieved: true,
            durationSeconds: Int(workout.duration),
            distanceMeters: workout.distance ?? 0,
            caloriesBurned: Int(workout.calories ?? 0),
            startedAt: ISO8601DateFormatter().string(from: workout.startDate),
            completedAt: ISO8601DateFormatter().string(from: workout.endDate),
            source: "healthkit",
            externalId: workout.id.uuidString
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("cardio_workouts")
                .upsert(insert, onConflict: "user_id,source,external_id")
                .execute()
            print("✅ [HEALTH] Saved HealthKit workout: \(sourceName) \(workoutType) (\(Int(workout.duration / 60))m)")
        } catch {
            // Silently handle duplicates (already exists in DB)
            if !error.localizedDescription.contains("duplicate") &&
               !error.localizedDescription.contains("conflict") {
                print("❌ [HEALTH] Failed to save HealthKit workout (\(sourceName) \(workoutType)): \(error)")
            }
        }
    }
    
    private func saveSleepFromHealthKit(hours: Double) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dateStr = ISO8601DateFormatter().string(from: yesterday)
        
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
            print("❌ [HEALTH] Failed to save HealthKit sleep: \(error)")
        }
    }
    
    // MARK: - Database Operations
    
    private func saveDailyActivity(from fitbitSummary: FitbitDailySummary, source: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let insert = DailyActivityInsert(
            userId: userId.uuidString,
            date: ISO8601DateFormatter().string(from: Date()),
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
            
            print("✅ [HEALTH] Saved daily activity from \(source)")
        } catch {
            print("❌ [HEALTH] Failed to save daily activity: \(error)")
        }
    }
    
    private func updateDailyActivityFromStrava(date: Date, calories: Int, distance: Double, activeMinutes: Int) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)
        
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
                    "calories_burned": AnyEncodable(max(current.caloriesBurned, current.caloriesBurned + calories)),
                    "distance_meters": AnyEncodable(max(current.distanceMeters, current.distanceMeters + distance)),
                    "very_active_minutes": AnyEncodable(max(current.veryActiveMinutes, current.veryActiveMinutes + activeMinutes)),
                    "sources": AnyEncodable(Array(Set(current.sources + ["strava"]))),
                    "updated_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
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
            
            print("✅ [HEALTH] Updated daily activity with Strava data")
        } catch {
            print("❌ [HEALTH] Failed to update Strava activity: \(error)")
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
            
            print("✅ [HEALTH] Saved sleep log from \(source)")
        } catch {
            print("❌ [HEALTH] Failed to save sleep log: \(error)")
        }
    }
    
    private func saveHeartRateData(from heartRate: FitbitHeartRateData, date: Date, source: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)
        
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
            
            print("✅ [HEALTH] Saved heart rate data from \(source)")
        } catch {
            print("❌ [HEALTH] Failed to save heart rate: \(error)")
        }
    }
    
    // MARK: - Fetch Aggregated Data
    
    func fetchWeeklyData() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // ⚡️ Sequential with 150ms gaps to avoid flooding URLSession during startup.
        // These are display-only queries — not critical for challenge sync.
        
        // Fetch weekly activity data
        do {
            let activities: [DailyActivitySummary] = try await SupabaseManager.shared.supabaseClient
                .from("daily_activity_summary")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date", value: dateFormatter.string(from: weekAgo))
                .order("date", ascending: false)
                .execute()
                .value
            
            weeklyActivityData = activities
            todaySummary = activities.first { calendar.isDateInToday(dateFormatter.date(from: $0.date) ?? Date()) }
            
            print("✅ [HEALTH] Fetched \(activities.count) days of activity data")
        } catch {
            print("❌ [HEALTH] Failed to fetch activity data: \(error)")
        }
        
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms throttle
        
        // Fetch sleep logs
        do {
            let sleepLogs: [SleepLogEntry] = try await SupabaseManager.shared.supabaseClient
                .from("sleep_logs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date_of_sleep", value: dateFormatter.string(from: weekAgo))
                .order("date_of_sleep", ascending: false)
                .execute()
                .value
            
            recentSleepLogs = sleepLogs
            calculateSleepStats()
            
            print("✅ [HEALTH] Fetched \(sleepLogs.count) sleep logs")
        } catch {
            print("❌ [HEALTH] Failed to fetch sleep data: \(error)")
        }
        
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms throttle
        
        // Fetch heart rate data
        do {
            let heartRates: [HeartRateDaily] = try await SupabaseManager.shared.supabaseClient
                .from("heart_rate_daily")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date", value: dateFormatter.string(from: weekAgo))
                .order("date", ascending: false)
                .execute()
                .value
            
            weeklyHeartRateData = heartRates
            todayHeartRate = heartRates.first { calendar.isDateInToday(dateFormatter.date(from: $0.date) ?? Date()) }
            calculateHeartRateTrend()
            
            print("✅ [HEALTH] Fetched \(heartRates.count) days of heart rate data")
        } catch {
            print("❌ [HEALTH] Failed to fetch heart rate data: \(error)")
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
                .gte("completed_at", value: ISO8601DateFormatter().string(from: startOfWeek))
                .execute()
                .value
            
            weeklyWorkoutCount = workouts.count
            weeklyCardioMinutes = workouts.reduce(0) { $0 + (($1.durationSeconds ?? 0) / 60) }
            weeklyCaloriesBurned = workouts.reduce(0) { $0 + Int($1.caloriesBurned ?? 0) }
            
            print("✅ [HEALTH] Weekly workouts: \(weeklyWorkoutCount), minutes: \(weeklyCardioMinutes)")
        } catch {
            print("❌ [HEALTH] Failed to fetch workout aggregates: \(error)")
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
    let startedAt: String
    let completedAt: String
    let source: String
    let externalId: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case activityType = "activity_type"
        case workoutName = "workout_name"
        case goalType = "goal_type"
        case goalAchieved = "goal_achieved"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case caloriesBurned = "calories_burned"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case source
        case externalId = "external_id"
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
