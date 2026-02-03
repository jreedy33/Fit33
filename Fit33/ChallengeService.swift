//
//  ChallengeService.swift
//  Fit33
//
//  Friend Challenge System - Create and participate in fitness challenges with friends
//  Supports: Step, Walk, Run, Lift, Workout Streak, Active Minutes challenges
//

import Foundation
import SwiftUI
import HealthKit

// MARK: - Flexible Date Parsing

/// Parses dates from various formats (DATE "2026-02-01" or TIMESTAMPTZ "2026-02-01T00:00:00+00:00")
func parseFlexibleDate(_ string: String) -> Date {
    // Try ISO8601 with time first
    let iso8601Formatter = ISO8601DateFormatter()
    iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso8601Formatter.date(from: string) {
        return date
    }
    
    // Try without fractional seconds
    iso8601Formatter.formatOptions = [.withInternetDateTime]
    if let date = iso8601Formatter.date(from: string) {
        return date
    }
    
    // Try date-only format (PostgreSQL DATE type)
    let dateOnlyFormatter = DateFormatter()
    dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
    dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")
    if let date = dateOnlyFormatter.date(from: string) {
        return date
    }
    
    // Fallback to current date
    print("⚠️ [CHALLENGES] Could not parse date: \(string)")
    return Date()
}

// MARK: - Challenge Service

@MainActor
class ChallengeService: ObservableObject {
    static let shared = ChallengeService()
    
    // MARK: - Cache Keys
    
    private let activeChallengesCacheKey = "fit33_cached_active_challenges"
    private let pendingInvitesCacheKey = "fit33_cached_pending_invites"
    private let cacheDateKey = "fit33_challenges_cache_date"
    
    // MARK: - Published Properties
    
    @Published var pendingInvites: [ChallengeInvite] = []
    @Published var activeChallenges: [ActiveChallenge] = []
    @Published var challengeTemplates: [ChallengeTemplate] = []
    @Published var isLoading = false
    
    // Track last known invite IDs for detecting new invites
    private var lastCheckedInviteIds: Set<UUID> = []
    
    private init() {
        // Load cached challenges immediately on init for instant display
        loadCachedChallenges()
    }
    
    // MARK: - Local Challenge Caching (survives force quit)
    
    /// Cache active challenges to UserDefaults for instant display on app restart
    private func cacheActiveChallenges() {
        guard !activeChallenges.isEmpty else {
            // Clear cache if no active challenges
            UserDefaults.standard.removeObject(forKey: activeChallengesCacheKey)
            print("🗑️ [CHALLENGES] Cleared cached active challenges")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(activeChallenges)
            UserDefaults.standard.set(data, forKey: activeChallengesCacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheDateKey)
            UserDefaults.standard.synchronize() // Force immediate write
            print("💾 [CHALLENGES] Cached \(activeChallenges.count) active challenges")
        } catch {
            print("❌ [CHALLENGES] Failed to cache active challenges: \(error)")
        }
    }
    
