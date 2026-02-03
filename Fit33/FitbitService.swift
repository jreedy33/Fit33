//
//  FitbitService.swift
//  Fit33
//
//  Fitbit API Integration - Syncs workouts, steps, sleep, and health data with Fit33
//

import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - Fitbit Service

@MainActor
final class FitbitService: ObservableObject {
    static let shared = FitbitService()
    
    // MARK: - Configuration (Add your Fitbit API credentials here)
    
    private struct Config {
        static let clientId = AppConfig.Fitbit.clientId
        static let clientSecret = AppConfig.Fitbit.clientSecret
        static let redirectUri = AppConfig.Fitbit.redirectUri
        static let authorizationUrl = AppConfig.Fitbit.authorizationUrl
        static let tokenUrl = AppConfig.Fitbit.tokenUrl
        static let apiBaseUrl = AppConfig.Fitbit.apiBaseUrl
        static let scopes = AppConfig.Fitbit.scopes
    }
    
    // MARK: - Published Properties
    
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var userProfile: FitbitUser?
    @Published var recentActivities: [FitbitActivity] = []
    @Published var todaySummary: FitbitDailySummary?
    @Published var sleepData: [FitbitSleepLog] = []
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "fitbit_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "fitbit_access_token") }
    }
    
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "fitbit_refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "fitbit_refresh_token") }
    }
    
    private var tokenExpiresAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: "fitbit_token_expires_at")
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "fitbit_token_expires_at")
        }
    }
    
    private var userId: String? {
        get { UserDefaults.standard.string(forKey: "fitbit_user_id") }
        set { UserDefaults.standard.set(newValue, forKey: "fitbit_user_id") }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Check if we have a valid connection
        isConnected = accessToken != nil && refreshToken != nil
        
        if isConnected {
            // Load cached profile
            if let data = UserDefaults.standard.data(forKey: "fitbit_user"),
               let user = try? JSONDecoder().decode(FitbitUser.self, from: data) {
                userProfile = user
            }
            
            // Load last sync date
            if let date = UserDefaults.standard.object(forKey: "fitbit_last_sync") as? Date {
                lastSyncDate = date
            }
        }
    }
    
    // MARK: - OAuth Flow
    
    /// Returns the OAuth authorization URL for Fitbit
    func getAuthorizationURL() -> URL? {
        // Generate code verifier and challenge for PKCE
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        // Store code verifier for token exchange
        UserDefaults.standard.set(codeVerifier, forKey: "fitbit_code_verifier")
        
        var components = URLComponents(string: Config.authorizationUrl)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Config.clientId),
            URLQueryItem(name: "redirect_uri", value: Config.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Config.scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }
    
    /// Handle the OAuth callback URL
    func handleCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw FitbitError.invalidCallback
        }
        
        // Check for errors in callback
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw FitbitError.authorizationDenied(error)
        }
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)
    }
    
    /// Exchange authorization code for access/refresh tokens
    private func exchangeCodeForTokens(code: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let codeVerifier = UserDefaults.standard.string(forKey: "fitbit_code_verifier") else {
            throw FitbitError.tokenExchangeFailed
        }
        
        // Build request body
        let bodyParams = [
            "client_id": Config.clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": Config.redirectUri
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        
        var request = URLRequest(url: URL(string: Config.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Fitbit requires Basic auth header with client_id:client_secret
        let credentials = "\(Config.clientId):\(Config.clientSecret)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FitbitError.tokenExchangeFailed
        }
        
        if httpResponse.statusCode != 200 {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ [FITBIT] Token exchange error: \(errorBody)")
            }
            throw FitbitError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(FitbitTokenResponse.self, from: data)
        
        // Save tokens
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        tokenExpiresAt = Date().addingTimeInterval(Double(tokenResponse.expiresIn))
        userId = tokenResponse.userId
        
        // Clear code verifier
        UserDefaults.standard.removeObject(forKey: "fitbit_code_verifier")
        
        isConnected = true
        
        print("✅ [FITBIT] Connected! User ID: \(tokenResponse.userId)")
        
        // Fetch user profile and sync data
        await fetchUserProfile()
        await syncAllData()
    }
    
    /// Refresh the access token if expired
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw FitbitError.notConnected
        }
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        
        var request = URLRequest(url: URL(string: Config.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Fitbit requires Basic auth header
        let credentials = "\(Config.clientId):\(Config.clientSecret)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Refresh failed - user needs to re-authenticate
            disconnect()
            throw FitbitError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(FitbitTokenResponse.self, from: data)
        
        accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        tokenExpiresAt = Date().addingTimeInterval(Double(tokenResponse.expiresIn))
        
        print("🔄 [FITBIT] Token refreshed")
    }
    
    /// Ensure we have a valid access token
    private func ensureValidToken() async throws -> String {
        guard let token = accessToken else {
            throw FitbitError.notConnected
        }
        
        // Check if token is expired or expiring soon (within 5 minutes)
        if let expiresAt = tokenExpiresAt, expiresAt.timeIntervalSinceNow < 300 {
            try await refreshAccessToken()
            guard let newToken = accessToken else {
                throw FitbitError.tokenRefreshFailed
            }
            return newToken
        }
        
        return token
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - API Methods
    
    /// Fetch user profile
    func fetchUserProfile() async {
        do {
            let token = try await ensureValidToken()
            
            var request = URLRequest(url: URL(string: "\(Config.apiBaseUrl)/1/user/-/profile.json")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FitbitError.apiError("Failed to fetch profile")
            }
            
            let profileResponse = try JSONDecoder().decode(FitbitProfileResponse.self, from: data)
            userProfile = profileResponse.user
            
            // Cache profile
            if let userData = try? JSONEncoder().encode(profileResponse.user) {
                UserDefaults.standard.set(userData, forKey: "fitbit_user")
            }
            
            print("✅ [FITBIT] Loaded profile: \(profileResponse.user.fullName)")
            
        } catch {
            print("❌ [FITBIT] Profile error: \(error)")
        }
    }
    
    /// Minimum time between syncs (5 minutes)
    private static let syncThrottleInterval: TimeInterval = 300
    private var isSyncing = false
    
    /// Sync all relevant data from Fitbit (throttled to prevent excessive API calls)
    func syncAllData(force: Bool = false) async {
        guard isConnected else { return }
        
        // Throttle: Skip if already syncing or synced recently (unless forced)
        if !force {
            if isSyncing {
                print("⏭️ [FITBIT] Skipping sync - already in progress")
                return
            }
            
            if let lastSync = lastSyncDate,
               Date().timeIntervalSince(lastSync) < Self.syncThrottleInterval {
                print("⏭️ [FITBIT] Skipping sync - synced \(Int(Date().timeIntervalSince(lastSync)))s ago (throttle: \(Int(Self.syncThrottleInterval))s)")
                return
            }
        }
        
        isSyncing = true
        isLoading = true
        errorMessage = nil
        
        // Sync in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.syncActivities(daysBack: 30) }
            group.addTask { await self.syncDailySummary() }
            group.addTask { await self.syncSleepData(daysBack: 7) }
        }
        
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "fitbit_last_sync")
        
        isLoading = false
        isSyncing = false
        print("✅ [FITBIT] Full sync complete")
    }
    
    /// Sync activities (workouts) from Fitbit
    func syncActivities(daysBack: Int = 30) async {
        do {
            let token = try await ensureValidToken()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let afterDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
            let afterDateStr = dateFormatter.string(from: afterDate)
            let todayStr = dateFormatter.string(from: Date())
            
            // Fetch activity logs
            let url = URL(string: "\(Config.apiBaseUrl)/1/user/-/activities/list.json?afterDate=\(afterDateStr)&sort=desc&limit=100&offset=0")!
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FitbitError.apiError("Failed to fetch activities")
            }
            
            let activitiesResponse = try JSONDecoder().decode(FitbitActivitiesResponse.self, from: data)
            recentActivities = activitiesResponse.activities
            
            // Save activities to Supabase
            await saveActivitiesToCloud(activitiesResponse.activities)
            
            print("✅ [FITBIT] Synced \(activitiesResponse.activities.count) activities")
            
        } catch {
            print("❌ [FITBIT] Activities sync error: \(error)")
            errorMessage = error.localizedDescription
        }
    }
    
    /// Sync daily summary (steps, calories, distance)
    func syncDailySummary() async {
        do {
            let token = try await ensureValidToken()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayStr = dateFormatter.string(from: Date())
            
            let url = URL(string: "\(Config.apiBaseUrl)/1/user/-/activities/date/\(todayStr).json")!
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FitbitError.apiError("Failed to fetch daily summary")
            }
            
            let summary = try JSONDecoder().decode(FitbitDailySummaryResponse.self, from: data)
            todaySummary = summary.summary
            
            print("✅ [FITBIT] Today: \(summary.summary.steps) steps, \(summary.summary.caloriesOut) cal")
            
        } catch {
            print("❌ [FITBIT] Daily summary error: \(error)")
        }
    }
    
    /// Sync sleep data
    func syncSleepData(daysBack: Int = 7) async {
        do {
            let token = try await ensureValidToken()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let afterDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
            let afterDateStr = dateFormatter.string(from: afterDate)
            let todayStr = dateFormatter.string(from: Date())
            
            let url = URL(string: "\(Config.apiBaseUrl)/1.2/user/-/sleep/date/\(afterDateStr)/\(todayStr).json")!
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw FitbitError.apiError("Failed to fetch sleep data")
            }
            
            let sleepResponse = try JSONDecoder().decode(FitbitSleepResponse.self, from: data)
            sleepData = sleepResponse.sleep
            
            print("✅ [FITBIT] Synced \(sleepResponse.sleep.count) sleep logs")
            
        } catch {
            print("❌ [FITBIT] Sleep sync error: \(error)")
        }
    }
    
    /// Fetch heart rate data for a specific day
    func fetchHeartRateData(for date: Date = Date()) async -> FitbitHeartRateData? {
        do {
            let token = try await ensureValidToken()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: date)
            
            let url = URL(string: "\(Config.apiBaseUrl)/1/user/-/activities/heart/date/\(dateStr)/1d.json")!
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let heartResponse = try JSONDecoder().decode(FitbitHeartRateResponse.self, from: data)
            return heartResponse.activitiesHeart.first?.value
            
        } catch {
            print("❌ [FITBIT] Heart rate error: \(error)")
            return nil
        }
    }
    
    // MARK: - Data Persistence
    
    /// Save synced activities to cardio_workouts table
    private func saveActivitiesToCloud(_ activities: [FitbitActivity]) async {
        guard let appUserId = SupabaseManager.shared.currentUser?.id else { return }
        
        var savedCount = 0
        var skippedCount = 0
        
        for activity in activities {
            // Map Fitbit activity type to app's activity type
            let activityType = mapFitbitActivityType(activity.activityName)
            
            // Parse dates
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            let startDate = dateFormatter.date(from: activity.startTime) ?? Date()
            let completedAt = startDate.addingTimeInterval(Double(activity.activeDuration / 1000))
            
            // Create the cardio workout insert record
            let insert = FitbitCardioWorkoutInsert(
                userId: appUserId.uuidString,
                activityType: activityType,
                workoutName: activity.activityName,
                goalType: "open_goal",
                goalAchieved: true,
                durationSeconds: activity.activeDuration / 1000, // Convert from ms
                distanceMeters: activity.distance ?? 0,
                caloriesBurned: Double(activity.calories),
                averageSpeed: activity.speed,
                maxSpeed: nil,
                averageHeartRate: activity.averageHeartRate,
                maxHeartRate: nil,
                totalElevationGain: activity.elevationGain,
                startedAt: ISO8601DateFormatter().string(from: startDate),
                completedAt: ISO8601DateFormatter().string(from: completedAt),
                source: "fitbit",
                externalId: String(activity.logId),
                externalUrl: nil
            )
            
            do {
                // Check if already exists
                let existing: [CardioWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                    .from("cardio_workouts")
                    .select()
                    .eq("user_id", value: appUserId.uuidString)
                    .eq("source", value: "fitbit")
                    .eq("external_id", value: String(activity.logId))
                    .execute()
                    .value
                
                if existing.isEmpty {
                    try await SupabaseManager.shared.supabaseClient
                        .from("cardio_workouts")
                        .insert(insert)
                        .execute()
                    savedCount += 1
                } else {
                    skippedCount += 1
                }
            } catch {
                print("⚠️ [FITBIT] Failed to save activity \(activity.logId): \(error)")
            }
        }
        
        print("✅ [FITBIT] Saved \(savedCount) activities, skipped \(skippedCount) existing")
        
        // Update streak if we synced activities from today
        let calendar = Calendar.current
        let dateFormatter = ISO8601DateFormatter()
        let todayActivities = activities.filter { activity in
            if let date = dateFormatter.date(from: activity.startTime) {
                return calendar.isDateInToday(date)
            }
            return false
        }
        
        if !todayActivities.isEmpty {
            await MainActor.run {
                UserManager.shared.updateStreak()
                print("🔥 [FITBIT] Updated streak - found \(todayActivities.count) activities from today")
            }
            
            // 🏆 Sync today's activities to challenges
            await syncActivitiesToChallenges(todayActivities)
        }
    }
    
    /// Sync Fitbit activities to active challenges
    private func syncActivitiesToChallenges(_ activities: [FitbitActivity]) async {
        let calendar = Calendar.current
        let todayActivities = activities.filter { activity in
            if let date = ISO8601DateFormatter().date(from: activity.startTime) {
                return calendar.isDateInToday(date)
            }
            return false
        }
        
        guard !todayActivities.isEmpty else {
            print("📊 [FITBIT] No activities from today to sync to challenges")
            return
        }
        
        print("🏆 [FITBIT] Checking \(todayActivities.count) today's activities against challenges...")
        
        for activity in todayActivities {
            await ChallengeService.shared.checkStravaWorkoutForChallenges(
                workoutType: activity.activityName,
                distanceMeters: activity.distance ?? 0,
                durationSeconds: activity.activeDuration / 1000, // Convert from ms
                source: "fitbit"
            )
        }
    }
    
    /// Map Fitbit activity name to app's activity type
    private func mapFitbitActivityType(_ fitbitType: String) -> String {
        let lowercased = fitbitType.lowercased()
        
        if lowercased.contains("run") || lowercased.contains("jog") {
            return lowercased.contains("treadmill") ? "treadmill" : "outdoor_run"
        } else if lowercased.contains("walk") {
            return "walk"
        } else if lowercased.contains("bike") || lowercased.contains("cycling") || lowercased.contains("ride") {
            return lowercased.contains("indoor") || lowercased.contains("stationary") ? "indoor_cycle" : "outdoor_cycle"
        } else if lowercased.contains("swim") {
            return "swimming"
        } else if lowercased.contains("elliptical") {
            return "elliptical"
        } else if lowercased.contains("stair") {
            return "stair_climber"
        } else if lowercased.contains("rowing") || lowercased.contains("row") {
            return "rowing"
        } else if lowercased.contains("hiit") || lowercased.contains("interval") || lowercased.contains("circuit") {
            return "hiit"
        } else if lowercased.contains("yoga") {
            return "yoga"
        } else if lowercased.contains("hike") || lowercased.contains("hiking") {
            return "walk"
        }
        
        return "outdoor_run" // Default
    }
    
    // MARK: - Disconnect
    
    /// Disconnect Fitbit account
    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        userId = nil
        userProfile = nil
        recentActivities = []
        todaySummary = nil
        sleepData = []
        lastSyncDate = nil
        isConnected = false
        
        UserDefaults.standard.removeObject(forKey: "fitbit_user")
        UserDefaults.standard.removeObject(forKey: "fitbit_last_sync")
        UserDefaults.standard.removeObject(forKey: "fitbit_code_verifier")
        
        print("🔌 [FITBIT] Disconnected")
    }
    
    // MARK: - Computed Properties
    
    /// Total steps today from Fitbit
    var todaySteps: Int {
        todaySummary?.steps ?? 0
    }
    
    /// Total calories burned today
    var todayCalories: Int {
        todaySummary?.caloriesOut ?? 0
    }
    
    /// Active minutes today
    var todayActiveMinutes: Int {
        let summary = todaySummary
        return (summary?.fairlyActiveMinutes ?? 0) + (summary?.veryActiveMinutes ?? 0)
    }
    
    /// Average sleep duration (last 7 days) in hours
    var averageSleepHours: Double {
        guard !sleepData.isEmpty else { return 0 }
        let totalMinutes = sleepData.reduce(0) { $0 + $1.duration }
        return Double(totalMinutes) / Double(sleepData.count) / 60.0 / 1000.0
    }
}

