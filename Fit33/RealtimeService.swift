//
//  RealtimeService.swift
//  Fit33
//
//  Supabase Realtime Service - Provides instant updates for social features
//  Handles: Friend requests, shared workouts, challenge updates
//
//  Created by Infrastructure Team - 2026-02-03
//

import Foundation
import Supabase
import Realtime

// MARK: - Realtime Service

/// Manages Supabase Realtime subscriptions for instant social updates
/// This eliminates the need for polling and provides immediate feedback
@MainActor
class RealtimeService: ObservableObject {
    static let shared = RealtimeService()
    
    // MARK: - Published State
    
    @Published var isConnected = false
    @Published var connectionError: String?
    
    /// Live feed of realtime events for debugging (most recent first, capped at 200)
    @Published var realtimeEventLog: [RealtimeEventEntry] = []
    
    /// Timestamp of the last realtime event received (any type)
    @Published var lastEventReceivedAt: Date?
    
    /// Timestamp of the last OPPONENT progress event received
    @Published var lastOpponentProgressAt: Date?
    
    /// Details of the last opponent progress update (for cross-device verification)
    @Published var lastOpponentProgressEvent: DailyProgressPayload?
    
    // MARK: - Channels
    
    private var friendshipsChannel: RealtimeChannelV2?
    private var sharedWorkoutsChannel: RealtimeChannelV2?
    private var challengesChannel: RealtimeChannelV2?
    private var dailyProgressChannel: RealtimeChannelV2?
    private var privateChallengeChannel: RealtimeChannelV2?
    private var communityChallengeChannel: RealtimeChannelV2?
    private var communityParticipantsChannel: RealtimeChannelV2?
    private var privateMembersChannel: RealtimeChannelV2?
    private var friendActivityFeedChannel: RealtimeChannelV2?
    
    // MARK: - Debounce State
    
    /// Debounce tasks for community and private challenge progress refreshes.
    /// For automated metrics like steps, many progress events fire in rapid succession.
    /// We debounce to avoid calling fetchMyChallenges() on every single event.
    private var communityProgressDebounceTask: Task<Void, Never>?
    private var privateProgressDebounceTask: Task<Void, Never>?
    
    /// Periodic refresh timer for auto-tracked community/private challenge progress.
    /// Manual-input challenges (protein, hydration) refresh in real-time via WebSocket.
    /// Auto-tracked challenges (steps, active_minutes, walk, run) refresh on this cadence
    /// since they update frequently in the background and real-time events would be noisy.
    private var autoTrackedRefreshTimer: Task<Void, Never>?
    private static let autoTrackedRefreshInterval: UInt64 = 90_000_000_000 // 90 seconds (was 30s — too aggressive)
    
    // MARK: - Throttle State (prevent cascading fetches)
    
    /// Last time we fetched community challenges from a realtime event.
    /// Used to throttle rapid-fire events from triggering redundant network calls.
    private var lastCommunityFetchTime: Date?
    private static let communityFetchThrottleInterval: TimeInterval = 3.0 // Don't re-fetch within 3s
    
    /// Last time we fetched 1v1/group challenges from a realtime event.
    private var lastChallengeFetchTime: Date?
    private static let challengeFetchThrottleInterval: TimeInterval = 3.0 // Don't re-fetch within 3s
    
    /// Last time we fetched private challenges from a realtime event.
    private var lastPrivateFetchTime: Date?
    private static let privateFetchThrottleInterval: TimeInterval = 3.0
    
    /// Throttled community challenge fetch — prevents cascading duplicate network calls.
    private func throttledCommunityFetch() async {
        let now = Date()
        if let last = lastCommunityFetchTime, now.timeIntervalSince(last) < Self.communityFetchThrottleInterval {
            return // Already fetched very recently
        }
        lastCommunityFetchTime = now
        await CommunityChallengeService.shared.fetchMyChallenges()
    }
    
    /// Throttled 1v1/group challenge fetch — prevents cascading duplicate network calls.
    private func throttledChallengeFetch() async {
        let now = Date()
        if let last = lastChallengeFetchTime, now.timeIntervalSince(last) < Self.challengeFetchThrottleInterval {
            return // Already fetched very recently
        }
        lastChallengeFetchTime = now
        await ChallengeService.shared.fetchActiveChallenges()
        await ChallengeService.shared.fetchActiveGroupChallenges()
    }
    
    /// Throttled private challenge fetch — prevents cascading duplicate network calls.
    private func throttledPrivateFetch() async {
        let now = Date()
        if let last = lastPrivateFetchTime, now.timeIntervalSince(last) < Self.privateFetchThrottleInterval {
            return // Already fetched very recently
        }
        lastPrivateFetchTime = now
        await PrivateChallengeService.shared.fetchMyChallenges()
    }
    
    /// Returns true if this challenge type is manually input by the user (protein, hydration, etc.).
    /// Manual-input challenges should refresh instantly when a real-time event arrives.
    /// Auto-tracked challenges (steps, active minutes) refresh on a periodic cadence instead.
    private static func isManualInputType(_ challengeType: String?) -> Bool {
        guard let type = challengeType else { return true } // Default to instant if unknown
        switch type {
        case "protein", "hydrate", "sleep", "lift", "workout_streak":
            return true  // User explicitly logs these — refresh instantly
        case "steps", "active_minutes", "walk", "run", "calories":
            return false // HealthKit auto-syncs these — refresh on cadence
        default:
            return true  // Unknown types default to instant
        }
    }
    
    /// Look up the challenge type for a community challenge by its ID.
    /// Returns nil if the challenge isn't in the user's local list.
    private func lookupCommunityChallengeType(challengeId: String) -> String? {
        guard let uuid = UUID(uuidString: challengeId) else { return nil }
        return CommunityChallengeService.shared.myChallenges
            .first(where: { $0.challengeId == uuid })?.challengeType
    }
    
    /// Look up the challenge type for a private challenge by its ID.
    private func lookupPrivateChallengeType(challengeId: String) -> String? {
        guard let uuid = UUID(uuidString: challengeId) else { return nil }
        return PrivateChallengeService.shared.myChallenges
            .first(where: { $0.challengeId == uuid })?.challengeType
    }
    
