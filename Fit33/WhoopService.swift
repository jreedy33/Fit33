//
//  WhoopService.swift
//  Fit33
//
//  WHOOP API Integration — Syncs recovery, strain, sleep, workouts, and body measurements
//

import Foundation
import AuthenticationServices
import SwiftUI

@MainActor
final class WhoopService: ObservableObject {
    static let shared = WhoopService()

    private struct Config {
        static let clientId = AppConfig.Whoop.clientId
        static let clientSecret = AppConfig.Whoop.clientSecret
        static let redirectUri = AppConfig.Whoop.redirectUri
        static let authorizationUrl = AppConfig.Whoop.authorizationUrl
        static let tokenUrl = AppConfig.Whoop.tokenUrl
        static let apiBaseUrl = AppConfig.Whoop.apiBaseUrl
        static let scopes = AppConfig.Whoop.scopes
    }

    // MARK: - Published Properties

    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?

    @Published var todayRecovery: WhoopRecoveryScore?
    @Published var todayStrain: WhoopCycleScore?
    @Published var lastSleep: WhoopSleepScore?
    @Published var userProfile: WhoopProfile?
    @Published var bodyMeasurements: WhoopBodyMeasurement?

    @Published var recentRecoveries: [WhoopRecoveryRecord] = []
    @Published var recentCycles: [WhoopCycleRecord] = []
    @Published var recentSleeps: [WhoopSleepRecord] = []
    @Published var recentWorkouts: [WhoopWorkoutRecord] = []

    // MARK: - Token Storage (Keychain)

    private var accessToken: String? {
        get { KeychainHelper.load(key: "whoop_access_token") }
        set {
            if let val = newValue { KeychainHelper.save(key: "whoop_access_token", value: val) }
            else { KeychainHelper.delete(key: "whoop_access_token") }
        }
    }

    private var refreshToken: String? {
        get { KeychainHelper.load(key: "whoop_refresh_token") }
        set {
            if let val = newValue { KeychainHelper.save(key: "whoop_refresh_token", value: val) }
            else { KeychainHelper.delete(key: "whoop_refresh_token") }
        }
    }

    private var tokenExpiresAt: Date? {
        get {
            guard let str = KeychainHelper.load(key: "whoop_token_expires_at"),
                  let timestamp = Double(str), timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let ts = newValue?.timeIntervalSince1970 {
                KeychainHelper.save(key: "whoop_token_expires_at", value: String(ts))
            } else {
                KeychainHelper.delete(key: "whoop_token_expires_at")
            }
        }
    }

    // MARK: - Sync Throttling

    private static let syncThrottleInterval: TimeInterval = 300
    private var isSyncing = false

    // MARK: - Initialization

    private init() {
        isConnected = accessToken != nil

        if isConnected {
            if let data = UserDefaults.standard.data(forKey: "whoop_profile"),
               let profile = try? JSONDecoder().decode(WhoopProfile.self, from: data) {
                userProfile = profile
            }
            if let data = UserDefaults.standard.data(forKey: "whoop_today_recovery"),
               let recovery = try? JSONDecoder().decode(WhoopRecoveryScore.self, from: data) {
                todayRecovery = recovery
            }
            if let data = UserDefaults.standard.data(forKey: "whoop_today_strain"),
               let strain = try? JSONDecoder().decode(WhoopCycleScore.self, from: data) {
                todayStrain = strain
            }
            if let date = UserDefaults.standard.object(forKey: "whoop_last_sync") as? Date {
                lastSyncDate = date
            }
        }
    }

    // MARK: - OAuth Flow

