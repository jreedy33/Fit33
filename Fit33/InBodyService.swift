//
//  InBodyService.swift
//  Fit33
//
//  Service for InBody body composition data integration
//  Uses InBody OAuth API: https://inbody.com/en/data
//

import Foundation
import SwiftUI
import Combine

// MARK: - InBody Service

/// Manages InBody OAuth connection and body composition data sync
class InBodyService: ObservableObject {
    static let shared = InBodyService()
    
    // MARK: - Configuration (Using centralized AppConfig)
    // Contact InBody for API credentials: https://inbody.com/en/data
    // Choose "OAuth API" for home-use InBody integration
    private let clientId = AppConfig.InBody.clientId
    private let clientSecret = AppConfig.InBody.clientSecret
    private let redirectUri = AppConfig.InBody.redirectUri
    private let baseURL = "https://api.inbody.com"  // InBody Cloud API
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    @Published var connectionError: String?
    @Published var latestScan: BodyCompositionScan?
    @Published var scanHistory: [BodyCompositionScan] = []
    @Published var userProfile: InBodyUserProfile?
    
    // MARK: - Private Properties
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private let supabase = SupabaseManager.shared
    
    // MARK: - Init
    
    private init() {
        loadConnectionState()
    }
    
    // MARK: - OAuth Flow
    
    /// Check if InBody integration is properly configured (not using placeholder credentials)
    var isConfigured: Bool {
        clientId != "YOUR_INBODY_CLIENT_ID" && clientSecret != "YOUR_INBODY_CLIENT_SECRET"
    }
    
