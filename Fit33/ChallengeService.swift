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

/// Cached date formatters to avoid expensive re-allocation on every call
/// DateFormatter creation is ~10x more expensive than reusing a cached instance
private enum ChallengeFormatters {
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    static let iso8601Standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    /// UTC date formatter — used for parsing server dates (start_date, end_date)
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // Use device's local timezone so dates match the user's day boundary
        // (Server-side functions use the challenge's stored creator_timezone for official "today")
        f.timeZone = TimeZone.current
        return f
    }()
    
    /// Local timezone date formatter — used for progress logging so that
    /// "today" in the user's timezone matches the server's timezone-aware queries.
    /// CRITICAL: get_active_challenges uses (NOW() AT TIME ZONE p_timezone)::DATE
    /// so we must log progress using the same local date, NOT UTC.
    static let localDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}

/// Parses dates from various formats (DATE "2026-02-01" or TIMESTAMPTZ "2026-02-01T00:00:00+00:00")
func parseFlexibleDate(_ string: String) -> Date {
    // Try ISO8601 with fractional seconds first
    if let date = ChallengeFormatters.iso8601WithFractional.date(from: string) {
        return date
    }
    
    // Try without fractional seconds
    if let date = ChallengeFormatters.iso8601Standard.date(from: string) {
        return date
    }
    
    // Try date-only format (PostgreSQL DATE type)
    if let date = ChallengeFormatters.dateOnly.date(from: string) {
        return date
    }
    
    // Fallback to current date
    AppLogger.warning("Could not parse date: \(string)", category: .social)
    return Date()
}

// MARK: - Shared Challenge Progress Data

struct ChallengeProgressData {
    let steps: Int
    let activeMinutes: Int
    let calories: Int
    let protein: Int
    let mealCalories: Int
    let hydrationMl: Int
    let walkMinutesToday: Int
    let runMinutesToday: Int
    let sleepMinutes: Int
    
    func hydrationInUnit(_ unit: String) -> Int {
        unit.lowercased() == "oz" ? Int(Double(hydrationMl) / 29.5735) : hydrationMl
    }
}

@MainActor
func gatherCurrentProgress() async -> ChallengeProgressData {
    MealService.shared.ensureFreshForToday()
    
    let hkService = HealthKitService.shared
    let hkManager = HealthKitManager.shared
    
    let steps = hkManager.todaySteps > 0 ? hkManager.todaySteps : hkService.todaySteps
    
    let walkMinutes = hkService.recentWorkouts
        .filter { $0.workoutType == .walking && Calendar.current.isDateInToday($0.startDate) }
        .reduce(0) { $0 + $1.durationMinutes }
    
    let runMinutes = hkService.recentWorkouts
        .filter { $0.workoutType == .running && Calendar.current.isDateInToday($0.startDate) }
        .reduce(0) { $0 + $1.durationMinutes }
    
    let sleepHours = hkService.lastNightSleep ?? 0
    
    return ChallengeProgressData(
        steps: steps,
        activeMinutes: hkService.todayActiveMinutes,
        calories: hkService.todayCalories,
        protein: MealService.shared.todaysMeals.reduce(0) { $0 + $1.protein },
        mealCalories: MealService.shared.todaysMeals.reduce(0) { $0 + $1.calories },
        hydrationMl: HydrationService.shared.todayTotal,
        walkMinutesToday: walkMinutes,
        runMinutesToday: runMinutes,
        sleepMinutes: Int(sleepHours * 60)
    )
}

// MARK: - Challenge Service

@MainActor
class ChallengeService: ObservableObject {
    static let shared = ChallengeService()
    private let logger = SessionLogManager.shared
    
    // MARK: - Cache Keys
    
    private let activeChallengesCacheKey = "fit33_cached_active_challenges"
    private let groupChallengesCacheKey = "fit33_cached_group_challenges"
    private let pendingInvitesCacheKey = "fit33_cached_pending_invites"
    private let pendingSentCacheKey = "fit33_cached_pending_sent_challenges"
    private let cacheDateKey = "fit33_challenges_cache_date"
    
    // MARK: - Published Properties
    
    @Published var pendingInvites: [ChallengeInvite] = []           // Incoming challenges (sent TO me)
    @Published var pendingSentChallenges: [PendingSentChallenge] = [] // Outgoing challenges (sent BY me)
    @Published var activeChallenges: [ActiveChallenge] = []
    @Published var activeGroupChallenges: [ActiveGroupChallenge] = [] // Group challenges (3+ people)
    @Published var challengeTemplates: [ChallengeTemplate] = []
    @Published var isLoading = false

    /// Last server-surfaced error from `createChallenge` (RPC + direct-insert paths).
    /// Cleared at the start of every send attempt, set when both RPC tries + direct
    /// insert all fail. The Send Challenge flow reads this so the user sees the
    /// real Postgres / network message ("Opponent not found", "Cannot challenge
    /// yourself", "Not authenticated", "offline") instead of the generic
    /// "There was an issue sending your challenge. Please try again." Surfaced
    /// 2026-04-27 sync-triage Phase 2 — the brother's "could not send" error
    /// was previously dead-end logged.
    @Published var lastCreateChallengeError: String?
    
    // Track last known invite IDs for detecting new invites
    private var lastCheckedInviteIds: Set<UUID> = []
    
    // MARK: - Challenge Sync Throttling
    private var lastChallengeSyncDate: Date?
    private var isChallengeSyncing = false
    private static let challengeSyncThrottleInterval: TimeInterval = 30
    
    #if DEBUG
    private var syncAttemptCount = 0
    private var syncThrottledCount = 0
    private var syncCompletedCount = 0
    
    /// Call to print a summary of sync attempts vs throttled vs completed
    func printSyncAudit() {
        AppLogger.debug("📊 [CHALLENGE SYNC AUDIT] attempts: \(syncAttemptCount), throttled: \(syncThrottledCount), completed: \(syncCompletedCount)", category: .social)
    }
    #endif
    
    private init() {
        loadCachedChallengesSync()
    }
    
    /// Synchronous cache load from UserDefaults — no Core Data, safe for init().
    /// Typically decodes 1-5 challenge objects per array (<1ms).
    private func loadCachedChallengesSync() {
        let cacheTimestamp = UserDefaults.standard.double(forKey: cacheDateKey)
        let cacheDate = cacheTimestamp > 0 ? Date(timeIntervalSince1970: cacheTimestamp) : nil
        let isCacheFromToday = cacheDate.map { Calendar.current.isDateInToday($0) } ?? false
        
        let decoder = JSONDecoder()
        
        if let activeData = UserDefaults.standard.data(forKey: activeChallengesCacheKey),
           var cached = try? decoder.decode([ActiveChallenge].self, from: activeData) {
            if !isCacheFromToday && !cached.isEmpty {
                cached = cached.map { challenge in
                    ActiveChallenge(
                        challengeId: challenge.challengeId, challengeType: challenge.challengeType,
                        title: challenge.title, description: challenge.description,
                        dailyTarget: challenge.dailyTarget, totalTarget: challenge.totalTarget,
                        targetUnit: challenge.targetUnit, startDate: challenge.startDate,
                        endDate: challenge.endDate, durationDays: challenge.durationDays,
                        daysElapsed: challenge.daysElapsed, daysRemaining: challenge.daysRemaining,
                        status: challenge.status, myTotalProgress: challenge.myTotalProgress,
                        myTodayProgress: 0, myDaysCompleted: challenge.myDaysCompleted,
                        myCurrentStreak: challenge.myCurrentStreak, opponentId: challenge.opponentId,
                        opponentName: challenge.opponentName, opponentUsername: challenge.opponentUsername,
                        opponentPhotoUrl: challenge.opponentPhotoUrl,
                        opponentTotalProgress: challenge.opponentTotalProgress,
                        opponentTodayProgress: 0, opponentDaysCompleted: challenge.opponentDaysCompleted,
                        amWinning: challenge.amWinning, amWinningToday: nil
                    )
                }
            }
            self.activeChallenges = cached
        }
        
        if let groupData = UserDefaults.standard.data(forKey: groupChallengesCacheKey),
           var cached = try? decoder.decode([ActiveGroupChallenge].self, from: groupData) {
            if !isCacheFromToday && !cached.isEmpty {
                cached = cached.map { $0.withZeroedTodayProgress() }
            }
            self.activeGroupChallenges = cached
        }
        
        if let invitesData = UserDefaults.standard.data(forKey: pendingInvitesCacheKey),
           let cached = try? decoder.decode([ChallengeInvite].self, from: invitesData) {
            self.pendingInvites = cached
        }
        
        if let sentData = UserDefaults.standard.data(forKey: pendingSentCacheKey),
           let cached = try? decoder.decode([PendingSentChallenge].self, from: sentData) {
            self.pendingSentChallenges = cached
        }
    }
    
    // MARK: - Local Challenge Caching (survives force quit)
    
    /// Cache active challenges to UserDefaults for instant display on app restart.
    /// Only updates cache on successful fetches — never clears good cache on transient failures.
    private func cacheActiveChallenges() {
        if activeChallenges.isEmpty {
            UserDefaults.standard.removeObject(forKey: activeChallengesCacheKey)
            AppLogger.debug("Cleared cached active challenges (server confirmed 0)", category: .social)
            ActiveChallengeWidgetBridge.publish(activeChallenges: [])
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(activeChallenges)
            UserDefaults.standard.set(data, forKey: activeChallengesCacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheDateKey)
            AppLogger.debug("Cached \(activeChallenges.count) active challenges", category: .social)
        } catch {
            // Local JSONEncoder failure — Codable struct, basically unreachable.
            // No network error to classify; downgrade keeps this out of bug-intel.
            AppLogger.warning("Failed to cache active challenges: \(error.localizedDescription)", category: .social)
        }

        ActiveChallengeWidgetBridge.publish(activeChallenges: activeChallenges)
    }
    