    func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: Config.authorizationUrl)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Config.clientId),
            URLQueryItem(name: "redirect_uri", value: Config.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Config.scopes),
            URLQueryItem(name: "state", value: generateState())
        ]
        return components?.url
    }

    func handleCallback(url: URL) async throws {
        AppLogger.info("[WHOOP] Received callback URL: \(url.absoluteString.prefix(80))...", category: .auth)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WhoopError.invalidCallback
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let desc = components.queryItems?.first(where: { $0.name == "error_description" })?.value
            AppLogger.error("[WHOOP] OAuth error: \(error) — \(desc ?? "no description")", category: .auth)
            throw WhoopError.authorizationDenied(desc ?? error)
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            AppLogger.error("[WHOOP] No 'code' parameter in callback. Params: \(components.queryItems?.map(\.name) ?? [])", category: .auth)
            throw WhoopError.invalidCallback
        }

        AppLogger.info("[WHOOP] Got authorization code, exchanging for tokens...", category: .auth)
        try await exchangeCodeForTokens(code: code)
    }

    private func exchangeCodeForTokens(code: String) async throws {
        isLoading = true
        defer { isLoading = false }

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: Config.clientId),
            URLQueryItem(name: "client_secret", value: Config.clientSecret),
            URLQueryItem(name: "redirect_uri", value: Config.redirectUri)
        ]
        guard let bodyString = bodyComponents.query else {
            throw WhoopError.tokenExchangeFailed
        }

        guard let tokenURL = URL(string: Config.tokenUrl) else {
            throw WhoopError.tokenExchangeFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhoopError.tokenExchangeFailed
        }

        AppLogger.info("[WHOOP] Token exchange response: HTTP \(httpResponse.statusCode)", category: .auth)

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                AppLogger.error("[WHOOP] Token exchange error (HTTP \(httpResponse.statusCode)): \(errorBody)", category: .auth)
            }
            throw WhoopError.tokenExchangeFailed
        }

        let tokenResponse: WhoopTokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(WhoopTokenResponse.self, from: data)
        } catch {
            if let body = String(data: data, encoding: .utf8) {
                AppLogger.error("[WHOOP] Token decode failed. Body: \(body.prefix(500))", category: .auth)
            }
            throw WhoopError.tokenExchangeFailed
        }

        accessToken = tokenResponse.accessToken
        if let rt = tokenResponse.refreshToken {
            refreshToken = rt
        }
        tokenExpiresAt = Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 3600))
        isConnected = true

        AppLogger.info("[WHOOP] Connected successfully (token expires in \(tokenResponse.expiresIn ?? 3600)s)", category: .health)

        Task {
            await SupabaseManager.shared.updateIntegrationStatus(integration: "whoop", isConnected: true)
        }

        await fetchProfile()
        await syncAllData()
    }

    private func refreshAccessToken() async throws {
        guard let currentRefreshToken = refreshToken else {
            throw WhoopError.notConnected
        }

        let bodyParams = [
            "client_id": Config.clientId,
            "client_secret": Config.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": currentRefreshToken
        ]
        let bodyString = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        guard let tokenURL = URL(string: Config.tokenUrl) else {
            throw WhoopError.tokenRefreshFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            disconnect()
            throw WhoopError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(WhoopTokenResponse.self, from: data)

        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        tokenExpiresAt = Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 3600))

        AppLogger.debug("[WHOOP] Token refreshed", category: .health)
    }

    private func ensureValidToken() async throws -> String {
        guard let token = accessToken else {
            throw WhoopError.notConnected
        }

        if let expiresAt = tokenExpiresAt, expiresAt.timeIntervalSinceNow < 300 {
            try await refreshAccessToken()
            guard let newToken = accessToken else {
                throw WhoopError.tokenRefreshFailed
            }
            return newToken
        }
        return token
    }

    private func generateState() -> String {
        var buffer = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// User-visible copy for WHOOP settings / Sync card (avoids raw ingress messages like "default backend - 404").
    private static func userFacingSyncErrorMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("default backend") {
            return "We couldn’t load your WHOOP data. Update Fit33 to the latest version, then tap Sync again."
        }
        if lower.contains("http 404") {
            return "WHOOP’s service didn’t respond. Check for an app update, then try Sync again."
        }
        return raw
    }

    private func setSyncError(_ error: Error) {
        errorMessage = Self.userFacingSyncErrorMessage(for: error)
    }

    // MARK: - Generic API Request

    private func apiRequest<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let token = try await ensureValidToken()

        var components = URLComponents(string: "\(Config.apiBaseUrl)\(path)")
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw WhoopError.apiError("Invalid URL: \(path)")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhoopError.apiError("No HTTP response")
        }

        if httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            return try await apiRequest(path, queryItems: queryItems)
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw WhoopError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Profile

    func fetchProfile() async {
        do {
            let profile: WhoopProfile = try await apiRequest("/v2/user/profile/basic")
            userProfile = profile
            if let encoded = try? JSONEncoder().encode(profile) {
                UserDefaults.standard.set(encoded, forKey: "whoop_profile")
            }
            AppLogger.info("[WHOOP] Loaded profile: \(profile.firstName ?? "") \(profile.lastName ?? "")", category: .health)
        } catch {
            AppLogger.error("[WHOOP] Profile error: \(error)", category: .health)
        }
    }

    func fetchBodyMeasurements() async {
        do {
            let body: WhoopBodyMeasurement = try await apiRequest("/v2/user/measurement/body")
            bodyMeasurements = body
            AppLogger.debug("[WHOOP] Body: \(body.weightKilogram ?? 0)kg, \(body.heightMeter ?? 0)m", category: .health)
        } catch {
            AppLogger.debug("[WHOOP] Body measurement not available (optional endpoint)", category: .health)
        }
    }

    // MARK: - Recovery

    func fetchRecovery(daysBack: Int = 7) async {
        do {
            let start = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date())
            let result: WhoopPaginatedResponse<WhoopRecoveryRecord> = try await apiRequest("/v2/recovery", queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "limit", value: "25")
            ])
            recentRecoveries = result.records

            if let latest = result.records.first, latest.scoreState == "SCORED",
               let score = latest.score {
                todayRecovery = score
                if let encoded = try? JSONEncoder().encode(score) {
                    UserDefaults.standard.set(encoded, forKey: "whoop_today_recovery")
                }
            }
            AppLogger.info("[WHOOP] Synced \(result.records.count) recovery records", category: .health)
        } catch let error as WhoopError where error.isConnectionError {
            AppLogger.debug("[WHOOP] Recovery skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[WHOOP] Recovery error: \(error)", category: .health)
            setSyncError(error)
        }
    }

    // MARK: - Cycles (Strain)

    func fetchCycles(daysBack: Int = 7) async {
        do {
            let start = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date())
            let result: WhoopPaginatedResponse<WhoopCycleRecord> = try await apiRequest("/v2/cycle", queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "limit", value: "25")
            ])
            recentCycles = result.records

            if let latest = result.records.first, latest.scoreState == "SCORED",
               let score = latest.score {
                todayStrain = score
                if let encoded = try? JSONEncoder().encode(score) {
                    UserDefaults.standard.set(encoded, forKey: "whoop_today_strain")
                }
            }
            AppLogger.info("[WHOOP] Synced \(result.records.count) cycle records", category: .health)
        } catch let error as WhoopError where error.isConnectionError {
            AppLogger.debug("[WHOOP] Cycles skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[WHOOP] Cycles error: \(error)", category: .health)
            setSyncError(error)
        }
    }

    // MARK: - Sleep

    func fetchSleep(daysBack: Int = 7) async {
        do {
            let start = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date())
            let result: WhoopPaginatedResponse<WhoopSleepRecord> = try await apiRequest("/v2/activity/sleep", queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "limit", value: "25")
            ])
            recentSleeps = result.records

            if let latest = result.records.first(where: { !$0.nap && $0.scoreState == "SCORED" }),
               let score = latest.score {
                lastSleep = score
            }
            AppLogger.info("[WHOOP] Synced \(result.records.count) sleep records", category: .health)
        } catch let error as WhoopError where error.isConnectionError {
            AppLogger.debug("[WHOOP] Sleep skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[WHOOP] Sleep error: \(error)", category: .health)
            setSyncError(error)
        }
    }

    // MARK: - Workouts

    func fetchWorkouts(daysBack: Int = 30) async {
        do {
            let start = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date())
            let result: WhoopPaginatedResponse<WhoopWorkoutRecord> = try await apiRequest("/v2/activity/workout", queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "limit", value: "25")
            ])
            recentWorkouts = result.records
            AppLogger.info("[WHOOP] Synced \(result.records.count) workout records", category: .health)
        } catch let error as WhoopError where error.isConnectionError {
            AppLogger.debug("[WHOOP] Workouts skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[WHOOP] Workouts error: \(error)", category: .health)
            setSyncError(error)
        }
    }

    // MARK: - Full Sync

    func syncAllData(force: Bool = false) async {
        guard isConnected else { return }

        if !force {
            if isSyncing {
                AppLogger.debug("[WHOOP] Skipping sync - already in progress", category: .health)
                return
            }
            if let lastSync = lastSyncDate,
               Date().timeIntervalSince(lastSync) < Self.syncThrottleInterval {
                AppLogger.debug("[WHOOP] Skipping sync - throttled", category: .health)
                return
            }
        }

        isSyncing = true
        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchRecovery(daysBack: 7) }
            group.addTask { await self.fetchCycles(daysBack: 7) }
            group.addTask { await self.fetchSleep(daysBack: 7) }
            group.addTask { await self.fetchWorkouts(daysBack: 30) }
            group.addTask { await self.fetchBodyMeasurements() }
        }

        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "whoop_last_sync")

        isLoading = false
        isSyncing = false
        AppLogger.info("[WHOOP] Full sync complete", category: .health)
    }

    // MARK: - Disconnect

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        userProfile = nil
        bodyMeasurements = nil
        todayRecovery = nil
        todayStrain = nil
        lastSleep = nil
        recentRecoveries = []
        recentCycles = []
        recentSleeps = []
        recentWorkouts = []
        lastSyncDate = nil
        isConnected = false

        for key in ["whoop_profile", "whoop_last_sync", "whoop_today_recovery", "whoop_today_strain"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        Task {
            await SupabaseManager.shared.updateIntegrationStatus(integration: "whoop", isConnected: false)
        }

        AppLogger.debug("[WHOOP] Disconnected", category: .health)
    }

    // MARK: - Recovery Level

    enum RecoveryLevel: String {
        case green, yellow, red, unknown

        init(score: Int) {
            switch score {
            case 67...100: self = .green
            case 34...66: self = .yellow
            case 0...33: self = .red
            default: self = .unknown
            }
        }

        var color: Color {
            switch self {
            case .green: return .green
            case .yellow: return .yellow
            case .red: return .red
            case .unknown: return .gray
            }
        }

        var label: String {
            switch self {
            case .green: return "Peak"
            case .yellow: return "Moderate"
            case .red: return "Recovery"
            case .unknown: return "No Data"
            }
        }
    }

    var currentRecoveryLevel: RecoveryLevel {
        guard let score = todayRecovery?.recoveryScore else { return .unknown }
        return RecoveryLevel(score: score)
    }
}