    /// Cache pending invites to UserDefaults
    private func cachePendingInvites() {
        guard !pendingInvites.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingInvitesCacheKey)
            print("🗑️ [CHALLENGES] Cleared cached pending invites")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pendingInvites)
            UserDefaults.standard.set(data, forKey: pendingInvitesCacheKey)
            UserDefaults.standard.synchronize()
            print("💾 [CHALLENGES] Cached \(pendingInvites.count) pending invites")
        } catch {
            print("❌ [CHALLENGES] Failed to cache pending invites: \(error)")
        }
    }
    
    /// Load cached challenges from UserDefaults (called on init for instant display)
    private func loadCachedChallenges() {
        print("🔍 [CHALLENGES] Loading cached challenges...")
        
        // Load cached active challenges
        if let data = UserDefaults.standard.data(forKey: activeChallengesCacheKey) {
            do {
                let decoder = JSONDecoder()
                let cached = try decoder.decode([ActiveChallenge].self, from: data)
                self.activeChallenges = cached
                print("✅ [CHALLENGES] Loaded \(cached.count) cached active challenges instantly")
            } catch {
                print("⚠️ [CHALLENGES] Failed to decode cached active challenges: \(error)")
                UserDefaults.standard.removeObject(forKey: activeChallengesCacheKey)
            }
        } else {
            print("ℹ️ [CHALLENGES] No cached active challenges found")
        }
        
        // Load cached pending invites
        if let data = UserDefaults.standard.data(forKey: pendingInvitesCacheKey) {
            do {
                let decoder = JSONDecoder()
                let cached = try decoder.decode([ChallengeInvite].self, from: data)
                self.pendingInvites = cached
                print("✅ [CHALLENGES] Loaded \(cached.count) cached pending invites instantly")
            } catch {
                print("⚠️ [CHALLENGES] Failed to decode cached pending invites: \(error)")
                UserDefaults.standard.removeObject(forKey: pendingInvitesCacheKey)
            }
        } else {
            print("ℹ️ [CHALLENGES] No cached pending invites found")
        }
    }
    
    /// Clear all challenge caches (call on logout)
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: activeChallengesCacheKey)
        UserDefaults.standard.removeObject(forKey: pendingInvitesCacheKey)
        UserDefaults.standard.removeObject(forKey: cacheDateKey)
        UserDefaults.standard.synchronize()
        activeChallenges = []
        pendingInvites = []
        print("🗑️ [CHALLENGES] Cleared all challenge caches")
    }
    
    // MARK: - Fetch All Data
    
    /// Refresh all challenge data
    func refreshAll() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        async let invitesTask: () = fetchPendingInvites()
        async let activesTask: () = fetchActiveChallenges()
        async let templatesTask: () = fetchTemplates()
        
        _ = await (invitesTask, activesTask, templatesTask)
    }
    
    // MARK: - Fetch Pending Invites
    
    func fetchPendingInvites() async {
        do {
            let result: [ChallengeInvite] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_pending_challenge_invites")
                .execute()
                .value
            
            self.pendingInvites = result
            cachePendingInvites() // Cache for instant display on next app launch
            print("✅ [CHALLENGES] Fetched \(result.count) pending challenge invites")
        } catch {
            print("❌ [CHALLENGES] Error fetching pending invites: \(error)")
        }
    }
    
    /// Check for new challenge invites and send notification
    func checkForNewChallengeInvites() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        let previousIds = lastCheckedInviteIds
        
        await fetchPendingInvites()
        
        let currentIds = Set(pendingInvites.map { $0.challengeId })
        let newInviteIds = currentIds.subtracting(previousIds)
        
        lastCheckedInviteIds = currentIds
        
        // Show notifications for new invites
        for newId in newInviteIds {
            if let invite = pendingInvites.first(where: { $0.challengeId == newId }) {
                print("🎯 [NEW CHALLENGE] Detected new challenge invite from \(invite.creatorName ?? "Friend")")
                
                // Send local notification
                NotificationManager.shared.sendChallengeInviteNotification(
                    fromName: invite.creatorName ?? "A friend",
                    challengeTitle: invite.title,
                    challengeId: invite.challengeId.uuidString
                )
                
                HapticManager.notification(.success)
            }
        }
    }
    
    // MARK: - Fetch Active Challenges
    
    func fetchActiveChallenges() async {
        do {
            let result: [ActiveChallenge] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_active_challenges")
                .execute()
                .value
            
            self.activeChallenges = result
            cacheActiveChallenges() // Cache for instant display on next app launch
            print("✅ [CHALLENGES] Fetched \(result.count) active challenges")
        } catch {
            print("❌ [CHALLENGES] Error fetching active challenges: \(error)")
        }
    }
    
    // MARK: - Fetch Templates
    
    /// Track if templates have been loaded to avoid unnecessary refetches
    private var hasLoadedTemplates = false
    
    func fetchTemplates(force: Bool = false) async {
        // Skip if already loaded and not forcing
        if hasLoadedTemplates && !force && !challengeTemplates.isEmpty {
            print("⏭️ [CHALLENGES] Templates already loaded (\(challengeTemplates.count)), skipping fetch")
            return
        }
        
        print("🔄 [CHALLENGES] Fetching templates... (force: \(force), hasLoaded: \(hasLoadedTemplates))")
        
        do {
            let result: [ChallengeTemplate] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenge_templates")
                .execute()
                .value
            
            // Only update on main actor to avoid threading issues
            await MainActor.run {
                // Only update if actually different to avoid unnecessary UI updates
                if self.challengeTemplates.count != result.count {
                    print("📝 [CHALLENGES] Updating templates: \(self.challengeTemplates.count) → \(result.count)")
                    self.challengeTemplates = result
                } else {
                    print("✅ [CHALLENGES] Templates unchanged (\(result.count))")
                }
                self.hasLoadedTemplates = true
            }
            print("✅ [CHALLENGES] Fetched \(result.count) challenge templates")
        } catch {
            print("❌ [CHALLENGES] Error fetching templates: \(error)")
        }
    }
    
    /// Get templates without triggering @Published updates (for use in sheets to avoid dismissal)
    /// Returns cached templates if available, otherwise fetches fresh ones
    func getTemplatesWithoutPublishing() async -> [ChallengeTemplate] {
        // Return cached if available
        if !challengeTemplates.isEmpty {
            print("🏆 [CHALLENGES] Returning cached templates: \(challengeTemplates.count)")
            return challengeTemplates
        }
        
        // Fetch fresh but don't update @Published property
        print("🔄 [CHALLENGES] Fetching templates silently (no publish)...")
        
        do {
            let result: [ChallengeTemplate] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenge_templates")
                .execute()
                .value
            
            print("✅ [CHALLENGES] Fetched \(result.count) templates (silent)")
            return result
        } catch {
            print("❌ [CHALLENGES] Error fetching templates silently: \(error)")
            return []
        }
    }
    
    // MARK: - Create Challenge
    
    func createChallenge(
        opponentId: UUID,
        type: ChallengeType,
        title: String,
        description: String? = nil,
        dailyTarget: Int? = nil,
        totalTarget: Int? = nil,
        targetUnit: String = "count",
        startDate: Date = Date(), // Today - challenge starts when opponent accepts
        durationDays: Int = 7
    ) async -> UUID? {
        do {
            struct CreateChallengeParams: Encodable {
                let p_opponent_id: String
                let p_challenge_type: String
                let p_title: String
                let p_description: String?
                let p_daily_target: Int?
                let p_total_target: Int?
                let p_target_unit: String
                let p_start_date: String
                let p_duration_days: Int
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let params = CreateChallengeParams(
                p_opponent_id: opponentId.uuidString,
                p_challenge_type: type.rawValue,
                p_title: title,
                p_description: description,
                p_daily_target: dailyTarget,
                p_total_target: totalTarget,
                p_target_unit: targetUnit,
                p_start_date: dateFormatter.string(from: startDate),
                p_duration_days: durationDays
            )
            
            let challengeId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("create_challenge", params: params)
                .execute()
                .value
            
            print("✅ [CHALLENGES] Created challenge: \(challengeId)")
            
            // Refresh active challenges
            await fetchActiveChallenges()
            
            // IMPORTANT: Sync creator's existing progress if challenge starts today or earlier
            // This ensures creators get credit for progress made before creating the challenge
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let challengeStartDay = calendar.startOfDay(for: startDate)
            
            if challengeStartDay <= today {
                print("🔄 [CHALLENGES] Challenge starts today - syncing creator's existing progress...")
                await syncCreatorProgressOnCreate(
                    challengeId: challengeId,
                    challengeType: type,
                    targetUnit: targetUnit
                )
            }
            
            return challengeId
        } catch {
            print("❌ [CHALLENGES] Error creating challenge: \(error)")
            return nil
        }
    }
    
    /// Sync creator's existing health data when they create a challenge that starts today
    /// This ensures they get credit for progress already made before creating the challenge
    private func syncCreatorProgressOnCreate(challengeId: UUID, challengeType: ChallengeType, targetUnit: String) async {
        print("🔄 [CHALLENGES] Syncing creator's existing progress for newly created challenge...")
        
        // First, refresh HealthKit data to ensure we have the latest
        print("📱 [CHALLENGES] Refreshing HealthKit data for creator...")
        await HealthKitService.shared.syncAllData(force: true)
        
        // Calculate progress from all available health data sources
        let progressValue = await calculateTotalProgressFromAllSources(
            challengeType: challengeType.rawValue,
            targetUnit: targetUnit
        )
        
        if progressValue > 0 {
            print("📊 [CHALLENGES] Found existing creator progress: \(progressValue) \(targetUnit)")
            
            let success = await logProgress(
                challengeId: challengeId,
                progressValue: progressValue,
                source: "healthkit"
            )
            
            if success {
                print("✅ [CHALLENGES] Logged creator's initial progress of \(progressValue) \(targetUnit)")
            }
        } else {
            print("ℹ️ [CHALLENGES] No existing progress to sync for creator")
        }
    }
    
    // MARK: - Respond to Challenge
    
    func respondToChallenge(challengeId: UUID, accept: Bool) async -> Bool {
        do {
            // Get challenge details BEFORE accepting (need type/unit for progress sync)
            let inviteDetails = pendingInvites.first { $0.challengeId == challengeId }
            
            struct RespondParams: Encodable {
                let p_challenge_id: String
                let p_accept: Bool
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("respond_to_challenge", params: RespondParams(
                    p_challenge_id: challengeId.uuidString,
                    p_accept: accept
                ))
                .execute()
                .value
            
            // Remove from pending invites and update cache
            pendingInvites.removeAll { $0.challengeId == challengeId }
            cachePendingInvites()
            
            if accept {
                // Refresh active challenges (this also caches)
                await fetchActiveChallenges()
                print("✅ [CHALLENGES] Accepted challenge")
                
                // IMPORTANT: Sync existing progress from today
                // User may have already completed their daily goal before accepting
                await syncExistingProgressOnAccept(challengeId: challengeId, inviteDetails: inviteDetails)
            } else {
                print("✅ [CHALLENGES] Declined challenge")
            }
            
            return true
        } catch {
            print("❌ [CHALLENGES] Error responding to challenge: \(error)")
            return false
        }
    }
    
    /// Sync existing health data when a challenge is accepted
    /// This ensures users get credit for progress already made today
    private func syncExistingProgressOnAccept(challengeId: UUID, inviteDetails: ChallengeInvite?) async {
        print("🔄 [CHALLENGES] Syncing existing progress for newly accepted challenge...")
        
        // First, refresh HealthKit data to ensure we have the latest
        print("📱 [CHALLENGES] Refreshing HealthKit data...")
        await HealthKitService.shared.syncAllData(force: true)
        
        // Also refresh Strava if connected
        if StravaService.shared.isConnected {
            print("🏃 [CHALLENGES] Refreshing Strava data...")
            await StravaService.shared.syncActivities()
        }
        
        // Find the accepted challenge in our active list
        guard let challenge = activeChallenges.first(where: { $0.challengeId == challengeId }) else {
            print("⚠️ [CHALLENGES] Could not find accepted challenge in active list")
            return
        }
        
        // Calculate progress from all available health data sources
        let progressValue = await calculateTotalProgressFromAllSources(
            challengeType: challenge.challengeType,
            targetUnit: challenge.targetUnit
        )
        
        if progressValue > 0 {
            print("📊 [CHALLENGES] Found existing progress: \(progressValue) \(challenge.targetUnit)")
            
            let success = await logProgress(
                challengeId: challengeId,
                progressValue: progressValue,
                source: "healthkit"
            )
            
            if success {
                print("✅ [CHALLENGES] Logged initial progress of \(progressValue) \(challenge.targetUnit) for '\(challenge.title)'")
                
                // Check if this already meets the daily target
                if progressValue >= (challenge.dailyTarget ?? 0) {
                    print("🎉 [CHALLENGES] User already met daily target! (\(progressValue)/\(challenge.dailyTarget ?? 0))")
                }
            }
        } else {
            print("ℹ️ [CHALLENGES] No existing progress to sync for this challenge type")
        }
    }
    
    /// Calculate total progress from HealthKit, Strava, and other sources
    private func calculateTotalProgressFromAllSources(challengeType: String, targetUnit: String) async -> Int {
        var totalProgress = 0
        
        // 1. Get HealthKit data
        let healthKitProgress = await calculateProgressFromHealthKit(
            challengeType: challengeType,
            targetUnit: targetUnit
        )
        totalProgress = max(totalProgress, healthKitProgress)
        print("📱 [CHALLENGES] HealthKit progress: \(healthKitProgress)")
        
        // 2. Get Strava data if connected
        let stravaProgress = await calculateProgressFromStrava(
            challengeType: challengeType,
            targetUnit: targetUnit
        )
        
        // For steps and active minutes, take the max (they might overlap)
        // For workouts/runs/walks, add them (different sources = different workouts)
        if challengeType == "steps" || challengeType == "active_minutes" {
            totalProgress = max(totalProgress, stravaProgress)
        } else {
            // For runs, walks, lifts - Strava activities are additional to HealthKit
            // But HealthKit might already include Strava data synced to Apple Health
            // So we still take max to avoid double counting
            totalProgress = max(totalProgress, healthKitProgress + stravaProgress / 2) // Conservative estimate
        }
        print("🏃 [CHALLENGES] Strava progress: \(stravaProgress)")
        
        print("📊 [CHALLENGES] Total progress from all sources: \(totalProgress)")
        return totalProgress
    }
    
    /// Calculate progress from Strava activities for today
    private func calculateProgressFromStrava(challengeType: String, targetUnit: String) async -> Int {
        let strava = StravaService.shared
        
        // Filter to today's activities (startDate is already a Date type)
        let todayActivities = strava.recentActivities.filter { activity in
            Calendar.current.isDateInToday(activity.startDate)
        }
        
        guard !todayActivities.isEmpty else { return 0 }
        
        switch challengeType {
        case "steps":
            // Strava doesn't directly track steps, but we can estimate from runs/walks
            // ~1300 steps per km for walking, ~1000 for running
            var estimatedSteps = 0
            for activity in todayActivities {
                let distanceKm = activity.distance / 1000
                if activity.type.lowercased().contains("run") {
                    estimatedSteps += Int(distanceKm * 1000)
                } else if activity.type.lowercased().contains("walk") || activity.type.lowercased().contains("hike") {
                    estimatedSteps += Int(distanceKm * 1300)
                }
            }
            return estimatedSteps
            
        case "run":
            let runActivities = todayActivities.filter { $0.type.lowercased().contains("run") }
            if targetUnit == "minutes" {
                return runActivities.reduce(0) { $0 + ($1.movingTime / 60) }
            } else if targetUnit == "miles" {
                let totalMeters = runActivities.reduce(0.0) { $0 + $1.distance }
                return Int(totalMeters / 1609.344)
            } else if targetUnit == "km" {
                let totalMeters = runActivities.reduce(0.0) { $0 + $1.distance }
                return Int(totalMeters / 1000)
            } else if targetUnit == "workouts" {
                return runActivities.count
            }
            return 0
            
        case "walk":
            let walkActivities = todayActivities.filter {
                $0.type.lowercased().contains("walk") || $0.type.lowercased().contains("hike")
            }
            if targetUnit == "minutes" {
                return walkActivities.reduce(0) { $0 + ($1.movingTime / 60) }
            } else if targetUnit == "miles" {
                let totalMeters = walkActivities.reduce(0.0) { $0 + $1.distance }
                return Int(totalMeters / 1609.344)
            } else if targetUnit == "km" {
                let totalMeters = walkActivities.reduce(0.0) { $0 + $1.distance }
                return Int(totalMeters / 1000)
            }
            return 0
            
        case "lift", "workout_streak":
            // Count strength-related activities
            let strengthActivities = todayActivities.filter {
                let type = $0.type.lowercased()
                return type.contains("weight") || type.contains("crossfit") || type.contains("workout")
            }
            return strengthActivities.count
            
        case "active_minutes":
            // Total moving time from all activities
            return todayActivities.reduce(0) { $0 + ($1.movingTime / 60) }
            
        default:
            return 0
        }
    }
    
    // MARK: - Cancel Challenge
    
    /// Cancel an active or pending challenge
    /// Notifies the opponent and removes the challenge from both users
    func cancelChallenge(challengeId: UUID) async -> Bool {
        do {
            struct CancelParams: Encodable {
                let p_challenge_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("cancel_challenge", params: CancelParams(
                    p_challenge_id: challengeId.uuidString
                ))
                .execute()
                .value
            
            // Remove from active challenges and update cache
            activeChallenges.removeAll { $0.challengeId == challengeId }
            cacheActiveChallenges()
            
            // Also check pending invites
            pendingInvites.removeAll { $0.challengeId == challengeId }
            cachePendingInvites()
            
            print("✅ [CHALLENGES] Challenge cancelled successfully")
            return true
        } catch {
            print("❌ [CHALLENGES] Error cancelling challenge: \(error)")
            return false
        }
    }
    
    // MARK: - Log Progress
    
    func logProgress(
        challengeId: UUID,
        progressValue: Int,
        date: Date = Date(),
        source: String = "manual",
        workoutId: UUID? = nil
    ) async -> Bool {
        do {
            struct LogProgressParams: Encodable {
                let p_challenge_id: String
                let p_progress_value: Int
                let p_progress_date: String
                let p_source: String
                let p_workout_id: String?
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("log_challenge_progress", params: LogProgressParams(
                    p_challenge_id: challengeId.uuidString,
                    p_progress_value: progressValue,
                    p_progress_date: dateFormatter.string(from: date),
                    p_source: source,
                    p_workout_id: workoutId?.uuidString
                ))
                .execute()
                .value
            
            print("✅ [CHALLENGES] Logged progress: \(progressValue)")
            
            // Refresh active challenges to show updated progress
            await fetchActiveChallenges()
            
            return true
        } catch {
            print("❌ [CHALLENGES] Error logging progress: \(error)")
            return false
        }
    }
    
    // MARK: - HealthKit Auto-Sync
    
    /// Sync HealthKit data to all active challenges
    /// Call this when HealthKit data updates (steps, workouts, active minutes)
    func syncHealthKitDataToChallenges() async {
        guard !activeChallenges.isEmpty else {
            print("📊 [CHALLENGES] No active challenges to sync")
            return
        }
        
        let healthKit = HealthKitService.shared
        
        print("🔄 [CHALLENGES] Syncing HealthKit data to \(activeChallenges.count) active challenges...")
        
        for challenge in activeChallenges {
            print("📊 [CHALLENGES] Checking challenge '\(challenge.title)' (status: \(challenge.status))")
            
            // Sync if challenge is active OR pending (pending means accepted but waiting for start date)
            // This ensures users who accept early get credit for progress made before start date
            guard challenge.status == "active" || challenge.status == "pending" else {
                print("⏭️ [CHALLENGES] Skipping '\(challenge.title)' - status is '\(challenge.status)'")
                continue
            }
            
            let progressValue = await calculateProgressFromHealthKit(
                challengeType: challenge.challengeType,
                targetUnit: challenge.targetUnit
            )
            
            print("📊 [CHALLENGES] Calculated \(progressValue) \(challenge.targetUnit) for '\(challenge.title)'")
            
            if progressValue > 0 {
                print("🔄 [CHALLENGES] Logging \(progressValue) \(challenge.targetUnit) for '\(challenge.title)'...")
                let success = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: progressValue,
                    source: "healthkit"
                )
                
                if success {
                    print("✅ [CHALLENGES] Synced \(progressValue) \(challenge.targetUnit) to '\(challenge.title)' from HealthKit")
                } else {
                    print("❌ [CHALLENGES] Failed to sync progress for '\(challenge.title)'")
                }
            } else {
                print("⏭️ [CHALLENGES] Skipping '\(challenge.title)' - progressValue is 0")
            }
        }
        
        print("✅ [CHALLENGES] HealthKit sync complete for all challenges")
    }
    
    /// Calculate progress value from HealthKit based on challenge type
    private func calculateProgressFromHealthKit(challengeType: String, targetUnit: String) async -> Int {
        let healthKit = HealthKitService.shared
        
        switch challengeType {
        case "steps":
            // Steps challenge - use today's step count
            return healthKit.todaySteps
            
        case "walk":
            // Walk challenge - use walking minutes or distance based on target unit
            if targetUnit == "minutes" {
                // Get walking minutes from today's workouts
                let walkingMinutes = healthKit.recentWorkouts
                    .filter { $0.workoutType == .walking && Calendar.current.isDateInToday($0.startDate) }
                    .reduce(0) { $0 + $1.durationMinutes }
                return walkingMinutes
            } else if targetUnit == "miles" || targetUnit == "km" {
                // Walking distance
                let walkingDistance = healthKit.recentWorkouts
                    .filter { $0.workoutType == .walking && Calendar.current.isDateInToday($0.startDate) }
                    .reduce(0.0) { $0 + ($1.distance ?? 0) }
                return targetUnit == "miles" ? Int(walkingDistance / 1609.344) : Int(walkingDistance / 1000)
            }
            return 0
            
        case "run":
            // Run challenge - use running distance or minutes
            let runningWorkouts = healthKit.recentWorkouts
                .filter { $0.workoutType == .running && Calendar.current.isDateInToday($0.startDate) }
            
            if targetUnit == "minutes" {
                return runningWorkouts.reduce(0) { $0 + $1.durationMinutes }
            } else if targetUnit == "miles" {
                let distance = runningWorkouts.reduce(0.0) { $0 + ($1.distance ?? 0) }
                return Int(distance / 1609.344)
            } else if targetUnit == "km" {
                let distance = runningWorkouts.reduce(0.0) { $0 + ($1.distance ?? 0) }
                return Int(distance / 1000)
            } else if targetUnit == "workouts" {
                return runningWorkouts.count
            }
            return 0
            
        case "lift", "workout_streak":
            // Workout challenges - count strength/functional workouts
            let workoutTypes: [HKWorkoutActivityType] = [
                .traditionalStrengthTraining,
                .functionalStrengthTraining,
                .crossTraining,
                .highIntensityIntervalTraining,
                .coreTraining
            ]
            
            let workoutCount = healthKit.recentWorkouts
                .filter { workoutTypes.contains($0.workoutType) && Calendar.current.isDateInToday($0.startDate) }
                .count
            
            // Also count any workout completed in Fit33 today (check if already logged)
            return max(1, workoutCount) // At least 1 if any workout exists
            
        case "active_minutes":
            // Active minutes challenge
            return healthKit.todayActiveMinutes
            
        default:
            print("⚠️ [CHALLENGES] Unknown challenge type: \(challengeType)")
            return 0
        }
    }
    
    /// Check if a Strava workout satisfies a challenge
    /// This is called when Strava syncs a workout
    func checkStravaWorkoutForChallenges(
        workoutType: String, // "run", "walk", "ride", etc.
        distanceMeters: Double,
        durationSeconds: Int,
        source: String = "strava"
    ) async {
        guard !activeChallenges.isEmpty else { return }
        
        print("🏃 [CHALLENGES] Checking Strava \(workoutType) workout against challenges...")
        
        for challenge in activeChallenges {
            guard challenge.status == "active" else { continue }
            
            var progressValue = 0
            var shouldLog = false
            
            switch challenge.challengeType {
            case "run":
                if workoutType.lowercased().contains("run") {
                    if challenge.targetUnit == "minutes" {
                        progressValue = durationSeconds / 60
                        shouldLog = true
                    } else if challenge.targetUnit == "miles" {
                        progressValue = Int(distanceMeters / 1609.344)
                        shouldLog = true
                    } else if challenge.targetUnit == "km" {
                        progressValue = Int(distanceMeters / 1000)
                        shouldLog = true
                    } else if challenge.targetUnit == "workouts" {
                        progressValue = 1
                        shouldLog = true
                    }
                }
                
            case "walk":
                if workoutType.lowercased().contains("walk") || workoutType.lowercased().contains("hike") {
                    if challenge.targetUnit == "minutes" {
                        progressValue = durationSeconds / 60
                        shouldLog = true
                    } else if challenge.targetUnit == "miles" {
                        progressValue = Int(distanceMeters / 1609.344)
                        shouldLog = true
                    }
                }
                
            case "active_minutes":
                // Any cardio workout counts towards active minutes
                progressValue = durationSeconds / 60
                shouldLog = true
                
            case "workout_streak":
                // Any workout counts for streak
                progressValue = 1
                shouldLog = true
                
            default:
                break
            }
            
            if shouldLog && progressValue > 0 {
                let success = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: progressValue,
                    source: source
                )
                
                if success {
                    print("✅ [CHALLENGES] Logged Strava \(workoutType): \(progressValue) \(challenge.targetUnit) to '\(challenge.title)'")
                }
            }
        }
    }
    
    /// Sync a Fit33 workout completion to challenges
    /// Called when a workout is finished in Fit33
    func syncFit33WorkoutToChallenge(workoutType: String) async {
        guard !activeChallenges.isEmpty else { return }
        
        print("💪 [CHALLENGES] Checking Fit33 \(workoutType) workout against challenges...")
        
        for challenge in activeChallenges {
            guard challenge.status == "active" else { continue }
            
            var shouldLog = false
            
            switch challenge.challengeType {
            case "lift":
                // Strength workout counts for lift challenges
                if workoutType == "strength" {
                    shouldLog = true
                }
                
            case "workout_streak":
                // Any Fit33 workout counts for streak
                shouldLog = true
                
            default:
                break
            }
            
            if shouldLog {
                let success = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: 1,
                    source: "fit33"
                )
                
                if success {
                    print("✅ [CHALLENGES] Logged Fit33 \(workoutType) workout to '\(challenge.title)'")
                }
            }
        }
    }
    
    // MARK: - Multi-Source Challenge Integration
    
    /// Log progress from any source (Fitbit, Strava, HealthKit, etc.)
    /// This is called by HealthDataService to sync all sources to challenges
    func logProgressFromSource(challengeType: String, progressValue: Int, source: String) async {
        guard progressValue > 0 else { return }
        
        for challenge in activeChallenges {
            guard challenge.status == "active" || challenge.status == "pending" else { continue }
            guard challenge.challengeType == challengeType else { continue }
            
            let success = await logProgress(
                challengeId: challenge.challengeId,
                progressValue: progressValue,
                source: source
            )
            
            if success {
                print("✅ [CHALLENGES] Logged \(source) \(challengeType): \(progressValue) to '\(challenge.title)'")
            }
        }
    }
    
    /// Recalculate progress for all active challenges from all sources
    /// Called after all health data sources have synced
    func recalculateAllChallengeProgress() async {
        guard !activeChallenges.isEmpty else { return }
        
        print("🔄 [CHALLENGES] Recalculating progress for \(activeChallenges.count) challenges...")
        
        for challenge in activeChallenges {
            guard challenge.status == "active" || challenge.status == "pending" else { continue }
            
            // Calculate total progress from ALL sources
            let totalProgress = await calculateTotalProgressFromAllSources(
                challengeType: challenge.challengeType,
                targetUnit: challenge.targetUnit
            )
            
            if totalProgress > 0 {
                // Log the max progress (this handles deduplication via the database)
                let _ = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: totalProgress,
                    source: "aggregated"
                )
            }
        }
        
        // Refresh challenges to show updated progress
        await fetchActiveChallenges()
        
        print("✅ [CHALLENGES] All challenge progress recalculated")
    }
    
    // MARK: - Get Challenge Details
    
    func getChallengeDetails(challengeId: UUID) async -> ChallengeDetails? {
        do {
            struct DetailsParams: Encodable {
                let p_challenge_id: String
            }
            
            let result: [ChallengeDetails] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenge_details", params: DetailsParams(p_challenge_id: challengeId.uuidString))
                .execute()
                .value
            
            return result.first
        } catch {
            print("❌ [CHALLENGES] Error fetching challenge details: \(error)")
            return nil
        }
    }
    
    // MARK: - Toggle Notification Preference
    
    /// Toggle whether to receive push notifications when opponent completes their daily challenge
    func toggleChallengeNotificationPreference(challengeId: UUID, notify: Bool) async -> Bool {
        do {
            struct ToggleParams: Encodable {
                let p_challenge_id: String
                let p_notify: Bool
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("toggle_challenge_notification_preference", params: ToggleParams(
                    p_challenge_id: challengeId.uuidString,
                    p_notify: notify
                ))
                .execute()
                .value
            
            print("✅ [CHALLENGES] Notification preference updated: \(notify ? "ON" : "OFF")")
            return true
        } catch {
            print("❌ [CHALLENGES] Error updating notification preference: \(error)")
            return false
        }
    }
    
    // MARK: - Get Challenges With Friend
    
    func getChallengesWithFriend(friendId: UUID) async -> [FriendChallenge] {
        do {
            struct FriendParams: Encodable {
                let p_friend_id: String
            }
            
            let result: [FriendChallenge] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenges_with_friend", params: FriendParams(p_friend_id: friendId.uuidString))
                .execute()
                .value
            
            return result
        } catch {
            print("❌ [CHALLENGES] Error fetching challenges with friend: \(error)")
            return []
        }
    }
    
    // MARK: - Sync HealthKit Progress
    
    /// Automatically sync HealthKit data to relevant challenges
    func syncHealthKitProgress() async {
        let healthKit = HealthKitService.shared
        
        // Ensure HealthKit is authorized
        guard healthKit.isAuthorized else { return }
        
        // Sync today's data to active step/walk/run challenges
        for challenge in activeChallenges {
            switch ChallengeType(rawValue: challenge.challengeType) {
            case .steps:
                await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: healthKit.todaySteps,
                    source: "healthkit"
                )
            case .activeMinutes:
                await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: healthKit.todayActiveMinutes,
                    source: "healthkit"
                )
            default:
                break
            }
        }
        
        print("✅ [CHALLENGES] Synced HealthKit data to challenges")
    }
}

