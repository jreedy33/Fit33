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
    /// Recent (~4 weeks) / YTD / all-time totals from Strava's `/athletes/{id}/stats`
    /// endpoint. Surfaced on the Strava settings page so users see the same long-form
    /// stats they'd get on strava.com.
    @Published var athleteStats: StravaAthleteStats?

    // MARK: - Sync Throttling (mirrors WhoopService / OuraService)

    /// Same 5-minute throttle window WHOOP and Oura use to coalesce repeated
    /// foreground sync calls (Dashboard tab-switches, scenePhase flicker, etc).
    /// Pass `force: true` to bypass — used by the explicit "Sync Now" button
    /// and by `BackgroundChallengeSyncService` after iOS wakes us.
    private static let syncThrottleInterval: TimeInterval = 300

    /// Coalesces overlapping `syncActivities` invocations so back-to-back
    /// foreground events don't double-fire the API call.
    private var isSyncing = false

    /// Single-flight guard for `refreshAccessToken()`. See DATA_BACKEND_AGENT.md
    /// invariant `4d-singleflight` for full rationale. Strava single-uses
    /// refresh tokens (always rotates), so concurrent refresh callers all
    /// sending the same `refresh_token` would result in the first POST
    /// rotating successfully and every subsequent POST receiving HTTP 400
    /// `invalid_grant` — which the existing code path interprets as a
    /// real revoke and calls `disconnect()`. With ≥2 simultaneous Strava
    /// `apiRequest` calls during a foreground sync (the activities-list
    /// fetch + per-activity detail enrichment + the webhook-triggered
    /// `syncActivities(daysBack: 1)`), the race fires whenever the
    /// access token enters its 5-minute pre-expiry window. Coalesces N
    /// concurrent refreshes into ONE network POST.
    private var refreshTask: Task<Void, Error>?

    /// 60-day inactivity guard — when the user hasn't foregrounded the app
    /// in this long AND token refresh fails, we treat the integration as
    /// abandoned and clear keychain. Until then we keep retrying, so the
    /// "I haven't opened Fit33 in two months" return user doesn't get
    /// silently disconnected from Strava.
    private static let inactivityDisconnectInterval: TimeInterval = 60 * 24 * 60 * 60
    
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
            loadCachedDataIfNeeded()
        }
    }

    /// Re-reads keychain to recompute `isConnected`. Mirrors
    /// `WhoopService.refreshConnectionState()` / `OuraService.refreshConnectionState()`
    /// — required because the singleton may be initialized during a `BGTask`
    /// wake while the device is locked, at which point the keychain is
    /// unreadable and `accessToken` returns nil even though tokens exist.
    /// Without this re-check, the dashboard Strava widget would stay hidden
    /// on the user's next foreground launch (same process, same singleton)
    /// until they manually reconnect. Called from
    /// `Fit33App.onChange(scenePhase: .active)` so the widget reliably
    /// appears on every cold start / resume when Strava is connected.
    func refreshConnectionState() {
        let nowConnected = accessToken != nil && refreshToken != nil
        if nowConnected != isConnected {
            AppLogger.info("[STRAVA] Connection state changed on foreground: \(isConnected) → \(nowConnected)", category: .auth)
            isConnected = nowConnected
        }
        if isConnected {
            loadCachedDataIfNeeded()
        }
    }

    /// Hydrates `athleteProfile` / `recentActivities` / `lastSyncDate` /
    /// `athleteStats` from `UserDefaults` whenever they're not yet
    /// populated. Safe to call repeatedly — only fills in values that are
    /// still nil so fresh API data isn't overwritten by stale cache. This
    /// is what makes the dashboard widget appear instantly on cold start
    /// without waiting for the network round-trip.
    private func loadCachedDataIfNeeded() {
        if athleteProfile == nil,
           let data = UserDefaults.standard.data(forKey: "strava_athlete"),
           let athlete = try? JSONDecoder().decode(StravaAthlete.self, from: data) {
            athleteProfile = athlete
        }
        if recentActivities.isEmpty,
           let data = UserDefaults.standard.data(forKey: "strava_recent_activities") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let cached = try? decoder.decode([StravaActivity].self, from: data) {
                recentActivities = cached
            }
        }
        if athleteStats == nil,
           let data = UserDefaults.standard.data(forKey: "strava_athlete_stats"),
           let stats = try? JSONDecoder().decode(StravaAthleteStats.self, from: data) {
            athleteStats = stats
        }
        if lastSyncDate == nil,
           let date = UserDefaults.standard.object(forKey: "strava_last_sync") as? Date {
            lastSyncDate = date
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

        // Phase 5 dual-write: mirror tokens to Supabase so the
        // strava-webhook edge function can call Strava on our behalf
        // when the iOS app is offline. Best-effort — failure here must
        // not block the iOS sync flow.
        await mirrorTokensToSupabase(
            access: tokenResponse.accessToken,
            refresh: tokenResponse.refreshToken,
            expiresAt: tokenResponse.expiresAt,
            athleteId: tokenResponse.athlete?.id
        )

        // Remove any HealthKit-imported Strava rows so the richer OAuth
        // sync becomes the single source of truth (no duplicates).
        await HealthDataService.shared.removeHealthKitDuplicates(for: .strava)

        // Sync activities after connecting
        await syncActivities()
    }
    
    /// Single-flight wrapper. See `refreshTask` comment above for rationale.
    /// Prevents the concurrent-replay race that otherwise calls `disconnect()`
    /// when 2+ in-flight Strava API calls all try to refresh the same
    /// access token simultaneously.
    private func refreshAccessToken() async throws {
        if let inflight = refreshTask {
            try await inflight.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            defer { self?.refreshTask = nil }
            try await self?._performTokenRefresh()
        }
        refreshTask = task
        try await task.value
    }

    /// Refresh the access token if expired
    private func _performTokenRefresh() async throws {
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

        guard let httpResponse = response as? HTTPURLResponse else {
            // No HTTP response — almost certainly a transient network issue.
            // Don't disconnect; the next sync will retry.
            throw StravaError.tokenRefreshFailed
        }

        guard httpResponse.statusCode == 200 else {
            // Strava returns 400 with `{"error":"invalid_grant"}` only when
            // the refresh token has been revoked (user revoked the app from
            // strava.com, or rotated the token elsewhere). For ANY other
            // status — 5xx outage, 429 rate limit, 502 gateway, transient
            // 401, network blip — we keep tokens in keychain and let the
            // next sync retry. The 60-day inactivity guard takes over for
            // truly abandoned integrations.
            let body = String(data: data, encoding: .utf8) ?? ""
            let isHardRevoke = (httpResponse.statusCode == 400 && body.contains("invalid_grant"))
                || (httpResponse.statusCode == 401 && body.contains("invalid_grant"))

            if isHardRevoke {
                AppLogger.warning(
                    "[STRAVA] Refresh token revoked (HTTP \(httpResponse.statusCode)) — disconnecting",
                    category: .auth
                )
                disconnect()
            } else {
                AppLogger.warning(
                    "[STRAVA] Token refresh transient failure (HTTP \(httpResponse.statusCode)) — will retry on next sync",
                    category: .auth
                )
            }
            throw StravaError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(StravaRefreshResponse.self, from: data)
        
        accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        tokenExpiresAt = Date(timeIntervalSince1970: Double(tokenResponse.expiresAt))
        
        AppLogger.debug("🔄 [STRAVA] Token refreshed (next expiry: \(tokenExpiresAt?.description ?? "?"))", category: .health)

        // Phase 5 dual-write: mirror the rotated refresh token to Supabase
        // so the webhook function never holds a stale value.
        await mirrorTokensToSupabase(
            access: tokenResponse.accessToken,
            refresh: tokenResponse.refreshToken,
            expiresAt: tokenResponse.expiresAt,
            athleteId: athleteProfile?.id
        )
    }

    /// Phase 5 helper: dual-write Strava tokens to Supabase via the
    /// `upsert_strava_tokens` SECURITY DEFINER RPC. The RPC pins
    /// caller user_id to `auth.uid()` (Data invariant #7) so we don't
    /// need to (and must not) pass the user id from the client.
    private func mirrorTokensToSupabase(
        access: String,
        refresh: String,
        expiresAt: Int,
        athleteId: Int64?
    ) async {
        do {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            let expiresIso = isoFormatter.string(
                from: Date(timeIntervalSince1970: Double(expiresAt))
            )

            struct UpsertParams: Encodable {
                let p_access: String
                let p_refresh: String
                let p_expires_at: String
                let p_athlete_id: Int64?
            }

            let params = UpsertParams(
                p_access: access,
                p_refresh: refresh,
                p_expires_at: expiresIso,
                p_athlete_id: athleteId
            )

            try await SupabaseManager.shared.client
                .rpc("upsert_strava_tokens", params: params)
                .execute()

            AppLogger.debug("[STRAVA] Tokens mirrored to Supabase", category: .health)
        } catch {
            // Best-effort. Don't break the iOS flow if dual-write fails —
            // it just means webhooks won't fire until next refresh.
            AppLogger.warning(
                "[STRAVA] Token mirror to Supabase failed: \(error.localizedDescription)",
                category: .health
            )
        }
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
    
    /// Sync activities from Strava.
    /// - Parameters:
    ///   - daysBack: How many days of history to pull. Defaults to 30; the
    ///     foreground / `BGTask` paths use 30 to keep the activity charts
    ///     fresh, the silent-push path uses 1.
    ///   - force: If `true`, bypasses the 5-minute throttle. Use for explicit
    ///     "Sync Now" taps and for `BGTask`-driven refreshes. The auto-sync
    ///     path on `scenePhase: .active` should call with `force: false` so
    ///     rapid foreground/background toggles don't burn API budget.
    func syncActivities(daysBack: Int = 30, force: Bool = false) async {
        guard isConnected else {
            AppLogger.debug("⏭️ [STRAVA] Skipping sync — not connected (token: \(accessToken != nil), refresh: \(refreshToken != nil))", category: .health)
            return
        }

        // Coalesce overlapping calls — Dashboard tab-switches and scenePhase
        // flicker can each trigger a sync within ~1s of each other.
        if isSyncing {
            AppLogger.debug("⏭️ [STRAVA] Skipping sync — already syncing", category: .health)
            return
        }

        // Same throttle window WHOOP / Oura use. Bypassed by explicit
        // user taps + by BGTask-driven refreshes (which already throttle
        // themselves at the OS level).
        if !force, let last = lastSyncDate,
           Date().timeIntervalSince(last) < Self.syncThrottleInterval {
            AppLogger.debug("⏭️ [STRAVA] Skipping sync — throttled (last sync \(Int(Date().timeIntervalSince(last)))s ago)", category: .health)
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        isLoading = true
        errorMessage = nil
        
        AppLogger.debug("🔄 [STRAVA] Starting sync (daysBack: \(daysBack), force: \(force), token expires: \(tokenExpiresAt?.description ?? "nil"))", category: .health)

        let startedAt = Date()
        let userId = SupabaseManager.shared.currentUser?.id

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
                // Cluster D: keep the body as a breadcrumb but don't fingerprint
                // here — the outer catch will route through NetworkErrorClassifier
                // with full op/endpoint/http_status context once we throw.
                // 401 from Strava is a revoked token (expected), 5xx are transient.
                AppLogger.warning("⚠️ [STRAVA] HTTP \(httpResponse.statusCode) body: \(body.prefix(500))", category: .network)
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

            // Persist the activity list so the dashboard widget + cardio
            // section have data on cold start before the network round-trip
            // returns. Cap to the most recent 50 to keep the cache bounded —
            // anything older is read from `cardio_workouts` via the cardio tab.
            persistRecentActivities(activities)

            AppLogger.debug("📊 [STRAVA] Decoded \(activities.count) activities", category: .health)
            for (i, activity) in activities.prefix(5).enumerated() {
                AppLogger.debug("   \(i+1). \(activity.type) — \(activity.name) — \(activity.startDate)", category: .health)
            }
            
            // Save activities to Supabase for persistence
            await saveActivitiesToCloud(activities)

            // Phase 2 enrichment — fetch detail + streams for activities
            // that haven't been enriched yet. Rate-limited internally so
            // a backlog won't burn the daily Strava budget.
            await StravaActivityEnricher.shared.enrichIfNeeded(activities: activities)

            // Check new activities against challenges
            await syncActivitiesToChallenges(activities)

            // Refresh long-form athlete totals (recent 4w / YTD / all-time)
            // for the Strava settings page. Best-effort — failure here
            // shouldn't fail the sync since the activity list is the
            // primary product.
            await refreshAthleteStatsIfNeeded()

            AppLogger.info("✅ [STRAVA] Synced \(activities.count) activities", category: .health)
            
        } catch {
            errorMessage = error.localizedDescription
            // Cluster D noise-suppression (fingerprint 9c11d1a9, 16 occurrences
            // on a single user across Dashboard tab-switches): `.notConnected`
            // and `.tokenRefreshFailed` are expected operational states
            // (Strava-side token revoke, first install, or a `disconnect()`
            // racing the sync), not bugs. Routing them through
            // `AppLogger.error` fingerprinted every Dashboard refresh. Per
            // QUALITY_PERFORMANCE_AGENT invariants 25 + 25a: drop these to
            // `.debug` and flip `isConnected = false` so future `syncActivities`
            // calls short-circuit at the guard above instead of re-throwing
            // the same error on every tab focus.
            //
            // Real network / HTTP / decoding failures still go through
            // NetworkErrorClassifier so transient NSURLError / 5xx land at
            // `.warning` with op/endpoint/pg_code context and genuine
            // malfunctions stay at `.error`.
            if let stravaError = error as? StravaError {
                switch stravaError {
                case .notConnected, .tokenRefreshFailed:
                    AppLogger.debug(
                        "⏭️ [STRAVA] Sync skipped — \(stravaError) (tokens cleared or revoked)",
                        category: .health,
                        context: DiagnosticContext(
                            op: PerformanceSignposts.Op.stravaSync.rawValue,
                            endpoint: "GET /athlete/activities"
                        )
                    )
                    if isConnected {
                        isConnected = false
                        Task {
                            await SupabaseManager.shared.updateIntegrationStatus(integration: "strava", isConnected: false)
                        }
                    }
                default:
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "[STRAVA] Sync error",
                        category: .health,
                        op: PerformanceSignposts.Op.stravaSync.rawValue,
                        endpoint: "GET /athlete/activities",
                        startedAt: startedAt,
                        userId: userId
                    )
                }
            } else {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "[STRAVA] Sync error",
                    category: .health,
                    op: PerformanceSignposts.Op.stravaSync.rawValue,
                    endpoint: "GET /athlete/activities",
                    startedAt: startedAt,
                    userId: userId
                )
            }
        }
        
        isLoading = false

        // Smart Adaptive Daily Goals (20260606) — fire-and-forget tick of
        // today's Strava-eligible quests. Detached so a slow RPC never
        // stalls the sync return path; the call is auth-pinned server-side
        // (`auth.uid()`) and short-circuits when there are no Strava
        // quests assigned.
        Task.detached(priority: .background) {
            await DailyQuestService.shared.onStravaActivityImported()
        }
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

    /// Get raw JSON activity detail by ID. Returned as a `[String: Any]` dict
    /// because we want to forward the splits / segment_efforts / map fields
    /// straight into Postgres JSONB columns without modeling every nested
    /// shape on the Swift side. The typed `getActivityDetail(id:)` is used
    /// only when callers want direct access (e.g. recap sheet test fixtures).
    func getActivityDetailJSON(id: Int64) async throws -> [String: Any] {
        let token = try await ensureValidToken()

        guard let activityURL = URL(string: "\(Config.apiBaseUrl)/activities/\(id)?include_all_efforts=false") else {
            throw StravaError.apiError("Invalid activity detail URL")
        }
        var request = URLRequest(url: activityURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Failed to fetch activity detail (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaError.apiError("Activity detail response was not a JSON object")
        }
        return json
    }

    /// Fetch raw activity streams (HR / pace / cadence / power / altitude).
    /// Returned as a dict keyed by stream type so we can pipe it directly
    /// into `cardio_workouts.streams_json`.
    func getActivityStreamsJSON(id: Int64) async throws -> [String: Any] {
        let token = try await ensureValidToken()

        let keys = "heartrate,cadence,watts,velocity_smooth,altitude,distance,time"
        guard let streamsURL = URL(string: "\(Config.apiBaseUrl)/activities/\(id)/streams?keys=\(keys)&key_by_type=true") else {
            throw StravaError.apiError("Invalid activity streams URL")
        }
        var request = URLRequest(url: streamsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.apiError("No HTTP response for streams")
        }

        // Strava returns 404 when the activity has no streams (e.g. manually
        // logged with no GPS / HR data). Treat that as "no streams" rather
        // than a hard failure so enrichment can still succeed for the detail
        // payload.
        if httpResponse.statusCode == 404 {
            return [:]
        }

        guard httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Failed to fetch activity streams (HTTP \(httpResponse.statusCode))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaError.apiError("Streams response was not a JSON object")
        }
        return json
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
            
            // Create the cardio workout insert record. `origin_app = 'strava'`
            // is required so cross-source dedup (HealthKit duplicate cleanup)
            // can target the right rows — see migration 20260417.
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
                externalUrl: "https://www.strava.com/activities/\(activity.id)",
                originApp: "strava",
                sufferScore: activity.sufferScore
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

            // Phase 3 streak shield hint: a single very-high-effort activity
            // (Strava suffer_score > 150 ≈ a hard tempo / race / long run)
            // pre-credits the day so a tomorrow rest day cannot break the
            // streak. Does not consume one of the user's monthly shields.
            if let highEffort = todayActivities.first(where: { ($0.sufferScore ?? 0) > 150 }) {
                await MainActor.run {
                    StreakShieldService.shared.creditHighEffortDay(
                        reason: "Strava \(highEffort.type) suffer=\(highEffort.sufferScore ?? 0)"
                    )
                }
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
        athleteStats = nil
        lastSyncDate = nil
        isConnected = false

        UserDefaults.standard.removeObject(forKey: "strava_athlete")
        UserDefaults.standard.removeObject(forKey: "strava_last_sync")
        UserDefaults.standard.removeObject(forKey: "strava_recent_activities")
        UserDefaults.standard.removeObject(forKey: "strava_athlete_stats")

        for key in ["strava_access_token", "strava_refresh_token", "strava_token_expires_at"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Update integration status in database
        Task {
            await SupabaseManager.shared.updateIntegrationStatus(integration: "strava", isConnected: false)
        }
        
        AppLogger.debug("🔌 [STRAVA] Disconnected", category: .health)
    }

    // MARK: - Cache Persistence

    /// Caches the most recent activities to UserDefaults so the dashboard
    /// widget appears instantly on cold start. Mirrors the pattern WHOOP /
    /// Oura use for `todayRecovery` / `todayReadiness`.
    private func persistRecentActivities(_ activities: [StravaActivity]) {
        let trimmed = Array(
            activities
                .sorted { $0.startDate > $1.startDate }
                .prefix(50)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(trimmed) {
            UserDefaults.standard.set(data, forKey: "strava_recent_activities")
        }
    }

    /// Refreshes the long-form `/athletes/{id}/stats` totals (recent 4w / YTD
    /// / all-time per sport). Throttled via the same 5-min window as the
    /// activity sync — Strava only updates these once a day so there's no
    /// reason to hit the endpoint more often than that.
    private func refreshAthleteStatsIfNeeded() async {
        guard isConnected else { return }
        do {
            let stats = try await getAthleteStats()
            athleteStats = stats
            if let data = try? JSONEncoder().encode(stats) {
                UserDefaults.standard.set(data, forKey: "strava_athlete_stats")
            }
        } catch {
            // Best-effort; the activity-list sync is the primary product
            // and is unaffected by stats failures.
            AppLogger.debug(
                "[STRAVA] Athlete stats refresh failed (non-fatal): \(error.localizedDescription)",
                category: .health
            )
        }
    }

    /// 60-day inactivity guard. Called from `Fit33App` startup — if the user
    /// hasn't synced Strava in 60+ days AND the next refresh fails, we treat
    /// the integration as abandoned. Until then we keep retrying so a return
    /// user doesn't get silently disconnected. Safe no-op when within window.
    func evaluateInactivityWindow() async {
        guard isConnected else { return }
        guard let last = lastSyncDate else { return }
        guard Date().timeIntervalSince(last) > Self.inactivityDisconnectInterval else { return }

        AppLogger.info("[STRAVA] Last sync \(Int(Date().timeIntervalSince(last) / 86400))d ago — probing token before disconnecting", category: .auth)
        do {
            _ = try await ensureValidToken()
            // Token still works, just stale data — let the foreground sync handle it.
            AppLogger.info("[STRAVA] Token still valid after inactivity window — keeping connection", category: .auth)
        } catch {
            AppLogger.warning("[STRAVA] Inactivity probe failed (\(error.localizedDescription)) — disconnecting", category: .auth)
            disconnect()
        }
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
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }
        return recentActivities
            .filter { $0.startDate >= startOfWeek }
            .reduce(0) { $0 + ($1.calories ?? 0) }
    }

    /// Activities so far this calendar month (uses the user's local calendar).
    var monthlyActivities: [StravaActivity] {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else {
            return []
        }
        return recentActivities.filter { $0.startDate >= startOfMonth }
    }

    /// Total elevation gained this week (in meters).
    var weeklyElevationGain: Double {
        let calendar = Calendar.current
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }
        return recentActivities
            .filter { $0.startDate >= startOfWeek }
            .reduce(0) { $0 + ($1.totalElevationGain ?? 0) }
    }

    /// Average pace this week across runs only (in seconds per km).
    /// Returns nil when there are no runs in the current week.
    var weeklyAveragePaceSecondsPerKm: Double? {
        let calendar = Calendar.current
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return nil
        }
        let runs = recentActivities.filter {
            $0.startDate >= startOfWeek
                && ($0.type == "Run" || $0.type == "VirtualRun")
                && $0.distance > 100
                && $0.movingTime > 0
        }
        guard !runs.isEmpty else { return nil }
        let totalDistance = runs.reduce(0) { $0 + $1.distance }
        let totalTime = runs.reduce(0) { $0 + $1.movingTime }
        guard totalDistance > 0 else { return nil }
        return Double(totalTime) / (totalDistance / 1000)
    }

    /// Most recent activity, regardless of age. Used by the dashboard widget
    /// + Strava settings hero so the widget reliably appears any time the
    /// integration is connected — not just within the 36h freshness window.
    var mostRecentActivity: StravaActivity? {
        recentActivities.sorted { $0.startDate > $1.startDate }.first
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
    
    // Formatted properties — honor the user's km/mi preference via UnitSettingsManager.
    var distanceFormatted: String {
        UnitSettingsManager.shared.formatStravaDistance(meters: distance)
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
        return UnitSettingsManager.shared.formatStravaPace(secondsPerKm: paceSecondsPerKm)
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
    let originApp: String
    let sufferScore: Int?

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
        case originApp = "origin_app"
        case sufferScore = "suffer_score"
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
