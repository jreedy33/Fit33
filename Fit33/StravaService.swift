//
//  StravaService.swift
//  Fit33
//
//  Strava API Integration - Syncs cardio activities with Fit33
//

import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - Strava Service

@MainActor
final class StravaService: ObservableObject {
    static let shared = StravaService()
    
    // MARK: - Configuration (Using centralized AppConfig)
    
    private struct Config {
        static let clientId = AppConfig.Strava.clientId
        static let clientSecret = AppConfig.Strava.clientSecret
        static let redirectUri = AppConfig.Strava.redirectUri
        static let authorizationUrl = AppConfig.Strava.authorizationUrl
        static let tokenUrl = AppConfig.Strava.tokenUrl
        static let apiBaseUrl = AppConfig.Strava.apiBaseUrl
        static let scopes = AppConfig.Strava.scopes
    }
    
    // MARK: - Published Properties
    
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var athleteProfile: StravaAthlete?
    @Published var recentActivities: [StravaActivity] = []
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var accessToken: String? {
        get { KeychainHelper.load(key: "strava_access_token") }
        set {
            if let val = newValue { KeychainHelper.save(key: "strava_access_token", value: val) }
            else { KeychainHelper.delete(key: "strava_access_token") }
        }
    }
    
    private var refreshToken: String? {
        get { KeychainHelper.load(key: "strava_refresh_token") }
        set {
            if let val = newValue { KeychainHelper.save(key: "strava_refresh_token", value: val) }
            else { KeychainHelper.delete(key: "strava_refresh_token") }
        }
    }
    