    /// Get the authorization URL to start OAuth flow
    func getAuthorizationURL() -> URL? {
        // Guard against using placeholder credentials
        guard isConfigured else {
            print("⚠️ [InBody] Cannot start OAuth — using placeholder credentials. Set real credentials in AppConfig.swift")
            connectionError = "InBody integration not configured"
            return nil
        }
        var components = URLComponents(string: "\(baseURL)/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read_measurements read_profile")
        ]
        return components?.url
    }
    
    /// Handle OAuth callback with authorization code
    func handleCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw InBodyError.invalidCallback
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            // Exchange code for tokens
            let tokens = try await exchangeCodeForTokens(code: code)
            
            // Save tokens
            accessToken = tokens.accessToken
            refreshToken = tokens.refreshToken
            tokenExpiresAt = tokens.expiresAt
            
            // Fetch user profile
            try await fetchUserProfile()
            
            // Save connection to database
            try await saveConnection()
            
            // Initial sync
            try await syncMeasurements()
            
            await MainActor.run {
                self.isConnected = true
                self.isLoading = false
                self.connectionError = nil
            }
            
            // Update integration status in database
            await SupabaseManager.shared.updateIntegrationStatus(integration: "inbody", isConnected: true)
            
            print("✅ [INBODY] Successfully connected and synced")
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.connectionError = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Exchange authorization code for access/refresh tokens
    private func exchangeCodeForTokens(code: String) async throws -> TokenResponse {
        guard let tokenURL = URL(string: "\(baseURL)/oauth/token") else {
            throw InBodyError.authenticationFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectUri
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw InBodyError.authenticationFailed
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }
    
    /// Refresh expired access token
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw InBodyError.noRefreshToken
        }
        
        guard let tokenURL = URL(string: "\(baseURL)/oauth/token") else {
            throw InBodyError.tokenRefreshFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Refresh failed, user needs to re-authenticate
            await MainActor.run { self.isConnected = false }
            throw InBodyError.tokenRefreshFailed
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokens = try decoder.decode(TokenResponse.self, from: data)
        
        accessToken = tokens.accessToken
        self.refreshToken = tokens.refreshToken ?? refreshToken
        tokenExpiresAt = tokens.expiresAt
        
        try await saveConnection()
    }
    
    // MARK: - Data Fetching
    
    /// Fetch user profile from InBody
    private func fetchUserProfile() async throws {
        let data = try await makeAuthenticatedRequest(endpoint: "/v1/user/profile")
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        userProfile = try decoder.decode(InBodyUserProfile.self, from: data)
    }
    
    /// Sync body composition measurements from InBody
    func syncMeasurements() async throws {
        await MainActor.run { isLoading = true }
        
        do {
            // Fetch measurements from InBody API
            // Default: last 30 days of measurements
            guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
                throw InBodyError.networkError
            }
            let fromDate = ISO8601DateFormatter().string(from: thirtyDaysAgo)
            
            let data = try await makeAuthenticatedRequest(
                endpoint: "/v1/measurements",
                queryItems: [URLQueryItem(name: "from", value: fromDate)]
            )
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(MeasurementsResponse.self, from: data)
            
            // Convert to our format and save
            for measurement in response.measurements {
                let scan = BodyCompositionScan(from: measurement)
                try await saveScanToDatabase(scan)
            }
            
            // Update local state
            await MainActor.run {
                self.scanHistory = response.measurements.map { BodyCompositionScan(from: $0) }
                self.latestScan = self.scanHistory.first
                self.lastSyncDate = Date()
                self.isLoading = false
            }
            
            // Save last sync time
            UserDefaults.standard.set(Date(), forKey: "inbody_last_sync")
            
            print("✅ [INBODY] Synced \(response.measurements.count) measurements")
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.connectionError = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Make authenticated request to InBody API
    private func makeAuthenticatedRequest(
        endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        // Check if token needs refresh
        if let expiresAt = tokenExpiresAt, expiresAt < Date() {
            try await refreshAccessToken()
        }
        
        guard let accessToken = accessToken else {
            throw InBodyError.notAuthenticated
        }
        
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else {
            throw InBodyError.networkError
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        guard let url = components.url else {
            throw InBodyError.networkError
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InBodyError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            // Token expired, try refresh
            try await refreshAccessToken()
            return try await makeAuthenticatedRequest(endpoint: endpoint, queryItems: queryItems)
        default:
            throw InBodyError.apiError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Database Operations
    
    /// Get the current user ID
    private var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }
    
    /// Save connection info to Supabase
    private func saveConnection() async throws {
        guard let userId = currentUserId,
              let accessToken = accessToken else { return }
        
        struct InBodyConnectionUpsert: Encodable {
            let user_id: String
            let access_token: String
            let refresh_token: String?
            let token_expires_at: String?
            let inbody_user_id: String?
            let inbody_email: String?
            let is_active: Bool
            let updated_at: String
        }
        
        let connection = InBodyConnectionUpsert(
            user_id: userId,
            access_token: accessToken,
            refresh_token: refreshToken,
            token_expires_at: tokenExpiresAt?.ISO8601Format(),
            inbody_user_id: userProfile?.id,
            inbody_email: userProfile?.email,
            is_active: true,
            updated_at: Date().ISO8601Format()
        )
        
        // Upsert connection
        try await supabase.supabaseClient
            .from("inbody_connections")
            .upsert(connection, onConflict: "user_id")
            .execute()
    }
    
    /// Save body composition scan to database
    private func saveScanToDatabase(_ scan: BodyCompositionScan) async throws {
        guard let userId = currentUserId else { return }
        
        struct BodyCompositionInsert: Encodable {
            let user_id: String
            let weight_kg: Double
            let weight_lbs: Double
            let body_fat_percentage: Double?
            let body_fat_mass_kg: Double?
            let skeletal_muscle_mass_kg: Double?
            let lean_body_mass_kg: Double?
            let body_water_kg: Double?
            let bmi: Double?
            let bmr: Double?
            let visceral_fat_level: Int?
            let inbody_score: Int?
            let source: String
            let device_model: String?
            let measured_at: String
        }
        
        let log = BodyCompositionInsert(
            user_id: userId,
            weight_kg: scan.weightKg,
            weight_lbs: scan.weightLbs,
            body_fat_percentage: scan.bodyFatPercentage,
            body_fat_mass_kg: scan.bodyFatMassKg,
            skeletal_muscle_mass_kg: scan.skeletalMuscleMassKg,
            lean_body_mass_kg: scan.leanBodyMassKg,
            body_water_kg: scan.bodyWaterKg,
            bmi: scan.bmi,
            bmr: scan.bmr,
            visceral_fat_level: scan.visceralFatLevel,
            inbody_score: scan.inbodyScore,
            source: "inbody",
            device_model: scan.deviceModel,
            measured_at: scan.measuredAt.ISO8601Format()
        )
        
        try await supabase.supabaseClient
            .from("body_composition_logs")
            .insert(log)
            .execute()
    }
    
    /// Load saved connection state
    private func loadConnectionState() {
        Task {
            guard let userId = currentUserId else { return }
            
            do {
                let response = try await supabase.supabaseClient
                    .from("inbody_connections")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("is_active", value: true)
                    .single()
                    .execute()
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let connection = try decoder.decode(InBodyConnection.self, from: response.data)
                
                await MainActor.run {
                    self.accessToken = connection.accessToken
                    self.refreshToken = connection.refreshToken
                    self.tokenExpiresAt = connection.tokenExpiresAt
                    self.lastSyncDate = connection.lastSyncAt
                    self.isConnected = true
                }
                
                // Load recent scans
                try await loadRecentScans()
                
            } catch {
                print("ℹ️ [INBODY] No active connection found")
            }
        }
    }
    
    /// Load recent scans from database
    private func loadRecentScans() async throws {
        guard let userId = currentUserId else { return }
        
        let response = try await supabase.supabaseClient
            .from("body_composition_logs")
            .select()
            .eq("user_id", value: userId)
            .order("measured_at", ascending: false)
            .limit(30)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let scans = try decoder.decode([BodyCompositionScan].self, from: response.data)
        
        await MainActor.run {
            self.scanHistory = scans
            self.latestScan = scans.first
        }
    }
    
    // MARK: - Disconnect
    
    /// Disconnect InBody account
    func disconnect() {
        Task {
            guard let userId = currentUserId else { return }
            
            struct DisconnectUpdate: Encodable {
                let is_active: Bool
            }
            
            // Mark connection as inactive
            try? await supabase.supabaseClient
                .from("inbody_connections")
                .update(DisconnectUpdate(is_active: false))
                .eq("user_id", value: userId)
                .execute()
            
            await MainActor.run {
                self.accessToken = nil
                self.refreshToken = nil
                self.tokenExpiresAt = nil
                self.isConnected = false
                self.userProfile = nil
                self.latestScan = nil
                self.scanHistory = []
            }
            
            // Update integration status in database
            await SupabaseManager.shared.updateIntegrationStatus(integration: "inbody", isConnected: false)
            
            print("✅ [INBODY] Disconnected")
        }
    }
}

// MARK: - Data Models

struct BodyCompositionScan: Codable, Identifiable {
    let id: UUID
    let weightKg: Double
    let weightLbs: Double
    let bodyFatPercentage: Double?
    let bodyFatMassKg: Double?
    let skeletalMuscleMassKg: Double?
    let leanBodyMassKg: Double?
    let bodyWaterKg: Double?
    let bmi: Double?
    let bmr: Double?
    let visceralFatLevel: Int?
    let inbodyScore: Int?
    let deviceModel: String?
    let measuredAt: Date
    let rawData: String?
    
    init(from measurement: InBodyMeasurement) {
        self.id = UUID()
        self.weightKg = measurement.weight
        self.weightLbs = measurement.weight * 2.20462
        self.bodyFatPercentage = measurement.bodyFatPercentage
        self.bodyFatMassKg = measurement.bodyFatMass
        self.skeletalMuscleMassKg = measurement.skeletalMuscleMass
        self.leanBodyMassKg = measurement.leanBodyMass
        self.bodyWaterKg = measurement.totalBodyWater
        self.bmi = measurement.bmi
        self.bmr = measurement.bmr
        self.visceralFatLevel = measurement.visceralFatLevel
        self.inbodyScore = measurement.inbodyScore
        self.deviceModel = measurement.deviceModel
        self.measuredAt = measurement.measuredAt
        self.rawData = nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case weightKg = "weight_kg"
        case weightLbs = "weight_lbs"
        case bodyFatPercentage = "body_fat_percentage"
        case bodyFatMassKg = "body_fat_mass_kg"
        case skeletalMuscleMassKg = "skeletal_muscle_mass_kg"
        case leanBodyMassKg = "lean_body_mass_kg"
        case bodyWaterKg = "body_water_kg"
        case bmi
        case bmr
        case visceralFatLevel = "visceral_fat_level"
        case inbodyScore = "inbody_score"
        case deviceModel = "device_model"
        case measuredAt = "measured_at"
        case rawData = "raw_data"
    }
}

struct InBodyMeasurement: Codable {
    let weight: Double
    let bodyFatPercentage: Double?
    let bodyFatMass: Double?
    let skeletalMuscleMass: Double?
    let leanBodyMass: Double?
    let totalBodyWater: Double?
    let bmi: Double?
    let bmr: Double?
    let visceralFatLevel: Int?
    let inbodyScore: Int?
    let deviceModel: String?
    let measuredAt: Date
}

struct MeasurementsResponse: Codable {
    let measurements: [InBodyMeasurement]
}

struct InBodyUserProfile: Codable {
    let id: String
    let email: String?
    let name: String?
}

struct InBodyConnection: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenExpiresAt: Date?
    let lastSyncAt: Date?
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    
    var expiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

// MARK: - Errors

enum InBodyError: LocalizedError {
    case invalidCallback
    case authenticationFailed
    case noRefreshToken
    case tokenRefreshFailed
    case notAuthenticated
    case networkError
    case apiError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid authorization callback"
        case .authenticationFailed:
            return "Failed to authenticate with InBody"
        case .noRefreshToken:
            return "No refresh token available"
        case .tokenRefreshFailed:
            return "Failed to refresh access token. Please reconnect."
        case .notAuthenticated:
            return "Not authenticated with InBody"
        case .networkError:
            return "Network error occurred"
        case .apiError(let statusCode):
            return "InBody API error (status: \(statusCode))"
        }
    }
}

