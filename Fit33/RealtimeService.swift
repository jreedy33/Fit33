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
    
    // MARK: - Connection Management
    
    /// Start all realtime subscriptions for the current user
    func connect() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [REALTIME] Cannot connect - not authenticated")
            return
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
        guard let record = action.record as? [String: Any],
              let status = record["status"] as? String,
              status == "pending" else { return }
        
        print("🔔 [REALTIME] New friend request received!")
        
        let payload = FriendRequestPayload(
            friendshipId: UUID(uuidString: record["id"] as? String ?? "") ?? UUID(),
            requesterId: UUID(uuidString: record["requester_id"] as? String ?? "") ?? UUID(),
            addresseeId: UUID(uuidString: record["addressee_id"] as? String ?? "") ?? UUID(),
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
        guard let record = action.record as? [String: Any],
              let status = record["status"] as? String else { return }
        
        if status == "accepted" {
            print("🎉 [REALTIME] Friend request accepted!")
            
            let payload = FriendRequestPayload(
                friendshipId: UUID(uuidString: record["id"] as? String ?? "") ?? UUID(),
                requesterId: UUID(uuidString: record["requester_id"] as? String ?? "") ?? UUID(),
                addresseeId: UUID(uuidString: record["addressee_id"] as? String ?? "") ?? UUID(),
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
        guard let record = action.record as? [String: Any] else { return }
        
        print("💪 [REALTIME] New workout shared!")
        
        let payload = SharedWorkoutPayload(
            workoutId: UUID(uuidString: record["id"] as? String ?? "") ?? UUID(),
            senderId: UUID(uuidString: record["sender_id"] as? String ?? "") ?? UUID(),
            recipientId: UUID(uuidString: record["recipient_id"] as? String ?? "") ?? UUID(),
            workoutName: record["workout_name"] as? String ?? "Workout",
            status: record["status"] as? String ?? "pending",
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
        
        Task {
            for await action in participantStatusChanges {
                await handleChallengeProgress(action, userId: userId)
            }
        }
        
        Task {
            for await action in allParticipantUpdates {
                await handleChallengeProgress(action, userId: userId)
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
    }
    
    private func handleChallengeInvite(_ action: InsertAction) async {
        guard let record = action.record as? [String: Any],
              let status = record["status"] as? String,
              status == "pending" else { return }
        
        print("🏆 [REALTIME] New challenge invite!")
        
        let payload = ChallengePayload(
            challengeId: UUID(uuidString: record["challenge_id"] as? String ?? "") ?? UUID(),
            participantId: UUID(uuidString: record["user_id"] as? String ?? "") ?? UUID(),
            status: status,
            totalProgress: record["total_progress"] as? Int ?? 0
        )
        
        // Trigger callback
        onChallengeInviteReceived?(payload)
        
        // Refresh challenge invites
        await ChallengeService.shared.fetchPendingInvites()
        
        // Haptic feedback
        HapticManager.notification(.success)
    }
    
    private func handleParticipantStatusChange(_ action: UpdateAction, userId: UUID) async {
        guard let record = action.record as? [String: Any] else { return }
        
        let challengeId = (record["challenge_id"] as? String) ?? ""
        let oldRecord = action.oldRecord as? [String: Any]
        let oldStatus = (oldRecord?["status"] as? String) ?? ""
        let newStatus = (record["status"] as? String) ?? ""
        
        print("🔔 [REALTIME] MY challenge participant status: \(oldStatus) → \(newStatus) (challenge: \(challengeId))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            print("✅ [REALTIME] I accepted a challenge - refreshing all lists")
            await ChallengeService.shared.fetchPendingInvites()  // Remove from pending
            await ChallengeService.shared.fetchActiveChallenges()  // Add to active
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            print("❌ [REALTIME] I declined a challenge")
            await ChallengeService.shared.fetchPendingInvites()
        }
    }
    
    private func handleAllParticipantUpdates(_ action: UpdateAction, userId: UUID) async {
        guard let record = action.record as? [String: Any] else { return }
        
        let participantUserId = (record["user_id"] as? String) ?? ""
        let challengeId = (record["challenge_id"] as? String) ?? ""
        let oldRecord = action.oldRecord as? [String: Any]
        let oldStatus = (oldRecord?["status"] as? String) ?? ""
        let newStatus = (record["status"] as? String) ?? ""
        
        // Skip if it's my own update (already handled above)
        guard participantUserId != userId.uuidString else { return }
        
        print("🔔 [REALTIME] OPPONENT challenge participant: \(oldStatus) → \(newStatus) (challenge: \(challengeId))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            print("✅ [REALTIME] Opponent ACCEPTED my challenge - moving from sent → active")
            await ChallengeService.shared.fetchPendingSentChallenges()  // Remove from sent
            await ChallengeService.shared.fetchActiveChallenges()  // Add to active
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            print("❌ [REALTIME] Opponent DECLINED my challenge - removing from sent")
            await ChallengeService.shared.fetchPendingSentChallenges()
        }
    }
    
    private func handleChallengeProgress(_ action: UpdateAction, userId: UUID) async {
        guard let record = action.record as? [String: Any],
              let participantUserId = record["user_id"] as? String else {
            print("⚠️ [REALTIME] handleChallengeProgress: missing data")
            return
        }
        
        let challengeId = (record["challenge_id"] as? String) ?? "unknown"
        let status = (record["status"] as? String) ?? ""
        let totalProgress = (record["total_progress"] as? Int) ?? 0
        
        print("🔔 [REALTIME] Challenge participant updated!")
        print("   Challenge ID: \(challengeId)")
        print("   Participant: \(participantUserId)")
        print("   Status: \(status)")
        print("   Progress: \(totalProgress)")
        
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
        await ChallengeService.shared.fetchPendingInvites()
        await ChallengeService.shared.fetchPendingSentChallenges()
        print("✅ [REALTIME] Challenge data refreshed after participant update")
    }
    
    private func handleChallengeStatusChange(_ action: UpdateAction) async {
        guard let record = action.record as? [String: Any] else {
            print("⚠️ [REALTIME] handleChallengeStatusChange: no record data")
            return
        }
        
        let challengeId = (record["id"] as? String) ?? "unknown"
        let status = (record["status"] as? String) ?? ""
        
        print("🔔 [REALTIME] Challenge status changed!")
        print("   Challenge ID: \(challengeId)")
        print("   New Status: \(status)")
        
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
        await ChallengeService.shared.fetchPendingInvites()  // This will remove cancelled challenges
        await ChallengeService.shared.fetchPendingSentChallenges()
        
        print("✅ [REALTIME] Challenge data refreshed")
        print("   Active: \(ChallengeService.shared.activeChallenges.count)")
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
    }
    
    private func handleDailyProgressChange(_ record: [String: Any]?, userId: UUID) async {
        guard let record = record,
              let opponentUserId = record["user_id"] as? String,
              opponentUserId != userId.uuidString, // Only process OPPONENT's updates, not my own
              let challengeIdString = record["challenge_id"] as? String,
              let challengeId = UUID(uuidString: challengeIdString),
              let progressValue = record["progress_value"] as? Int else {
            return
        }
        
        let targetHit = record["target_hit"] as? Bool ?? false
        let progressDate = record["progress_date"] as? String ?? ""
        
        print("🎯 [REALTIME] Opponent daily progress: \(progressValue), target hit: \(targetHit)")
        
        let payload = DailyProgressPayload(
            challengeId: challengeId,
            opponentId: UUID(uuidString: opponentUserId) ?? UUID(),
            progressDate: progressDate,
            progressValue: progressValue,
            targetHit: targetHit
        )
        
        // Trigger callback (ChallengeDetailView listens to this)
        onOpponentDailyProgressUpdated?(payload)
        
        // Refresh active challenges so the list view also updates
        await ChallengeService.shared.fetchActiveChallenges()
        
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

// MARK: - App Integration Extension

extension RealtimeService {
    /// Setup default callbacks for notifications
    /// Call this after authentication
    func setupDefaultCallbacks() {
        // Friend request received → show local notification
        onFriendRequestReceived = { payload in
            Task {
                // Fetch the sender's name
                let senderName = await self.fetchUserName(userId: payload.requesterId)
                
                NotificationManager.shared.sendFriendRequestNotification(
                    fromName: senderName,
                    requestId: payload.friendshipId.uuidString
                )
            }
        }
        
        // Friend request accepted → show notification
        onFriendRequestAccepted = { payload in
            Task {
                let accepterName = await self.fetchUserName(userId: payload.addresseeId)
                
                NotificationManager.shared.sendFriendRequestAcceptedNotification(
                    accepterName: accepterName,
                    friendId: payload.addresseeId.uuidString
                )
            }
        }
        
        // Workout received → show notification
        onWorkoutReceived = { payload in
            Task {
                let senderName = await self.fetchUserName(userId: payload.senderId)
                
                NotificationManager.shared.sendSharedWorkoutNotification(
                    senderName: senderName,
                    workoutName: payload.workoutName,
                    workoutId: payload.workoutId.uuidString
                )
            }
        }
        
        // Challenge invite → show notification
        onChallengeInviteReceived = { payload in
            Task {
                // Fetch challenge details
                if let challenge = await ChallengeService.shared.getChallengeDetails(challengeId: payload.challengeId) {
                    let participants = challenge.participants ?? []
                    let creator = participants.first { $0.isCreator }
                    
                    NotificationManager.shared.sendChallengeInviteNotification(
                        fromName: creator?.displayName ?? "A friend",
                        challengeTitle: challenge.title,
                        challengeId: payload.challengeId.uuidString
                    )
                }
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
