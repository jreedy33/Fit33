//
//  OuraService.swift
//  Fit33
//
//  Oura Ring API Integration — Syncs readiness, activity, sleep, SpO2, and workouts
//

import Foundation
import AuthenticationServices
import SwiftUI

@MainActor
final class OuraService: ObservableObject {
    static let shared = OuraService()

    private struct Config {
        static let clientId = AppConfig.Oura.clientId
        static let clientSecret = AppConfig.Oura.clientSecret
        static let redirectUri = AppConfig.Oura.redirectUri
        static let authorizationUrl = AppConfig.Oura.authorizationUrl
        static let tokenUrl = AppConfig.Oura.tokenUrl
        static let apiBaseUrl = AppConfig.Oura.apiBaseUrl
        static let scopes = AppConfig.Oura.scopes
    }

    // MARK: - Published Properties

    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?

    @Published var todayReadiness: OuraReadinessRecord?
    @Published var todayActivity: OuraActivityRecord?
    @Published var lastSleep: OuraSleepRecord?
    @Published var todaySpo2: OuraSpo2Record?
    @Published var personalInfo: OuraPersonalInfo?

    @Published var recentReadiness: [OuraReadinessRecord] = []
    @Published var recentActivity: [OuraActivityRecord] = []
    @Published var recentSleeps: [OuraSleepRecord] = []
    @Published var recentWorkouts: [OuraWorkoutRecord] = []

    // MARK: - Token Storage (Keychain)

    private var accessToken: String? {
        get { KeychainHelper.load(key: "oura_access_token") }
        set {
            if let val = newValue { KeychainHelper.save(key: "oura_access_token", value: val) }
            else { KeychainHelper.delete(key: "oura_access_token") }
        }
    }

    private var refreshToken: String? {
        get { KeychainHelper.load(key: "oura_refresh_token") }
        set {
            if let val = newValue { KeychainHelper.save(key: "oura_refresh_token", value: val) }
            else { KeychainHelper.delete(key: "oura_refresh_token") }
        }
    }