    // MARK: - Callbacks
    
    /// Called when a new friend request is received
    var onFriendRequestReceived: ((FriendRequestPayload) -> Void)?
    
    /// Called when a friend request is accepted
    var onFriendRequestAccepted: ((FriendRequestPayload) -> Void)?
    
    /// Called when a new workout is shared with the user
    var onWorkoutReceived: ((SharedWorkoutPayload) -> Void)?
    
    /// Called when a challenge invite is received
    var onChallengeInviteReceived: ((ChallengePayload) -> Void)?
    
    /// Called when challenge progress is updated
    var onChallengeProgressUpdated: ((ChallengePayload) -> Void)?
    
    /// Called when opponent's daily progress updates (for live challenge widget)
    var onOpponentDailyProgressUpdated: ((DailyProgressPayload) -> Void)?
    
    private init() {}
    
    // MARK: - Safe JSON Value Extraction
    
    /// Safely extracts an Int from a JSON value that may arrive as AnyJSON, Int, Double, NSNumber, or String.
    /// Supabase Realtime v2.40+ wraps ALL record values in AnyJSON enum (.integer, .double, .string, etc.)
    /// Direct `as? Int` FAILS silently on AnyJSON.integer(42), causing progress updates to be dropped.
    private func jsonInt(_ value: Any?) -> Int? {
        // ── AnyJSON (the ACTUAL type from Supabase Realtime v2) ──
        if let json = value as? AnyJSON {
            if let i = json.intValue { return i }
            if let d = json.doubleValue { return Int(d) }
            if let s = json.stringValue, let i = Int(s) { return i }
            return nil
        }
        // ── Fallback for raw Swift types (manual dict construction, tests, etc.) ──
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let i = Int(s) { return i }
        return nil
    }
    
    /// Safely extracts a String from a JSON value (handles AnyJSON wrapper)
    private func jsonString(_ value: Any?) -> String? {
        // ── AnyJSON (the ACTUAL type from Supabase Realtime v2) ──
        if let json = value as? AnyJSON {
            if let s = json.stringValue { return s }
            if let i = json.intValue { return String(i) }
            if let d = json.doubleValue { return String(d) }
            if let b = json.boolValue { return String(b) }
            return nil
        }
        // ── Fallback for raw Swift types ──
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let d = value as? Double { return String(Int(d)) }
        if let i = value as? Int { return String(i) }
        return nil
    }
    
    /// Safely extracts a Bool from a JSON value (handles AnyJSON wrapper)
    private func jsonBool(_ value: Any?) -> Bool? {
        // ── AnyJSON (the ACTUAL type from Supabase Realtime v2) ──
        if let json = value as? AnyJSON {
            if let b = json.boolValue { return b }
            if let i = json.intValue { return i != 0 }
            if let s = json.stringValue { return s.lowercased() == "true" || s == "1" }
            return nil
        }
        // ── Fallback for raw Swift types ──
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let i = value as? Int { return i != 0 }
        if let s = value as? String { return s.lowercased() == "true" || s == "1" }
        return nil
    }
    
    // MARK: - Event Logging
    
    /// Log a realtime event for debugging visibility
    func logRealtimeEvent(type: String, source: String, details: String, isError: Bool = false) {
        let entry = RealtimeEventEntry(
            timestamp: Date(),
            type: type,
            source: source,
            details: details,
            isError: isError
        )
        realtimeEventLog.insert(entry, at: 0)
        // Cap at 200 entries
        if realtimeEventLog.count > 200 {
            realtimeEventLog = Array(realtimeEventLog.prefix(200))
        }
        lastEventReceivedAt = Date()
    }
    
    // MARK: - Connection Management
    