// MARK: - Error Types

enum FitbitError: LocalizedError {
    case invalidCallback
    case authorizationDenied(String)
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notConnected
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid callback from Fitbit"
        case .authorizationDenied(let reason):
            return "Authorization denied: \(reason)"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code"
        case .tokenRefreshFailed:
            return "Failed to refresh access token. Please reconnect."
        case .notConnected:
            return "Not connected to Fitbit"
        case .apiError(let message):
            return message
        }
    }
}

// MARK: - API Response Models

struct FitbitTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String
    let tokenType: String
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case userId = "user_id"
    }
}

struct FitbitProfileResponse: Codable {
    let user: FitbitUser
}

struct FitbitUser: Codable, Identifiable {
    let encodedId: String
    let displayName: String
    let firstName: String?
    let lastName: String?
    let avatar: String?
    let avatar150: String?
    let gender: String?
    let height: Double?
    let weight: Double?
    let age: Int?
    let dateOfBirth: String?
    let averageDailySteps: Int?
    let memberSince: String?
    
    var id: String { encodedId }
    
    var fullName: String {
        if let first = firstName, let last = lastName {
            return "\(first) \(last)"
        }
        return displayName
    }
}

struct FitbitActivitiesResponse: Codable {
    let activities: [FitbitActivity]
    let pagination: FitbitPagination?
}