    /// Cache pending invites to UserDefaults
    private func cachePendingInvites() {
        guard !pendingInvites.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingInvitesCacheKey)
            AppLogger.debug("Cleared cached pending invites", category: .social)
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pendingInvites)
            UserDefaults.standard.set(data, forKey: pendingInvitesCacheKey)
            AppLogger.debug("Cached \(pendingInvites.count) pending invites", category: .social)
        } catch {
            AppLogger.warning("Failed to cache pending invites: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Cache group challenges to UserDefaults for instant display on app restart.
    /// Only updates cache on successful fetches — never clears good cache on transient failures.
    private func cacheGroupChallenges() {
        if activeGroupChallenges.isEmpty {
            UserDefaults.standard.removeObject(forKey: groupChallengesCacheKey)
            AppLogger.debug("Cleared cached group challenges (server confirmed 0)", category: .social)
            return
        }

        do {
            let data = try JSONEncoder().encode(activeGroupChallenges)
            UserDefaults.standard.set(data, forKey: groupChallengesCacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheDateKey)
            AppLogger.debug("Cached \(activeGroupChallenges.count) group challenges", category: .social)
        } catch {
            AppLogger.warning("Failed to cache group challenges: \(error.localizedDescription)", category: .social)
        }
    }

    /// Load cached challenges from UserDefaults (called on init for instant display)
    private func loadCachedChallenges() {
        AppLogger.debug("Loading cached challenges...", category: .social)
        
        // Check if the cache is from a previous day — if so, today's progress values are stale
        let cacheTimestamp = UserDefaults.standard.double(forKey: cacheDateKey)
        let cacheDate = cacheTimestamp > 0 ? Date(timeIntervalSince1970: cacheTimestamp) : nil
        let isCacheFromToday = cacheDate.map { Calendar.current.isDateInToday($0) } ?? false
        
        // Load cached active challenges
        if let data = UserDefaults.standard.data(forKey: activeChallengesCacheKey) {
            do {
                let decoder = JSONDecoder()
                var cached = try decoder.decode([ActiveChallenge].self, from: data)
                
                // If cache is from a previous day, zero out today-specific fields
                // so stale yesterday progress doesn't appear as today's progress
                if !isCacheFromToday && !cached.isEmpty {
                    AppLogger.debug("Cache is from previous day — zeroing out today's progress for clean reset", category: .social)
                    cached = cached.map { challenge in
                        ActiveChallenge(
                            challengeId: challenge.challengeId,
                            challengeType: challenge.challengeType,
                            title: challenge.title,
                            description: challenge.description,
                            dailyTarget: challenge.dailyTarget,
                            totalTarget: challenge.totalTarget,
                            targetUnit: challenge.targetUnit,
                            startDate: challenge.startDate,
                            endDate: challenge.endDate,
                            durationDays: challenge.durationDays,
                            daysElapsed: challenge.daysElapsed,
                            daysRemaining: challenge.daysRemaining,
                            status: challenge.status,
                            myTotalProgress: challenge.myTotalProgress,
                            myTodayProgress: 0,          // Reset: today hasn't started yet
                            myDaysCompleted: challenge.myDaysCompleted,
                            myCurrentStreak: challenge.myCurrentStreak,
                            opponentId: challenge.opponentId,
                            opponentName: challenge.opponentName,
                            opponentUsername: challenge.opponentUsername,
                            opponentPhotoUrl: challenge.opponentPhotoUrl,
                            opponentTotalProgress: challenge.opponentTotalProgress,
                            opponentTodayProgress: 0,    // Reset: opponent's today starts at 0
                            opponentDaysCompleted: challenge.opponentDaysCompleted,
                            amWinning: challenge.amWinning,
                            amWinningToday: nil           // Reset: no today winner yet
                        )
                    }
                }
                
                self.activeChallenges = cached
                AppLogger.info("Loaded \(cached.count) cached active challenges instantly\(isCacheFromToday ? "" : " (today progress zeroed)")", category: .social)
                ActiveChallengeWidgetBridge.publish(activeChallenges: cached)
            } catch {
                AppLogger.warning("Failed to decode cached active challenges: \(error.localizedDescription)", category: .social)
                UserDefaults.standard.removeObject(forKey: activeChallengesCacheKey)
            }
        } else {
            AppLogger.debug("No cached active challenges found", category: .social)
        }
        
        // Load cached pending invites
        if let data = UserDefaults.standard.data(forKey: pendingInvitesCacheKey) {
            do {
                let decoder = JSONDecoder()
                let cached = try decoder.decode([ChallengeInvite].self, from: data)
                self.pendingInvites = cached
                AppLogger.info("Loaded \(cached.count) cached pending invites instantly", category: .social)
            } catch {
                AppLogger.warning("Failed to decode cached pending invites: \(error.localizedDescription)", category: .social)
                UserDefaults.standard.removeObject(forKey: pendingInvitesCacheKey)
            }
        } else {
            AppLogger.debug("No cached pending invites found", category: .social)
        }
        
        // Load cached pending sent challenges (outgoing)
        if let data = UserDefaults.standard.data(forKey: pendingSentCacheKey) {
            do {
                let cached = try JSONDecoder().decode([PendingSentChallenge].self, from: data)
                self.pendingSentChallenges = cached
                AppLogger.info("Loaded \(cached.count) cached pending sent challenges instantly", category: .social)
            } catch {
                AppLogger.warning("Failed to decode cached pending sent: \(error.localizedDescription)", category: .social)
                UserDefaults.standard.removeObject(forKey: pendingSentCacheKey)
            }
        }

        // Load cached group challenges
        if let data = UserDefaults.standard.data(forKey: groupChallengesCacheKey) {
            do {
                var cached = try JSONDecoder().decode([ActiveGroupChallenge].self, from: data)
                if !isCacheFromToday && !cached.isEmpty {
                    AppLogger.debug("Group cache from previous day — zeroing today's member progress", category: .social)
                    cached = cached.map { $0.withZeroedTodayProgress() }
                }
                self.activeGroupChallenges = cached
                AppLogger.info("Loaded \(cached.count) cached group challenges instantly\(isCacheFromToday ? "" : " (today progress zeroed)")", category: .social)
            } catch {
                AppLogger.warning("Failed to decode cached group challenges: \(error.localizedDescription)", category: .social)
                UserDefaults.standard.removeObject(forKey: groupChallengesCacheKey)
            }
        } else {
            AppLogger.debug("No cached group challenges found", category: .social)
        }
    }
    
    /// Clear all challenge caches (call on logout)
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: activeChallengesCacheKey)
        UserDefaults.standard.removeObject(forKey: groupChallengesCacheKey)
        UserDefaults.standard.removeObject(forKey: pendingInvitesCacheKey)
        UserDefaults.standard.removeObject(forKey: pendingSentCacheKey)
        UserDefaults.standard.removeObject(forKey: cacheDateKey)
        activeChallenges = []
        activeGroupChallenges = []
        pendingInvites = []
        pendingSentChallenges = []
        AppLogger.debug("Cleared all challenge caches", category: .social)
    }
    
    // MARK: - Fetch All Data
    
    /// Refresh all challenge data
    func refreshAll() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        async let invitesTask: () = fetchPendingInvites()
        async let sentTask: () = fetchPendingSentChallenges()
        async let activesTask: () = fetchActiveChallenges()
        async let groupTask: () = fetchActiveGroupChallenges()
        async let templatesTask: () = fetchTemplates()
        async let communityTask: () = CommunityChallengeService.shared.fetchMyChallenges()
        
        _ = await (invitesTask, sentTask, activesTask, groupTask, templatesTask, communityTask)
    }
    
    // MARK: - Fetch Pending Invites
    
    func fetchPendingInvites() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        do {
            let result: [ChallengeInvite] = try await withCancelRetry(label: "pending_invites") {
                try await SupabaseManager.shared.supabaseClient
                    .rpc("get_pending_challenge_invites")
                    .execute()
                    .value
            }
            
            self.pendingInvites = result
            cachePendingInvites() // Cache for instant display on next app launch
            
            // Preload creator photos for instant display on invite widgets
            let creatorPhotos: [(id: String, url: String?)] = result.map {
                (id: $0.creatorId.uuidString, url: $0.creatorPhotoUrl)
            }
            if !creatorPhotos.isEmpty {
                FriendPhotoCache.shared.preloadPhotos(for: creatorPhotos)
            }
            
            AppLogger.info("Fetched \(result.count) pending challenge invites", category: .social)
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return }
            // Cluster F (fingerprint 3b62d367): offline / -1005 / -1009
            // during dashboard pending-invite fetch. Classifier routes
            // transient network to `.warning` and leaves the cached list
            // intact for the retry queue.
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching pending invites",
                category: .social,
                op: "challenges.fetch_pending_invites",
                endpoint: "rpc/get_pending_challenge_invites",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
                AppLogger.info("Detected new challenge invite from \(invite.creatorName ?? "Friend")", category: .social)
                
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
    
    // MARK: - Fetch Pending Sent Challenges (Outgoing)
    
    /// Fetch challenges I sent that are waiting for opponent to accept
    func fetchPendingSentChallenges() async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("Not authenticated, skipping pending sent fetch", category: .social)
            return
        }
        
        do {
            let result: [PendingSentChallenge] = try await withCancelRetry(label: "pending_sent") {
                try await SupabaseManager.shared.supabaseClient
                    .rpc("get_pending_sent_challenges")
                    .execute()
                    .value
            }
            
            // Update on main thread
            await MainActor.run {
                // Clear old cache if server returns different data
                if result.count != self.pendingSentChallenges.count {
                    AppLogger.debug("Pending sent count changed: \(self.pendingSentChallenges.count) → \(result.count)", category: .social)
                }
                self.pendingSentChallenges = result
            }
            cachePendingSentChallenges()
            logger.log(.info, category: .challenge, message: "Fetched \(result.count) pending SENT challenges", metadata: result.isEmpty ? nil : [
                "challenges": result.map { "\($0.displayTitle) → \($0.opponentName ?? "?")" }.joined(separator: ", ")
            ])
            AppLogger.debug("Cached \(result.count) pending sent challenges", category: .social)
            AppLogger.info("Fetched \(result.count) pending sent challenges", category: .social)
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return }
            logger.log(.warning, category: .challenge, message: "Failed to fetch pending sent challenges", metadata: ["error": "\(error)"])
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching pending sent challenges",
                category: .social,
                op: PerformanceSignposts.Op.challengeRead.rawValue,
                endpoint: "rpc/get_pending_sent_challenges",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }
    
    /// Cache pending sent challenges
    private func cachePendingSentChallenges() {
        guard !pendingSentChallenges.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingSentCacheKey)
            return
        }
        
        do {
            let data = try JSONEncoder().encode(pendingSentChallenges)
            UserDefaults.standard.set(data, forKey: pendingSentCacheKey)
            AppLogger.debug("Cached \(pendingSentChallenges.count) pending sent challenges", category: .social)
        } catch {
            AppLogger.warning("Failed to cache pending sent: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Cancel a pending challenge I sent
    func cancelPendingChallenge(challengeId: UUID) async -> Bool {
        AppLogger.debug("cancelPendingChallenge called for: \(challengeId)", category: .social)
        do {
            struct CancelParams: Encodable {
                let p_challenge_id: String
            }
            
            AppLogger.debug("Calling cancel_challenge RPC...", category: .social)
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("cancel_challenge", params: CancelParams(p_challenge_id: challengeId.uuidString))
                .execute()
                .value
            AppLogger.info("cancel_challenge RPC successful", category: .social)
            
            // Remove from local list on main thread
            await MainActor.run {
                pendingSentChallenges.removeAll { $0.challengeId == challengeId }
                AppLogger.debug("Removed from local pendingSentChallenges", category: .social)
            }
            cachePendingSentChallenges()
            
            // Also refresh from server to ensure consistency
            AppLogger.debug("Refreshing pending sent challenges from server...", category: .social)
            await fetchPendingSentChallenges()
            
            AppLogger.info("Cancelled pending challenge: \(challengeId)", category: .social)
            AppLogger.debug("Remaining pending sent: \(pendingSentChallenges.count)", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error cancelling challenge",
                category: .social,
                op: PerformanceSignposts.Op.challengeWrite.rawValue,
                endpoint: "rpc/cancel_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Retry Helper (handles -999 cancelled errors from network congestion)
    
    /// Retries an async operation up to `maxRetries` times if it fails with a retryable URL error
    /// (cancelled -999 or timed out -1001). Uses exponential backoff between attempts.
    /// Stops immediately if app is backgrounded or task is cancelled.
    private func withCancelRetry<T>(
        label: String,
        maxRetries: Int = 2,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var didRefresh401 = false
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard !Task.isCancelled else { throw error }
                let nsError = error as NSError
                let isRetryable = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorCancelled || nsError.code == NSURLErrorTimedOut)

                // Cluster D: one-shot 401 retry. PostgREST surfaces 401 in
                // `localizedDescription` via PgErrorExtractor. A stale JWT
                // during dashboard cold-start used to throw 401 once and
                // give up; we now refresh the session and retry exactly
                // once so transient JWT expiry doesn't land in
                // bug_intelligence_fingerprints.
                let http = PgErrorExtractor.httpStatus(from: error)
                if !didRefresh401, http == 401, attempt < maxRetries {
                    didRefresh401 = true
                    AppLogger.warning(
                        "\(label) got 401 — refreshing session + retrying",
                        category: .social,
                        context: DiagnosticContext(op: "challenges.retry_401", endpoint: label, httpStatus: 401, retryAttempt: attempt + 1)
                    )
                    await SupabaseManager.shared.recoverSessionIfNeeded()
                    guard SupabaseManager.shared.isAuthenticated else { throw error }
                    continue
                }

                if isRetryable && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    let reason = nsError.code == NSURLErrorTimedOut ? "timed out" : "cancelled"
                    AppLogger.warning("\(label) \(reason) (attempt \(attempt + 1)/\(maxRetries + 1)) — retrying in \(delay / 1_000_000_000)s...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? NSError(domain: "ChallengeService", code: -1)
    }
    
    // MARK: - Fetch Active Challenges
    
    private var lastActiveFetchTime: Date = .distantPast
    private var lastGroupFetchTime: Date = .distantPast
    // 2026-04-25: was 5.0, but a single workout writes progress to multiple
    // challenges (steps + active_minutes + workout_streak), and each
    // logProgress success calls fetchActiveChallenges. The 5s gate dropped
    // every call after the first, leaving 1v1/group widgets stale. 1.0s is
    // enough to absorb genuinely duplicate UI navigations while letting
    // realtime + post-write refreshes through; RequestCoalescer dedupes any
    // truly concurrent fetch.
    private let fetchMinInterval: TimeInterval = 1.0
    
    func fetchActiveChallenges() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        let now = Date()
        guard now.timeIntervalSince(lastActiveFetchTime) > fetchMinInterval else { return }
        lastActiveFetchTime = now
        // Sprint 5 M-8: dedupe concurrent dashboard + realtime triggers so we
        // never hit `get_active_challenges` twice in parallel. The 5s throttle
        // above is MainActor-serialized but the RPC + decode are not — a
        // coalesced in-flight Task guarantees single network round-trip.
        await RequestCoalescer.shared.coalesceVoid(key: "fetchActiveChallenges") { [weak self] in
            await self?._fetchActiveChallengesBody()
        }
    }

    private func _fetchActiveChallengesBody() async {
        do {
            struct TimezoneParams: Encodable {
                let p_timezone: String
            }
            
            let result: [ActiveChallenge] = try await withCancelRetry(label: "active_challenges") {
                try await SupabaseManager.shared.supabaseClient
                    .rpc("get_active_challenges", params: TimezoneParams(
                        p_timezone: TimeZone.current.identifier
                    ))
                    .execute()
                    .value
            }
            
            self.activeChallenges = result
            cacheActiveChallenges() // Cache for instant display on next app launch
            
            // Preload opponent photos for instant display on challenge widgets
            let opponentPhotos: [(id: String, url: String?)] = result.map {
                (id: $0.opponentId.uuidString, url: $0.opponentPhotoUrl)
            }
            if !opponentPhotos.isEmpty {
                FriendPhotoCache.shared.preloadPhotos(for: opponentPhotos)
            }
            
            // Advanced logging: show exactly what progress values the widget will display
            for c in result {
                AppLogger.verbose("Widget data '\(c.displayTitle)' → myTotal: \(c.myTotalProgress), myToday: \(c.myTodayProgress ?? -1), oppTotal: \(c.opponentTotalProgress), oppToday: \(c.opponentTodayProgress ?? -1), amWinning: \(c.amWinning), amWinningToday: \(c.amWinningToday ?? false)", category: .social)
            }
            
            logger.log(.info, category: .challenge, message: "Fetched \(result.count) active challenges", metadata: result.isEmpty ? nil : [
                "challenges": result.map { "\($0.displayTitle) vs \($0.opponentName ?? "?")" }.joined(separator: ", ")
            ])
            AppLogger.info("Fetched \(result.count) active challenges", category: .social)
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return }
            // Preserve existing cached challenges on fetch failure.
            //
            // Cluster F (fingerprint 11c8a6f3, 12 occurrences / 4 users,
            // MEDIUM): the prior `logger.log(.error, …)` line double-logged
            // alongside NetworkErrorClassifier, so every offline tab-switch
            // produced TWO distinct bug-intel fingerprints. Classifier owns
            // leveling here (-1005 / -1009 → .warning; real errors → .error)
            // so the logger call is redundant. Keep only the classifier path
            // and hand it pg_code/http_status/elapsed context.
            _ = NetworkErrorClassifier.log(
                error,
                context: "[CHALLENGES] Fetch failed (keeping \(activeChallenges.count) cached)",
                category: .social,
                op: "challenges.fetch_active",
                endpoint: "rpc/get_active_challenges",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }
    
    // MARK: - Fetch Templates
    
    /// Track if templates have been loaded to avoid unnecessary refetches
    private var hasLoadedTemplates = false
    
    func fetchTemplates(force: Bool = false) async {
        if hasLoadedTemplates && !force && !challengeTemplates.isEmpty {
            AppLogger.debug("Templates already loaded (\(challengeTemplates.count)), skipping fetch", category: .social)
            return
        }

        // Cluster D: auth guard — template fetch was landing as 401 noise
        // when called from the dashboard cold-path before JWT was fresh.
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug(
                "Skipping fetchTemplates — not authenticated",
                category: .social,
                context: DiagnosticContext(op: "challenges.fetch_templates", endpoint: "rpc/get_challenge_templates")
            )
            return
        }

        AppLogger.debug("Fetching templates... (force: \(force), hasLoaded: \(hasLoadedTemplates))", category: .social)

        let startedAt = Date()
        do {
            let result: [ChallengeTemplate] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenge_templates")
                .execute()
                .value

            await MainActor.run {
                if self.challengeTemplates.count != result.count {
                    AppLogger.debug("Updating templates: \(self.challengeTemplates.count) → \(result.count)", category: .social)
                    self.challengeTemplates = result
                } else {
                    AppLogger.debug("Templates unchanged (\(result.count))", category: .social)
                }
                self.hasLoadedTemplates = true
            }
            AppLogger.info("Fetched \(result.count) challenge templates", category: .social)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching templates",
                category: .social,
                op: "challenges.fetch_templates",
                endpoint: "rpc/get_challenge_templates",
                startedAt: startedAt,
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }
    
    /// Get templates without triggering @Published updates (for use in sheets to avoid dismissal)
    /// Returns cached templates if available, otherwise fetches fresh ones
    func getTemplatesWithoutPublishing() async -> [ChallengeTemplate] {
        // Return cached if available
        if !challengeTemplates.isEmpty {
            AppLogger.debug("Returning cached templates: \(challengeTemplates.count)", category: .social)
            return challengeTemplates
        }
        
        // Fetch fresh but don't update @Published property
        AppLogger.debug("Fetching templates silently (no publish)...", category: .social)
        
        do {
            let result: [ChallengeTemplate] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenge_templates")
                .execute()
                .value
            
            AppLogger.info("Fetched \(result.count) templates (silent)", category: .social)
            return result
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching templates silently",
                category: .social,
                op: PerformanceSignposts.Op.challengeRead.rawValue,
                endpoint: "rpc/get_challenge_templates",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
        // Sync-triage 2026-04-27 Phase 2: clear last error at the START of
        // every attempt so a stale message from a previous failed send isn't
        // shown after a successful retry.
        lastCreateChallengeError = nil

        // Breadcrumb for bug-intel: when the user shakes after a "could not
        // send" alert, this logs the op + opponent prefix so triage can see
        // exactly which call path was attempted (and the error message we
        // captured below if it failed).
        SessionLogManager.shared.log(
            .info,
            category: .social,
            message: "Sending 1v1 challenge",
            metadata: [
                "op": "challenges.create",
                "opponent_id_prefix": String(opponentId.uuidString.prefix(8)),
                "type": type.rawValue,
                "duration_days": "\(durationDays)",
                "daily_target": dailyTarget.map { "\($0)" } ?? "nil"
            ]
        )

        let startDateStr = ChallengeFormatters.dateOnly.string(from: startDate)

        // Try RPC first (preferred - atomic transaction in DB)
        if let challengeId = await createChallengeViaRPC(
            opponentId: opponentId, type: type, title: title, description: description,
            dailyTarget: dailyTarget, totalTarget: totalTarget, targetUnit: targetUnit,
            startDateStr: startDateStr, durationDays: durationDays
        ) {
            await postChallengeCreation(challengeId: challengeId, opponentId: opponentId, type: type, targetUnit: targetUnit, startDate: startDate)
            lastCreateChallengeError = nil
            return challengeId
        }

        // Retry RPC once after a brief delay (transient network issues)
        AppLogger.debug("Retrying challenge creation after delay...", category: .social)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

        if let challengeId = await createChallengeViaRPC(
            opponentId: opponentId, type: type, title: title, description: description,
            dailyTarget: dailyTarget, totalTarget: totalTarget, targetUnit: targetUnit,
            startDateStr: startDateStr, durationDays: durationDays
        ) {
            await postChallengeCreation(challengeId: challengeId, opponentId: opponentId, type: type, targetUnit: targetUnit, startDate: startDate)
            lastCreateChallengeError = nil
            return challengeId
        }

        // Fallback: Direct table inserts if RPC is broken/missing
        AppLogger.warning("RPC failed twice, attempting direct table insert fallback...", category: .social)
        if let challengeId = await createChallengeDirectInsert(
            opponentId: opponentId, type: type, title: title, description: description,
            dailyTarget: dailyTarget, totalTarget: totalTarget, targetUnit: targetUnit,
            startDateStr: startDateStr, durationDays: durationDays
        ) {
            await postChallengeCreation(challengeId: challengeId, opponentId: opponentId, type: type, targetUnit: targetUnit, startDate: startDate)
            lastCreateChallengeError = nil
            return challengeId
        }

        AppLogger.error("All challenge creation methods failed", category: .social)
        // If neither RPC try nor the direct-insert path set a more specific
        // message, fall back to a generic one so the alert still shows
        // something actionable.
        if lastCreateChallengeError == nil {
            lastCreateChallengeError = "Couldn't reach the server. Check your connection and try again."
        }
        return nil
    }
    
    /// Create challenge via RPC function (preferred - single atomic transaction)
    private func createChallengeViaRPC(
        opponentId: UUID, type: ChallengeType, title: String, description: String?,
        dailyTarget: Int?, totalTarget: Int?, targetUnit: String,
        startDateStr: String, durationDays: Int
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
                let p_timezone: String
            }
            
            let params = CreateChallengeParams(
                p_opponent_id: opponentId.uuidString,
                p_challenge_type: type.rawValue,
                p_title: title,
                p_description: description,
                p_daily_target: dailyTarget,
                p_total_target: totalTarget,
                p_target_unit: targetUnit,
                p_start_date: startDateStr,
                p_duration_days: durationDays,
                p_timezone: TimeZone.current.identifier
            )
            
            AppLogger.debug("Calling create_challenge RPC... opponent: \(opponentId.uuidString.prefix(8)), type: \(type.rawValue), title: \(title), daily_target: \(dailyTarget ?? 0), duration: \(durationDays)d", category: .social)
            
            let challengeId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("create_challenge", params: params)
                .execute()
                .value
            
            AppLogger.info("RPC created challenge: \(challengeId)", category: .social)
            return challengeId
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "RPC create_challenge failed",
                category: .social,
                op: PerformanceSignposts.Op.challengeWrite.rawValue,
                endpoint: "rpc/create_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
            // Sync-triage 2026-04-27 Phase 2: capture the actual error so the
            // Send Challenge flow can show "Opponent not found" / "Cannot
            // challenge yourself" / "Not authenticated" / network-timeout
            // copy instead of the generic "There was an issue sending..."
            // alert. Prefer PostgrestError.message (server-supplied) over
            // localizedDescription (which is often "The operation couldn't
            // be completed.") and fall back to the raw error description if
            // neither is human-readable.
            lastCreateChallengeError = Self.extractUserFacingErrorMessage(from: error)
            return nil
        }
    }
    
    /// Fallback: Create challenge via direct table inserts (if RPC is broken)
    private func createChallengeDirectInsert(
        opponentId: UUID, type: ChallengeType, title: String, description: String?,
        dailyTarget: Int?, totalTarget: Int?, targetUnit: String,
        startDateStr: String, durationDays: Int
    ) async -> UUID? {
        guard let currentUserId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("No current user for direct insert", category: .social)
            return nil
        }
        
        let challengeId = UUID()
        let endDate: String
        if let start = ChallengeFormatters.dateOnly.date(from: startDateStr) {
            endDate = ChallengeFormatters.dateOnly.string(from: Calendar.current.date(byAdding: .day, value: durationDays, to: start) ?? start)
        } else {
            endDate = startDateStr
        }
        
        // Detect mode from title prefix
        let mode = title.hasPrefix("🤝") ? "accountability" : "competition"
        
        do {
            // Step 1: Insert into group_challenges
            struct ChallengeInsert: Encodable {
                let id: String
                let created_by: String
                let challenge_type: String
                let title: String
                let description: String?
                let mode: String
                let daily_target: Int?
                let total_target: Int?
                let target_unit: String
                let start_date: String
                let end_date: String
                let duration_days: Int
                let status: String
                let creator_timezone: String
            }
            
            let challenge = ChallengeInsert(
                id: challengeId.uuidString,
                created_by: currentUserId.uuidString,
                challenge_type: type.rawValue,
                title: title,
                description: description,
                mode: mode,
                daily_target: dailyTarget,
                total_target: totalTarget,
                target_unit: targetUnit,
                start_date: startDateStr,
                end_date: endDate,
                duration_days: durationDays,
                status: "pending",
                creator_timezone: TimeZone.current.identifier
            )
            
            AppLogger.debug("Direct insert: group_challenges...", category: .social)
            try await SupabaseManager.shared.supabaseClient
                .from("group_challenges")
                .insert(challenge)
                .execute()
            AppLogger.info("group_challenges row created: \(challengeId)", category: .social)
            
            // Step 2: Insert creator + opponent participants
            // Note: challenge_participants has NO "role" column
            struct ParticipantInsert: Encodable {
                let challenge_id: String
                let user_id: String
                let status: String
                let total_progress: Int
                let days_completed: Int
                let current_streak: Int
                let best_streak: Int
                let notify_on_opponent_complete: Bool
            }
            
            let creatorParticipant = ParticipantInsert(
                challenge_id: challengeId.uuidString,
                user_id: currentUserId.uuidString,
                status: "accepted",
                total_progress: 0, days_completed: 0, current_streak: 0, best_streak: 0,
                notify_on_opponent_complete: true
            )
            
            let opponentParticipant = ParticipantInsert(
                challenge_id: challengeId.uuidString,
                user_id: opponentId.uuidString,
                status: "pending",
                total_progress: 0, days_completed: 0, current_streak: 0, best_streak: 0,
                notify_on_opponent_complete: true
            )
            
            AppLogger.debug("Direct insert: challenge_participants...", category: .social)
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("challenge_participants")
                    .insert([creatorParticipant, opponentParticipant])
                    .execute()
                AppLogger.info("Both participants created", category: .social)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Participant insert failed — cleaning up orphaned challenge \(challengeId)",
                    category: .social,
                    op: PerformanceSignposts.Op.challengeWrite.rawValue,
                    endpoint: "challenge_participants(insert)",
                    userId: currentUserId
                )
                try? await SupabaseManager.shared.supabaseClient
                    .from("group_challenges")
                    .delete()
                    .eq("id", value: challengeId.uuidString)
                    .execute()
                throw error
            }
            
            // Step 3: Queue push notification (non-critical)
            do {
                struct NotificationInsert: Encodable {
                    let recipient_user_id: String
                    let notification_type: String
                    let title: String
                    let body: String
                    let data: [String: String]
                    let status: String
                }
                
                let notification = NotificationInsert(
                    recipient_user_id: opponentId.uuidString,
                    notification_type: "challenge_invite",
                    title: "You've been challenged! 🏆",
                    body: "Accept the \"\(title)\" challenge!",
                    data: [
                        "type": "challenge_invite",
                        "challenge_id": challengeId.uuidString,
                        "from_user_id": currentUserId.uuidString,
                        "challenge_type": type.rawValue,
                        "challenge_title": title
                    ],
                    status: "pending"
                )
                
                try await SupabaseManager.shared.supabaseClient
                    .from("push_notification_queue")
                    .insert(notification)
                    .execute()
                AppLogger.info("Push notification queued", category: .social)
            } catch {
                AppLogger.warning("Failed to queue notification (non-critical): \(error.localizedDescription)", category: .social)
            }
            
            AppLogger.info("Direct insert challenge created: \(challengeId)", category: .social)
            return challengeId
            
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Direct insert fallback failed",
                category: .social,
                op: PerformanceSignposts.Op.challengeWrite.rawValue,
                endpoint: "group_challenges(insert)",
                userId: currentUserId
            )
            // Phase 2 — capture the same error message here so the user
            // sees the real problem even when the RPC + direct-insert paths
            // both fail. RPC error wins if it was already set (the RPC is
            // the canonical write path); otherwise the direct-insert error
            // becomes the user-facing message.
            if lastCreateChallengeError == nil {
                lastCreateChallengeError = Self.extractUserFacingErrorMessage(from: error)
            }
            return nil
        }
    }

    /// Phase 2 helper — turn a Supabase / URLSession error into a sentence
    /// the Send Challenge alert can show without exposing raw stack frames
    /// or PostgrestError struct dumps.
    ///
    /// Priority (most-specific to most-generic):
    ///   1. `PostgrestError.message` (server-supplied human text:
    ///      "Opponent not found", "Cannot challenge yourself",
    ///      "Not authenticated", "JWT expired", etc.)
    ///   2. `URLError` → friendly network copy (offline, timeout, no DNS)
    ///   3. `NSError` `localizedDescription` if it looks human-readable
    ///   4. The raw `String(describing:)` as a final fallback so triage
    ///      still gets *something*.
    static func extractUserFacingErrorMessage(from error: Error) -> String {
        // PostgrestError exposes `.message` reliably across the supabase-swift
        // versions we ship (it's the message field on the Codable struct
        // returned by PostgREST). Reflection avoids importing the type at
        // every call site.
        let mirror = Mirror(reflecting: error)
        for child in mirror.children {
            if child.label == "message", let msg = child.value as? String, !msg.isEmpty {
                // Strip the "ERROR:  42501: " prefix Postgres adds to RLS
                // / RAISE EXCEPTION messages so the alert reads naturally.
                let cleaned = msg
                    .replacingOccurrences(of: #"^ERROR:\s+\d+:\s+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You're offline. Reconnect and try again."
            case .timedOut:
                return "The server took too long to respond. Try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Couldn't reach the server. Try again in a moment."
            default:
                return urlErr.localizedDescription
            }
        }

        let ns = error as NSError
        let localized = ns.localizedDescription
        if !localized.isEmpty,
           !localized.contains("operation couldn") /* "The operation couldn't be completed." — useless */ {
            return localized
        }

        return String(describing: error)
    }
    
    /// Post-creation tasks (logging, syncing, etc.)
    private func postChallengeCreation(challengeId: UUID, opponentId: UUID, type: ChallengeType, targetUnit: String, startDate: Date) async {
        logger.log(.info, category: .challenge, message: "🏆 Challenge CREATED", metadata: [
            "challenge_id": challengeId.uuidString.prefix(8),
            "opponent_id": opponentId.uuidString.prefix(8),
            "type": type.rawValue,
            "unit": targetUnit
        ])
        AppLogger.info("Created challenge: \(challengeId)", category: .social)
        
        // Log interaction for friend ranking
        await FriendRankingService.shared.logInteraction(
            withFriendId: opponentId,
            type: .challengeCreated,
            referenceId: challengeId,
            referenceType: "challenge"
        )
        
        // Update daily quest progress for sending a challenge
        await DailyQuestService.shared.onChallengeSent()
        
        // Refresh PENDING sent challenges (NOT active - challenge is pending until opponent accepts)
        await fetchPendingSentChallenges()
        
        // IMPORTANT: Sync creator's existing progress if challenge starts today or earlier.
        // This is fire-and-forget — the work is HK force-sync + Strava check + multi-source
        // progress calc + logProgress server roundtrip (3-10s under network pressure). Blocking
        // the send-button spinner on it produces the "took forever" feel reported in
        // 1.38 (56) logs (S963 visible 77s; user shook the phone). Realtime + the next
        // BG / HK observer sync will reflect any landed progress within seconds anyway,
        // and `fetchPendingSentChallenges` (above) already updated the dashboard list.
        // QP invariants 19c/19d/19e: split user-visible work from background-sync work.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let challengeStartDay = calendar.startOfDay(for: startDate)

        if challengeStartDay <= today {
            AppLogger.debug("Challenge starts today - scheduling creator's existing progress sync (fire-and-forget)", category: .social)
            Task { [weak self] in
                await self?.syncCreatorProgressOnCreate(
                    challengeId: challengeId,
                    challengeType: type,
                    targetUnit: targetUnit
                )
            }
        }

        PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "challenge_created")
    }
    
    // MARK: - Create Group Challenge
    
    func createGroupChallenge(
        memberIds: [UUID],
        type: ChallengeType,
        title: String,
        description: String? = nil,
        mode: String = "competition",
        dailyTarget: Int? = nil,
        totalTarget: Int? = nil,
        targetUnit: String = "count",
        startDate: Date = Date(),
        durationDays: Int = 7
    ) async -> UUID? {
        let startDateStr = ChallengeFormatters.dateOnly.string(from: startDate)
        
        // Try RPC first
        do {
            struct CreateGroupParams: Encodable {
                let p_member_ids: [String]
                let p_challenge_type: String
                let p_title: String
                let p_description: String?
                let p_mode: String
                let p_daily_target: Int?
                let p_total_target: Int?
                let p_target_unit: String
                let p_start_date: String
                let p_duration_days: Int
                let p_timezone: String
            }
            
            let params = CreateGroupParams(
                p_member_ids: memberIds.map { $0.uuidString },
                p_challenge_type: type.rawValue,
                p_title: title,
                p_description: description,
                p_mode: mode,
                p_daily_target: dailyTarget,
                p_total_target: totalTarget,
                p_target_unit: targetUnit,
                p_start_date: startDateStr,
                p_duration_days: durationDays,
                p_timezone: TimeZone.current.identifier
            )
            
            AppLogger.debug("Calling create_group_challenge RPC with \(memberIds.count) members...", category: .social)
            
            let groupId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("create_group_challenge", params: params)
                .execute()
                .value
            
            AppLogger.info("Created group challenge: \(groupId)", category: .social)
            
            for memberId in memberIds {
                await FriendRankingService.shared.logInteraction(
                    withFriendId: memberId,
                    type: .challengeCreated,
                    referenceId: groupId,
                    referenceType: "group_challenge"
                )
            }
            
            await fetchActiveGroupChallenges()
            
            PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "group_challenge_created")
            
            return groupId
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "RPC create_group_challenge failed",
                category: .social,
                op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                endpoint: "rpc/create_group_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
        
        // Fallback: Direct inserts
        AppLogger.warning("Attempting direct insert fallback for group challenge...", category: .social)
        guard let currentUserId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("No current user for group challenge fallback", category: .social)
            return nil
        }
        
        let challengeId = UUID()
        let endDateStr: String = {
            if let start = ChallengeFormatters.dateOnly.date(from: startDateStr) {
                return ChallengeFormatters.dateOnly.string(from: Calendar.current.date(byAdding: .day, value: durationDays, to: start) ?? start)
            }
            return startDateStr
        }()
        
        do {
            struct ChallengeInsert: Encodable {
                let id: String
                let created_by: String
                let challenge_type: String
                let title: String
                let description: String?
                let mode: String
                let daily_target: Int?
                let total_target: Int?
                let target_unit: String
                let start_date: String
                let end_date: String
                let duration_days: Int
                let status: String
                let creator_timezone: String
            }
            
            try await SupabaseManager.shared.supabaseClient
                .from("group_challenges")
                .insert(ChallengeInsert(
                    id: challengeId.uuidString, created_by: currentUserId.uuidString,
                    challenge_type: type.rawValue, title: title, description: description,
                    mode: mode, daily_target: dailyTarget, total_target: totalTarget,
                    target_unit: targetUnit, start_date: startDateStr, end_date: endDateStr,
                    duration_days: durationDays, status: "pending",
                    creator_timezone: TimeZone.current.identifier
                ))
                .execute()
            
            // Note: challenge_participants has NO "role" column
            struct ParticipantInsert: Encodable {
                let challenge_id: String
                let user_id: String
                let status: String
                let total_progress: Int
                let days_completed: Int
                let current_streak: Int
                let best_streak: Int
                let notify_on_opponent_complete: Bool
            }
            
            var participants = [ParticipantInsert(
                challenge_id: challengeId.uuidString, user_id: currentUserId.uuidString,
                status: "accepted",
                total_progress: 0, days_completed: 0, current_streak: 0, best_streak: 0,
                notify_on_opponent_complete: true
            )]
            
            for memberId in memberIds where memberId != currentUserId {
                participants.append(ParticipantInsert(
                    challenge_id: challengeId.uuidString, user_id: memberId.uuidString,
                    status: "pending",
                    total_progress: 0, days_completed: 0, current_streak: 0, best_streak: 0,
                    notify_on_opponent_complete: true
                ))
            }
            
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("challenge_participants")
                    .insert(participants)
                    .execute()
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Group participant insert failed — cleaning up orphaned challenge \(challengeId)",
                    category: .social,
                    op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                    endpoint: "challenge_participants(insert)",
                    userId: currentUserId
                )
                try? await SupabaseManager.shared.supabaseClient
                    .from("group_challenges")
                    .delete()
                    .eq("id", value: challengeId.uuidString)
                    .execute()
                throw error
            }
            
            AppLogger.info("Group challenge created via direct insert: \(challengeId)", category: .social)
            
            for memberId in memberIds {
                await FriendRankingService.shared.logInteraction(
                    withFriendId: memberId,
                    type: .challengeCreated,
                    referenceId: challengeId,
                    referenceType: "group_challenge"
                )
            }
            
            await fetchActiveGroupChallenges()
            return challengeId
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Group challenge direct insert failed",
                category: .social,
                op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                endpoint: "group_challenges(insert)",
                userId: currentUserId
            )
            return nil
        }
    }
    
    // MARK: - Fetch Active Group Challenges
    
    func fetchActiveGroupChallenges() async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("[GROUP] Skipping fetch — not authenticated", category: .social)
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastGroupFetchTime) > fetchMinInterval else {
            AppLogger.debug("[GROUP] Skipping fetch — throttled (\(Int(now.timeIntervalSince(lastGroupFetchTime)))s ago)", category: .social)
            return
        }
        lastGroupFetchTime = now
        AppLogger.debug("[GROUP] Fetching active group challenges via RPC...", category: .social)
        // Sprint 5 M-8: see comment on `fetchActiveChallenges` — same dedupe
        // rationale. Group challenges get a separate key so they don't block
        // each other.
        await RequestCoalescer.shared.coalesceVoid(key: "fetchActiveGroupChallenges") { [weak self] in
            await self?._fetchActiveGroupChallengesBody()
        }
    }

    private func _fetchActiveGroupChallengesBody() async {
        do {
            struct TimezoneParams: Encodable {
                let p_timezone: String
            }
            
            let result: [ActiveGroupChallenge] = try await withCancelRetry(label: "group_challenges") {
                try await SupabaseManager.shared.supabaseClient
                    .rpc("get_active_group_challenges", params: TimezoneParams(
                        p_timezone: TimeZone.current.identifier
                    ))
                    .execute()
                    .value
            }
            
            activeGroupChallenges = result
            cacheGroupChallenges()
            
            // Preload member photos for instant display on group challenge widgets
            var memberPhotos: [(id: String, url: String?)] = []
            for challenge in result {
                if let members = challenge.members {
                    for m in members {
                        memberPhotos.append((id: m.userId.uuidString, url: m.profilePhotoUrl))
                    }
                }
            }
            if !memberPhotos.isEmpty {
                FriendPhotoCache.shared.preloadPhotos(for: memberPhotos)
            }
            
            AppLogger.info("Fetched \(result.count) active group challenges", category: .social)
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                AppLogger.debug("[GROUP] Fetch cancelled (task cancellation)", category: .social)
                return
            }
            // Preserve existing cached challenges on fetch failure
            _ = NetworkErrorClassifier.log(
                error,
                context: "[GROUP] Fetch failed (keeping \(activeGroupChallenges.count) cached)",
                category: .social,
                op: PerformanceSignposts.Op.challengeRead.rawValue,
                endpoint: "rpc/get_active_group_challenges",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }
    
    // MARK: - Accept/Decline Group Challenge
    
    func acceptGroupChallenge(challengeId: UUID) async -> Bool {
        do {
            struct AcceptParams: Encodable { let p_challenge_id: String }
            let allAccepted: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("accept_group_challenge", params: AcceptParams(p_challenge_id: challengeId.uuidString))
                .execute()
                .value
            
            AppLogger.info("Accepted group challenge: \(challengeId), all accepted: \(allAccepted)", category: .social)
            await fetchActiveGroupChallenges()
            
            // IMPORTANT: Sync existing health data immediately after accepting
            // User may already have progress for today (e.g., 4K steps before accepting a 3K step challenge)
            await syncExistingProgressToGroupChallenge(challengeId: challengeId)
            
            // Refresh again to show updated progress
            await fetchActiveGroupChallenges()
            
            // Update app icon badge after clearing a pending invite
            await MainActor.run { NotificationManager.shared.updateBadgeCount() }
            
            return allAccepted
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error accepting group challenge",
                category: .social,
                op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                endpoint: "rpc/accept_group_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    func declineGroupChallenge(challengeId: UUID) async {
        do {
            struct DeclineParams: Encodable { let p_challenge_id: String }
            try await SupabaseManager.shared.supabaseClient
                .rpc("decline_group_challenge", params: DeclineParams(p_challenge_id: challengeId.uuidString))
                .execute()
            
            AppLogger.info("Declined group challenge: \(challengeId)", category: .social)
            
            // Remove from local list immediately
            activeGroupChallenges.removeAll { $0.challengeId == challengeId }
            
            // Refresh both — decline may convert to 1v1 for remaining members
            await fetchActiveGroupChallenges()
            await fetchActiveChallenges()
            
            // Update app icon badge after clearing a pending invite
            await MainActor.run { NotificationManager.shared.updateBadgeCount() }
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error declining group challenge",
                category: .social,
                op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                endpoint: "rpc/decline_group_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }
    
    // MARK: - Leave Group Challenge
    
    /// Leave a group challenge. Returns the result: "left", "converted" (to 1v1), or "cancelled"
    func leaveGroupChallenge(challengeId: UUID) async -> String? {
        do {
            struct LeaveParams: Encodable { let p_challenge_id: String }
            let result: String = try await SupabaseManager.shared.supabaseClient
                .rpc("leave_group_challenge", params: LeaveParams(p_challenge_id: challengeId.uuidString))
                .execute()
                .value
            
            AppLogger.info("Left group challenge: \(challengeId), result: \(result)", category: .social)
            
            // Remove from local group challenges
            activeGroupChallenges.removeAll { $0.challengeId == challengeId }
            
            // If converted to 1v1, refresh active challenges so it shows up
            if result == "converted" {
                await fetchActiveChallenges()
            }
            
            // Refresh group challenges
            await fetchActiveGroupChallenges()
            
            return result
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error leaving group challenge",
                category: .social,
                op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                endpoint: "rpc/leave_group_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return nil
        }
    }
    
    // MARK: - Cancel Group Challenge
    
    /// Cancel an entire group challenge — removes everyone
    func cancelGroupChallenge(challengeId: UUID) async -> Bool {
        do {
            struct CancelParams: Encodable { let p_challenge_id: String }
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("cancel_group_challenge", params: CancelParams(p_challenge_id: challengeId.uuidString))
                .execute()
                .value
            
            // Remove from local list
            activeGroupChallenges.removeAll { $0.challengeId == challengeId }
            
            AppLogger.info("Cancelled group challenge: \(challengeId)", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error cancelling group challenge",
                category: .social,
                op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                endpoint: "rpc/cancel_group_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Nudge Group Challenge Member
    
    /// Send a one-time nudge to a pending group challenge member. Returns true if sent, false if already nudged.
    func nudgeGroupChallengeMember(challengeId: UUID, recipientId: UUID) async -> Bool {
        do {
            struct NudgeParams: Encodable {
                let p_challenge_id: String
                let p_recipient_id: String
            }
            let sent: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("nudge_group_challenge_member", params: NudgeParams(
                    p_challenge_id: challengeId.uuidString,
                    p_recipient_id: recipientId.uuidString
                ))
                .execute()
                .value
            
            AppLogger.info("Nudged member \(recipientId) for challenge \(challengeId): \(sent ? "sent" : "already nudged")", category: .social)
            return sent
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error nudging member",
                category: .social,
                op: PerformanceSignposts.Op.challengeGroupWrite.rawValue,
                endpoint: "rpc/nudge_group_challenge_member",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Group Challenge Progress
    
    /// Log progress for a group challenge
    func logGroupProgress(challengeId: UUID, progressValue: Int, allowDecrease: Bool = false) async -> Bool {
        do {
            struct LogParams: Encodable {
                let p_challenge_id: String
                let p_progress: Int
                let p_timezone: String
                let p_allow_decrease: Bool
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("log_group_challenge_progress", params: LogParams(
                    p_challenge_id: challengeId.uuidString,
                    p_progress: progressValue,
                    p_timezone: TimeZone.current.identifier,
                    p_allow_decrease: allowDecrease
                ))
                .execute()
            
            AppLogger.info("Logged group progress: \(progressValue) for \(challengeId)", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error logging group progress",
                category: .social,
                op: PerformanceSignposts.Op.challengeProgressSync.rawValue,
                endpoint: "rpc/log_group_challenge_progress",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    /// Sync existing health data immediately after accepting a group challenge
    private func syncExistingProgressToGroupChallenge(challengeId: UUID) async {
        AppLogger.debug("Syncing existing progress for group challenge \(challengeId)...", category: .social)
        
        // Refresh HealthKit data first
        await HealthKitService.shared.syncAllData(force: true)
        
        // Find this group challenge
        guard let challenge = activeGroupChallenges.first(where: { $0.challengeId == challengeId }) else {
            AppLogger.warning("Could not find group challenge in active list", category: .social)
            return
        }
        
        // Calculate progress from all health data sources
        let progressValue = await calculateTotalProgressFromAllSources(
            challengeType: challenge.challengeType,
            targetUnit: challenge.targetUnit
        )
        
        if progressValue > 0 {
            AppLogger.debug("Found existing progress: \(progressValue) \(challenge.targetUnit)", category: .social)
            let success = await logGroupProgress(challengeId: challengeId, progressValue: progressValue)
            if success {
                AppLogger.info("Synced \(progressValue) \(challenge.targetUnit) to group challenge", category: .social)
            }
        } else {
            AppLogger.debug("No existing progress to sync for group challenge", category: .social)
        }
    }
    
    /// Sync HealthKit data to ALL active group challenges (called alongside 1v1 sync)
    func syncHealthKitDataToGroupChallenges() async {
        // Auto-populate the group challenge list if cold so we never skip a
        // push while private / community push. See PrivateChallengeService
        // for full rationale (2026-04-24 Paul cross-surface inconsistency).
        if activeGroupChallenges.isEmpty {
            await fetchActiveGroupChallenges()
        }
        guard !activeGroupChallenges.isEmpty else { return }

        // Force-refresh HealthKit before reading per-challenge values (same
        // dawn-ghost guard as `syncHealthKitDataToChallenges`). Coalescer makes
        // concurrent force-refreshes effectively free.
        await HealthKitService.shared.syncAllData(force: true)

        AppLogger.debug("Syncing HealthKit data to \(activeGroupChallenges.count) active group challenges...", category: .social)

        for challenge in activeGroupChallenges {
            // Sync if user has accepted, even if challenge is still "pending" (waiting for others)
            // This ensures early accepters get credit for progress before all members join
            guard challenge.iHaveAccepted else { continue }
            
            let progressValue = await calculateProgressFromHealthKit(
                challengeType: challenge.challengeType,
                targetUnit: challenge.targetUnit
            )

            let resolvedType = challenge.resolvedType
            let isRecalculable = (resolvedType == .protein ||
                                  resolvedType == .hydrate ||
                                  resolvedType == .calories ||
                                  resolvedType == .steps ||
                                  resolvedType == .activeMinutes)

            if progressValue > 0 || isRecalculable {
                let success = await logGroupProgress(
                    challengeId: challenge.challengeId,
                    progressValue: max(progressValue, 0),
                    allowDecrease: isRecalculable
                )
                if success {
                    AppLogger.info("Synced \(progressValue) \(challenge.targetUnit) to group '\(challenge.displayTitle)'", category: .social)
                }
            }
        }
        
        // Refresh to show updated progress
        await fetchActiveGroupChallenges()
        AppLogger.info("Group challenge HealthKit sync complete", category: .social)
    }
    
    /// Sync creator's existing health data when they create a challenge that starts today
    /// This ensures they get credit for progress already made before creating the challenge
    private func syncCreatorProgressOnCreate(challengeId: UUID, challengeType: ChallengeType, targetUnit: String) async {
        AppLogger.debug("Syncing creator's existing progress for newly created challenge...", category: .social)
        
        // First, refresh HealthKit data to ensure we have the latest
        AppLogger.debug("Refreshing HealthKit data for creator...", category: .social)
        await HealthKitService.shared.syncAllData(force: true)
        
        // Calculate progress from all available health data sources
        let progressValue = await calculateTotalProgressFromAllSources(
            challengeType: challengeType.rawValue,
            targetUnit: targetUnit
        )
        
        if progressValue > 0 {
            AppLogger.debug("Found existing creator progress: \(progressValue) \(targetUnit)", category: .social)
            
            let success = await logProgress(
                challengeId: challengeId,
                progressValue: progressValue,
                source: "healthkit"
            )
            
            if success {
                AppLogger.info("Logged creator's initial progress of \(progressValue) \(targetUnit)", category: .social)
            }
        } else {
            AppLogger.debug("No existing progress to sync for creator", category: .social)
        }
    }
    
    // MARK: - Respond to Challenge
    
    func respondToChallenge(challengeId: UUID, accept: Bool) async -> Bool {
        logger.log(.info, category: .challenge, message: accept ? "⚡ ACCEPTING challenge" : "❌ DECLINING challenge", metadata: [
            "challenge_id": challengeId.uuidString.prefix(8)
        ])
        AppLogger.debug("respondToChallenge called - challengeId: \(challengeId), accept: \(accept)", category: .social)
        do {
            // Get challenge details BEFORE accepting (need type/unit for progress sync)
            let inviteDetails = pendingInvites.first { $0.challengeId == challengeId }
            AppLogger.debug("Invite details: \(inviteDetails?.title ?? "not found")", category: .social)

            // Sprint 5 (C-6): use atomic `accept_challenge` / `decline_challenge`
            // RPCs which take a `SELECT ... FOR UPDATE` on the participant row
            // — fixes double-tap accepts that previously slipped two UPDATE
            // statements past the idempotency check and produced duplicate
            // pushes / flashing UI. The RPCs return a structured jsonb payload
            // so we can distinguish "accepted just now" from "already accepted"
            // and skip the heavy post-accept sync on idempotent replays.
            struct AtomicResponseParams: Encodable { let p_challenge_id: String }
            struct AtomicResponse: Decodable {
                let status: String
                let all_accepted: Bool?
                let cancelled: Bool?
                let challenge_status: String?
                let message: String?
            }

            let rpcName = accept ? "accept_challenge" : "decline_challenge"
            AppLogger.debug("Calling \(rpcName) RPC (atomic, C-6)...", category: .social)
            let response: AtomicResponse = try await SupabaseManager.shared.supabaseClient
                .rpc(rpcName, params: AtomicResponseParams(p_challenge_id: challengeId.uuidString))
                .execute()
                .value
            AppLogger.info("\(rpcName) RPC -> status=\(response.status)", category: .social)

            switch response.status {
            case "not_found":
                AppLogger.warning("\(rpcName): challenge not found (\(response.message ?? "n/a"))", category: .social)
                return false
            case "cancelled":
                AppLogger.info("\(rpcName): challenge already cancelled server-side; clearing local pending", category: .social)
                await MainActor.run { pendingInvites.removeAll { $0.challengeId == challengeId } }
                await fetchPendingInvites()
                return false
            case "already_accepted":
                AppLogger.debug("\(rpcName): server reports already accepted — treating as idempotent success", category: .social)
            case "already_declined":
                AppLogger.debug("\(rpcName): server reports already declined — treating as idempotent success", category: .social)
            default:
                break
            }
            
            // Force refresh from server to ensure UI updates properly
            await MainActor.run {
                // Clear locally first
                pendingInvites.removeAll { $0.challengeId == challengeId }
                AppLogger.debug("Removed challenge from pending invites locally", category: .social)
            }
            
            if accept {
                AppLogger.info("[ACCEPT FLOW] Step 1: RPC successful - starting data refresh", category: .social)
                
                // Fetch fresh data from server (both 1v1 AND group challenges)
                await fetchPendingInvites()
                await fetchActiveChallenges()
                await fetchActiveGroupChallenges()  // CRITICAL: Group challenge may have been accepted via 1v1 path
                await fetchPendingSentChallenges()
                
                AppLogger.debug("[ACCEPT FLOW] Step 2: After initial fetch - Active 1v1: \(activeChallenges.count), Active Group: \(activeGroupChallenges.count), myToday: \(activeChallenges.first?.myTodayProgress ?? -1), oppToday: \(activeChallenges.first?.opponentTodayProgress ?? -1)", category: .social)
                
                // IMPORTANT: Sync existing progress from today
                AppLogger.debug("[ACCEPT FLOW] Step 3: Syncing existing HealthKit progress...", category: .social)
                await syncExistingProgressOnAccept(challengeId: challengeId, inviteDetails: inviteDetails)
                
                // Also sync group challenge progress if this was a group challenge
                await syncExistingProgressToGroupChallenge(challengeId: challengeId)
                
                // Fetch AGAIN after syncing our progress so the widget shows updated numbers
                AppLogger.debug("[ACCEPT FLOW] Step 4: Fetching active challenges AGAIN after progress sync...", category: .social)
                await fetchActiveChallenges()
                await fetchActiveGroupChallenges()
                
                AppLogger.debug("[ACCEPT FLOW] Step 5: Final state - Active 1v1: \(activeChallenges.count), Active Group: \(activeGroupChallenges.count), myToday: \(activeChallenges.first?.myTodayProgress ?? -1), oppToday: \(activeChallenges.first?.opponentTodayProgress ?? -1)", category: .social)
                AppLogger.info("[ACCEPT FLOW] Complete - widget should now show correct progress", category: .social)
            } else {
                AppLogger.info("Declined challenge - refreshing pending invites", category: .social)
                await fetchPendingInvites()  // Refresh to remove the declined one
            }
            
            await MainActor.run { NotificationManager.shared.updateBadgeCount() }
            
            PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: accept ? "challenge_accepted" : "challenge_declined")
            
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error responding to challenge",
                category: .social,
                op: PerformanceSignposts.Op.challengeWrite.rawValue,
                endpoint: "rpc/respond_to_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    /// Sync existing health data when a challenge is accepted
    /// This ensures users get credit for progress already made today
    private func syncExistingProgressOnAccept(challengeId: UUID, inviteDetails: ChallengeInvite?) async {
        AppLogger.debug("Syncing existing progress for newly accepted challenge...", category: .social)
        
        // First, refresh HealthKit data to ensure we have the latest
        AppLogger.debug("Refreshing HealthKit data...", category: .social)
        await HealthKitService.shared.syncAllData(force: true)
        
        // Also refresh Strava if connected
        if StravaService.shared.isConnected {
            AppLogger.debug("Refreshing Strava data...", category: .social)
            await StravaService.shared.syncActivities(force: true)
        }
        
        // Find the accepted challenge in our active list
        guard let challenge = activeChallenges.first(where: { $0.challengeId == challengeId }) else {
            AppLogger.warning("Could not find accepted challenge in active list", category: .social)
            return
        }
        
        // Calculate progress from all available health data sources
        let progressValue = await calculateTotalProgressFromAllSources(
            challengeType: challenge.challengeType,
            targetUnit: challenge.targetUnit
        )
        
        if progressValue > 0 {
            AppLogger.debug("Found existing progress: \(progressValue) \(challenge.targetUnit)", category: .social)
            
            let success = await logProgress(
                challengeId: challengeId,
                progressValue: progressValue,
                source: "healthkit"
            )
            
            if success {
                AppLogger.info("Logged initial progress of \(progressValue) \(challenge.targetUnit) for '\(challenge.title)'", category: .social)
                
                // Check if this already meets the daily target
                if progressValue >= (challenge.dailyTarget ?? 0) {
                    AppLogger.info("User already met daily target! (\(progressValue)/\(challenge.dailyTarget ?? 0))", category: .social)
                }
            }
        } else {
            AppLogger.debug("No existing progress to sync for this challenge type", category: .social)
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
        AppLogger.verbose("HealthKit progress: \(healthKitProgress)", category: .social)
        
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
        AppLogger.verbose("Strava progress: \(stravaProgress)", category: .social)
        
        AppLogger.verbose("Total progress from all sources: \(totalProgress)", category: .social)
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
            
            AppLogger.info("Challenge cancelled successfully", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error cancelling challenge",
                category: .social,
                op: PerformanceSignposts.Op.challengeWrite.rawValue,
                endpoint: "rpc/cancel_challenge",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Log Progress
    
    func logProgress(
        challengeId: UUID,
        progressValue: Int,
        date: Date? = nil,
        source: String = "manual",
        workoutId: UUID? = nil,
        allowDecrease: Bool = false
    ) async -> Bool {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("[CHALLENGE] Skipping logProgress — not authenticated (source: \(source), challenge: \(challengeId.uuidString.prefix(8)))", category: .social)
            return false
        }
        
        struct LogProgressParams: Encodable {
            let p_challenge_id: String
            let p_progress_value: Int
            let p_progress_date: String?
            let p_source: String
            let p_workout_id: String?
            let p_timezone: String
            let p_allow_decrease: Bool
        }
        
        // When date is nil (default), let the SERVER determine "today" using
        // the challenge's stored creator_timezone. This ensures both participants
        // see the same day boundary (midnight in the creator's timezone).
        // Only pass an explicit date for simulator/backfill scenarios.
        let dateStr: String? = date.map { ChallengeFormatters.localDateOnly.string(from: $0) }
        
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                let _: Bool = try await SupabaseManager.shared.supabaseClient
                    .rpc("log_challenge_progress", params: LogProgressParams(
                        p_challenge_id: challengeId.uuidString,
                        p_progress_value: progressValue,
                        p_progress_date: dateStr,
                        p_source: source,
                        p_workout_id: workoutId?.uuidString,
                        p_timezone: TimeZone.current.identifier,
                        p_allow_decrease: allowDecrease
                    ))
                    .execute()
                    .value
                
                AppLogger.info("Logged \(progressValue) (source: \(source)) for challenge \(challengeId.uuidString.prefix(8))", category: .social)
                
                // Refresh active challenges to show updated progress
                await fetchActiveChallenges()
                
                // Log what the widget will now show
                if let updated = activeChallenges.first(where: { $0.challengeId == challengeId }) {
                    AppLogger.verbose("After refresh → myToday: \(updated.myTodayProgress ?? -1), oppToday: \(updated.opponentTodayProgress ?? -1), myTotal: \(updated.myTotalProgress), oppTotal: \(updated.opponentTotalProgress)", category: .social)
                }
                
                return true
            } catch {
                guard !Task.isCancelled else {
                    AppLogger.debug("log_challenge_progress task cancelled, stopping retries", category: .social)
                    return false
                }
                let nsError = error as NSError
                let errorDesc = error.localizedDescription
                
                // "Not authenticated" from server means session expired — don't retry
                if errorDesc.localizedCaseInsensitiveContains("not authenticated") || errorDesc.localizedCaseInsensitiveContains("JWT") {
                    AppLogger.warning("[CHALLENGE] logProgress auth expired (challenge: \(challengeId.uuidString.prefix(8)), source: \(source))", category: .social)
                    return false
                }
                
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    AppLogger.warning("log_challenge_progress cancelled (attempt \(attempt)/\(maxRetries)), retrying in \(Double(delay) / 1_000_000_000)s...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "[CHALLENGE] logProgress failed (attempt \(attempt)/\(maxRetries), source: \(source))",
                        category: .social,
                        op: PerformanceSignposts.Op.challengeProgressSync.rawValue,
                        endpoint: "rpc/log_challenge_progress",
                        userId: SupabaseManager.shared.currentUser?.id,
                        retryAttempt: attempt
                    )
                    return false
                }
            }
        }
        return false
    }
    
    // MARK: - HealthKit Auto-Sync
    
    /// Sync HealthKit data to all active challenges
    /// Call this when HealthKit data updates (steps, workouts, active minutes)
    func syncHealthKitDataToChallenges() async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("[CHALLENGE SYNC] Skipping HK sync — not authenticated", category: .social)
            return
        }
        // Auto-populate the 1v1 challenge list if cold so we never skip a
        // push while private / community go through — cross-surface
        // consistency guard (2026-04-24 Paul bug).
        if activeChallenges.isEmpty {
            await fetchActiveChallenges()
        }
        guard !activeChallenges.isEmpty else {
            AppLogger.debug("No active challenges to sync", category: .social)
            return
        }
        
        #if DEBUG
        syncAttemptCount += 1
        #endif
        if isChallengeSyncing {
            #if DEBUG
            syncThrottledCount += 1
            #endif
            AppLogger.debug("⏭️ [CHALLENGE SYNC] Skipping HK sync — already in progress", category: .social)
            return
        }
        if let lastSync = lastChallengeSyncDate,
           Date().timeIntervalSince(lastSync) < Self.challengeSyncThrottleInterval {
            #if DEBUG
            syncThrottledCount += 1
            #endif
            AppLogger.debug("⏭️ [CHALLENGE SYNC] Skipping HK sync — synced \(Int(Date().timeIntervalSince(lastSync)))s ago", category: .social)
            return
        }
        isChallengeSyncing = true
        defer {
            isChallengeSyncing = false
            lastChallengeSyncDate = Date()
            #if DEBUG
            syncCompletedCount += 1
            printSyncAudit()
            #endif
        }
        
        MealService.shared.ensureFreshForToday()

        // Force-refresh HealthKit so `todaySteps` / `todayActiveMinutes` /
        // `todayCalories` reflect the current local day before we push. Dawn
        // bug (2026-04-24): without this, the @Published cache can still hold
        // yesterday's EoD total and the server's GREATEST() clause pins the
        // ghost until midnight. Coalescer makes concurrent force-refreshes free.
        await HealthKitService.shared.syncAllData(force: true)

        let healthKit = HealthKitService.shared

        AppLogger.debug("Syncing HealthKit data to \(activeChallenges.count) active challenges...", category: .social)
        
        for challenge in activeChallenges {
            AppLogger.verbose("Checking challenge '\(challenge.title)' (status: \(challenge.status))", category: .social)
            
            // Sync if challenge is active OR pending (pending means accepted but waiting for start date)
            // This ensures users who accept early get credit for progress made before start date
            guard challenge.status == "active" || challenge.status == "pending" else {
                AppLogger.verbose("Skipping '\(challenge.title)' - status is '\(challenge.status)'", category: .social)
                continue
            }
            
            let progressValue = await calculateProgressFromHealthKit(
                challengeType: challenge.challengeType,
                targetUnit: challenge.targetUnit
            )
            
            AppLogger.verbose("Calculated \(progressValue) \(challenge.targetUnit) for '\(challenge.title)'", category: .social)
            
            // For "recalculable" types (protein, hydration, calories) the local value
            // is authoritative — we MUST log even when 0 so stale yesterday rows
            // get overwritten (e.g. 203g protein from yesterday).
            let resolvedType = challenge.resolvedType
            // steps + activeMinutes added 2026-04-24 (dawn-ghost bug, fingerprint
            // 6be18e3a). HealthKit cumulative counters can @Published-cache yesterday's
            // EoD across midnight; without allowDecrease the server's GREATEST() pins
            // the ghost until next midnight.
            let isRecalculable = (resolvedType == .protein ||
                                  resolvedType == .hydrate ||
                                  resolvedType == .calories ||
                                  resolvedType == .steps ||
                                  resolvedType == .activeMinutes)
            
            if progressValue > 0 || isRecalculable {
                AppLogger.debug("Logging \(progressValue) \(challenge.targetUnit) for '\(challenge.title)' (allowDecrease: \(isRecalculable))...", category: .social)
                let success = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: max(progressValue, 0),
                    source: "healthkit",
                    allowDecrease: isRecalculable
                )
                
                if success {
                    AppLogger.info("Synced \(progressValue) \(challenge.targetUnit) to '\(challenge.title)' from HealthKit", category: .social)
                } else {
                    // 2026-04-26 (bug-intel bb8962ac / 0d1100de): the underlying
                    // `logProgress` already routes the real failure through
                    // `NetworkErrorClassifier.log(...)` with op + endpoint + pg_code,
                    // so a top-level `.error` here is double-reporting and creates
                    // cascade fingerprints whose root cause (e.g. 40P01 deadlock)
                    // is already captured below. Keep the breadcrumb at `.warning`.
                    AppLogger.warning("Failed to sync progress for '\(challenge.title)' (see classifier log for cause)", category: .social)
                }
            } else {
                AppLogger.verbose("Skipping '\(challenge.title)' - progressValue is 0", category: .social)
            }
        }
        
        AppLogger.info("HealthKit sync complete for all 1v1 challenges", category: .social)
        
        // Also sync group challenges
        await syncHealthKitDataToGroupChallenges()
    }
    
    /// Calculate progress value from HealthKit based on challenge type
    private func calculateProgressFromHealthKit(challengeType: String, targetUnit: String) async -> Int {
        let healthKit = HealthKitService.shared
        
        switch challengeType {
        case "steps":
            // Steps challenge - prefer real-time HealthKitManager, fall back to HealthKitService
            let managerSteps = HealthKitManager.shared.todaySteps
            let serviceSteps = healthKit.todaySteps
            return managerSteps > 0 ? managerSteps : serviceSteps
            
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
            
        case "hydrate":
            // Hydration challenge — pull from HydrationService
            let totalMl = HydrationService.shared.todayTotal
            if targetUnit.lowercased() == "oz" {
                return Int(Double(totalMl) / 29.5735)
            }
            return totalMl
            
        case "protein":
            // Protein challenge — pull from MealService
            return MealService.shared.todaysMeals.reduce(0) { $0 + $1.protein }
            
        case "calories":
            // Calorie challenge uses burned calories only (HealthKit active energy)
            return healthKit.todayCalories
            
        default:
            AppLogger.warning("Unknown challenge type: \(challengeType)", category: .social)
            return 0
        }
    }
    
    // MARK: - Universal Tracking Sync
    
    /// Sync ALL tracking data (hydration, meals, HealthKit) to active challenges.
    /// Call this on foreground, after any log event, and periodically.
    func syncAllTrackingToChallenges() async {
        guard !activeChallenges.isEmpty || !activeGroupChallenges.isEmpty else { return }
        
        #if DEBUG
        syncAttemptCount += 1
        #endif
        if isChallengeSyncing {
            #if DEBUG
            syncThrottledCount += 1
            #endif
            AppLogger.debug("⏭️ [CHALLENGE SYNC] Skipping universal sync — already in progress", category: .social)
            return
        }
        if let lastSync = lastChallengeSyncDate,
           Date().timeIntervalSince(lastSync) < Self.challengeSyncThrottleInterval {
            #if DEBUG
            syncThrottledCount += 1
            #endif
            AppLogger.debug("⏭️ [CHALLENGE SYNC] Skipping universal sync — synced \(Int(Date().timeIntervalSince(lastSync)))s ago", category: .social)
            return
        }
        isChallengeSyncing = true
        defer {
            isChallengeSyncing = false
            lastChallengeSyncDate = Date()
            #if DEBUG
            syncCompletedCount += 1
            printSyncAudit()
            #endif
        }
        
        MealService.shared.ensureFreshForToday()
        
        AppLogger.debug("Universal sync: pushing all tracking data to challenges...", category: .social)
        
        // Sync 1v1 challenges
        for challenge in activeChallenges {
            guard challenge.status == "active" || challenge.status == "pending" else { continue }
            
            let resolvedType = challenge.resolvedType
            var progressValue = 0
            var source = "auto_sync"
            
            switch resolvedType {
            case .hydrate:
                let totalMl = HydrationService.shared.todayTotal
                progressValue = challenge.targetUnit.lowercased() == "oz"
                    ? Int(Double(totalMl) / 29.5735)
                    : totalMl
                source = "hydration"
                
            case .protein:
                progressValue = MealService.shared.todaysMeals.reduce(0) { $0 + $1.protein }
                source = "meals"
                
            case .calories:
                progressValue = HealthKitService.shared.todayCalories
                source = "healthkit"
                
            case .steps:
                let steps = HealthKitManager.shared.todaySteps > 0
                    ? HealthKitManager.shared.todaySteps
                    : HealthKitService.shared.todaySteps
                progressValue = steps
                source = "healthkit"
                
            case .activeMinutes:
                progressValue = HealthKitService.shared.todayActiveMinutes
                source = "healthkit"
                
            case .walk, .run:
                progressValue = await calculateProgressFromHealthKit(
                    challengeType: challenge.challengeType,
                    targetUnit: challenge.targetUnit
                )
                source = "healthkit"
                
            case .lift, .workoutStreak:
                progressValue = await calculateProgressFromHealthKit(
                    challengeType: challenge.challengeType,
                    targetUnit: challenge.targetUnit
                )
                source = "healthkit"

            case .sleepHours:
                // Phase 5 wearable challenge — read from ReadinessService.
                // Unit label is "h" so progress is whole hours slept.
                let hours = ReadinessService.shared.todayReadiness.sleepHours ?? 0
                progressValue = Int(hours.rounded())
                source = "readiness"

            case .readinessAverage:
                // Readiness score is already 0–100, matches unit "/ 100".
                progressValue = ReadinessService.shared.todayReadiness.score
                source = "readiness"

            case .strainBudget:
                // WHOOP strain from the previous day cycle (0–21).
                // Non-WHOOP users don't have strain; progress stays 0.
                let strain = ReadinessService.shared.todayReadiness.strainPrev ?? 0
                progressValue = Int(strain.rounded())
                source = "readiness"
            }
            
            // For re-calculable types (protein, hydration, calories) the local value
            // is authoritative — it's freshly computed from today's meals/logs.
            // We MUST use allowDecrease so the DB accepts the correct value even
            // when it's lower than a stale value that was previously logged
            // (e.g. yesterday's protein carried over due to a timing bug).
            // steps + activeMinutes added 2026-04-24 (dawn-ghost bug, fingerprint
            // 6be18e3a). HealthKit cumulative counters can @Published-cache yesterday's
            // EoD across midnight; without allowDecrease the server's GREATEST() pins
            // the ghost until next midnight.
            let isRecalculable = (resolvedType == .protein ||
                                  resolvedType == .hydrate ||
                                  resolvedType == .calories ||
                                  resolvedType == .steps ||
                                  resolvedType == .activeMinutes)
            
            let progressToLog: Int
            if isRecalculable {
                // Trust the local value — it was just recomputed from today's data
                progressToLog = progressValue
            } else {
                // For HealthKit-sourced types (steps, active minutes, workouts),
                // use max of local and server to avoid sending a lower value
                let serverToday = challenge.myTodayProgress ?? 0
                progressToLog = max(progressValue, serverToday)
            }
            
            if progressToLog > 0 || isRecalculable {
                let _ = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: max(progressToLog, 0),
                    source: source,
                    allowDecrease: isRecalculable
                )
            }
        }
        
        // Also sync group challenges
        await syncHealthKitDataToGroupChallenges()
        
        // Refresh to show latest
        await fetchActiveChallenges()
        await fetchActiveGroupChallenges()
        
        // Also sync community challenges
        await CommunityChallengeService.shared.syncAllTrackingToCommunityChallenges()
        
        AppLogger.info("Universal tracking sync complete", category: .social)
    }
    
    /// Quick sync for a SPECIFIC challenge type (called immediately when user logs data).
    /// Much faster than full sync — only touches matching challenges.
    /// Pass `allowDecrease: true` when the value may have gone DOWN (e.g. meal removed).
    func syncTrackingForType(_ type: ChallengeType, value: Int, source: String = "auto_sync", allowDecrease: Bool = false) async {
        // Sync to 1v1 challenges
        let matching = activeChallenges.filter { challenge in
            challenge.resolvedType == type && (challenge.status == "active" || challenge.status == "pending")
        }
        
        // Sync to group challenges too
        let matchingGroup = activeGroupChallenges.filter { challenge in
            challenge.resolvedType == type && challenge.iHaveAccepted
        }
        
        // Always sync to community & private challenges (they have their own tables).
        // Fire these in parallel — they don't block 1v1/group sync below.
        // Always pass allowDecrease: true for community/private — the synced value
        // is the authoritative total for today (e.g. recalculated protein after meal removal),
        // so the DB must accept it even if it's lower than the previous GREATEST() value.
        async let communitySync: () = CommunityChallengeService.shared.syncTrackingForType(type, value: value, source: source, allowDecrease: true)
        async let privateSync: () = PrivateChallengeService.shared.syncTrackingForType(type, value: value, source: source, allowDecrease: true)
        
        guard !matching.isEmpty || !matchingGroup.isEmpty else {
            // No 1v1/group matches, but still wait for community/private
            _ = await (communitySync, privateSync)
            return
        }
        
        let totalCount = matching.count + matchingGroup.count
        AppLogger.debug("Quick sync \(type.rawValue): \(value) \(type.unitLabel) to \(totalCount) challenge(s) (allowDecrease: \(allowDecrease))", category: .social)
        
        for challenge in matching {
            var adjustedValue = value
            // Handle unit conversion for hydration
            if type == .hydrate && challenge.targetUnit.lowercased() == "oz" {
                adjustedValue = Int(Double(value) / 29.5735)
            }
            
            let progressToLog: Int
            if allowDecrease {
                // When decreasing (e.g. meal removed), send the actual value —
                // the DB will accept it because p_allow_decrease=true bypasses GREATEST
                progressToLog = adjustedValue
            } else {
                // Use max of local and server to ensure we never send a value lower
                // than what's already stored (which would be silently ignored by GREATEST
                // in the DB and not trigger a realtime event for the opponent)
                let serverToday = challenge.myTodayProgress ?? 0
                progressToLog = max(adjustedValue, serverToday)
            }
            
            if progressToLog > 0 || allowDecrease {
                let _ = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: max(progressToLog, 0),
                    source: source,
                    allowDecrease: allowDecrease
                )
            }
        }
        
        for group in matchingGroup {
            var adjustedValue = value
            if type == .hydrate && group.targetUnit.lowercased() == "oz" {
                adjustedValue = Int(Double(value) / 29.5735)
            }
            if adjustedValue > 0 || allowDecrease {
                let _ = await logGroupProgress(
                    challengeId: group.challengeId,
                    progressValue: max(adjustedValue, 0),
                    allowDecrease: allowDecrease
                )
            }
        }
        
        // Light refresh — fetch both 1v1 and group to reflect new progress
        async let fetch1v1: () = fetchActiveChallenges()
        async let fetchGroup: () = fetchActiveGroupChallenges()
        _ = await (fetch1v1, fetchGroup)
        
        // Wait for community & private sync started at the top
        _ = await (communitySync, privateSync)
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
        
        AppLogger.debug("Checking Strava \(workoutType) workout against challenges...", category: .social)
        
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
                    AppLogger.info("Logged Strava \(workoutType): \(progressValue) \(challenge.targetUnit) to '\(challenge.title)'", category: .social)
                }
            }
        }
    }
    
    /// Sync a Fit33 workout completion to challenges
    /// Called when a workout is finished in Fit33
    func syncFit33WorkoutToChallenge(workoutType: String) async {
        guard !activeChallenges.isEmpty else { return }
        
        AppLogger.debug("Checking Fit33 \(workoutType) workout against challenges...", category: .social)
        
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
                    AppLogger.info("Logged Fit33 \(workoutType) workout to '\(challenge.title)'", category: .social)
                }
            }
        }
    }
    
    // MARK: - Multi-Source Challenge Integration
    
    /// Log progress from any source (Fitbit, Strava, HealthKit, etc.)
    /// This is called by HealthDataService to sync all sources to challenges
    func logProgressFromSource(challengeType: String, progressValue: Int, source: String) async {
        guard progressValue > 0 else { return }
        
        // 1v1 challenges
        for challenge in activeChallenges {
            guard challenge.status == "active" else { continue }
            guard challenge.challengeType == challengeType else { continue }
            
            let success = await logProgress(
                challengeId: challenge.challengeId,
                progressValue: progressValue,
                source: source
            )
            
            if success {
                AppLogger.info("Logged \(source) \(challengeType): \(progressValue) to '\(challenge.title)'", category: .social)
            }
        }
        
        // Group challenges
        for challenge in activeGroupChallenges {
            guard challenge.isActive, challenge.iHaveAccepted else { continue }
            guard challenge.challengeType == challengeType else { continue }
            
            let success = await logGroupProgress(
                challengeId: challenge.challengeId,
                progressValue: progressValue
            )
            
            if success {
                AppLogger.info("Logged \(source) \(challengeType): \(progressValue) to group '\(challenge.displayTitle)'", category: .social)
            }
        }
    }
    
    /// Recalculate progress for all active challenges from all sources
    /// Called after all health data sources have synced
    func recalculateAllChallengeProgress() async {
        guard !activeChallenges.isEmpty else { return }
        
        #if DEBUG
        syncAttemptCount += 1
        #endif
        if isChallengeSyncing {
            #if DEBUG
            syncThrottledCount += 1
            #endif
            AppLogger.debug("⏭️ [CHALLENGE SYNC] Skipping recalculate — sync in progress", category: .social)
            return
        }
        if let lastSync = lastChallengeSyncDate,
           Date().timeIntervalSince(lastSync) < Self.challengeSyncThrottleInterval {
            #if DEBUG
            syncThrottledCount += 1
            #endif
            AppLogger.debug("⏭️ [CHALLENGE SYNC] Skipping recalculate — synced \(Int(Date().timeIntervalSince(lastSync)))s ago", category: .social)
            return
        }
        isChallengeSyncing = true
        defer {
            isChallengeSyncing = false
            lastChallengeSyncDate = Date()
            #if DEBUG
            syncCompletedCount += 1
            printSyncAudit()
            #endif
        }
        
        MealService.shared.ensureFreshForToday()
        
        AppLogger.debug("Recalculating progress for \(activeChallenges.count) challenges...", category: .social)
        
        let eligible = activeChallenges.filter { $0.status == "active" || $0.status == "pending" }
        
        for (index, challenge) in eligible.enumerated() {
            // Calculate total progress from ALL sources
            let totalProgress = await calculateTotalProgressFromAllSources(
                challengeType: challenge.challengeType,
                targetUnit: challenge.targetUnit
            )
            
            // For "recalculable" types (protein, hydration, calories) the local value
            // is authoritative — we MUST log even when 0 so stale yesterday rows
            // get overwritten (e.g. 203g protein from yesterday).
            let resolvedType = challenge.resolvedType
            // steps + activeMinutes added 2026-04-24 (dawn-ghost bug, fingerprint
            // 6be18e3a). HealthKit cumulative counters can @Published-cache yesterday's
            // EoD across midnight; without allowDecrease the server's GREATEST() pins
            // the ghost until next midnight.
            let isRecalculable = (resolvedType == .protein ||
                                  resolvedType == .hydrate ||
                                  resolvedType == .calories ||
                                  resolvedType == .steps ||
                                  resolvedType == .activeMinutes)
            
            if totalProgress > 0 || isRecalculable {
                let _ = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: max(totalProgress, 0),
                    source: "healthkit",
                    allowDecrease: isRecalculable
                )
                
                // Small delay between RPCs to avoid overwhelming URLSession connections
                if index < eligible.count - 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                }
            }
        }
        
        // Refresh challenges to show updated progress
        await fetchActiveChallenges()
        
        AppLogger.info("All challenge progress recalculated", category: .social)
    }
    
    // MARK: - Get Challenge Details
    
    func getChallengeDetails(challengeId: UUID) async -> ChallengeDetails? {
        let startedAt = Date()
        let userId = SupabaseManager.shared.currentUser?.id
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
            // Cluster E noise-suppression (fingerprint 6f90ec9a): this RPC is
            // fired from the challenge detail sheet's `.task`; dismissing the
            // sheet before it resolves surfaces `NSURLError -999 (cancelled)`.
            // Logging at `.error` fingerprinted every dismiss. Route through
            // NetworkErrorClassifier so cancelled/transient land at `.warning`
            // and only genuine RPC failures stay at `.error` (QP invariants 25 + 25a).
            _ = NetworkErrorClassifier.log(
                error,
                context: "[Social] Error fetching challenge details",
                category: .social,
                transientLevel: .debug,
                op: "social.get_challenge_details",
                endpoint: "rpc/get_challenge_details",
                startedAt: startedAt,
                userId: userId
            )
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
            
            AppLogger.info("Notification preference updated: \(notify ? "ON" : "OFF")", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error updating notification preference",
                category: .social,
                op: PerformanceSignposts.Op.challengePreferences.rawValue,
                endpoint: "rpc/toggle_challenge_notification_preference",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Get Challenges With Friend
    
    func getChallengesWithFriend(friendId: UUID) async -> [FriendChallenge] {
        struct FriendParams: Encodable {
            let p_friend_id: String
        }
        
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                let result: [FriendChallenge] = try await SupabaseManager.shared.supabaseClient
                    .rpc("get_challenges_with_friend", params: FriendParams(p_friend_id: friendId.uuidString))
                    .execute()
                    .value
                
                return result
            } catch {
                guard !Task.isCancelled else { return [] }
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCancelled)
                if isTimeout && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    AppLogger.warning("getChallengesWithFriend timeout (attempt \(attempt)/\(maxRetries)), retrying...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error fetching challenges with friend",
                        category: .social,
                        op: PerformanceSignposts.Op.challengeRead.rawValue,
                        endpoint: "rpc/get_challenges_with_friend",
                        userId: SupabaseManager.shared.currentUser?.id,
                        retryAttempt: attempt
                    )
                }
            }
        }
        return []
    }
}