    private var tokenExpiresAt: Date? {
        get {
            guard let str = KeychainHelper.load(key: "oura_token_expires_at"),
                  let timestamp = Double(str), timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let ts = newValue?.timeIntervalSince1970 {
                KeychainHelper.save(key: "oura_token_expires_at", value: String(ts))
            } else {
                KeychainHelper.delete(key: "oura_token_expires_at")
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
            loadCachedDataIfNeeded()
        }
    }

    /// Re-reads keychain to recompute `isConnected`. Mirrors
    /// `WhoopService.refreshConnectionState()` — see that doc comment for the
    /// `BGTask`-wake / locked-device race this guards against. Called from
    /// `Fit33App.onChange(scenePhase: .active)` so the dashboard Oura widget
    /// reliably appears on every cold start / resume when Oura is connected.
    func refreshConnectionState() {
        let nowConnected = accessToken != nil
        if nowConnected != isConnected {
            AppLogger.info("[OURA] Connection state changed on foreground: \(isConnected) → \(nowConnected)", category: .auth)
            isConnected = nowConnected
        }
        if isConnected {
            loadCachedDataIfNeeded()
        }
    }

    /// Hydrates published cache properties from `UserDefaults` — only fills in
    /// values that are still nil so fresh API data isn't overwritten.
    private func loadCachedDataIfNeeded() {
        if personalInfo == nil,
           let data = UserDefaults.standard.data(forKey: "oura_profile"),
           let profile = try? JSONDecoder().decode(OuraPersonalInfo.self, from: data) {
            personalInfo = profile
        }
        if todayReadiness == nil,
           let data = UserDefaults.standard.data(forKey: "oura_today_readiness"),
           let readiness = try? JSONDecoder().decode(OuraReadinessRecord.self, from: data) {
            todayReadiness = readiness
        }
        if todayActivity == nil,
           let data = UserDefaults.standard.data(forKey: "oura_today_activity"),
           let activity = try? JSONDecoder().decode(OuraActivityRecord.self, from: data) {
            todayActivity = activity
        }
        if lastSyncDate == nil,
           let date = UserDefaults.standard.object(forKey: "oura_last_sync") as? Date {
            lastSyncDate = date
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
        AppLogger.info("[OURA] Received callback URL: \(url.absoluteString.prefix(80))...", category: .auth)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OuraError.invalidCallback
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let desc = components.queryItems?.first(where: { $0.name == "error_description" })?.value
            AppLogger.error("[OURA] OAuth error: \(error) — \(desc ?? "no description")", category: .auth)
            throw OuraError.authorizationDenied(desc ?? error)
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            AppLogger.error("[OURA] No 'code' parameter in callback. Params: \(components.queryItems?.map(\.name) ?? [])", category: .auth)
            throw OuraError.invalidCallback
        }

        AppLogger.info("[OURA] Got authorization code, exchanging for tokens...", category: .auth)
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
            throw OuraError.tokenExchangeFailed
        }

        guard let tokenURL = URL(string: Config.tokenUrl) else {
            throw OuraError.tokenExchangeFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OuraError.tokenExchangeFailed
        }

        AppLogger.info("[OURA] Token exchange response: HTTP \(httpResponse.statusCode)", category: .auth)

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                AppLogger.error("[OURA] Token exchange error (HTTP \(httpResponse.statusCode)): \(errorBody)", category: .auth)
            }
            throw OuraError.tokenExchangeFailed
        }

        let tokenResponse: OuraTokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(OuraTokenResponse.self, from: data)
        } catch {
            if let body = String(data: data, encoding: .utf8) {
                AppLogger.error("[OURA] Token decode failed. Body: \(body.prefix(500))", category: .auth)
            }
            throw OuraError.tokenExchangeFailed
        }

        accessToken = tokenResponse.accessToken
        if let rt = tokenResponse.refreshToken {
            refreshToken = rt
        }
        tokenExpiresAt = Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 86400))
        isConnected = true

        AppLogger.info("[OURA] Connected successfully (token expires in \(tokenResponse.expiresIn ?? 86400)s)", category: .health)

        Task {
            await SupabaseManager.shared.updateIntegrationStatus(integration: "oura", isConnected: true)
        }

        // Remove any HealthKit-imported Oura rows so the Oura OAuth feed
        // is the single source of truth for this user going forward.
        await HealthDataService.shared.removeHealthKitDuplicates(for: .oura)

        await fetchPersonalInfo()
        await syncAllData()
    }

    private func refreshAccessToken() async throws {
        guard let currentRefreshToken = refreshToken else {
            // Don't auto-disconnect on a nil refresh token. See the matching
            // doc comment in `WhoopService.refreshAccessToken` — the typical
            // cause is a locked keychain during a BGTask wake, not an actual
            // missing token. Wiping cached state on every transient nil read
            // is what made users find Oura "spontaneously disconnected" after
            // routine TestFlight / App Store updates. Throw and let the
            // caller decide whether to surface the reconnect prompt.
            AppLogger.warning("[OURA] refreshAccessToken: no stored refresh token (keychain locked?) — throwing, NOT disconnecting", category: .auth)
            throw OuraError.notConnected
        }

        let bodyParams = [
            "client_id": Config.clientId,
            "client_secret": Config.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": currentRefreshToken
        ]
        let bodyString = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        guard let tokenURL = URL(string: Config.tokenUrl) else {
            throw OuraError.tokenRefreshFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let errorBody = String(data: data, encoding: .utf8) {
                AppLogger.error("[OURA] Token refresh failed (HTTP \(status)): \(errorBody.prefix(300))", category: .auth)
            }
            // Only disconnect on PERMANENT failures (refresh token actually
            // revoked / invalidated). 5xx, 429, and other transient statuses
            // must NOT wipe tokens — the grant is still valid, the API just
            // hiccupped. Previously every 5xx permanently signed users out,
            // which is the root cause behind "I haven't deleted the app,
            // why is Oura disconnected again". Mirror of WhoopService.
            if (400...403).contains(status) {
                AppLogger.error("[OURA] Refresh token rejected (HTTP \(status)) — disconnecting", category: .auth)
                disconnect()
            } else {
                AppLogger.warning("[OURA] Token refresh transient failure (HTTP \(status)) — keeping tokens, will retry", category: .auth)
            }
            throw OuraError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(OuraTokenResponse.self, from: data)

        accessToken = tokenResponse.accessToken
        // CRITICAL: Oura (like WHOOP and most OAuth providers) does not always
        // return a new `refresh_token` on every successful refresh — they rotate
        // on their own schedule. The `refreshToken` setter DELETES the keychain
        // entry when passed nil, so unconditionally writing `tokenResponse.refreshToken`
        // back would wipe our refresh capability any time Oura declined to
        // rotate. The result is a zombie "connected" state where every
        // subsequent API call silently no-op's until the user manually
        // disconnects + reconnects. Only overwrite when the server actually
        // sent a replacement. Mirrors the `exchangeCodeForTokens` defensive
        // pattern already used on the initial-authorization path.
        if let rotated = tokenResponse.refreshToken, !rotated.isEmpty {
            refreshToken = rotated
        }
        tokenExpiresAt = Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 86400))

        AppLogger.debug("[OURA] Token refreshed (expires in \(tokenResponse.expiresIn ?? 86400)s)", category: .health)
    }

    private func ensureValidToken() async throws -> String {
        guard let token = accessToken else {
            throw OuraError.notConnected
        }

        if let expiresAt = tokenExpiresAt, expiresAt.timeIntervalSinceNow < 300 {
            try await refreshAccessToken()
            guard let newToken = accessToken else {
                throw OuraError.tokenRefreshFailed
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

    // MARK: - Generic API Request

    private func apiRequest<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let token = try await ensureValidToken()

        var components = URLComponents(string: "\(Config.apiBaseUrl)\(path)")
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw OuraError.apiError("Invalid URL: \(path)")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OuraError.apiError("No HTTP response")
        }

        if httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            return try await apiRequest(path, queryItems: queryItems)
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OuraError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Personal Info

    func fetchPersonalInfo() async {
        do {
            let info: OuraPersonalInfo = try await apiRequest("/v2/usercollection/personal_info")
            personalInfo = info
            if let encoded = try? JSONEncoder().encode(info) {
                UserDefaults.standard.set(encoded, forKey: "oura_profile")
            }
            AppLogger.info("[OURA] Loaded profile: age \(info.age ?? 0), email \(info.email ?? "n/a")", category: .health)
        } catch {
            AppLogger.error("[OURA] Personal info error: \(error)", category: .health)
        }
    }

    // MARK: - Daily Readiness

    func fetchDailyReadiness(daysBack: Int = 7) async {
        do {
            let startDate = dateString(daysBack: daysBack)
            let endDate = dateString(daysBack: 0)
            let result: OuraPaginatedResponse<OuraReadinessRecord> = try await apiRequest("/v2/usercollection/daily_readiness", queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate)
            ])
            recentReadiness = result.data

            if let latest = result.data.last {
                todayReadiness = latest
                if let encoded = try? JSONEncoder().encode(latest) {
                    UserDefaults.standard.set(encoded, forKey: "oura_today_readiness")
                }
            }
            AppLogger.info("[OURA] Synced \(result.data.count) readiness records", category: .health)
        } catch let error as OuraError where error.isConnectionError {
            AppLogger.debug("[OURA] Readiness skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[OURA] Readiness error: \(error)", category: .health)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Daily Activity

    func fetchDailyActivity(daysBack: Int = 7) async {
        do {
            let startDate = dateString(daysBack: daysBack)
            let endDate = dateString(daysBack: 0)
            let result: OuraPaginatedResponse<OuraActivityRecord> = try await apiRequest("/v2/usercollection/daily_activity", queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate)
            ])
            recentActivity = result.data

            if let latest = result.data.last {
                todayActivity = latest
                if let encoded = try? JSONEncoder().encode(latest) {
                    UserDefaults.standard.set(encoded, forKey: "oura_today_activity")
                }
            }
            AppLogger.info("[OURA] Synced \(result.data.count) activity records", category: .health)
        } catch let error as OuraError where error.isConnectionError {
            AppLogger.debug("[OURA] Activity skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[OURA] Activity error: \(error)", category: .health)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sleep

    func fetchSleep(daysBack: Int = 7) async {
        do {
            let startDate = dateString(daysBack: daysBack)
            let endDate = dateString(daysBack: 0)
            let result: OuraPaginatedResponse<OuraSleepRecord> = try await apiRequest("/v2/usercollection/sleep", queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate)
            ])
            recentSleeps = result.data

            if let latest = result.data.last(where: { $0.type == "long_sleep" }) {
                lastSleep = latest
            }
            AppLogger.info("[OURA] Synced \(result.data.count) sleep records", category: .health)
        } catch let error as OuraError where error.isConnectionError {
            AppLogger.debug("[OURA] Sleep skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[OURA] Sleep error: \(error)", category: .health)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Daily SpO2

    func fetchDailySpo2(daysBack: Int = 7) async {
        do {
            let startDate = dateString(daysBack: daysBack)
            let endDate = dateString(daysBack: 0)
            let result: OuraPaginatedResponse<OuraSpo2Record> = try await apiRequest("/v2/usercollection/daily_spo2", queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate)
            ])
            todaySpo2 = result.data.last
            AppLogger.info("[OURA] Synced \(result.data.count) SpO2 records", category: .health)
        } catch let error as OuraError where error.isConnectionError {
            AppLogger.debug("[OURA] SpO2 skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[OURA] SpO2 error: \(error)", category: .health)
        }
    }

    // MARK: - Workouts

    func fetchWorkouts(daysBack: Int = 30) async {
        do {
            let startDate = dateString(daysBack: daysBack)
            let endDate = dateString(daysBack: 0)
            let result: OuraPaginatedResponse<OuraWorkoutRecord> = try await apiRequest("/v2/usercollection/workout", queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate)
            ])
            recentWorkouts = result.data
            AppLogger.info("[OURA] Synced \(result.data.count) workout records", category: .health)
        } catch let error as OuraError where error.isConnectionError {
            AppLogger.debug("[OURA] Workouts skipped: \(error.localizedDescription ?? "not connected")", category: .health)
        } catch {
            AppLogger.error("[OURA] Workouts error: \(error)", category: .health)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Full Sync

    func syncAllData(force: Bool = false) async {
        guard isConnected else { return }

        if !force {
            if isSyncing {
                AppLogger.debug("[OURA] Skipping sync - already in progress", category: .health)
                return
            }
            if let lastSync = lastSyncDate,
               Date().timeIntervalSince(lastSync) < Self.syncThrottleInterval {
                AppLogger.debug("[OURA] Skipping sync - throttled", category: .health)
                return
            }
        }

        isSyncing = true
        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchDailyReadiness(daysBack: 7) }
            group.addTask { await self.fetchDailyActivity(daysBack: 7) }
            group.addTask { await self.fetchSleep(daysBack: 7) }
            group.addTask { await self.fetchDailySpo2(daysBack: 7) }
            group.addTask { await self.fetchWorkouts(daysBack: 30) }
        }

        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "oura_last_sync")

        isLoading = false
        isSyncing = false
        AppLogger.info("[OURA] Full sync complete", category: .health)
    }

    // MARK: - Disconnect

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        personalInfo = nil
        todayReadiness = nil
        todayActivity = nil
        lastSleep = nil
        todaySpo2 = nil
        recentReadiness = []
        recentActivity = []
        recentSleeps = []
        recentWorkouts = []
        lastSyncDate = nil
        isConnected = false

        for key in ["oura_profile", "oura_last_sync", "oura_today_readiness", "oura_today_activity"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        Task {
            await SupabaseManager.shared.updateIntegrationStatus(integration: "oura", isConnected: false)
        }

        AppLogger.debug("[OURA] Disconnected", category: .health)
    }

    // MARK: - Readiness Level

    enum ReadinessLevel: String {
        case optimal, good, payAttention, unknown

        init(score: Int) {
            switch score {
            case 85...100: self = .optimal
            case 70...84: self = .good
            case 0...69: self = .payAttention
            default: self = .unknown
            }
        }

        var color: Color {
            switch self {
            case .optimal: return .green
            case .good: return .yellow
            case .payAttention: return .red
            case .unknown: return .gray
            }
        }

        var label: String {
            switch self {
            case .optimal: return "Optimal"
            case .good: return "Good"
            case .payAttention: return "Pay Attention"
            case .unknown: return "No Data"
            }
        }
    }

    var currentReadinessLevel: ReadinessLevel {
        guard let score = todayReadiness?.score else { return .unknown }
        return ReadinessLevel(score: score)
    }

    // MARK: - Helpers

    private func dateString(daysBack: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Error Types

enum OuraError: LocalizedError {
    case invalidCallback
    case authorizationDenied(String)
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notConnected
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCallback: return "Invalid callback from Oura"
        case .authorizationDenied(let reason): return "Authorization denied: \(reason)"
        case .tokenExchangeFailed: return "Failed to exchange authorization code"
        case .tokenRefreshFailed: return "Failed to refresh access token. Please reconnect."
        case .notConnected: return "Not connected to Oura"
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

struct OuraTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int?
    let refreshToken: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

// MARK: - Paginated Response (Oura uses "data" key + optional "next_token")

struct OuraPaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextToken = "next_token"
    }
}