    private var tokenExpiresAt: Date? {
        get {
            guard let str = KeychainHelper.load(key: "strava_token_expires_at"),
                  let timestamp = Double(str), timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let ts = newValue?.timeIntervalSince1970 {
                KeychainHelper.save(key: "strava_token_expires_at", value: String(ts))
            } else {
                KeychainHelper.delete(key: "strava_token_expires_at")
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        migrateTokensFromUserDefaults()
        
        isConnected = accessToken != nil && refreshToken != nil
        
        if isConnected {
            if let data = UserDefaults.standard.data(forKey: "strava_athlete"),
               let athlete = try? JSONDecoder().decode(StravaAthlete.self, from: data) {
                athleteProfile = athlete
            }
            
            if let date = UserDefaults.standard.object(forKey: "strava_last_sync") as? Date {
                lastSyncDate = date
            }
        }
    }
    
    private func migrateTokensFromUserDefaults() {
        let ud = UserDefaults.standard
        let keys = ["strava_access_token", "strava_refresh_token"]
        
        for key in keys {
            if let val = ud.string(forKey: key), KeychainHelper.load(key: key) == nil {
                KeychainHelper.save(key: key, value: val)
                ud.removeObject(forKey: key)
            }
        }
        
        let expiresKey = "strava_token_expires_at"
        let ts = ud.double(forKey: expiresKey)
        if ts > 0 && KeychainHelper.load(key: expiresKey) == nil {
            KeychainHelper.save(key: expiresKey, value: String(ts))
            ud.removeObject(forKey: expiresKey)
        }
    }
    
    // MARK: - OAuth Flow
    
    /// Returns the OAuth authorization URL for Strava
    func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: Config.authorizationUrl)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Config.clientId),
            URLQueryItem(name: "redirect_uri", value: Config.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: Config.scopes)
        ]
        return components?.url
    }
    
    /// Handle the OAuth callback URL
    func handleCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.invalidCallback
        }
        
        // Check for errors in callback
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw StravaError.authorizationDenied(error)
        }
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)
    }
    
    /// Exchange authorization code for access/refresh tokens
    private func exchangeCodeForTokens(code: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let body: [String: String] = [
            "client_id": Config.clientId,
            "client_secret": Config.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        
        guard let tokenURL = URL(string: Config.tokenUrl) else {
            throw StravaError.tokenExchangeFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        
        // Save tokens
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        tokenExpiresAt = Date(timeIntervalSince1970: Double(tokenResponse.expiresAt))
        athleteProfile = tokenResponse.athlete
        
        // Cache athlete profile
        if let athlete = tokenResponse.athlete,
           let athleteData = try? JSONEncoder().encode(athlete) {
            UserDefaults.standard.set(athleteData, forKey: "strava_athlete")
        }
        
        isConnected = true
        
        AppLogger.info("✅ [STRAVA] Connected as \(tokenResponse.athlete?.firstname ?? "Unknown") \(tokenResponse.athlete?.lastname ?? "")", category: .health)
        
        // Update integration status in database
        Task {
            await SupabaseManager.shared.updateIntegrationStatus(integration: "strava", isConnected: true)
        }
        
        // Sync activities after connecting
        await syncActivities()
    }
    
    /// Refresh the access token if expired
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw StravaError.notConnected
        }
        
        let body: [String: String] = [
            "client_id": Config.clientId,
            "client_secret": Config.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        guard let tokenURL = URL(string: Config.tokenUrl) else {
            throw StravaError.tokenRefreshFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Refresh failed - user needs to re-authenticate
            disconnect()
            throw StravaError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(StravaRefreshResponse.self, from: data)
        
        accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        tokenExpiresAt = Date(timeIntervalSince1970: Double(tokenResponse.expiresAt))
        
        AppLogger.debug("🔄 [STRAVA] Token refreshed", category: .health)
    }
    
    /// Ensure we have a valid access token
    private func ensureValidToken() async throws -> String {
        guard let token = accessToken else {
            throw StravaError.notConnected
        }
        
        // Check if token is expired or expiring soon (within 5 minutes)
        if let expiresAt = tokenExpiresAt, expiresAt.timeIntervalSinceNow < 300 {
            try await refreshAccessToken()
            guard let newToken = accessToken else {
                throw StravaError.tokenRefreshFailed
            }
            return newToken
        }
        
        return token
    }
    
    // MARK: - API Methods
    
    /// Sync activities from Strava
    func syncActivities(daysBack: Int = 30) async {
        guard isConnected else {
            AppLogger.debug("⏭️ [STRAVA] Skipping sync — not connected (token: \(accessToken != nil), refresh: \(refreshToken != nil))", category: .health)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        AppLogger.debug("🔄 [STRAVA] Starting sync (daysBack: \(daysBack), token expires: \(tokenExpiresAt?.description ?? "nil"))", category: .health)
        
        do {
            let token = try await ensureValidToken()
            AppLogger.debug("🔑 [STRAVA] Token valid, fetching activities...", category: .health)
            
            guard let after = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) else {
                throw StravaError.apiError("Failed to compute date range")
            }
            let afterTimestamp = Int(after.timeIntervalSince1970)
            
            guard var components = URLComponents(string: "\(Config.apiBaseUrl)/athlete/activities") else {
                throw StravaError.apiError("Invalid activities URL")
            }
            components.queryItems = [
                URLQueryItem(name: "after", value: String(afterTimestamp)),
                URLQueryItem(name: "per_page", value: "100")
            ]
            
            guard let activitiesURL = components.url else {
                throw StravaError.apiError("Invalid activities URL")
            }
            var request = URLRequest(url: activitiesURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StravaError.apiError("No HTTP response")
            }
            
            AppLogger.debug("📡 [STRAVA] API response: \(httpResponse.statusCode), body size: \(data.count) bytes", category: .network)
            
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.error("❌ [STRAVA] API error body: \(body.prefix(500))", category: .network)
                throw StravaError.apiError("HTTP \(httpResponse.statusCode): \(body.prefix(200))")
            }
            
            let decoder = JSONDecoder()
            // Do NOT use .convertFromSnakeCase — CodingKeys already handle snake_case mapping
            // Using both causes double-conversion: start_date → startDate but CodingKey expects "start_date"
            decoder.dateDecodingStrategy = .iso8601
            
            let activities = try decoder.decode([StravaActivity].self, from: data)
            
            recentActivities = activities
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "strava_last_sync")
            
            AppLogger.debug("📊 [STRAVA] Decoded \(activities.count) activities", category: .health)
            for (i, activity) in activities.prefix(5).enumerated() {
                AppLogger.debug("   \(i+1). \(activity.type) — \(activity.name) — \(activity.startDate)", category: .health)
            }
            
            // Save activities to Supabase for persistence
            await saveActivitiesToCloud(activities)
            
            // Check new activities against challenges
            await syncActivitiesToChallenges(activities)
            
            AppLogger.info("✅ [STRAVA] Synced \(activities.count) activities", category: .health)
            
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.error("❌ [STRAVA] Sync error: \(error)", category: .health)
        }
        
        isLoading = false
    }
    
    /// Get detailed activity by ID
    func getActivityDetail(id: Int64) async throws -> StravaActivityDetail {
        let token = try await ensureValidToken()
        
        guard let activityURL = URL(string: "\(Config.apiBaseUrl)/activities/\(id)") else {
            throw StravaError.apiError("Invalid activity detail URL")
        }
        var request = URLRequest(url: activityURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Failed to fetch activity detail")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(StravaActivityDetail.self, from: data)
    }
    
    /// Get athlete stats
    func getAthleteStats() async throws -> StravaAthleteStats {
        let token = try await ensureValidToken()
        
        guard let athleteId = athleteProfile?.id else {
            throw StravaError.notConnected
        }
        
        guard let statsURL = URL(string: "\(Config.apiBaseUrl)/athletes/\(athleteId)/stats") else {
            throw StravaError.apiError("Invalid athlete stats URL")
        }
        var request = URLRequest(url: statsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Failed to fetch athlete stats")
        }
        
        let decoder = JSONDecoder()
        
        return try decoder.decode(StravaAthleteStats.self, from: data)
    }
    
    // MARK: - Data Persistence
    
    /// Save synced activities to cardio_workouts table (integrates with app's workout system)
    private func saveActivitiesToCloud(_ activities: [StravaActivity]) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        var savedCount = 0
        var skippedCount = 0
        
        for activity in activities {
            // Only sync cardio activities (skip weight training, yoga, etc.)
            guard isCardioActivity(activity.type) else {
                skippedCount += 1
                continue
            }
            
            // Map Strava activity type to app's activity type
            let activityType = mapStravaActivityType(activity.type)
            
            // Convert speed from m/s to km/h
            let avgSpeedKmh = activity.averageSpeed.map { $0 * 3.6 }
            let maxSpeedKmh = activity.maxSpeed.map { $0 * 3.6 }
            
            // Calculate completed_at from start + duration
            let completedAt = activity.startDate.addingTimeInterval(Double(activity.movingTime))
            
            // Create the cardio workout insert record
            let insert = StravaCardioWorkoutInsert(
                userId: userId.uuidString,
                activityType: activityType,
                workoutName: activity.name,
                goalType: "open_goal",
                goalAchieved: true, // Already completed
                durationSeconds: activity.movingTime,
                distanceMeters: activity.distance,
                caloriesBurned: Double(activity.calories ?? 0),
                averageSpeed: avgSpeedKmh,
                maxSpeed: maxSpeedKmh,
                averageHeartRate: activity.averageHeartrate.map { Int($0) },
                maxHeartRate: activity.maxHeartrate.map { Int($0) },
                totalElevationGain: activity.totalElevationGain,
                startedAt: ISO8601DateFormatter().string(from: activity.startDate),
                completedAt: ISO8601DateFormatter().string(from: completedAt),
                source: "strava",
                externalId: String(activity.id),
                externalUrl: "https://www.strava.com/activities/\(activity.id)"
            )
            
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("cardio_workouts")
                    .upsert(insert, onConflict: "user_id,source,external_id")
                    .execute()
                savedCount += 1
            } catch {
                // If upsert fails due to constraint, try without conflict handling
                // This handles the case where the unique index doesn't exist yet
                do {
                    // Check if already exists
                    let existing: [CardioWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                        .from("cardio_workouts")
                        .select()
                        .eq("user_id", value: userId.uuidString)
                        .eq("source", value: "strava")
                        .eq("external_id", value: String(activity.id))
                        .execute()
                        .value
                    
                    if existing.isEmpty {
                        // Insert new
                        try await SupabaseManager.shared.supabaseClient
                            .from("cardio_workouts")
                            .insert(insert)
                            .execute()
                        savedCount += 1
                    } else {
                        skippedCount += 1 // Already exists
                    }
                } catch {
                    AppLogger.warning("⚠️ [STRAVA] Failed to save activity \(activity.id): \(error)", category: .health)
                }
            }
        }
        
        AppLogger.info("✅ [STRAVA] Synced \(savedCount) activities to cardio_workouts, skipped \(skippedCount)", category: .health)
        
        // Notify dashboard to reload cardio workouts so Strava workouts appear in Recent Activity
        if savedCount > 0 {
            await MainActor.run {
                NotificationCenter.default.post(name: .externalWorkoutSynced, object: nil)
            }
        }
        
        // 🔥 Update streak if we synced any activities from today
        // Check if any synced activity was from today
        let calendar = Calendar.current
        let todayActivities = activities.filter { calendar.isDateInToday($0.startDate) }
        if !todayActivities.isEmpty {
            await MainActor.run {
                UserManager.shared.updateStreak()
                AppLogger.debug("🔥 [STRAVA] Updated streak - found \(todayActivities.count) activities from today", category: .health)
            }
        }
    }
    
    /// Check if a Strava activity type is cardio (vs strength/yoga/etc)
    private func isCardioActivity(_ type: String) -> Bool {
        let cardioTypes = ["Run", "Ride", "Walk", "Hike", "Swim", "VirtualRun", "VirtualRide", 
                          "Rowing", "Elliptical", "StairStepper", "Crossfit", "Workout"]
        return cardioTypes.contains(type)
    }
    
    /// Map Strava activity type to app's activity type
    private func mapStravaActivityType(_ stravaType: String) -> String {
        switch stravaType {
        case "Run": return "outdoor_run"
        case "VirtualRun": return "treadmill"
        case "Ride": return "outdoor_cycle"
        case "VirtualRide": return "indoor_cycle"
        case "Walk", "Hike": return "walk"
        case "Swim": return "swimming"
        case "Rowing": return "rowing"
        case "Elliptical": return "elliptical"
        case "StairStepper": return "stair_climber"
        case "Crossfit", "Workout": return "hiit"
        default: return "outdoor_run"
        }
    }
    
    // MARK: - Sync Activities to Challenges
    
    /// Check Strava activities against active challenges and log progress
    private func syncActivitiesToChallenges(_ activities: [StravaActivity]) async {
        // Only process today's activities for challenges
        let calendar = Calendar.current
        let todayActivities = activities.filter { calendar.isDateInToday($0.startDate) }
        
        guard !todayActivities.isEmpty else {
            AppLogger.debug("📊 [STRAVA] No activities from today to sync to challenges", category: .health)
            return
        }
        
        AppLogger.debug("🏆 [STRAVA] Checking \(todayActivities.count) today's activities against challenges...", category: .health)
        
        for activity in todayActivities {
            await ChallengeService.shared.checkStravaWorkoutForChallenges(
                workoutType: activity.type,
                distanceMeters: activity.distance,
                durationSeconds: activity.movingTime,
                source: "strava"
            )
        }
    }
    
    // MARK: - Disconnect
    
    /// Disconnect Strava account
    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        athleteProfile = nil
        recentActivities = []
        lastSyncDate = nil
        isConnected = false
        
        UserDefaults.standard.removeObject(forKey: "strava_athlete")
        UserDefaults.standard.removeObject(forKey: "strava_last_sync")
        
        for key in ["strava_access_token", "strava_refresh_token", "strava_token_expires_at"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Update integration status in database
        Task {
            await SupabaseManager.shared.updateIntegrationStatus(integration: "strava", isConnected: false)
        }
        
        AppLogger.debug("🔌 [STRAVA] Disconnected", category: .health)
    }
    
    // MARK: - Computed Properties
    
    /// Total cardio minutes this week from Strava
    var weeklyCardioMinutes: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        
        return recentActivities
            .filter { $0.startDate >= startOfWeek }
            .filter { ["Run", "Ride", "Walk", "Hike", "Swim"].contains($0.type) }
            .reduce(0) { $0 + ($1.movingTime / 60) }
    }
    
    /// Total distance this week (in km)
    var weeklyDistanceKm: Double {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        
        return recentActivities
            .filter { $0.startDate >= startOfWeek }
            .reduce(0) { $0 + ($1.distance / 1000) }
    }
    
    /// Total calories burned this week from cardio
    var weeklyCaloriesBurned: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        
        return recentActivities
            .filter { $0.startDate >= startOfWeek }
            .reduce(0) { $0 + ($1.calories ?? 0) }
    }
}