// MARK: - Challenge Progress Resolver
/// Resolves live "my today" progress from the corresponding tracking service for each challenge type.
/// Use this to show real-time progress on challenge widgets instead of stale server data.
/// Must be @MainActor because the services it reads from publish on the main actor.
@MainActor
class ChallengeProgressResolver: ObservableObject {
    static let shared = ChallengeProgressResolver()
    
    private init() {}
    
    static func resolveProgress(challengeType: ChallengeType, targetUnit: String, serverValue: Int) -> Int {
        let localValue: Int
        var localHasData = false
        
        switch challengeType {
        case .steps:
            // Bug-intel 80234a6b (2026-04-27): use the day-boundary-gated
            // accessor so a stale pre-midnight cache returns 0 instead of
            // yesterday's count. `effectiveTodaySteps` returns 0 when
            // HealthKitManager's `todaySteps` was last fetched on a
            // different local calendar day — preventing the
            // "4,253 steps at 4:12 AM" perceived regression.
            let managerSteps = HealthKitManager.shared.effectiveTodaySteps
            if managerSteps > 0 {
                localValue = managerSteps
                localHasData = true
            } else {
                let serviceSyncedToday = HealthKitService.shared.lastSyncDate.map { Calendar.current.isDateInToday($0) } ?? false
                localValue = serviceSyncedToday ? HealthKitService.shared.todaySteps : 0
                localHasData = serviceSyncedToday
            }
            
        case .hydrate:
            let totalMl = HydrationService.shared.todayTotal
            if targetUnit.lowercased() == "oz" {
                localValue = Int(Double(totalMl) / 29.5735)
            } else {
                localValue = totalMl
            }
            localHasData = true
            
        case .protein:
            localValue = MealService.shared.todaysMeals.reduce(0) { $0 + $1.protein }
            localHasData = true
            
        case .calories:
            localValue = HealthKitService.shared.todayCalories
            localHasData = HealthKitService.shared.lastSyncDate.map { Calendar.current.isDateInToday($0) } ?? false
            
        case .activeMinutes:
            localValue = HealthKitService.shared.todayActiveMinutes
            localHasData = HealthKitService.shared.lastSyncDate.map { Calendar.current.isDateInToday($0) } ?? false
            
        case .walk, .run:
            if targetUnit.lowercased().contains("min") {
                localValue = HealthKitService.shared.todayActiveMinutes
            } else {
                let km = HealthKitService.shared.todayDistance / 1000.0
                localValue = Int(km.rounded())
            }
            localHasData = HealthKitService.shared.lastSyncDate.map { Calendar.current.isDateInToday($0) } ?? false
            
        case .lift, .workoutStreak:
            localValue = 0

        case .sleepHours:
            // Wearable-sourced: hours slept last night from ReadinessService.
            let readiness = ReadinessService.shared.todayReadiness
            localValue = Int((readiness.sleepHours ?? 0).rounded())
            localHasData = readiness.hasWearableSignal && readiness.sleepHours != nil

        case .readinessAverage:
            // Wearable-sourced: today's readiness score (0–100).
            let readiness = ReadinessService.shared.todayReadiness
            localValue = readiness.score
            localHasData = readiness.hasWearableSignal

        case .strainBudget:
            // WHOOP-only: previous cycle strain. Other wearables → 0.
            let readiness = ReadinessService.shared.todayReadiness
            localValue = Int((readiness.strainPrev ?? 0).rounded())
            localHasData = readiness.strainPrev != nil
        }
        
        if localHasData {
            return localValue
        }
        return max(localValue, serverValue)
    }
    