// MARK: - Personal Info

struct OuraPersonalInfo: Codable {
    let id: String?
    let age: Int?
    let weight: Double?
    let height: Double?
    let biologicalSex: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id, age, weight, height
        case biologicalSex = "biological_sex"
        case email
    }
}

// MARK: - Daily Readiness

struct OuraReadinessRecord: Codable, Identifiable {
    let id: String?
    let day: String
    let score: Int?
    let temperatureDeviation: Double?
    let temperatureTrendDeviation: Double?
    let contributors: OuraReadinessContributors?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, day, score
        case temperatureDeviation = "temperature_deviation"
        case temperatureTrendDeviation = "temperature_trend_deviation"
        case contributors, timestamp
    }
}

struct OuraReadinessContributors: Codable {
    let activityBalance: Int?
    let bodyTemperature: Int?
    let hrvBalance: Int?
    let previousDayActivity: Int?
    let previousNight: Int?
    let recoveryIndex: Int?
    let restingHeartRate: Int?
    let sleepBalance: Int?
    let sleepRegularity: Int?

    enum CodingKeys: String, CodingKey {
        case activityBalance = "activity_balance"
        case bodyTemperature = "body_temperature"
        case hrvBalance = "hrv_balance"
        case previousDayActivity = "previous_day_activity"
        case previousNight = "previous_night"
        case recoveryIndex = "recovery_index"
        case restingHeartRate = "resting_heart_rate"
        case sleepBalance = "sleep_balance"
        case sleepRegularity = "sleep_regularity"
    }
}