// MARK: - Error Types

enum StravaError: LocalizedError {
    case invalidCallback
    case authorizationDenied(String)
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notConnected
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid callback from Strava"
        case .authorizationDenied(let reason):
            return "Authorization denied: \(reason)"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .notConnected:
            return "Not connected to Strava"
        case .apiError(let message):
            return message
        }
    }
}

// MARK: - API Response Models

struct StravaTokenResponse: Codable {
    let tokenType: String
    let expiresAt: Int
    let expiresIn: Int
    let refreshToken: String
    let accessToken: String
    let athlete: StravaAthlete?
    
    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case accessToken = "access_token"
        case athlete
    }
}

struct StravaRefreshResponse: Codable {
    let tokenType: String
    let expiresAt: Int
    let expiresIn: Int
    let refreshToken: String
    let accessToken: String
    
    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case accessToken = "access_token"
    }
}

struct StravaAthlete: Codable, Identifiable {
    let id: Int64
    let username: String?
    let firstname: String?
    let lastname: String?
    let city: String?
    let state: String?
    let country: String?
    let sex: String?
    let profile: String?  // Profile picture URL
    let profileMedium: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, firstname, lastname, city, state, country, sex, profile
        case profileMedium = "profile_medium"
    }
    
    var fullName: String {
        [firstname, lastname].compactMap { $0 }.joined(separator: " ")
    }
}