    func liveProgress(for challenge: ActiveChallenge) -> Int {
        Self.resolveProgress(
            challengeType: challenge.resolvedType,
            targetUnit: challenge.targetUnit,
            serverValue: challenge.myTodayProgress ?? 0
        )
    }
    
    /// Returns a formatted string for the live progress + unit
    func formattedProgress(for challenge: ActiveChallenge) -> String {
        let value = liveProgress(for: challenge)
        return formatValue(value, unit: challenge.targetUnit, type: challenge.resolvedType)
    }
    
    /// Formats a progress value with the appropriate unit label
    func formatValue(_ value: Int, unit: String, type: ChallengeType) -> String {
        switch type {
        case .hydrate:
            if unit.lowercased() == "oz" {
                return "\(value) oz"
            }
            if value >= 1000 {
                return String(format: "%.1fL", Double(value) / 1000)
            }
            return "\(value) ml"
        case .protein:
            return "\(value)g"
        case .calories:
            if value >= 10000 {
                return String(format: "%.1fk", Double(value) / 1000)
            }
            return "\(value) cal"
        case .steps:
            if value >= 10000 {
                return String(format: "%.1fk", Double(value) / 1000)
            }
            return value.formatted()
        default:
            if value >= 10000 {
                return String(format: "%.1fk", Double(value) / 1000)
            }
            return value.formatted()
        }
    }
    