// MARK: - Daily Activity

struct OuraActivityRecord: Codable, Identifiable {
    let id: String?
    let day: String
    let score: Int?
    let activeCalories: Int?
    let steps: Int?
    let totalCalories: Int?
    let equivalentWalkingDistance: Int?
    let highActivityMetMinutes: Int?
    let highActivityTime: Int?
    let lowActivityMetMinutes: Int?
    let lowActivityTime: Int?
    let mediumActivityMetMinutes: Int?
    let mediumActivityTime: Int?
    let restingTime: Int?
    let sedentaryTime: Int?
    let nonWearTime: Int?
    let targetCalories: Int?
    let metersToTarget: Int?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, day, score, steps, timestamp
        case activeCalories = "active_calories"
        case totalCalories = "total_calories"
        case equivalentWalkingDistance = "equivalent_walking_distance"
        case highActivityMetMinutes = "high_activity_met_minutes"
        case highActivityTime = "high_activity_time"
        case lowActivityMetMinutes = "low_activity_met_minutes"
        case lowActivityTime = "low_activity_time"
        case mediumActivityMetMinutes = "medium_activity_met_minutes"
        case mediumActivityTime = "medium_activity_time"
        case restingTime = "resting_time"
        case sedentaryTime = "sedentary_time"
        case nonWearTime = "non_wear_time"
        case targetCalories = "target_calories"
        case metersToTarget = "meters_to_target"
    }
}