// MARK: - Challenge Type Enum

enum ChallengeType: String, CaseIterable, Identifiable {
    case steps = "steps"
    case walk = "walk"
    case run = "run"
    case lift = "lift"
    case workoutStreak = "workout_streak"
    case activeMinutes = "active_minutes"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .steps: return "Step Challenge"
        case .walk: return "Walk Challenge"
        case .run: return "Run Challenge"
        case .lift: return "Lift Challenge"
        case .workoutStreak: return "Workout Streak"
        case .activeMinutes: return "Active Minutes"
        }
    }
    
    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .walk: return "figure.walk.motion"
        case .run: return "figure.run"
        case .lift: return "dumbbell.fill"
        case .workoutStreak: return "flame.fill"
        case .activeMinutes: return "timer"
        }
    }
    
    var color: Color {
        switch self {
        case .steps: return .green
        case .walk: return .blue
        case .run: return .orange
        case .lift: return .purple
        case .workoutStreak: return .red
        case .activeMinutes: return .cyan
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .steps: return [.green, .mint]
        case .walk: return [.blue, .cyan]
        case .run: return [.orange, .yellow]
        case .lift: return [.purple, .pink]
        case .workoutStreak: return [.red, .orange]
        case .activeMinutes: return [.cyan, .blue]
        }
    }
}