    /// Progress percentage (0.0–1.0) based on live data vs daily target
    func progressPercentage(for challenge: ActiveChallenge) -> Double {
        guard let target = challenge.dailyTarget, target > 0 else { return 0 }
        let value = Double(liveProgress(for: challenge))
        return min(1.0, value / Double(target))
    }
    
    // MARK: - Group Challenge Live Progress
    
    /// Returns live "my today" progress for a group challenge, using the same
    /// HealthKit / tracking-service data that the 1v1 resolver uses.
    /// Always returns max(local, server) so the displayed value is never lower
    /// than what the server has — keeps all devices consistent.
    func liveProgress(for challenge: ActiveGroupChallenge, serverValue: Int = 0) -> Int {
        Self.resolveProgress(
            challengeType: challenge.resolvedType,
            targetUnit: challenge.targetUnit,
            serverValue: serverValue
        )
    }
    
    // MARK: - Community Challenge Live Progress
    
    /// Returns live "my today" progress for a community challenge, using local
    /// HealthKit / tracking-service data. Always returns max(local, server) so
    /// the displayed value is never lower than what the server has.
    func liveProgress(for challenge: CommunityChallenge) -> Int {
        Self.resolveProgress(
            challengeType: challenge.resolvedType,
            targetUnit: challenge.targetUnit,
            serverValue: challenge.myTodayProgress ?? 0
        )
    }
    