// MARK: - Error Types

enum WhoopError: LocalizedError {
    case invalidCallback
    case authorizationDenied(String)
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notConnected
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCallback: return "Invalid callback from WHOOP"
        case .authorizationDenied(let reason): return "Authorization denied: \(reason)"
        case .tokenExchangeFailed: return "Failed to exchange authorization code"
        case .tokenRefreshFailed: return "Failed to refresh access token. Please reconnect."
        case .notConnected: return "Not connected to WHOOP"
        case .apiError(let message): return message
        }
    }

    var isConnectionError: Bool {
        switch self {
        case .notConnected, .tokenRefreshFailed: return true
        default: return false
        }
    }
}

// MARK: - Token Response

struct WhoopTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

// MARK: - Paginated Response

struct WhoopPaginatedResponse<T: Codable>: Codable where T: Codable {
    let records: [T]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

// MARK: - Profile & Body

struct WhoopProfile: Codable {
    let userId: Int?
    let email: String?
    let firstName: String?
    let lastName: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case firstName = "first_name"
        case lastName = "last_name"
    }

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

struct WhoopBodyMeasurement: Codable {
    let heightMeter: Double?
    let weightKilogram: Double?
    let maxHeartRate: Int?

    enum CodingKeys: String, CodingKey {
        case heightMeter = "height_meter"
        case weightKilogram = "weight_kilogram"
        case maxHeartRate = "max_heart_rate"
    }
}

// MARK: - Recovery

struct WhoopRecoveryRecord: Codable, Identifiable {
    let cycleId: Int64
    let sleepId: String?
    let userId: Int?
    let createdAt: String?
    let updatedAt: String?
    let scoreState: String
    let score: WhoopRecoveryScore?