// MARK: - Extensions for Goal Integration

extension InBodyService {
    
    /// Get personalized insights based on body composition
    func getBodyCompositionInsights() -> [String] {
        guard let scan = latestScan else { return [] }
        
        var insights: [String] = []
        
        // Body fat insights
        if let bf = scan.bodyFatPercentage {
            if bf < 10 {
                insights.append("⚠️ Very low body fat. Consider maintenance calories.")
            } else if bf < 15 {
                insights.append("💪 Athletic body fat range. Great for performance!")
            } else if bf < 20 {
                insights.append("✅ Healthy body fat range. Keep it up!")
            } else if bf < 25 {
                insights.append("📈 Good progress potential for body recomposition")
            } else {
                insights.append("🎯 Focus on fat loss while preserving muscle")
            }
        }
        
        // Muscle mass insights
        if let smm = scan.skeletalMuscleMassKg, let weight = Optional(scan.weightKg) {
            let musclePercentage = (smm / weight) * 100
            if musclePercentage > 45 {
                insights.append("💪 Excellent muscle mass ratio!")
            } else if musclePercentage > 40 {
                insights.append("✅ Good muscle development")
            } else {
                insights.append("📈 Room for muscle growth - focus on progressive overload")
            }
        }
        
        // Visceral fat
        if let vf = scan.visceralFatLevel {
            if vf <= 9 {
                insights.append("✅ Healthy visceral fat level")
            } else if vf <= 14 {
                insights.append("⚠️ Elevated visceral fat - prioritize cardio and nutrition")
            } else {
                insights.append("🚨 High visceral fat - consult a healthcare provider")
            }
        }
        
        return insights
    }
    