    /// Formatted live progress string for a community challenge
    func formattedProgress(for challenge: CommunityChallenge) -> String {
        let value = liveProgress(for: challenge)
        return formatValue(value, unit: challenge.targetUnit, type: challenge.resolvedType)
    }
    
    /// Progress percentage (0.0–1.0) for a community challenge based on live data
    func progressPercentage(for challenge: CommunityChallenge) -> Double {
        guard challenge.dailyTarget > 0 else { return 0 }
        let value = Double(liveProgress(for: challenge))
        return min(1.0, value / Double(challenge.dailyTarget))
    }
    
    // MARK: - Private Challenge Live Progress
    
    /// Returns live "my today" progress for a private challenge, using the same
    /// HealthKit / tracking-service data. Always returns max(local, server).
    func liveProgress(for challenge: PrivateChallenge) -> Int {
        Self.resolveProgress(
            challengeType: challenge.resolvedType,
            targetUnit: challenge.targetUnit,
            serverValue: challenge.myTodayProgress ?? 0
        )
    }
    
    /// Formatted live progress string for a private challenge
    func formattedProgress(for challenge: PrivateChallenge) -> String {
        let value = liveProgress(for: challenge)
        return formatValue(value, unit: challenge.targetUnit, type: challenge.resolvedType)
    }
    