// MARK: - Data Models

struct ChallengeInvite: Codable, Identifiable {
    let challengeId: UUID
    let challengeType: String
    let title: String
    let description: String?
    let emoji: String?
    let dailyTarget: Int?
    let totalTarget: Int?
    let targetUnit: String
    private let startDateString: String
    private let endDateString: String
    let durationDays: Int
    let creatorId: UUID
    let creatorName: String?
    let creatorUsername: String?
    let creatorPhotoUrl: String?
    let invitedAt: Date
    
    var id: UUID { challengeId }
    
    var startDate: Date { parseFlexibleDate(startDateString) }
    var endDate: Date { parseFlexibleDate(endDateString) }
    
    var displayEmoji: String {
        emoji ?? "🏆"
    }
    
    var type: ChallengeType? {
        ChallengeType(rawValue: challengeType)
    }
    
    // Convenience initializer for previews and testing
    init(
        challengeId: UUID,
        challengeType: String,
        title: String,
        description: String?,
        emoji: String?,
        dailyTarget: Int?,
        totalTarget: Int?,
        targetUnit: String,
        startDate: Date,
        endDate: Date,
        durationDays: Int,
        creatorId: UUID,
        creatorName: String?,
        creatorUsername: String?,
        creatorPhotoUrl: String?,
        invitedAt: Date
    ) {
        self.challengeId = challengeId
        self.challengeType = challengeType
        self.title = title
        self.description = description
        self.emoji = emoji
        self.dailyTarget = dailyTarget
        self.totalTarget = totalTarget
        self.targetUnit = targetUnit
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.startDateString = dateFormatter.string(from: startDate)
        self.endDateString = dateFormatter.string(from: endDate)
        
        self.durationDays = durationDays
        self.creatorId = creatorId
        self.creatorName = creatorName
        self.creatorUsername = creatorUsername
        self.creatorPhotoUrl = creatorPhotoUrl
        self.invitedAt = invitedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case challengeType = "challenge_type"
        case title
        case description
        case emoji
        case dailyTarget = "daily_target"
        case totalTarget = "total_target"
        case targetUnit = "target_unit"
        case startDateString = "start_date"
        case endDateString = "end_date"
        case durationDays = "duration_days"
        case creatorId = "creator_id"
        case creatorName = "creator_name"
        case creatorUsername = "creator_username"
        case creatorPhotoUrl = "creator_photo_url"
        case invitedAt = "invited_at"
    }
}