    /// Get recommended fitness goal based on body composition
    func getRecommendedGoal() -> String {
        guard let scan = latestScan,
              let bf = scan.bodyFatPercentage,
              let smm = scan.skeletalMuscleMassKg else {
            return "Build Muscle" // Default
        }
        
        let muscleRatio = smm / scan.weightKg * 100
        
        // Decision matrix
        if bf > 25 {
            return "Get Lean"  // High BF → prioritize fat loss
        } else if bf < 12 && muscleRatio < 40 {
            return "Build Muscle"  // Low BF but also low muscle
        } else if bf >= 15 && bf <= 20 && muscleRatio >= 40 {
            return "Get Stronger"  // Good composition → focus on performance
        } else if bf > 20 && muscleRatio >= 38 {
            return "Get Lean"  // Has muscle, needs to cut
        } else {
            return "Build Muscle"  // Default to muscle building
        }
    }
    
    /// Calculate accurate TDEE using InBody BMR
    func calculateTDEE(activityLevel: String) -> Int? {
        guard let bmr = latestScan?.bmr else { return nil }
        
        let multiplier: Double
        switch activityLevel.lowercased() {
        case "sedentary":
            multiplier = 1.2
        case "light":
            multiplier = 1.375
        case "moderate":
            multiplier = 1.55
        case "active":
            multiplier = 1.725
        case "very active":
            multiplier = 1.9
        default:
            multiplier = 1.55
        }
        
        return Int(bmr * multiplier)
    }
}