    /// Progress percentage (0.0–1.0) for a private challenge based on live data
    func progressPercentage(for challenge: PrivateChallenge) -> Double {
        guard challenge.dailyTarget > 0 else { return 0 }
        let value = Double(liveProgress(for: challenge))
        return min(1.0, value / Double(challenge.dailyTarget))
    }
    
    // MARK: - Community Leaderboard Response Live Progress
    
    /// Returns live "my today" progress for a community leaderboard response.
    func liveProgress(for lb: CommunityLeaderboardResponse) -> Int {
        Self.resolveProgress(
            challengeType: lb.resolvedType,
            targetUnit: lb.targetUnit,
            serverValue: lb.myTodayProgress
        )
    }
    
    /// Whether the user hit today's target for a community leaderboard response
    func targetHitToday(for lb: CommunityLeaderboardResponse) -> Bool {
        guard lb.dailyTarget > 0 else { return false }
        return liveProgress(for: lb) >= lb.dailyTarget
    }
    
    // MARK: - Community Detail Live Progress
    
    /// Returns live "my today" progress for a community detail response.
    func liveProgress(for detail: CommunityDetailResponse) -> Int {
        Self.resolveProgress(
            challengeType: detail.resolvedType,
            targetUnit: detail.targetUnit,
            serverValue: detail.myTodayProgress
        )
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
    case hydrate = "hydrate"
    case calories = "calories"
    case protein = "protein"

    // MARK: Wearable Personalization Platform — Phase 5
    //
    // Three new wearable-powered challenge types. All read from
    // `ReadinessService.shared` (wearable-agnostic) so WHOOP, Oura,
    // Fitbit, and Apple Health users are all on the same leaderboard.
    // Server-side `get_daily_quests` challenge-override map must be
    // extended to route these to the matching quest keys (Data
    // invariant #31):
    //   sleep_hours       → `sleep_8h_wearable`
    //   readinessAverage  → `recovery_above_67`
    //   strainBudget      → `complete_workout` (strain implies training)
    /// Weekly avg sleep duration (hours). Progress reads
    /// `daily_readiness_history.sleep_hours`.
    case sleepHours = "sleep_hours"
    /// Avg readiness score across the window. Fair across wearables.
    case readinessAverage = "readiness_average"
    /// Accumulate strain without crashing recovery. Compound metric
    /// that rewards smart volume, not grinding.
    case strainBudget = "strain_budget"

    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .steps: return "Step Challenge"
        case .walk: return "Walk Challenge"
        case .run: return "Run Challenge"
        case .lift: return "Lift Challenge"
        case .workoutStreak: return "Workout Streak"
        case .activeMinutes: return "Active Minutes"
        case .hydrate: return "Hydration Challenge"
        case .calories: return "Calorie Challenge"
        case .protein: return "Protein Challenge"
        case .sleepHours: return "Sleep Challenge"
        case .readinessAverage: return "Readiness Challenge"
        case .strainBudget: return "Strain Budget"
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
        case .hydrate: return "drop.fill"
        case .calories: return "flame.fill"
        case .protein: return "fork.knife"
        case .sleepHours: return "bed.double.fill"
        case .readinessAverage: return "heart.text.square.fill"
        case .strainBudget: return "bolt.heart.fill"
        }
    }
    
    var emoji: String {
        switch self {
        case .steps: return "👟"
        case .walk: return "🚶"
        case .run: return "🏃"
        case .lift: return "🏋️"
        case .workoutStreak: return "🔥"
        case .activeMinutes: return "⏱️"
        case .hydrate: return "💧"
        case .calories: return "🔥"
        case .protein: return "🥩"
        case .sleepHours: return "😴"
        case .readinessAverage: return "💚"
        case .strainBudget: return "⚡"
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
        case .hydrate: return .cyan
        case .calories: return .orange
        case .protein: return .pink
        case .sleepHours: return .indigo
        case .readinessAverage: return .green
        case .strainBudget: return .yellow
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
        case .hydrate: return [.cyan, .blue]
        case .calories: return [.orange, .red]
        case .protein: return [.pink, .purple]
        case .sleepHours: return [.indigo, .purple]
        case .readinessAverage: return [.green, .teal]
        case .strainBudget: return [.yellow, .orange]
        }
    }
    
    /// The unit label to display for this challenge type
    var unitLabel: String {
        switch self {
        case .steps: return "steps"
        case .walk: return "min"
        case .run: return "min"
        case .lift: return "reps"
        case .workoutStreak: return "days"
        case .activeMinutes: return "min"
        case .hydrate: return "ml"
        case .calories: return "cal"
        case .protein: return "g"
        case .sleepHours: return "h"
        case .readinessAverage: return "/ 100"
        case .strainBudget: return "strain"
        }
    }

    /// True ⇔ progress for this challenge comes from
    /// `daily_readiness_history` (wearable-agnostic) rather than from
    /// HealthKit steps / Fitbit activity / manual logs. Phase 5
    /// `BackgroundChallengeSyncService` uses this flag to route
    /// progress through `ReadinessService.shared` instead of the
    /// HealthKit-first paths. Feature-flagged via
    /// `AppConfig.FeatureFlags.wearableChallenges`.
    var isWearableSourced: Bool {
        switch self {
        case .sleepHours, .readinessAverage, .strainBudget: return true
        default: return false
        }
    }
}

// MARK: - Challenge Type Resolution Protocol

protocol ChallengeTypeResolvable {
    var challengeType: String { get }
    var targetUnit: String { get }
    var title: String { get }
}

extension ChallengeTypeResolvable {
    var resolvedType: ChallengeType {
        if let direct = ChallengeType(rawValue: challengeType),
           direct != .steps && direct != .activeMinutes { return direct }
        switch targetUnit.lowercased() {
        case "ml", "oz": return .hydrate
        case "grams", "g": return .protein
        case "calories", "cal", "kcal": return .calories
        default: break
        }
        if title.contains("💧") { return .hydrate }
        if title.contains("🥩") || title.contains("🍗") || title.contains("🥚") { return .protein }
        if title.contains("🔥") && (targetUnit.lowercased().contains("cal")) { return .calories }
        return ChallengeType(rawValue: challengeType) ?? .steps
    }
}

// MARK: - Data Models

struct ChallengeInvite: Codable, Identifiable, ChallengeTypeResolvable {
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
    