struct ActiveChallenge: Codable, Identifiable {
    let challengeId: UUID
    let challengeType: String
    let title: String
    let description: String?
    let dailyTarget: Int?
    let totalTarget: Int?
    let targetUnit: String
    private let startDateString: String
    private let endDateString: String
    let durationDays: Int
    let daysElapsed: Int
    let daysRemaining: Int
    let status: String
    let myTotalProgress: Int
    let myDaysCompleted: Int
    let myCurrentStreak: Int
    let opponentId: UUID
    let opponentName: String?
    let opponentUsername: String?
    let opponentPhotoUrl: String?
    let opponentTotalProgress: Int
    let opponentDaysCompleted: Int
    let amWinning: Bool
    
    var id: UUID { challengeId }
    
    var startDate: Date { parseFlexibleDate(startDateString) }
    var endDate: Date { parseFlexibleDate(endDateString) }
    
    // Convenience initializer for previews and testing
    init(
        challengeId: UUID,
        challengeType: String,
        title: String,
        description: String?,
        dailyTarget: Int?,
        totalTarget: Int?,
        targetUnit: String,
        startDate: Date,
        endDate: Date,
        durationDays: Int,
        daysElapsed: Int,
        daysRemaining: Int,
        status: String,
        myTotalProgress: Int,
        myDaysCompleted: Int,
        myCurrentStreak: Int,
        opponentId: UUID,
        opponentName: String?,
        opponentUsername: String?,
        opponentPhotoUrl: String?,
        opponentTotalProgress: Int,
        opponentDaysCompleted: Int,
        amWinning: Bool
    ) {
        self.challengeId = challengeId
        self.challengeType = challengeType
        self.title = title
        self.description = description
        self.dailyTarget = dailyTarget
        self.totalTarget = totalTarget
        self.targetUnit = targetUnit
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.startDateString = dateFormatter.string(from: startDate)
        self.endDateString = dateFormatter.string(from: endDate)
        
        self.durationDays = durationDays
        self.daysElapsed = daysElapsed
        self.daysRemaining = daysRemaining
        self.status = status
        self.myTotalProgress = myTotalProgress
        self.myDaysCompleted = myDaysCompleted
        self.myCurrentStreak = myCurrentStreak
        self.opponentId = opponentId
        self.opponentName = opponentName
        self.opponentUsername = opponentUsername
        self.opponentPhotoUrl = opponentPhotoUrl
        self.opponentTotalProgress = opponentTotalProgress
        self.opponentDaysCompleted = opponentDaysCompleted
        self.amWinning = amWinning
    }
    
