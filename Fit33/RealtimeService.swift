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
            print("⚠️ [REALTIME] Cannot connect - not authenticated")
            return
        }
        
        // BUG FIX: Disconnect existing channels BEFORE creating new ones.
        // Without this, calling connect() twice (e.g. from .task + .active scenePhase)
        // creates duplicate channels, causing "postgresChange after joining" warnings.
        if isConnected || friendshipsChannel != nil {
            print("🔄 [REALTIME] Cleaning up existing channels before reconnecting...")
            await disconnect()
        }
        
        print("🔄 [REALTIME] Connecting to realtime channels...")
        
        // Subscribe to all relevant channels
        await subscribeFriendships(userId: userId)
        await subscribeSharedWorkouts(userId: userId)
        await subscribeChallenges(userId: userId)
        await subscribeDailyProgress(userId: userId)
        
        isConnected = true
        connectionError = nil
        print("✅ [REALTIME] Connected to all channels")
        logRealtimeEvent(type: "CONNECTED", source: "RealtimeService",
                        details: "✅ All 4 channels active: friendships, shared_workouts, challenges, daily_progress")
    }
    
    /// Disconnect from all realtime channels
    func disconnect() async {
        print("🔌 [REALTIME] Disconnecting from channels...")
        
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
        
        friendshipsChannel = nil
        sharedWorkoutsChannel = nil
        challengesChannel = nil
        dailyProgressChannel = nil
        
        isConnected = false
        print("✅ [REALTIME] Disconnected from all channels")
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
        
        print("📡 [REALTIME] Subscribed to friendships for user \(userId)")
    }
    
    private func handleFriendshipInsert(_ action: InsertAction) async {
        let record = action.record
        guard let status = jsonString(record["status"]),
              status == "pending" else { return }
        
        print("🔔 [REALTIME] New friend request received!")
        
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
            print("🎉 [REALTIME] Friend request accepted!")
            
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
        
        print("📡 [REALTIME] Subscribed to shared_workouts for user \(userId)")
    }
    
    private func handleSharedWorkoutInsert(_ action: InsertAction) async {
        let record = action.record
        
        print("💪 [REALTIME] New workout shared!")
        
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
        
        print("📡 [REALTIME] Subscribed to challenges for user \(userId)")
        logRealtimeEvent(type: "SUBSCRIBED", source: "challenges",
                        details: "✅ Listening on challenge_participants (INSERT+UPDATE) + group_challenges (UPDATE)")
    }
    
    private func handleChallengeInvite(_ action: InsertAction) async {
        let record = action.record
        guard let status = jsonString(record["status"]),
              status == "pending" else { return }
        
        print("🏆 [REALTIME] New challenge invite!")
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
        
        print("🔔 [REALTIME] MY challenge participant: status \(oldStatus) → \(newStatus), progress \(oldTotalProgress) → \(totalProgress) (challenge: \(challengeId))")
        logRealtimeEvent(type: "MY_PARTICIPANT", source: "challenge_participants",
                        details: "status: \(oldStatus)→\(newStatus), progress: \(oldTotalProgress)→\(totalProgress), challenge: \(challengeId.prefix(8))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            print("✅ [REALTIME] I accepted a challenge - refreshing all lists (1v1 + group)")
            await ChallengeService.shared.fetchPendingInvites()  // Remove from pending
            await ChallengeService.shared.fetchActiveChallenges()  // Add to active (1v1)
            await ChallengeService.shared.fetchActiveGroupChallenges()  // Add to active (group)
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            print("❌ [REALTIME] I declined a challenge")
            await ChallengeService.shared.fetchPendingInvites()
        } else if totalProgress != oldTotalProgress {
            // My progress was confirmed in DB — refresh group challenges to show DB-backed values
            print("📊 [REALTIME] My own progress confirmed in DB: \(totalProgress) — refreshing")
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchActiveGroupChallenges()
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
        
        print("🔔 [REALTIME] OPPONENT challenge participant: \(oldStatus) → \(newStatus), progress: \(oldTotalProgress) → \(totalProgress) (challenge: \(challengeId))")
        logRealtimeEvent(type: "OPPONENT_PARTICIPANT", source: "challenge_participants",
                        details: "user: \(participantUserId.prefix(8)), status: \(oldStatus)→\(newStatus), progress: \(oldTotalProgress)→\(totalProgress), challenge: \(challengeId.prefix(8))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            print("✅ [REALTIME] Opponent ACCEPTED my challenge - moving from sent → active (1v1 + group)")
            logRealtimeEvent(type: "OPPONENT_ACCEPTED", source: "challenge_participants",
                            details: "✅ Opponent accepted! Refreshing all lists...")
            await ChallengeService.shared.fetchPendingSentChallenges()  // Remove from sent
            await ChallengeService.shared.fetchActiveChallenges()  // Add to active (1v1)
            await ChallengeService.shared.fetchActiveGroupChallenges()  // Add to active (group)
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            print("❌ [REALTIME] Opponent DECLINED my challenge - removing from sent")
            logRealtimeEvent(type: "OPPONENT_DECLINED", source: "challenge_participants",
                            details: "Opponent declined challenge \(challengeId.prefix(8))")
            await ChallengeService.shared.fetchPendingSentChallenges()
        } else if totalProgress != oldTotalProgress {
            // Opponent's progress changed (they logged new steps/hydration/etc.)
            print("📊 [REALTIME] Opponent progress changed: \(oldTotalProgress) → \(totalProgress) - refreshing all challenges")
            logRealtimeEvent(type: "OPPONENT_PROGRESS", source: "challenge_participants",
                            details: "🔥 Progress: \(oldTotalProgress)→\(totalProgress) for challenge \(challengeId.prefix(8))")
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchActiveGroupChallenges()
        } else {
            // DEFENSIVE: Even if progress looks unchanged, refresh if we got an update event
            // This catches cases where oldRecord is empty (REPLICA IDENTITY not FULL)
            let hasOldData = !oldRecord.isEmpty
            if !hasOldData {
                print("⚠️ [REALTIME] No old record data — REPLICA IDENTITY may not be FULL. Refreshing defensively.")
                logRealtimeEvent(type: "OPPONENT_UPDATE_NO_OLD", source: "challenge_participants",
                                details: "⚠️ No old record data — refreshing defensively. newProgress=\(totalProgress)")
                await ChallengeService.shared.fetchActiveChallenges()
                await ChallengeService.shared.fetchActiveGroupChallenges()
            }
        }
    }
    
    private func handleChallengeProgress(_ action: UpdateAction, userId: UUID) async {
        let record = action.record
        
        guard let participantUserId = jsonString(record["user_id"]) else {
            print("⚠️ [REALTIME] handleChallengeProgress: missing user_id. Keys: \(record.keys.joined(separator: ", "))")
            logRealtimeEvent(type: "CHALLENGE_PROGRESS", source: "challenge_participants", details: "❌ Missing user_id in record", isError: true)
            return
        }
        
        let challengeId = jsonString(record["challenge_id"]) ?? "unknown"
        let status = jsonString(record["status"]) ?? ""
        let totalProgress = jsonInt(record["total_progress"]) ?? 0
        
        print("🔔 [REALTIME] Challenge participant updated!")
        print("   Challenge ID: \(challengeId)")
        print("   Participant: \(participantUserId)")
        print("   Status: \(status)")
        print("   Progress: \(totalProgress)")
        
        logRealtimeEvent(type: "CHALLENGE_PROGRESS", source: "challenge_participants",
                        details: "user: \(participantUserId.prefix(8)), challenge: \(challengeId.prefix(8)), status: \(status), progress: \(totalProgress)")
        
        // If it's my own update, skip
        if participantUserId == userId.uuidString {
            print("⏭️ [REALTIME] Skipping own update")
            return
        }
        
        print("📊 [REALTIME] Opponent's progress/status changed - refreshing!")
        
        let payload = ChallengePayload(
            challengeId: UUID(uuidString: challengeId) ?? UUID(),
            participantId: UUID(uuidString: participantUserId) ?? UUID(),
            status: status,
            totalProgress: totalProgress
        )
        
        // Trigger callback
        onChallengeProgressUpdated?(payload)
        
        // Refresh all challenge data (in case status changed from pending to accepted)
        await ChallengeService.shared.fetchActiveChallenges()
        await ChallengeService.shared.fetchActiveGroupChallenges()
        await ChallengeService.shared.fetchPendingInvites()
        await ChallengeService.shared.fetchPendingSentChallenges()
        print("✅ [REALTIME] Challenge data refreshed after participant update")
    }
    
    private func handleChallengeStatusChange(_ action: UpdateAction) async {
        let record = action.record
        
        let challengeId = jsonString(record["id"]) ?? "unknown"
        let status = jsonString(record["status"]) ?? ""
        
        print("🔔 [REALTIME] Challenge status changed!")
        print("   Challenge ID: \(challengeId)")
        print("   New Status: \(status)")
        logRealtimeEvent(type: "CHALLENGE_STATUS", source: "group_challenges", details: "Challenge \(challengeId.prefix(8)) → \(status)")
        
        if status == "active" {
            print("🎯 [REALTIME] Challenge is now ACTIVE! Both participants accepted.")
        } else if status == "completed" {
            print("🏁 [REALTIME] Challenge COMPLETED!")
        } else if status == "cancelled" {
            print("❌ [REALTIME] Challenge CANCELLED! Refreshing to remove from all lists...")
        } else if status == "declined" {
            print("👎 [REALTIME] Challenge DECLINED!")
        }
        
        // Refresh all challenge states - this handles when opponent accepts/declines/cancels
        print("🔄 [REALTIME] Refreshing all challenge data...")
        await ChallengeService.shared.fetchActiveChallenges()
        await ChallengeService.shared.fetchActiveGroupChallenges()
        await ChallengeService.shared.fetchPendingInvites()  // This will remove cancelled challenges
        await ChallengeService.shared.fetchPendingSentChallenges()
        
        print("✅ [REALTIME] Challenge data refreshed")
        print("   Active 1v1: \(ChallengeService.shared.activeChallenges.count)")
        print("   Active Group: \(ChallengeService.shared.activeGroupChallenges.count)")
        print("   Pending Invites: \(ChallengeService.shared.pendingInvites.count)")
        print("   Pending Sent: \(ChallengeService.shared.pendingSentChallenges.count)")
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
        
        print("📡 [REALTIME] Subscribed to daily progress updates")
        logRealtimeEvent(type: "SUBSCRIBED", source: "challenge_daily_progress",
                        details: "✅ Listening for INSERT + UPDATE on challenge_daily_progress (all rows)")
    }
    
    private func handleDailyProgressChange(_ record: [String: AnyJSON]?, userId: UUID) async {
        // CRITICAL FIX: Supabase Realtime v2 sends records as [String: AnyJSON].
        // AnyJSON wraps values in enum cases (.string, .integer, .double, etc.)
        // Direct `as? String` / `as? Int` FAILS on AnyJSON — must use jsonString/jsonInt helpers.
        guard let record = record else {
            print("⚠️ [REALTIME] handleDailyProgressChange: nil record")
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ nil record", isError: true)
            return
        }
        
        guard let recordUserId = jsonString(record["user_id"]) else {
            print("⚠️ [REALTIME] handleDailyProgressChange: missing user_id. Keys: \(record.keys.joined(separator: ", ")), types: \(record.map { "\($0.key)=\(type(of: $0.value))" }.joined(separator: ", "))")
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ Missing user_id. Keys: \(record.keys.joined(separator: ", "))", isError: true)
            return
        }
        
        guard let challengeIdString = jsonString(record["challenge_id"]),
              let challengeId = UUID(uuidString: challengeIdString) else {
            print("⚠️ [REALTIME] handleDailyProgressChange: missing/invalid challenge_id")
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ Missing challenge_id", isError: true)
            return
        }
        
        // Use jsonInt for safe extraction — this was the ROOT BUG
        guard let progressValue = jsonInt(record["progress_value"]) else {
            print("⚠️ [REALTIME] handleDailyProgressChange: cannot parse progress_value. Raw: \(String(describing: record["progress_value"])), type: \(type(of: record["progress_value"] as Any))")
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress",
                            details: "❌ Cannot parse progress_value: \(String(describing: record["progress_value"]))", isError: true)
            return
        }
        
        let isOwnUpdate = recordUserId == userId.uuidString
        let targetHit = jsonBool(record["target_hit"]) ?? false
        let progressDate = jsonString(record["progress_date"]) ?? ""
        
        if isOwnUpdate {
            // Own progress was written to DB — refresh so widgets show updated data
            print("📊 [REALTIME] Own daily progress confirmed in DB: \(progressValue) — refreshing all challenges")
            logRealtimeEvent(type: "OWN_DAILY_PROGRESS", source: "challenge_daily_progress",
                            details: "✅ Own progress confirmed: \(progressValue), challenge: \(challengeIdString.prefix(8))")
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchActiveGroupChallenges()
            return
        }
        
        // ═══════════════════════════════════════════════════════════
        // OPPONENT'S daily progress changed — this is the CRITICAL path
        // ═══════════════════════════════════════════════════════════
        
        let timestamp = Date()
        print("🎯 [REALTIME] ⚡️ OPPONENT DAILY PROGRESS UPDATE RECEIVED ⚡️")
        print("   Challenge: \(challengeIdString.prefix(8))")
        print("   Opponent: \(recordUserId.prefix(8))")
        print("   Progress: \(progressValue)")
        print("   Target Hit: \(targetHit)")
        print("   Date: \(progressDate)")
        print("   Received at: \(timestamp)")
        
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
        
        // Refresh BOTH 1v1 and group challenges so all widgets update IMMEDIATELY
        async let fetch1v1: () = ChallengeService.shared.fetchActiveChallenges()
        async let fetchGroup: () = ChallengeService.shared.fetchActiveGroupChallenges()
        _ = await (fetch1v1, fetchGroup)
        
        print("✅ [REALTIME] Challenge data refreshed after opponent progress update")
        logRealtimeEvent(type: "REFRESH_COMPLETE", source: "ChallengeService",
                        details: "✅ Refreshed 1v1 + group challenges after opponent update")
        
        // Haptic feedback when opponent hits their daily target
        if targetHit {
            HapticManager.notification(.warning)
        }
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
                print("📡 [REALTIME] Friend request data refreshed from realtime callback")
                // NOTE: No local notification here — the push notification from Supabase
                // handles the user-facing alert. Sending both would cause duplicates.
            }
        }
        
        // Friend request accepted → refresh data (push notification handles the alert)
        onFriendRequestAccepted = { _ in
            Task { @MainActor in
                await FriendService.shared.fetchFriends()
                print("📡 [REALTIME] Friends list refreshed after acceptance")
            }
        }
        
        // Workout received → refresh data (push notification handles the alert)
        onWorkoutReceived = { _ in
            Task { @MainActor in
                await FriendService.shared.loadReceivedWorkouts()
                NotificationManager.shared.updateBadgeCount()
                print("📡 [REALTIME] Received workouts refreshed from realtime")
            }
        }
        
        // Challenge invite → refresh data (push notification handles the alert)
        onChallengeInviteReceived = { _ in
            Task { @MainActor in
                await ChallengeService.shared.fetchPendingInvites()
                await ChallengeService.shared.fetchActiveGroupChallenges()
                NotificationManager.shared.updateBadgeCount()
                print("📡 [REALTIME] Challenge invites refreshed from realtime")
            }
        }
        
        print("✅ [REALTIME] Default callbacks configured")
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
            print("⚠️ [REALTIME] Error fetching user name: \(error)")
        }
        
        return "Someone"
    }
}