struct FitbitActivity: Codable, Identifiable {
    let logId: Int64
    let activityName: String
    let activityTypeId: Int
    let calories: Int
    let activeDuration: Int  // milliseconds
    let distance: Double?
    let distanceUnit: String?
    let startTime: String  // ISO8601 format
    let steps: Int?
    let speed: Double?
    let pace: Double?
    let averageHeartRate: Int?
    let elevationGain: Double?
    let hasGps: Bool?
    let source: FitbitActivitySource?
    
    var id: Int64 { logId }
    
    // Computed properties for display
    var durationMinutes: Int {
        activeDuration / 60000
    }
    
    var distanceKm: Double {
        (distance ?? 0) / 1000
    }
    
    var activityIcon: String {
        let name = activityName.lowercased()
        if name.contains("run") { return "figure.run" }
        if name.contains("walk") { return "figure.walk" }
        if name.contains("bike") || name.contains("cycling") { return "bicycle" }
        if name.contains("swim") { return "figure.pool.swim" }
        if name.contains("yoga") { return "figure.mind.and.body" }
        if name.contains("weight") || name.contains("strength") { return "dumbbell.fill" }
        return "figure.mixed.cardio"
    }
}

struct FitbitActivitySource: Codable {
    let id: String?
    let name: String?
    let type: String?
}