    /// Start all realtime subscriptions for the current user
    func connect() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("Cannot connect - not authenticated", category: .network)
            return
        }
        
        // BUG FIX: Disconnect existing channels BEFORE creating new ones.
        // Without this, calling connect() twice (e.g. from .task + .active scenePhase)
        // creates duplicate channels, causing "postgresChange after joining" warnings.
        if isConnected || friendshipsChannel != nil {
            AppLogger.debug("Cleaning up existing channels before reconnecting...", category: .network)
            await disconnect()
        }
        
        AppLogger.debug("Connecting to realtime channels...", category: .network)
        
        // Subscribe to all relevant channels
        await subscribeFriendships(userId: userId)
        await subscribeSharedWorkouts(userId: userId)
        await subscribeChallenges(userId: userId)
        await subscribeDailyProgress(userId: userId)
        await subscribePrivateChallengeProgress(userId: userId)
        await subscribeCommunityChallengeProgress(userId: userId)
        await subscribeCommunityParticipants(userId: userId)
        await subscribePrivateMembers(userId: userId)
        await subscribeFriendActivityFeed(userId: userId)
        
        // Start periodic cadence refresh for auto-tracked challenges (steps, active_minutes, etc.)
        startAutoTrackedRefreshTimer()
        
        isConnected = true
        connectionError = nil
        AppLogger.info("Connected to all channels", category: .network)
        logRealtimeEvent(type: "CONNECTED", source: "RealtimeService",
                        details: "✅ All 9 channels active: friendships, shared_workouts, challenges, daily_progress, private_challenges, community_challenges, community_participants, private_members, friend_activity_feed + auto-tracked refresh timer")
    }
    
    /// Disconnect from all realtime channels
    func disconnect() async {
        AppLogger.debug("Disconnecting from channels...", category: .network)
        
        if let channel = friendshipsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = sharedWorkoutsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = challengesChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = dailyProgressChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = privateChallengeChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = communityChallengeChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = communityParticipantsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = privateMembersChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = friendActivityFeedChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        
        // Also tear down service-level realtime channels so they can re-subscribe on reconnect.
        // Without this, the services hold a stale channel reference and the guard in
        // subscribeToRealtimeUpdates() prevents re-subscription after background → foreground.
        await PrivateChallengeService.shared.unsubscribeFromRealtimeUpdates()
        await CommunityChallengeService.shared.unsubscribeFromRealtimeUpdates()
        
        // Cancel any pending debounced refresh tasks and the cadence timer
        communityProgressDebounceTask?.cancel()
        privateProgressDebounceTask?.cancel()
        communityProgressDebounceTask = nil
        privateProgressDebounceTask = nil
        stopAutoTrackedRefreshTimer()
        
        friendshipsChannel = nil
        sharedWorkoutsChannel = nil
        challengesChannel = nil
        dailyProgressChannel = nil
        privateChallengeChannel = nil
        communityChallengeChannel = nil
        communityParticipantsChannel = nil
        privateMembersChannel = nil
        friendActivityFeedChannel = nil
        
        isConnected = false
        AppLogger.info("Disconnected from all channels", category: .network)
    }
    
    // MARK: - Friend Activity Feed Subscription
    
    private func subscribeFriendActivityFeed(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("friend_activity_feed-\(userId.uuidString)")
        
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "friend_activity_feed"
        )
        
        Task {
            for await _ in insertions {
                AppLogger.debug("New friend activity feed item!", category: .network)
                logRealtimeEvent(type: "INSERT", source: "friend_activity_feed",
                                details: "New activity in feed — refreshing")
                await ActivityFeedService.shared.fetchFeed()
                ActivityFeedService.shared.lastRealtimeUpdate = Date()
            }
        }
        
        await channel.subscribe()
        friendActivityFeedChannel = channel
        
        AppLogger.debug("Subscribed to friend_activity_feed for user \(userId)", category: .network)
    }
    
    // MARK: - Friend Requests Subscription
    
    private func subscribeFriendships(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        // Create channel for friendships table changes targeting this user
        let channel = client.realtimeV2.channel("friendships-\(userId.uuidString)")
        
        // Subscribe to new friend requests (where I am the addressee)
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "friendships",
            filter: "addressee_id=eq.\(userId.uuidString)"
        )
        
        // Subscribe to updates (for when my requests are accepted)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "friendships",
            filter: "requester_id=eq.\(userId.uuidString)"
        )
        
        // Also subscribe to updates where I'm the addressee (for status changes)
        let myUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "friendships",
            filter: "addressee_id=eq.\(userId.uuidString)"
        )
        
        Task {
            for await action in insertions {
                await handleFriendshipInsert(action)
            }
        }
        
        Task {
            for await action in updates {
                await handleFriendshipUpdate(action, isRequester: true)
            }
        }
        
        Task {
            for await action in myUpdates {
                await handleFriendshipUpdate(action, isRequester: false)
            }
        }
        
        await channel.subscribe()
        friendshipsChannel = channel
        
        AppLogger.debug("Subscribed to friendships for user \(userId)", category: .network)
    }
    
    private func handleFriendshipInsert(_ action: InsertAction) async {
        let record = action.record
        guard let status = jsonString(record["status"]),
              status == "pending" else { return }
        
        AppLogger.debug("New friend request received!", category: .network)
        
        let payload = FriendRequestPayload(
            friendshipId: UUID(uuidString: jsonString(record["id"]) ?? "") ?? UUID(),
            requesterId: UUID(uuidString: jsonString(record["requester_id"]) ?? "") ?? UUID(),
            addresseeId: UUID(uuidString: jsonString(record["addressee_id"]) ?? "") ?? UUID(),
            status: status,
            createdAt: Date()
        )
        
        // Trigger callback
        onFriendRequestReceived?(payload)
        
        // Refresh friend requests in FriendService
        await FriendService.shared.fetchPendingRequests()
        
        // Haptic feedback
        HapticManager.notification(.success)
    }
    
    private func handleFriendshipUpdate(_ action: UpdateAction, isRequester: Bool) async {
        let record = action.record
        guard let status = jsonString(record["status"]) else { return }
        
        if status == "accepted" {
            AppLogger.info("Friend request accepted!", category: .network)
            
            let payload = FriendRequestPayload(
                friendshipId: UUID(uuidString: jsonString(record["id"]) ?? "") ?? UUID(),
                requesterId: UUID(uuidString: jsonString(record["requester_id"]) ?? "") ?? UUID(),
                addresseeId: UUID(uuidString: jsonString(record["addressee_id"]) ?? "") ?? UUID(),
                status: status,
                createdAt: Date()
            )
            
            if isRequester {
                // My request was accepted
                onFriendRequestAccepted?(payload)
            }
            
            // Refresh friends list
            await FriendService.shared.fetchFriends()
            
            // Haptic feedback
            HapticManager.notification(.success)
        }
    }
    
    // MARK: - Shared Workouts Subscription
    
    private func subscribeSharedWorkouts(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("shared_workouts-\(userId.uuidString)")
        
        // Subscribe to new shared workouts where I am the recipient
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "shared_workouts",
            filter: "recipient_id=eq.\(userId.uuidString)"
        )
        
        Task {
            for await action in insertions {
                await handleSharedWorkoutInsert(action)
            }
        }
        
        await channel.subscribe()
        sharedWorkoutsChannel = channel
        
        AppLogger.debug("Subscribed to shared_workouts for user \(userId)", category: .network)
    }
    
    private func handleSharedWorkoutInsert(_ action: InsertAction) async {
        let record = action.record
        
        AppLogger.debug("New workout shared!", category: .network)
        
        let payload = SharedWorkoutPayload(
            workoutId: UUID(uuidString: jsonString(record["id"]) ?? "") ?? UUID(),
            senderId: UUID(uuidString: jsonString(record["sender_id"]) ?? "") ?? UUID(),
            recipientId: UUID(uuidString: jsonString(record["recipient_id"]) ?? "") ?? UUID(),
            workoutName: jsonString(record["workout_name"]) ?? "Workout",
            status: jsonString(record["status"]) ?? "pending",
            createdAt: Date()
        )
        
        // Trigger callback
        onWorkoutReceived?(payload)
        
        // Refresh received workouts
        await FriendService.shared.fetchReceivedWorkouts()
        
        // Haptic feedback
        HapticManager.notification(.success)
    }
    
    // MARK: - Challenges Subscription
    
    private func subscribeChallenges(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("challenges-\(userId.uuidString)")
        
        // Subscribe to new challenge invites (challenge_participants)
        let invites = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "challenge_participants",
            filter: "user_id=eq.\(userId.uuidString)"
        )
        
        // Subscribe to challenge participant updates (status changes: pending → accepted/declined)
        let participantStatusChanges = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "challenge_participants",
            filter: "user_id=eq.\(userId.uuidString)"
        )
        
        // Subscribe to ALL challenge participant updates (for opponent accepting your sent challenge)
        let allParticipantUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "challenge_participants"
        )
        
        // Subscribe to challenge status changes (group_challenges is the actual table)
        let challengeUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "group_challenges"
        )
        
        Task {
            for await action in invites {
                await handleChallengeInvite(action)
            }
        }
        
        // Route MY status changes (e.g. I accepted a challenge) to the proper handler
        Task {
            for await action in participantStatusChanges {
                await handleParticipantStatusChange(action, userId: userId)
            }
        }
        
        // Route ALL participant updates (opponent accepting, progress changes) to the proper handler
        Task {
            for await action in allParticipantUpdates {
                await handleAllParticipantUpdates(action, userId: userId)
            }
        }
        
        Task {
            for await action in challengeUpdates {
                await handleChallengeStatusChange(action)
            }
        }
        
        await channel.subscribe()
        challengesChannel = channel
        
        AppLogger.debug("Subscribed to challenges for user \(userId)", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "challenges",
                        details: "✅ Listening on challenge_participants (INSERT+UPDATE) + group_challenges (UPDATE)")
    }
    
    private func handleChallengeInvite(_ action: InsertAction) async {
        let record = action.record
        guard let status = jsonString(record["status"]),
              status == "pending" else { return }
        
        AppLogger.debug("New challenge invite!", category: .network)
        logRealtimeEvent(type: "CHALLENGE_INVITE", source: "challenge_participants", details: "New challenge invite received")
        
        let payload = ChallengePayload(
            challengeId: UUID(uuidString: jsonString(record["challenge_id"]) ?? "") ?? UUID(),
            participantId: UUID(uuidString: jsonString(record["user_id"]) ?? "") ?? UUID(),
            status: status,
            totalProgress: jsonInt(record["total_progress"]) ?? 0
        )
        
        // Trigger callback
        onChallengeInviteReceived?(payload)
        
        // Refresh challenge invites
        await ChallengeService.shared.fetchPendingInvites()
        
        // Haptic feedback
        HapticManager.notification(.success)
    }
    
    private func handleParticipantStatusChange(_ action: UpdateAction, userId: UUID) async {
        let record = action.record
        let oldRecord = action.oldRecord
        
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let oldStatus = jsonString(oldRecord["status"]) ?? ""
        let newStatus = jsonString(record["status"]) ?? ""
        let totalProgress = jsonInt(record["total_progress"]) ?? 0
        let oldTotalProgress = jsonInt(oldRecord["total_progress"]) ?? 0
        
        AppLogger.debug("MY challenge participant: status \(oldStatus) → \(newStatus), progress \(oldTotalProgress) → \(totalProgress) (challenge: \(challengeId))", category: .network)
        logRealtimeEvent(type: "MY_PARTICIPANT", source: "challenge_participants",
                        details: "status: \(oldStatus)→\(newStatus), progress: \(oldTotalProgress)→\(totalProgress), challenge: \(challengeId.prefix(8))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            AppLogger.info("I accepted a challenge - refreshing all lists (1v1 + group)", category: .network)
            await ChallengeService.shared.fetchPendingInvites()  // Remove from pending
            await throttledChallengeFetch()  // Add to active (1v1 + group) — throttled
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            AppLogger.debug("I declined a challenge", category: .network)
            await ChallengeService.shared.fetchPendingInvites()
        } else if totalProgress != oldTotalProgress {
            // My progress was confirmed in DB — refresh group challenges to show DB-backed values
            AppLogger.debug("My own progress confirmed in DB: \(totalProgress) — refreshing", category: .network)
            await throttledChallengeFetch()
        }
    }
    
    private func handleAllParticipantUpdates(_ action: UpdateAction, userId: UUID) async {
        let record = action.record
        let oldRecord = action.oldRecord
        
        let participantUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let oldStatus = jsonString(oldRecord["status"]) ?? ""
        let newStatus = jsonString(record["status"]) ?? ""
        let totalProgress = jsonInt(record["total_progress"]) ?? 0
        let oldTotalProgress = jsonInt(oldRecord["total_progress"]) ?? 0
        
        // Skip if it's my own update (already handled by handleParticipantStatusChange)
        guard participantUserId != userId.uuidString else { return }
        
        AppLogger.debug("OPPONENT challenge participant: \(oldStatus) → \(newStatus), progress: \(oldTotalProgress) → \(totalProgress) (challenge: \(challengeId))", category: .network)
        logRealtimeEvent(type: "OPPONENT_PARTICIPANT", source: "challenge_participants",
                        details: "user: \(participantUserId.prefix(8)), status: \(oldStatus)→\(newStatus), progress: \(oldTotalProgress)→\(totalProgress), challenge: \(challengeId.prefix(8))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            AppLogger.info("Opponent ACCEPTED my challenge - moving from sent → active (1v1 + group)", category: .network)
            logRealtimeEvent(type: "OPPONENT_ACCEPTED", source: "challenge_participants",
                            details: "✅ Opponent accepted! Refreshing all lists...")
            await ChallengeService.shared.fetchPendingSentChallenges()  // Remove from sent
            await throttledChallengeFetch()  // Add to active (1v1 + group)
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            AppLogger.debug("Opponent DECLINED my challenge - removing from sent", category: .network)
            logRealtimeEvent(type: "OPPONENT_DECLINED", source: "challenge_participants",
                            details: "Opponent declined challenge \(challengeId.prefix(8))")
            await ChallengeService.shared.fetchPendingSentChallenges()
        } else if totalProgress != oldTotalProgress {
            // Opponent's progress changed (they logged new steps/hydration/etc.)
            AppLogger.debug("Opponent progress changed: \(oldTotalProgress) → \(totalProgress) - refreshing all challenges", category: .network)
            logRealtimeEvent(type: "OPPONENT_PROGRESS", source: "challenge_participants",
                            details: "🔥 Progress: \(oldTotalProgress)→\(totalProgress) for challenge \(challengeId.prefix(8))")
            await throttledChallengeFetch()
        } else {
            // DEFENSIVE: Even if progress looks unchanged, refresh if we got an update event
            // This catches cases where oldRecord is empty (REPLICA IDENTITY not FULL)
            let hasOldData = !oldRecord.isEmpty
            if !hasOldData {
                AppLogger.warning("No old record data — REPLICA IDENTITY may not be FULL. Refreshing defensively.", category: .network)
                logRealtimeEvent(type: "OPPONENT_UPDATE_NO_OLD", source: "challenge_participants",
                                details: "⚠️ No old record data — refreshing defensively. newProgress=\(totalProgress)")
                await throttledChallengeFetch()
            }
        }
    }
    
    private func handleChallengeProgress(_ action: UpdateAction, userId: UUID) async {
        let record = action.record
        
        guard let participantUserId = jsonString(record["user_id"]) else {
            AppLogger.warning("handleChallengeProgress: missing user_id. Keys: \(record.keys.joined(separator: ", "))", category: .network)
            logRealtimeEvent(type: "CHALLENGE_PROGRESS", source: "challenge_participants", details: "❌ Missing user_id in record", isError: true)
            return
        }
        
        let challengeId = jsonString(record["challenge_id"]) ?? "unknown"
        let status = jsonString(record["status"]) ?? ""
        let totalProgress = jsonInt(record["total_progress"]) ?? 0
        
        logRealtimeEvent(type: "CHALLENGE_PROGRESS", source: "challenge_participants",
                        details: "user: \(participantUserId.prefix(8)), challenge: \(challengeId.prefix(8)), status: \(status), progress: \(totalProgress)")
        
        // If it's my own update, skip — we already know our own progress
        if participantUserId == userId.uuidString {
            return
        }
        
        let payload = ChallengePayload(
            challengeId: UUID(uuidString: challengeId) ?? UUID(),
            participantId: UUID(uuidString: participantUserId) ?? UUID(),
            status: status,
            totalProgress: totalProgress
        )
        
        // Trigger callback
        onChallengeProgressUpdated?(payload)
        
        // ⚡️ PERF FIX: Use throttled fetch instead of 4 sequential fetches
        await throttledChallengeFetch()
    }
    
    private func handleChallengeStatusChange(_ action: UpdateAction) async {
        let record = action.record
        
        let challengeId = jsonString(record["id"]) ?? "unknown"
        let status = jsonString(record["status"]) ?? ""
        
        #if DEBUG
        AppLogger.debug("Challenge status: \(challengeId.prefix(8)) → \(status)", category: .network)
        #endif
        logRealtimeEvent(type: "CHALLENGE_STATUS", source: "group_challenges", details: "Challenge \(challengeId.prefix(8)) → \(status)")
        
        // ⚡️ PERF FIX: Use throttled fetch instead of 4 sequential fetches.
        // Status changes (cancelled, completed, declined) are infrequent, so one
        // consolidated fetch is sufficient — the throttle prevents cascading.
        await throttledChallengeFetch()
        await ChallengeService.shared.fetchPendingInvites()
        
        #if DEBUG
        AppLogger.info("Challenge data refreshed after status change", category: .network)
        #endif
    }
    
    // MARK: - Daily Progress Subscription (for live challenge widget)
    
    /// Subscribe to opponent's daily progress updates
    /// This is battery-efficient: uses WebSocket (no polling), only triggers on actual changes
    private func subscribeDailyProgress(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        // Subscribe to challenge_daily_progress table
        // We listen for ALL changes, then filter client-side to only process opponent updates
        let channel = client.realtimeV2.channel("daily_progress-\(userId.uuidString)")
        
        // Listen for inserts (new daily progress logged)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "challenge_daily_progress"
        )
        
        // Listen for updates (progress value changed)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "challenge_daily_progress"
        )
        
        Task {
            for await action in inserts {
                await handleDailyProgressChange(action.record, userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handleDailyProgressChange(action.record, userId: userId)
            }
        }
        
        await channel.subscribe()
        dailyProgressChannel = channel
        
        AppLogger.debug("Subscribed to daily progress updates", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "challenge_daily_progress",
                        details: "✅ Listening for INSERT + UPDATE on challenge_daily_progress (all rows)")
    }
    
    private func handleDailyProgressChange(_ record: [String: AnyJSON]?, userId: UUID) async {
        // CRITICAL FIX: Supabase Realtime v2 sends records as [String: AnyJSON].
        // AnyJSON wraps values in enum cases (.string, .integer, .double, etc.)
        // Direct `as? String` / `as? Int` FAILS on AnyJSON — must use jsonString/jsonInt helpers.
        guard let record = record else {
            AppLogger.warning("handleDailyProgressChange: nil record", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ nil record", isError: true)
            return
        }
        
        guard let recordUserId = jsonString(record["user_id"]) else {
            AppLogger.warning("handleDailyProgressChange: missing user_id. Keys: \(record.keys.joined(separator: ", ")), types: \(record.map { "\($0.key)=\(type(of: $0.value))" }.joined(separator: ", "))", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ Missing user_id. Keys: \(record.keys.joined(separator: ", "))", isError: true)
            return
        }
        
        guard let challengeIdString = jsonString(record["challenge_id"]),
              let challengeId = UUID(uuidString: challengeIdString) else {
            AppLogger.warning("handleDailyProgressChange: missing/invalid challenge_id", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ Missing challenge_id", isError: true)
            return
        }
        
        // Use jsonInt for safe extraction — this was the ROOT BUG
        guard let progressValue = jsonInt(record["progress_value"]) else {
            AppLogger.warning("handleDailyProgressChange: cannot parse progress_value. Raw: \(String(describing: record["progress_value"])), type: \(type(of: record["progress_value"] as Any))", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress",
                            details: "❌ Cannot parse progress_value: \(String(describing: record["progress_value"]))", isError: true)
            return
        }
        
        let isOwnUpdate = recordUserId == userId.uuidString
        let targetHit = jsonBool(record["target_hit"]) ?? false
        let progressDate = jsonString(record["progress_date"]) ?? ""
        
        if isOwnUpdate {
            // ⚡️ PERF FIX: Skip fetching for own daily progress — we already have the data locally.
            // The DB just confirmed what we wrote. Fetching here caused redundant network calls.
            logRealtimeEvent(type: "OWN_DAILY_PROGRESS", source: "challenge_daily_progress",
                            details: "✅ Own progress confirmed: \(progressValue), challenge: \(challengeIdString.prefix(8)) — SKIPPED refresh")
            return
        }
        
        // ═══════════════════════════════════════════════════════════
        // OPPONENT'S daily progress changed — this is the CRITICAL path
        // ═══════════════════════════════════════════════════════════
        
        let timestamp = Date()
        #if DEBUG
        AppLogger.debug("Opponent daily progress: \(recordUserId.prefix(8)) → \(progressValue) (hit: \(targetHit)) challenge: \(challengeIdString.prefix(8))", category: .network)
        #endif
        
        logRealtimeEvent(type: "🔥 OPPONENT_DAILY_PROGRESS", source: "challenge_daily_progress",
                        details: "⚡️ Opponent \(recordUserId.prefix(8)) → \(progressValue) (hit: \(targetHit)) challenge: \(challengeIdString.prefix(8))")
        
        let payload = DailyProgressPayload(
            challengeId: challengeId,
            opponentId: UUID(uuidString: recordUserId) ?? UUID(),
            progressDate: progressDate,
            progressValue: progressValue,
            targetHit: targetHit
        )
        
        // Store for cross-device verification
        lastOpponentProgressAt = timestamp
        lastOpponentProgressEvent = payload
        
        // Trigger callback (ChallengeDetailView and GroupChallengeDetailView listen to this)
        onOpponentDailyProgressUpdated?(payload)
        
        // Refresh BOTH 1v1 and group challenges — throttled to prevent cascading duplicates
        await throttledChallengeFetch()
        
        // Haptic feedback when opponent hits their daily target
        if targetHit {
            HapticManager.notification(.warning)
        }
    }
    // MARK: - Private Challenge Progress Subscription
    
    /// Subscribe to private_challenge_daily_progress updates.
    /// When ANY member of a private challenge logs progress, all other members
    /// see it instantly via WebSocket — no polling required.
    private func subscribePrivateChallengeProgress(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("private_challenge_progress-\(userId.uuidString)")
        
        // Listen for inserts (new daily progress logged by any member)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_daily_progress"
        )
        
        // Listen for updates (progress value changed for any member)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "private_challenge_daily_progress"
        )
        
        Task {
            for await action in inserts {
                await handlePrivateChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handlePrivateChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        await channel.subscribe()
        privateChallengeChannel = channel
        
        AppLogger.debug("Subscribed to private_challenge_daily_progress updates", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "private_challenge_daily_progress",
                        details: "✅ Listening for INSERT + UPDATE on private_challenge_daily_progress")
    }
    
    private func handlePrivateChallengeProgressChange(_ record: [String: AnyJSON]?, userId: UUID) async {
        guard let record = record else { return }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let progressValue = jsonInt(record["progress_value"]) ?? 0
        
        let isOwnUpdate = recordUserId == userId.uuidString
        let challengeType = lookupPrivateChallengeType(challengeId: challengeId)
        let isManual = Self.isManualInputType(challengeType)
        
        if isOwnUpdate {
            logRealtimeEvent(type: "OWN_PRIVATE_PROGRESS", source: "private_challenge_daily_progress",
                            details: "✅ Own progress: \(progressValue), challenge: \(challengeId.prefix(8)) — SKIPPED refresh")
            // ⚡️ PERF FIX: Skip fetching for own updates — we already have the data locally.
            return
        }
        
        AppLogger.debug("Private challenge member progress: \(recordUserId.prefix(8)) → \(progressValue) (challenge: \(challengeId.prefix(8)), type: \(challengeType ?? "?"), manual: \(isManual))", category: .network)
        logRealtimeEvent(type: "🔥 PRIVATE_MEMBER_PROGRESS", source: "private_challenge_daily_progress",
                        details: "⚡️ Member \(recordUserId.prefix(8)) → \(progressValue), challenge: \(challengeId.prefix(8)), manual: \(isManual)")
        
        if isManual {
            // Manual-input challenges (protein, hydration, etc.): debounced refresh
            // Cancels any pending debounce and waits 1.5s before fetching.
            privateProgressDebounceTask?.cancel()
            privateProgressDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
                guard !Task.isCancelled else { return }
                await throttledPrivateFetch()
            }
        }
        // Auto-tracked challenges: refresh on periodic cadence timer instead.
    }
    
    // MARK: - Community Challenge Progress Subscription
    
    /// Subscribe to community_challenge_daily_progress updates.
    /// When ANY community member logs progress, the leaderboard updates live.
    private func subscribeCommunityChallengeProgress(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("community_challenge_progress-\(userId.uuidString)")
        
        // Listen for inserts (new daily progress logged by any member)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_challenge_daily_progress"
        )
        
        // Listen for updates (progress value changed for any member)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "community_challenge_daily_progress"
        )
        
        Task {
            for await action in inserts {
                await handleCommunityChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handleCommunityChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        await channel.subscribe()
        communityChallengeChannel = channel
        
        AppLogger.debug("Subscribed to community_challenge_daily_progress updates", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "community_challenge_daily_progress",
                        details: "✅ Listening for INSERT + UPDATE on community_challenge_daily_progress")
    }
    
    private func handleCommunityChallengeProgressChange(_ record: [String: AnyJSON]?, userId: UUID) async {
        guard let record = record else {
            AppLogger.warning("Community progress event with nil record", category: .network)
            return
        }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let progressValue = jsonInt(record["progress_value"]) ?? 0
        
        let isOwnUpdate = recordUserId == userId.uuidString
        
        // PERF FIX: Skip own events entirely — we already know our own progress.
        // These arrive because we subscribe without a user_id filter, and each
        // INSERT/UPDATE from our own log_community_challenge_progress triggers
        // 2 events (insert + update) that cascade into redundant fetchMyChallenges() calls.
        if isOwnUpdate {
            #if DEBUG
            AppLogger.debug("Community progress (OWN) — skipping refresh for \(challengeId.prefix(8))", category: .network)
            #endif
            logRealtimeEvent(type: "OWN_COMMUNITY_PROGRESS", source: "community_challenge_daily_progress",
                            details: "✅ Own community progress confirmed: \(progressValue), challenge: \(challengeId.prefix(8)) — SKIPPED refresh")
            return
        }
        
        let challengeType = lookupCommunityChallengeType(challengeId: challengeId)
        let isManual = Self.isManualInputType(challengeType)
        
        #if DEBUG
        AppLogger.debug("COMMUNITY PROGRESS — user: \(recordUserId.prefix(8)), challenge: \(challengeId.prefix(8)), value: \(progressValue), type: \(challengeType ?? "unknown"), manual: \(isManual)", category: .network)
        #endif
        
        logRealtimeEvent(type: "🌍 COMMUNITY_MEMBER_PROGRESS", source: "community_challenge_daily_progress",
                        details: "⚡️ Member \(recordUserId.prefix(8)) → \(progressValue), challenge: \(challengeId.prefix(8)), manual: \(isManual)")
        
        if isManual {
            // Manual-input challenges (protein, hydration, etc.): debounced refresh
            // Cancels any pending debounce and waits 1.5s before fetching, so rapid-fire
            // events (e.g. logging 3 waters in quick succession) only trigger ONE fetch.
            communityProgressDebounceTask?.cancel()
            communityProgressDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
                guard !Task.isCancelled else { return }
                AppLogger.debug("Community manual input (debounced) — refreshing community challenges", category: .network)
                await throttledCommunityFetch()
                AppLogger.info("Community challenges refreshed after member progress update", category: .network)
            }
        }
        // Auto-tracked challenges (steps, active_minutes): skip immediate refresh.
        // These update on the periodic cadence timer instead (every 90s) to avoid
        // flooding the UI with rapid HealthKit-driven updates.
    }
    
    // MARK: - Community Participants Subscription (Join/Leave Events)
    
    /// Subscribe to community_challenge_participants for real-time join/leave events.
    /// When a user joins or leaves a community challenge, all members see the update instantly.
    private func subscribeCommunityParticipants(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("community_participants-\(userId.uuidString)")
        
        // Listen for new members joining (INSERT)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_challenge_participants"
        )
        
        // Listen for member status changes (UPDATE) — e.g. deactivation
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "community_challenge_participants"
        )
        
        Task {
            for await action in inserts {
                await handleCommunityParticipantChange(action.record, type: "JOIN", userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handleCommunityParticipantChange(action.record, type: "UPDATE", userId: userId)
            }
        }
        
        await channel.subscribe()
        communityParticipantsChannel = channel
        
        AppLogger.debug("Subscribed to community_challenge_participants (join/leave)", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "community_challenge_participants",
                        details: "✅ Listening for INSERT + UPDATE on community_challenge_participants")
    }
    
    private func handleCommunityParticipantChange(_ record: [String: AnyJSON]?, type: String, userId: UUID) async {
        guard let record = record else { return }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let isOwnJoin = recordUserId == userId.uuidString
        
        AppLogger.debug("Community participant \(type): user \(recordUserId.prefix(8)) in challenge \(challengeId.prefix(8))", category: .network)
        logRealtimeEvent(type: "COMMUNITY_PARTICIPANT_\(type)", source: "community_challenge_participants",
                        details: "\(isOwnJoin ? "You" : "Member \(recordUserId.prefix(8))") \(type.lowercased()) community challenge \(challengeId.prefix(8))")
        
        // Throttled refresh — join/leave events are infrequent but can still double-fire
        await throttledCommunityFetch()
        
        if !isOwnJoin {
            HapticManager.impact(.light)
        }
    }
    
    // MARK: - Private Challenge Members Subscription (Join/Leave Events)
    
    /// Subscribe to private_challenge_members for real-time join/leave events.
    /// When a user joins or leaves a private challenge, all members see it instantly.
    private func subscribePrivateMembers(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("private_members-\(userId.uuidString)")
        
        // Listen for new members joining (INSERT)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_members"
        )
        
        // Listen for member status changes (UPDATE) — e.g. role change, deactivation
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "private_challenge_members"
        )
        
        Task {
            for await action in inserts {
                await handlePrivateMemberChange(action.record, type: "JOIN", userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handlePrivateMemberChange(action.record, type: "UPDATE", userId: userId)
            }
        }
        
        await channel.subscribe()
        privateMembersChannel = channel
        
        AppLogger.debug("Subscribed to private_challenge_members (join/leave)", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "private_challenge_members",
                        details: "✅ Listening for INSERT + UPDATE on private_challenge_members")
    }
    
    private func handlePrivateMemberChange(_ record: [String: AnyJSON]?, type: String, userId: UUID) async {
        guard let record = record else { return }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let isOwnJoin = recordUserId == userId.uuidString
        
        AppLogger.debug("Private member \(type): user \(recordUserId.prefix(8)) in challenge \(challengeId.prefix(8))", category: .network)
        logRealtimeEvent(type: "PRIVATE_MEMBER_\(type)", source: "private_challenge_members",
                        details: "\(isOwnJoin ? "You" : "Member \(recordUserId.prefix(8))") \(type.lowercased()) private challenge \(challengeId.prefix(8))")
        
        // Throttled refresh — join/leave events are infrequent but can still double-fire
        await throttledPrivateFetch()
        
        // Signal detail views to reload their member list
        PrivateChallengeService.shared.memberChangeToken = UUID()
        
        if !isOwnJoin {
            HapticManager.impact(.light)
        }
    }
    
    // MARK: - Periodic Cadence Refresh (Community + Private Challenges)
    
    /// Start the periodic refresh timer for community/private challenges.
    /// Called when realtime connects. This serves two purposes:
    /// 1. Auto-tracked challenges (steps, active_minutes) rely on this instead of instant WebSocket updates (too noisy)
    /// 2. Fallback for ALL community/private challenges in case WebSocket events aren't delivered
    ///    (e.g., Supabase Realtime publication not configured, cross-table RLS blocking events)
    ///
    /// ⚡️ PERF FIX: Only fetches when the community view is currently visible.
    /// When not visible, the timer still runs but skips fetches to avoid background network storms.
    func startAutoTrackedRefreshTimer() {
        autoTrackedRefreshTimer?.cancel()
        autoTrackedRefreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.autoTrackedRefreshInterval)
                guard !Task.isCancelled else { break }
                
                // ⚡️ PERF FIX: Only refresh when the community view is visible.
                // Background refreshes were firing every 30s regardless, causing
                // network storms and @MainActor contention that froze the UI.
                guard CommunityChallengeService.shared.isCommunityViewVisible else {
                    continue
                }
                
                // Skip if we already fetched recently from a realtime event (prevents redundant calls)
                let communityStale = lastCommunityFetchTime.map { Date().timeIntervalSince($0) > 30 } ?? true
                let privateStale = lastPrivateFetchTime.map { Date().timeIntervalSince($0) > 30 } ?? true
                
                let hasCommunity = !CommunityChallengeService.shared.myChallenges.isEmpty
                let hasPrivate = !PrivateChallengeService.shared.myChallenges.isEmpty
                
                if (hasCommunity && communityStale) || (hasPrivate && privateStale) {
                    AppLogger.debug("Cadence refresh for community/private challenges (every \(Self.autoTrackedRefreshInterval / 1_000_000_000)s)", category: .network)
                    
                    if hasCommunity && communityStale {
                        lastCommunityFetchTime = Date()
                        await CommunityChallengeService.shared.fetchMyChallenges()
                    }
                    if hasPrivate && privateStale {
                        lastPrivateFetchTime = Date()
                        await PrivateChallengeService.shared.fetchMyChallenges()
                    }
                }
            }
        }
    }
    
    /// Stop the periodic refresh timer (called on disconnect).
    func stopAutoTrackedRefreshTimer() {
        autoTrackedRefreshTimer?.cancel()
        autoTrackedRefreshTimer = nil
    }
}