    var type: ChallengeType? {
        ChallengeType(rawValue: challengeType)
    }
    
    var progressPercentage: Double {
        guard let target = dailyTarget, target > 0 else { return 0 }
        let todayProgress = Double(myTotalProgress) / Double(max(1, daysElapsed))
        return min(1.0, todayProgress / Double(target))
    }
    
    var opponentProgressPercentage: Double {
        guard let target = dailyTarget, target > 0 else { return 0 }
        let todayProgress = Double(opponentTotalProgress) / Double(max(1, daysElapsed))
        return min(1.0, todayProgress / Double(target))
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case challengeType = "challenge_type"
        case title
        case description
        case dailyTarget = "daily_target"
        case totalTarget = "total_target"
        case targetUnit = "target_unit"
        case startDateString = "start_date"
        case endDateString = "end_date"
        case durationDays = "duration_days"
        case daysElapsed = "days_elapsed"
        case daysRemaining = "days_remaining"
        case status
        case myTotalProgress = "my_total_progress"
        case myDaysCompleted = "my_days_completed"
        case myCurrentStreak = "my_current_streak"
        case opponentId = "opponent_id"
        case opponentName = "opponent_name"
        case opponentUsername = "opponent_username"
        case opponentPhotoUrl = "opponent_photo_url"
        case opponentTotalProgress = "opponent_total_progress"
        case opponentDaysCompleted = "opponent_days_completed"
        case amWinning = "am_winning"
    }
}