struct FitbitPagination: Codable {
    let afterDate: String?
    let limit: Int?
    let next: String?
    let offset: Int?
    let previous: String?
    let sort: String?
}

struct FitbitDailySummaryResponse: Codable {
    let summary: FitbitDailySummary
    let goals: FitbitGoals?
}

struct FitbitDailySummary: Codable {
    let steps: Int
    let caloriesOut: Int
    let caloriesBMR: Int?
    let activityCalories: Int?
    let marginalCalories: Int?
    let sedentaryMinutes: Int?
    let lightlyActiveMinutes: Int?
    let fairlyActiveMinutes: Int?
    let veryActiveMinutes: Int?
    let distances: [FitbitDistance]?
    let floors: Int?
    let elevation: Double?
    let restingHeartRate: Int?
}

struct FitbitDistance: Codable {
    let activity: String
    let distance: Double
}

struct FitbitGoals: Codable {
    let steps: Int?
    let caloriesOut: Int?
    let distance: Double?
    let floors: Int?
    let activeMinutes: Int?
}

struct FitbitSleepResponse: Codable {
    let sleep: [FitbitSleepLog]
    let summary: FitbitSleepSummary?
}

struct FitbitSleepLog: Codable, Identifiable {
    let logId: Int64
    let dateOfSleep: String
    let startTime: String
    let endTime: String
    let duration: Int  // milliseconds
    let efficiency: Int?
    let minutesAsleep: Int?
    let minutesAwake: Int?
    let timeInBed: Int?
    let mainSleep: Bool?
    let type: String?
    
    var id: Int64 { logId }
    
    var sleepHours: Double {
        Double(duration) / 3600000.0
    }
}

struct FitbitSleepSummary: Codable {
    let totalMinutesAsleep: Int?
    let totalSleepRecords: Int?
    let totalTimeInBed: Int?
}

struct FitbitHeartRateResponse: Codable {
    let activitiesHeart: [FitbitHeartRateDay]
    
    enum CodingKeys: String, CodingKey {
        case activitiesHeart = "activities-heart"
    }
}

struct FitbitHeartRateDay: Codable {
    let dateTime: String
    let value: FitbitHeartRateData
}

struct FitbitHeartRateData: Codable {
    let restingHeartRate: Int?
    let heartRateZones: [FitbitHeartRateZone]?
}

struct FitbitHeartRateZone: Codable {
    let name: String
    let min: Int
    let max: Int
    let minutes: Int?
    let caloriesOut: Double?
}

// MARK: - Database Records

/// Insert record for saving Fitbit activities to cardio_workouts table
struct FitbitCardioWorkoutInsert: Codable {
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
    let externalUrl: String?
    
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

// MARK: - CommonCrypto import for SHA256
import CommonCrypto