// MARK: - Payload Types

struct FriendRequestPayload {
    let friendshipId: UUID
    let requesterId: UUID
    let addresseeId: UUID
    let status: String
    let createdAt: Date
}

struct SharedWorkoutPayload {
    let workoutId: UUID
    let senderId: UUID
    let recipientId: UUID
    let workoutName: String
    let status: String
    let createdAt: Date
}

struct ChallengePayload {
    let challengeId: UUID
    let participantId: UUID
    let status: String
    let totalProgress: Int
}

struct DailyProgressPayload {
    let challengeId: UUID
    let opponentId: UUID
    let progressDate: String
    let progressValue: Int
    let targetHit: Bool
}

/// Entry for the realtime event debug log (visible in simulator & dev menu)
struct RealtimeEventEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: String           // e.g. "OPPONENT_DAILY_PROGRESS", "CHALLENGE_STATUS", etc.
    let source: String         // e.g. "challenge_daily_progress", "challenge_participants"
    let details: String
    let isError: Bool
    
    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}

// MARK: - App Integration Extension

extension RealtimeService {
    /// Setup default callbacks for notifications
    /// Call this after authentication
    func setupDefaultCallbacks() {
        // Friend request received → refresh data (push notification handles the alert)
        onFriendRequestReceived = { payload in
            Task { @MainActor in
                // Refresh immediately so the UI shows the request instantly
                await FriendService.shared.fetchPendingRequests()
                NotificationManager.shared.updateBadgeCount()
                AppLogger.debug("Friend request data refreshed from realtime callback", category: .network)
                // NOTE: No local notification here — the push notification from Supabase
                // handles the user-facing alert. Sending both would cause duplicates.
            }
        }
        
        // Friend request accepted → refresh data (push notification handles the alert)
        onFriendRequestAccepted = { _ in
            Task { @MainActor in
                await FriendService.shared.fetchFriends()
                AppLogger.debug("Friends list refreshed after acceptance", category: .network)
            }
        }
        
        // Workout received → refresh data (push notification handles the alert)
        onWorkoutReceived = { _ in
            Task { @MainActor in
                await FriendService.shared.loadReceivedWorkouts()
                NotificationManager.shared.updateBadgeCount()
                AppLogger.debug("Received workouts refreshed from realtime", category: .network)
            }
        }
        
        // Challenge invite → refresh data (push notification handles the alert)
        onChallengeInviteReceived = { _ in
            Task { @MainActor in
                await ChallengeService.shared.fetchPendingInvites()
                await ChallengeService.shared.fetchActiveGroupChallenges()
                NotificationManager.shared.updateBadgeCount()
                AppLogger.debug("Challenge invites refreshed from realtime", category: .network)
            }
        }
        
        AppLogger.info("Default callbacks configured", category: .network)
    }
    
    /// Fetch a user's display name
    private func fetchUserName(userId: UUID) async -> String {
        do {
            struct UserProfile: Decodable {
                let name: String?
                let username: String?
            }
            
            let response: [UserProfile] = try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .select("name, username")
                .eq("id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            
            if let profile = response.first {
                return profile.name ?? profile.username ?? "Someone"
            }
        } catch {
            AppLogger.warning("Error fetching user name: \(error.localizedDescription)", category: .network)
        }
        
        return "Someone"
    }
}