struct ChallengeTemplate: Codable, Identifiable {
    let id: UUID
    let challengeType: String
    let title: String
    let description: String?
    let emoji: String?
    let defaultDailyTarget: Int?
    let defaultDurationDays: Int
    let targetUnit: String
    let isFeatured: Bool
    
    var type: ChallengeType? {
        ChallengeType(rawValue: challengeType)
    }
    
    var displayEmoji: String {
        emoji ?? "🏆"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case challengeType = "challenge_type"
        case title
        case description
        case emoji
        case defaultDailyTarget = "default_daily_target"
        case defaultDurationDays = "default_duration_days"
        case targetUnit = "target_unit"
        case isFeatured = "is_featured"
    }
}

struct ChallengeDetails: Codable, Identifiable {
    let challengeId: UUID
    let challengeType: String
    let title: String
    let description: String?
    let dailyTarget: Int?
    let totalTarget: Int?
    let targetUnit: String
    private let startDateString: String
    private let endDateString: String
    let durationDays: Int
    let status: String
    let createdAt: Date
    let notifyOnOpponentComplete: Bool?
    let participants: [ChallengeParticipantDetails]?
    
    var id: UUID { challengeId }
    
    var startDate: Date { parseFlexibleDate(startDateString) }
    var endDate: Date { parseFlexibleDate(endDateString) }
    