    var displayTitle: String {
        var t = title
        if t.hasPrefix("🤝 ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if t.hasPrefix("⚔️ ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        while let first = t.unicodeScalars.first, first.properties.isEmoji && first.value > 0x238C {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let next = t.unicodeScalars.first, next.value == 0xFE0F {
                t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        t = t.replacingOccurrences(of: "\\b(\\d{1,})(000)\\b", with: "$1K", options: .regularExpression)
        return t
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
        
        self.startDateString = ChallengeFormatters.dateOnly.string(from: startDate)
        self.endDateString = ChallengeFormatters.dateOnly.string(from: endDate)
        
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

/// Challenge I sent that is waiting for the opponent to accept
struct PendingSentChallenge: Codable, Identifiable, ChallengeTypeResolvable {
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
    let opponentId: UUID
    let opponentName: String?
    let opponentUsername: String?
    let opponentPhotoUrl: String?
    let sentAt: Date
    let opponentIsVerified: Bool?
    let opponentIsGoldVerified: Bool?

    var id: UUID { challengeId }
    
    var startDate: Date { parseFlexibleDate(startDateString) }
    var endDate: Date { parseFlexibleDate(endDateString) }
    
    var displayEmoji: String {
        emoji ?? "🏆"
    }
    
    var type: ChallengeType? {
        ChallengeType(rawValue: challengeType)
    }
    
    var displayTitle: String {
        var t = title
        if t.hasPrefix("🤝 ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if t.hasPrefix("⚔️ ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        while let first = t.unicodeScalars.first, first.properties.isEmoji && first.value > 0x238C {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let next = t.unicodeScalars.first, next.value == 0xFE0F {
                t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        t = t.replacingOccurrences(of: "\\b(\\d{1,})(000)\\b", with: "$1K", options: .regularExpression)
        return t
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
        case opponentId = "opponent_id"
        case opponentName = "opponent_name"
        case opponentUsername = "opponent_username"
        case opponentPhotoUrl = "opponent_photo_url"
        case sentAt = "sent_at"
        case opponentIsVerified = "opponent_is_verified"
        case opponentIsGoldVerified = "opponent_is_gold_verified"
    }
}

struct ActiveChallenge: Codable, Identifiable, Hashable, ChallengeTypeResolvable {
    let challengeId: UUID
    
    func hash(into hasher: inout Hasher) { hasher.combine(challengeId) }
    static func == (lhs: ActiveChallenge, rhs: ActiveChallenge) -> Bool { lhs.challengeId == rhs.challengeId }
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
    let myTodayProgress: Int?         // NEW: Today's progress specifically
    let opponentId: UUID
    let opponentName: String?
    let opponentUsername: String?
    let opponentPhotoUrl: String?
    let opponentTotalProgress: Int
    let opponentDaysCompleted: Int
    let opponentTodayProgress: Int?   // NEW: Opponent's today progress
    let amWinning: Bool
    let amWinningToday: Bool?
    let opponentIsVerified: Bool?
    let opponentIsGoldVerified: Bool?
    /// Realtime Widget Server Pull, Phase 2a/2b (2026-04-26):
    /// Stored as raw ISO-8601 strings — same pattern as `startDateString`
    /// / `endDateString` above — so the synthesized `Codable` decoder
    /// doesn't depend on `JSONDecoder.dateDecodingStrategy` being set
    /// (the existing `SupabaseManager.client.rpc(...).execute()` path
    /// uses the default decoder; flipping that would touch every
    /// existing model). The computed `myLastProgressAt` /
    /// `opponentLastProgressAt` accessors below do the parse on demand.
    /// Sourced from `get_active_challenges`'s new
    /// `my_last_progress_at` / `opponent_last_progress_at` columns
    /// (migration #122). NULL when the participant has no
    /// `challenge_daily_progress` rows since the challenge started —
    /// `Shared/ProgressFreshness.swift` (Phase 6) maps NULL → unknown
    /// and renders the value as-is rather than masking with `—`.
    private let myLastProgressAtString: String?
    private let opponentLastProgressAtString: String?

    var id: UUID { challengeId }

    /// Most recent server-side `MAX(updated_at)` on the caller's
    /// `challenge_daily_progress` rows for this challenge (or `nil`
    /// when the RPC didn't return one — older deploys / never logged).
    var myLastProgressAt: Date? {
        ActiveChallenge.parseProgressTimestamp(myLastProgressAtString)
    }

    /// Same shape, opponent side — the headline freshness signal the
    /// home-screen widget renders to call out a stale opponent.
    var opponentLastProgressAt: Date? {
        ActiveChallenge.parseProgressTimestamp(opponentLastProgressAtString)
    }

    /// Parses Postgres `TIMESTAMPTZ` strings (`2026-04-26T18:14:32.123456+00:00`
    /// / `2026-04-26T18:14:32Z`) into `Date`. Static so we don't pay a
    /// per-instance formatter init. `ISO8601DateFormatter` with
    /// fractional-second support handles every shape Supabase returns.
    private static let progressTimestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let progressTimestampFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseProgressTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = progressTimestampFormatter.date(from: raw) { return d }
        return progressTimestampFormatterNoFraction.date(from: raw)
    }

    /// Safe display name for opponent (falls back to "Unknown User" when nil)
    var opponentDisplayName: String { opponentName ?? "Unknown User" }
    
    /// Safe URL for opponent avatar (returns nil if string is nil or invalid)
    var opponentAvatarURL: URL? {
        guard let urlString = opponentPhotoUrl else { return nil }
        return URL(string: urlString)
    }
    
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
        myTodayProgress: Int? = nil,
        myDaysCompleted: Int,
        myCurrentStreak: Int,
        opponentId: UUID,
        opponentName: String?,
        opponentUsername: String?,
        opponentPhotoUrl: String?,
        opponentTotalProgress: Int,
        opponentTodayProgress: Int? = nil,
        opponentDaysCompleted: Int,
        amWinning: Bool,
        amWinningToday: Bool? = nil,
        opponentIsVerified: Bool? = nil,
        opponentIsGoldVerified: Bool? = nil,
        myLastProgressAt: Date? = nil,
        opponentLastProgressAt: Date? = nil
    ) {
        self.challengeId = challengeId
        self.challengeType = challengeType
        self.title = title
        self.description = description
        self.dailyTarget = dailyTarget
        self.totalTarget = totalTarget
        self.targetUnit = targetUnit
        
        self.startDateString = ChallengeFormatters.dateOnly.string(from: startDate)
        self.endDateString = ChallengeFormatters.dateOnly.string(from: endDate)
        
        self.durationDays = durationDays
        self.daysElapsed = daysElapsed
        self.daysRemaining = daysRemaining
        self.status = status
        self.myTotalProgress = myTotalProgress
        self.myTodayProgress = myTodayProgress
        self.myDaysCompleted = myDaysCompleted
        self.myCurrentStreak = myCurrentStreak
        self.opponentId = opponentId
        self.opponentName = opponentName
        self.opponentUsername = opponentUsername
        self.opponentPhotoUrl = opponentPhotoUrl
        self.opponentTotalProgress = opponentTotalProgress
        self.opponentTodayProgress = opponentTodayProgress
        self.opponentDaysCompleted = opponentDaysCompleted
        self.amWinning = amWinning
        self.amWinningToday = amWinningToday
        self.opponentIsVerified = opponentIsVerified
        self.opponentIsGoldVerified = opponentIsGoldVerified
        // Convenience init takes typed `Date?` and re-serialises into the
        // same ISO-8601 wire shape Supabase returns. Lets call sites
        // (previews, simulator, fixtures) use familiar `Date` arithmetic
        // (`Date().addingTimeInterval(-3600)` for "1h ago") without
        // having to remember the formatter incantation.
        self.myLastProgressAtString = myLastProgressAt.map { ActiveChallenge.progressTimestampFormatter.string(from: $0) }
        self.opponentLastProgressAtString = opponentLastProgressAt.map { ActiveChallenge.progressTimestampFormatter.string(from: $0) }
    }
    
    var type: ChallengeType? {
        ChallengeType(rawValue: challengeType)
    }
    
    var mode: ChallengeMode {
        ChallengeMode.from(title: title)
    }
    
    /// Whether both participants completed their daily target today
    var bothCompletedToday: Bool {
        guard let target = dailyTarget, target > 0 else { return false }
        let myDone = (myTodayProgress ?? 0) >= target
        let oppDone = (opponentTodayProgress ?? 0) >= target
        return myDone && oppDone
    }
    
    /// Display title without the mode prefix emoji or activity emoji, with K formatting
    var displayTitle: String {
        var t = title
        // Strip mode prefix
        if t.hasPrefix("🤝 ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if t.hasPrefix("⚔️ ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        // Strip any leading emoji (activity emoji like 🚶, 🏃, etc.)
        while let first = t.unicodeScalars.first,
              first.properties.isEmoji && first.value > 0x238C {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            // Also handle emoji with variation selectors (multi-scalar)
            if let next = t.unicodeScalars.first, next.value == 0xFE0F {
                t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        // Format thousands as K (e.g. "10000 steps" → "10K steps")
        t = t.replacingOccurrences(of: "\\b(\\d{1,})(000)\\b", with: "$1K", options: .regularExpression)
        return t
    }
    
    /// Progress percentage for today (0.0 to 1.0)
    var progressPercentage: Double {
        guard let target = dailyTarget, target > 0 else { return 0 }
        // Use today's progress, not cumulative total
        let todayProgress = Double(myTodayProgress ?? 0)
        return min(1.0, todayProgress / Double(target))
    }
    
    /// Opponent's progress percentage for today (0.0 to 1.0)
    var opponentProgressPercentage: Double {
        guard let target = dailyTarget, target > 0 else { return 0 }
        // Use today's progress, not cumulative total
        let todayProgress = Double(opponentTodayProgress ?? 0)
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
        case myTodayProgress = "my_today_progress"
        case myDaysCompleted = "my_days_completed"
        case myCurrentStreak = "my_current_streak"
        case opponentId = "opponent_id"
        case opponentName = "opponent_name"
        case opponentUsername = "opponent_username"
        case opponentPhotoUrl = "opponent_photo_url"
        case opponentTotalProgress = "opponent_total_progress"
        case opponentTodayProgress = "opponent_today_progress"
        case opponentDaysCompleted = "opponent_days_completed"
        case amWinning = "am_winning"
        case amWinningToday = "am_winning_today"
        case opponentIsVerified = "opponent_is_verified"
        case opponentIsGoldVerified = "opponent_is_gold_verified"
        case myLastProgressAtString = "my_last_progress_at"
        case opponentLastProgressAtString = "opponent_last_progress_at"
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

// MARK: - Group Challenge Models

struct GroupChallengeMember: Codable, Identifiable {
    let userId: UUID
    let status: String
    let totalProgress: Int
    let todayProgress: Int
    let daysCompleted: Int
    let currentStreak: Int
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let isVerified: Bool?
    let isGoldVerified: Bool?

    var id: UUID { userId }

    var displayName: String {
        if let username = username, !username.isEmpty { return "@\(username)" }
        return name ?? "Unknown"
    }

    var firstName: String {
        name?.components(separatedBy: " ").first ?? username ?? "Friend"
    }

    var isAccepted: Bool { status == "accepted" }
    var isPending: Bool { status == "pending" }

    func withZeroedTodayProgress() -> GroupChallengeMember {
        GroupChallengeMember(
            userId: userId, status: status, totalProgress: totalProgress,
            todayProgress: 0, daysCompleted: daysCompleted, currentStreak: currentStreak,
            name: name, username: username, profilePhotoUrl: profilePhotoUrl,
            isVerified: isVerified, isGoldVerified: isGoldVerified
        )
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case status
        case totalProgress = "total_progress"
        case todayProgress = "today_progress"
        case daysCompleted = "days_completed"
        case currentStreak = "current_streak"
        case name
        case username
        case profilePhotoUrl = "profile_photo_url"
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
    }
}

struct ActiveGroupChallenge: Codable, Identifiable, Hashable, ChallengeTypeResolvable {
    let challengeId: UUID
    
    func hash(into hasher: inout Hasher) { hasher.combine(challengeId) }
    static func == (lhs: ActiveGroupChallenge, rhs: ActiveGroupChallenge) -> Bool { lhs.challengeId == rhs.challengeId }
    let title: String
    let description: String?
    let challengeType: String
    let mode: String
    let dailyTarget: Int?
    let totalTarget: Int?
    let targetUnit: String
    private let startDateString: String
    private let endDateString: String
    let durationDays: Int
    let daysElapsed: Int
    let daysRemaining: Int
    let status: String
    let createdBy: UUID
    let memberCount: Int
    let members: [GroupChallengeMember]?
    
    var id: UUID { challengeId }
    var startDate: Date { parseFlexibleDate(startDateString) }
    var endDate: Date { parseFlexibleDate(endDateString) }
    
    var type: ChallengeType? {
        ChallengeType(rawValue: challengeType)
    }
    
    var challengeMode: ChallengeMode {
        ChallengeMode.from(title: title)
    }
    
    /// Display title without the mode prefix emoji or activity emoji, with K formatting
    var displayTitle: String {
        var t = title
        // Strip mode prefix
        if t.hasPrefix("🤝 ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if t.hasPrefix("⚔️ ") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        // Strip any leading emoji (activity emoji like 🚶, 🏃, etc.)
        while let first = t.unicodeScalars.first,
              first.properties.isEmoji && first.value > 0x238C {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let next = t.unicodeScalars.first, next.value == 0xFE0F {
                t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        // Format thousands as K (e.g. "10000 steps" → "10K steps")
        t = t.replacingOccurrences(of: "\\b(\\d{1,})(000)\\b", with: "$1K", options: .regularExpression)
        return t
    }
    
    var isActive: Bool { status == "active" }
    var isPending: Bool { status == "pending" }
    
    /// The current user's member status in this group challenge
    var myMemberStatus: String? {
        guard let currentUserId = SupabaseManager.shared.currentUser?.id else { return nil }
        return members?.first(where: { $0.userId == currentUserId })?.status
    }
    
    /// Whether the current user still needs to accept/decline this invite
    var isMyInvitePending: Bool {
        myMemberStatus == "pending"
    }
    
    /// Whether the current user has already accepted
    var iHaveAccepted: Bool {
        myMemberStatus == "accepted"
    }
    
    /// The creator's name
    var creatorName: String? {
        members?.first(where: { $0.userId == createdBy })?.name?.components(separatedBy: " ").first
            ?? members?.first(where: { $0.userId == createdBy })?.username
    }
    
    var acceptedMembers: [GroupChallengeMember] {
        members?.filter(\.isAccepted) ?? []
    }
    
    var pendingMembers: [GroupChallengeMember] {
        members?.filter(\.isPending) ?? []
    }
    
    /// Whether all members have completed today's target
    var allCompletedToday: Bool {
        guard let target = dailyTarget, target > 0, let members = members else { return false }
        return members.filter(\.isAccepted).allSatisfy { $0.todayProgress >= target }
    }

    func withZeroedTodayProgress() -> ActiveGroupChallenge {
        ActiveGroupChallenge(
            challengeId: challengeId, title: title, description: description,
            challengeType: challengeType, mode: mode, dailyTarget: dailyTarget,
            totalTarget: totalTarget, targetUnit: targetUnit,
            startDateString: startDateString, endDateString: endDateString,
            durationDays: durationDays, daysElapsed: daysElapsed, daysRemaining: daysRemaining,
            status: status, createdBy: createdBy, memberCount: memberCount,
            members: members?.map { $0.withZeroedTodayProgress() }
        )
    }

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description
        case challengeType = "challenge_type"
        case mode
        case dailyTarget = "daily_target"
        case totalTarget = "total_target"
        case targetUnit = "target_unit"
        case startDateString = "start_date"
        case endDateString = "end_date"
        case durationDays = "duration_days"
        case daysElapsed = "days_elapsed"
        case daysRemaining = "days_remaining"
        case status
        case createdBy = "created_by"
        case memberCount = "member_count"
        case members
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

struct FriendChallenge: Codable, Identifiable, ChallengeTypeResolvable {
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