struct StravaActivity: Codable, Identifiable {
    let id: Int64
    let name: String
    let type: String
    let sportType: String?
    let startDate: Date
    let distance: Double  // meters
    let movingTime: Int  // seconds
    let elapsedTime: Int  // seconds
    let totalElevationGain: Double?  // meters
    let averageSpeed: Double?  // m/s
    let maxSpeed: Double?  // m/s
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let calories: Int?
    let sufferScore: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, distance, calories
        case sportType = "sport_type"
        case startDate = "start_date"
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case sufferScore = "suffer_score"
    }
    
    // Formatted properties
    var distanceFormatted: String {
        let km = distance / 1000
        if km >= 1 {
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
    
    var durationFormatted: String {
        let hours = movingTime / 3600
        let minutes = (movingTime % 3600) / 60
        let seconds = movingTime % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var paceFormatted: String? {
        guard let speed = averageSpeed, speed > 0 else { return nil }
        let paceSecondsPerKm = 1000 / speed
        let minutes = Int(paceSecondsPerKm) / 60
        let seconds = Int(paceSecondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
    
    var activityIcon: String {
        switch type {
        case "Run": return "figure.run"
        case "Ride": return "bicycle"
        case "Swim": return "figure.pool.swim"
        case "Walk": return "figure.walk"
        case "Hike": return "figure.hiking"
        case "WeightTraining": return "dumbbell.fill"
        case "Yoga": return "figure.mind.and.body"
        case "Workout": return "figure.strengthtraining.traditional"
        default: return "figure.mixed.cardio"
        }
    }
}

struct StravaActivityDetail: Codable {
    let id: Int64
    let name: String
    let description: String?
    let type: String
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let startDate: Date
    let calories: Int?
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let segmentEfforts: [StravaSegmentEffort]?
    let laps: [StravaLap]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, type, distance, calories
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case startDate = "start_date"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case segmentEfforts = "segment_efforts"
        case laps
    }
}

struct StravaSegmentEffort: Codable, Identifiable {
    let id: Int64
    let name: String
    let elapsedTime: Int
    let movingTime: Int
    let distance: Double
    let averageHeartrate: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, name, distance
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case averageHeartrate = "average_heartrate"
    }
}

struct StravaLap: Codable, Identifiable {
    let id: Int64
    let name: String
    let elapsedTime: Int
    let movingTime: Int
    let distance: Double
    let averageSpeed: Double?
    let averageHeartrate: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, name, distance
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case averageSpeed = "average_speed"
        case averageHeartrate = "average_heartrate"
    }
}

struct StravaAthleteStats: Codable {
    let recentRunTotals: StravaTotals?
    let recentRideTotals: StravaTotals?
    let recentSwimTotals: StravaTotals?
    let ytdRunTotals: StravaTotals?
    let ytdRideTotals: StravaTotals?
    let ytdSwimTotals: StravaTotals?
    let allRunTotals: StravaTotals?
    let allRideTotals: StravaTotals?
    let allSwimTotals: StravaTotals?
    
    enum CodingKeys: String, CodingKey {
        case recentRunTotals = "recent_run_totals"
        case recentRideTotals = "recent_ride_totals"
        case recentSwimTotals = "recent_swim_totals"
        case ytdRunTotals = "ytd_run_totals"
        case ytdRideTotals = "ytd_ride_totals"
        case ytdSwimTotals = "ytd_swim_totals"
        case allRunTotals = "all_run_totals"
        case allRideTotals = "all_ride_totals"
        case allSwimTotals = "all_swim_totals"
    }
}

struct StravaTotals: Codable {
    let count: Int?
    let distance: Double?
    let movingTime: Int?
    let elapsedTime: Int?
    let elevationGain: Double?
    
    enum CodingKeys: String, CodingKey {
        case count, distance
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case elevationGain = "elevation_gain"
    }
}

// MARK: - Database Records

/// Insert record for saving Strava activities to cardio_workouts table
struct StravaCardioWorkoutInsert: Codable {
    let userId: String
    let activityType: String
    let workoutName: String?
    let goalType: String
    let goalAchieved: Bool
    let durationSeconds: Int
    let distanceMeters: Double
    let caloriesBurned: Double
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let totalElevationGain: Double?
    let startedAt: String
    let completedAt: String
    let source: String
    let externalId: String
    let externalUrl: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case activityType = "activity_type"
        case workoutName = "workout_name"
        case goalType = "goal_type"
        case goalAchieved = "goal_achieved"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case caloriesBurned = "calories_burned"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case totalElevationGain = "total_elevation_gain"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case source
        case externalId = "external_id"
        case externalUrl = "external_url"
    }
}

/// Legacy record for strava_activities table (kept for backwards compatibility)
struct StravaActivityRecord: Codable {
    let id: UUID
    let userId: UUID
    let stravaId: Int64
    let name: String
    let type: String
    let sportType: String?
    let startDate: Date
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let calories: Int?
    let sufferScore: Int?
    let syncedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case stravaId = "strava_id"
        case name, type
        case sportType = "sport_type"
        case startDate = "start_date"
        case distance
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case calories
        case sufferScore = "suffer_score"
        case syncedAt = "synced_at"
    }
}