    /// Returns the notification preference, defaulting to true if not set
    var shouldNotifyOnOpponentComplete: Bool {
        notifyOnOpponentComplete ?? true
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case challengeType = "challenge_type"
        case title
        case description
        case dailyTarget = "daily_target"
        case totalTarget = "total_target"
        case targetUnit = "target_unit"
        case startDateString = "start_date"
        case endDateString = "end_date"
        case durationDays = "duration_days"
        case status
        case createdAt = "created_at"
        case notifyOnOpponentComplete = "notify_on_opponent_complete"
        case participants
    }
}

struct ChallengeParticipantDetails: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let photoUrl: String?
    let status: String
    let totalProgress: Int
    let daysCompleted: Int
    let currentStreak: Int
    let bestStreak: Int
    let isCreator: Bool
    let dailyProgress: [DailyProgressEntry]?
    
    var id: UUID { userId }
    
    var displayName: String {
        if let username = username, !username.isEmpty {
            return "@\(username)"
        }
        return name ?? "Unknown"
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case username
        case photoUrl = "photo_url"
        case status
        case totalProgress = "total_progress"
        case daysCompleted = "days_completed"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case isCreator = "is_creator"
        case dailyProgress = "daily_progress"
    }
}

struct DailyProgressEntry: Codable, Identifiable {
    private let dateString: String
    let value: Int
    let source: String
    
    var date: Date { parseFlexibleDate(dateString) }
    var id: String { dateString }
    
    enum CodingKeys: String, CodingKey {
        case dateString = "date"
        case value
        case source
    }
}

struct FriendChallenge: Codable, Identifiable {
    let challengeId: UUID
    let challengeType: String
    let title: String
    let status: String
    private let startDateString: String
    private let endDateString: String
    let myProgress: Int
    let friendProgress: Int
    let amWinning: Bool
    let dailyTarget: Int?
    let targetUnit: String
    
    var id: UUID { challengeId }
    
    var startDate: Date { parseFlexibleDate(startDateString) }
    var endDate: Date { parseFlexibleDate(endDateString) }
    
    var type: ChallengeType? {
        ChallengeType(rawValue: challengeType)
    }
    
    var isActive: Bool {
        status == "active"
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case challengeType = "challenge_type"
        case title
        case status
        case startDateString = "start_date"
        case endDateString = "end_date"
        case myProgress = "my_progress"
        case friendProgress = "friend_progress"
        case amWinning = "am_winning"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
    }
}
