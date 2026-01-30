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
        get { UserDefaults.standard.string(forKey: "strava_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "strava_access_token") }
    }
    
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "strava_refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "strava_refresh_token") }
    }
    
    private var tokenExpiresAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: "strava_token_expires_at")
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "strava_token_expires_at")
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Check if we have a valid connection
        isConnected = accessToken != nil && refreshToken != nil
        
        if isConnected {
            // Load cached athlete profile
            if let data = UserDefaults.standard.data(forKey: "strava_athlete"),
               let athlete = try? JSONDecoder().decode(StravaAthlete.self, from: data) {
                athleteProfile = athlete
            }
            
            // Load last sync date
            if let date = UserDefaults.standard.object(forKey: "strava_last_sync") as? Date {
                lastSyncDate = date
            }
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
        
        var request = URLRequest(url: URL(string: Config.tokenUrl)!)
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
        
        print("✅ [STRAVA] Connected as \(tokenResponse.athlete?.firstname ?? "Unknown") \(tokenResponse.athlete?.lastname ?? "")")
        
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
        
        var request = URLRequest(url: URL(string: Config.tokenUrl)!)
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
        
        print("🔄 [STRAVA] Token refreshed")
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
        guard isConnected else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let token = try await ensureValidToken()
            
            let after = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
            let afterTimestamp = Int(after.timeIntervalSince1970)
            
            var components = URLComponents(string: "\(Config.apiBaseUrl)/athlete/activities")!
            components.queryItems = [
                URLQueryItem(name: "after", value: String(afterTimestamp)),
                URLQueryItem(name: "per_page", value: "100")
            ]
            
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw StravaError.apiError("Failed to fetch activities")
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            
            let activities = try decoder.decode([StravaActivity].self, from: data)
            
            recentActivities = activities
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "strava_last_sync")
            
            // Save activities to Supabase for persistence
            await saveActivitiesToCloud(activities)
            
            print("✅ [STRAVA] Synced \(activities.count) activities")
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [STRAVA] Sync error: \(error)")
        }
        
        isLoading = false
    }
    
    /// Get detailed activity by ID
    func getActivityDetail(id: Int64) async throws -> StravaActivityDetail {
        let token = try await ensureValidToken()
        
        var request = URLRequest(url: URL(string: "\(Config.apiBaseUrl)/activities/\(id)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Failed to fetch activity detail")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(StravaActivityDetail.self, from: data)
    }
    
    /// Get athlete stats
    func getAthleteStats() async throws -> StravaAthleteStats {
        let token = try await ensureValidToken()
        
        guard let athleteId = athleteProfile?.id else {
            throw StravaError.notConnected
        }
        
        var request = URLRequest(url: URL(string: "\(Config.apiBaseUrl)/athletes/\(athleteId)/stats")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Failed to fetch athlete stats")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(StravaAthleteStats.self, from: data)
    }
    
    // MARK: - Data Persistence
    
    /// Save synced activities to Supabase
    private func saveActivitiesToCloud(_ activities: [StravaActivity]) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        for activity in activities {
            let stravaActivity = StravaActivityRecord(
                id: UUID(),
                userId: userId,
                stravaId: activity.id,
                name: activity.name,
                type: activity.type,
                sportType: activity.sportType,
                startDate: activity.startDate,
                distance: activity.distance,
                movingTime: activity.movingTime,
                elapsedTime: activity.elapsedTime,
                totalElevationGain: activity.totalElevationGain,
                averageSpeed: activity.averageSpeed,
                maxSpeed: activity.maxSpeed,
                averageHeartrate: activity.averageHeartrate,
                maxHeartrate: activity.maxHeartrate,
                calories: activity.calories,
                sufferScore: activity.sufferScore,
                syncedAt: Date()
            )
            
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("strava_activities")
                    .upsert(stravaActivity, onConflict: "user_id,strava_id")
                    .execute()
            } catch {
                print("⚠️ [STRAVA] Failed to save activity \(activity.id): \(error)")
            }
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
        
        print("🔌 [STRAVA] Disconnected")
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

// MARK: - Database Record

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