// MARK: - Sleep (Detailed)

struct OuraSleepRecord: Codable, Identifiable {
    let id: String?
    let day: String
    let averageBreath: Double?
    let averageHeartRate: Double?
    let averageHrv: Double?
    let awakeTime: Int?
    let bedtimeEnd: String?
    let bedtimeStart: String?
    let deepSleepDuration: Int?
    let efficiency: Int?
    let latency: Int?
    let lightSleepDuration: Int?
    let lowestHeartRate: Int?
    let remSleepDuration: Int?
    let restlessPeriods: Int?
    let timeInBed: Int?
    let totalSleepDuration: Int?
    let type: String?
    let readiness: OuraSleepReadiness?

    enum CodingKeys: String, CodingKey {
        case id, day, efficiency, latency, type, readiness
        case averageBreath = "average_breath"
        case averageHeartRate = "average_heart_rate"
        case averageHrv = "average_hrv"
        case awakeTime = "awake_time"
        case bedtimeEnd = "bedtime_end"
        case bedtimeStart = "bedtime_start"
        case deepSleepDuration = "deep_sleep_duration"
        case lightSleepDuration = "light_sleep_duration"
        case lowestHeartRate = "lowest_heart_rate"
        case remSleepDuration = "rem_sleep_duration"
        case restlessPeriods = "restless_periods"
        case timeInBed = "time_in_bed"
        case totalSleepDuration = "total_sleep_duration"
    }
}