    var id: Int64 { cycleId }

    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case sleepId = "sleep_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case scoreState = "score_state"
        case score
    }
}

struct WhoopRecoveryScore: Codable {
    let userCalibrating: Bool?
    let recoveryScore: Int?
    let restingHeartRate: Int?
    let hrvRmssdMilli: Double?
    let spo2Percentage: Double?
    let skinTempCelsius: Double?

    enum CodingKeys: String, CodingKey {
        case userCalibrating = "user_calibrating"
        case recoveryScore = "recovery_score"
        case restingHeartRate = "resting_heart_rate"
        case hrvRmssdMilli = "hrv_rmssd_milli"
        case spo2Percentage = "spo2_percentage"
        case skinTempCelsius = "skin_temp_celsius"
    }
}

// MARK: - Cycles (Strain)

struct WhoopCycleRecord: Codable, Identifiable {
    let id: Int64
    let userId: Int?
    let createdAt: String?
    let updatedAt: String?
    let start: String?
    let end: String?
    let timezoneOffset: String?
    let scoreState: String
    let score: WhoopCycleScore?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case scoreState = "score_state"
        case score
    }
}

struct WhoopCycleScore: Codable {
    let strain: Double?
    let kilojoule: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?

    enum CodingKeys: String, CodingKey {
        case strain
        case kilojoule
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
    }
}

// MARK: - Sleep

struct WhoopSleepRecord: Codable, Identifiable {
    let id: String
    let cycleId: Int64?
    let userId: Int?
    let createdAt: String?
    let updatedAt: String?
    let start: String?
    let end: String?
    let timezoneOffset: String?
    let nap: Bool
    let scoreState: String
    let score: WhoopSleepScore?

    enum CodingKeys: String, CodingKey {
        case id
        case cycleId = "cycle_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case nap
        case scoreState = "score_state"
        case score
    }
}

struct WhoopSleepScore: Codable {
    let stageSummary: WhoopSleepStageSummary?
    let sleepNeeded: WhoopSleepNeeded?
    let respiratoryRate: Double?
    let sleepPerformancePercentage: Double?
    let sleepConsistencyPercentage: Double?
    let sleepEfficiencyPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case stageSummary = "stage_summary"
        case sleepNeeded = "sleep_needed"
        case respiratoryRate = "respiratory_rate"
        case sleepPerformancePercentage = "sleep_performance_percentage"
        case sleepConsistencyPercentage = "sleep_consistency_percentage"
        case sleepEfficiencyPercentage = "sleep_efficiency_percentage"
    }
}

struct WhoopSleepStageSummary: Codable {
    let totalInBedTimeMilli: Int?
    let totalAwakeTimeMilli: Int?
    let totalNoDataTimeMilli: Int?
    let totalLightSleepTimeMilli: Int?
    let totalSlowWaveSleepTimeMilli: Int?
    let totalRemSleepTimeMilli: Int?
    let sleepCycleCount: Int?
    let disturbanceCount: Int?

    enum CodingKeys: String, CodingKey {
        case totalInBedTimeMilli = "total_in_bed_time_milli"
        case totalAwakeTimeMilli = "total_awake_time_milli"
        case totalNoDataTimeMilli = "total_no_data_time_milli"
        case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
        case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
        case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
        case sleepCycleCount = "sleep_cycle_count"
        case disturbanceCount = "disturbance_count"
    }
}

struct WhoopSleepNeeded: Codable {
    let baselineMilli: Int?
    let needFromSleepDebtMilli: Int?
    let needFromRecentStrainMilli: Int?
    let needFromRecentNapMilli: Int?

    enum CodingKeys: String, CodingKey {
        case baselineMilli = "baseline_milli"
        case needFromSleepDebtMilli = "need_from_sleep_debt_milli"
        case needFromRecentStrainMilli = "need_from_recent_strain_milli"
        case needFromRecentNapMilli = "need_from_recent_nap_milli"
    }
}

// MARK: - Workouts

struct WhoopWorkoutRecord: Codable, Identifiable {
    let id: String
    let userId: Int?
    let createdAt: String?
    let updatedAt: String?
    let start: String?
    let end: String?
    let timezoneOffset: String?
    let sportName: String?
    let sportId: Int?
    let scoreState: String
    let score: WhoopWorkoutScore?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case sportName = "sport_name"
        case sportId = "sport_id"
        case scoreState = "score_state"
        case score
    }
}

struct WhoopWorkoutScore: Codable {
    let strain: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let kilojoule: Double?
    let percentRecorded: Double?
    let distanceMeter: Double?
    let altitudeGainMeter: Double?
    let altitudeChangeMeter: Double?
    let zoneDurations: WhoopZoneDurations?

    enum CodingKeys: String, CodingKey {
        case strain
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case kilojoule
        case percentRecorded = "percent_recorded"
        case distanceMeter = "distance_meter"
        case altitudeGainMeter = "altitude_gain_meter"
        case altitudeChangeMeter = "altitude_change_meter"
        case zoneDurations = "zone_durations"
    }
}

struct WhoopZoneDurations: Codable {
    let zoneZeroMilli: Int?
    let zoneOneMilli: Int?
    let zoneTwoMilli: Int?
    let zoneThreeMilli: Int?
    let zoneFourMilli: Int?
    let zoneFiveMilli: Int?

    enum CodingKeys: String, CodingKey {
        case zoneZeroMilli = "zone_zero_milli"
        case zoneOneMilli = "zone_one_milli"
        case zoneTwoMilli = "zone_two_milli"
        case zoneThreeMilli = "zone_three_milli"
        case zoneFourMilli = "zone_four_milli"
        case zoneFiveMilli = "zone_five_milli"
    }
}