struct OuraSleepReadiness: Codable {
    let score: Int?
    let temperatureDeviation: Double?
    let temperatureTrendDeviation: Double?
    let contributors: OuraReadinessContributors?

    enum CodingKeys: String, CodingKey {
        case score, contributors
        case temperatureDeviation = "temperature_deviation"
        case temperatureTrendDeviation = "temperature_trend_deviation"
    }
}

// MARK: - Daily SpO2

struct OuraSpo2Record: Codable, Identifiable {
    let id: String?
    let day: String
    let spo2Percentage: OuraSpo2Percentage?
    let breathingDisturbanceIndex: Double?

    enum CodingKeys: String, CodingKey {
        case id, day
        case spo2Percentage = "spo2_percentage"
        case breathingDisturbanceIndex = "breathing_disturbance_index"
    }
}

struct OuraSpo2Percentage: Codable {
    let average: Double?
}

// MARK: - Workouts

struct OuraWorkoutRecord: Codable, Identifiable {
    let id: String?
    let activity: String?
    let calories: Double?
    let day: String?
    let distance: Double?
    let endDatetime: String?
    let intensity: String?
    let label: String?
    let source: String?
    let startDatetime: String?

    enum CodingKeys: String, CodingKey {
        case id, activity, calories, day, distance, intensity, label, source
        case endDatetime = "end_datetime"
        case startDatetime = "start_datetime"
    }
}
