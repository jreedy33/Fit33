//
//  PrivateChallengeService.swift
//  Fit33
//
//  Private Challenge System — invite-only challenge communities.
//  The creator is admin and can invite friends, manage members, and configure the challenge.
//  Members must be invited & accept before joining. Think: office step challenge, friend group fitness.
//

import Foundation
import SwiftUI
import Supabase
import Realtime

// MARK: - Private Challenge Models

/// A member in a private challenge (used in top_members JSON array and leaderboard)
struct PrivateChallengeMember: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let role: String?
    let todayProgress: Int?
    let daysCompleted: Int?
    let currentStreak: Int?
    let bestStreak: Int?
    let targetHitToday: Bool?
    let isCurrentUser: Bool?
    let rank: Int?
    
    var id: UUID { userId }
    
    var displayName: String {
        if let name = name, !name.isEmpty { return name }
        if let username = username, !username.isEmpty { return "@\(username)" }
        return "Anonymous"
    }
    
    var firstName: String {
        name?.components(separatedBy: " ").first ?? username ?? "User"
    }
    
    var initial: String {
        String(firstName.prefix(1)).uppercased()
    }
    
    var isAdmin: Bool { role == "admin" }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, username
        case profilePhotoUrl = "profile_photo_url"
        case role
        case todayProgress = "today_progress"
        case daysCompleted = "days_completed"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case targetHitToday = "target_hit_today"
        case isCurrentUser = "is_current_user"
        case rank
    }
}

/// A private challenge summary (returned by get_my_private_challenges)
struct PrivateChallenge: Codable, Identifiable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let memberCount: Int
    let maxMembers: Int?
    let joinCode: String
    let isRecurring: Bool
    let showLeaderboard: Bool
    let allowMemberInvites: Bool
    let myTodayProgress: Int?
    let myDaysCompleted: Int?
    let myCurrentStreak: Int?
    let myRole: String?
    let myRank: Int?
    let createdBy: UUID?
    let creatorName: String?
    let creatorUsername: String?
    let status: String?
    let topMembers: [PrivateChallengeMember]?
    let lastChatMessage: String?
    let lastChatSender: String?
    let lastChatAt: Date?
    let unreadCount: Int?
    
    var id: UUID { challengeId }
    
    var displayEmoji: String { emoji ?? "🔒" }
    
    var isAdmin: Bool { myRole == "admin" }
    
    var resolvedType: ChallengeType {
        ChallengeType(rawValue: challengeType) ?? .steps
    }
    
    /// Progress percentage for today (0.0 to 1.0)
    var todayProgressPercentage: Double {
        guard dailyTarget > 0 else { return 0 }
        return min(1.0, Double(myTodayProgress ?? 0) / Double(dailyTarget))
    }
    
    /// Whether today's target is hit
    var targetHitToday: Bool {
        (myTodayProgress ?? 0) >= dailyTarget
    }
    
    var formattedMemberCount: String {
        if let max = maxMembers {
            return "\(memberCount)/\(max)"
        }
        return "\(memberCount)"
    }
    
    /// Shareable URL for this challenge
    var shareURL: URL? {
        URL(string: "https://fit33.app/pc/\(joinCode)")
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case memberCount = "member_count"
        case maxMembers = "max_members"
        case joinCode = "join_code"
        case isRecurring = "is_recurring"
        case showLeaderboard = "show_leaderboard"
        case allowMemberInvites = "allow_member_invites"
        case myTodayProgress = "my_today_progress"
        case myDaysCompleted = "my_days_completed"
        case myCurrentStreak = "my_current_streak"
        case myRole = "my_role"
        case myRank = "my_rank"
        case createdBy = "created_by"
        case creatorName = "creator_name"
        case creatorUsername = "creator_username"
        case status
        case topMembers = "top_members"
        case lastChatMessage = "last_chat_message"
        case lastChatSender = "last_chat_sender"
        case lastChatAt = "last_chat_at"
        case unreadCount = "unread_count"
    }
}

/// Full detail response for a private challenge
struct PrivateChallengeDetail: Codable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let memberCount: Int
    let maxMembers: Int?
    let joinCode: String
    let isRecurring: Bool
    let showLeaderboard: Bool
    let allowMemberInvites: Bool
    let notificationsEnabled: Bool
    let totalCompletions: Int
    let createdBy: UUID
    let status: String
    let createdAt: Date?
    // My stats
    let myTodayProgress: Int
    let myDaysCompleted: Int
    let myCurrentStreak: Int
    let myBestStreak: Int
    let myTotalProgress: Int
    let myRank: Int
    let myRole: String
    // Community stats
    let avgTodayProgress: Int
    let topTodayProgress: Int
    let totalActiveToday: Int
    let completionRateToday: Double
    // Full leaderboard
    let leaderboard: [PrivateChallengeMember]?
    // Pending invites count
    let pendingInvitesCount: Int
    
    var displayEmoji: String { emoji ?? "🔒" }
    var isAdmin: Bool { myRole == "admin" }
    
    var resolvedType: ChallengeType {
        ChallengeType(rawValue: challengeType) ?? .steps
    }
    
    var todayProgressPercentage: Double {
        guard dailyTarget > 0 else { return 0 }
        return min(1.0, Double(myTodayProgress) / Double(dailyTarget))
    }
    
    var targetHitToday: Bool {
        myTodayProgress >= dailyTarget
    }
    
    var formattedMemberCount: String {
        if let max = maxMembers {
            return "\(memberCount)/\(max)"
        }
        return "\(memberCount)"
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case memberCount = "member_count"
        case maxMembers = "max_members"
        case joinCode = "join_code"
        case isRecurring = "is_recurring"
        case showLeaderboard = "show_leaderboard"
        case allowMemberInvites = "allow_member_invites"
        case notificationsEnabled = "notifications_enabled"
        case totalCompletions = "total_completions"
        case createdBy = "created_by"
        case status
        case createdAt = "created_at"
        case myTodayProgress = "my_today_progress"
        case myDaysCompleted = "my_days_completed"
        case myCurrentStreak = "my_current_streak"
        case myBestStreak = "my_best_streak"
        case myTotalProgress = "my_total_progress"
        case myRank = "my_rank"
        case myRole = "my_role"
        case avgTodayProgress = "avg_today_progress"
        case topTodayProgress = "top_today_progress"
        case totalActiveToday = "total_active_today"
        case completionRateToday = "completion_rate_today"
        case leaderboard
        case pendingInvitesCount = "pending_invites_count"
    }
}

/// An invite to a private challenge (received by the user)
struct PrivateChallengeInvite: Codable, Identifiable {
    let inviteId: UUID
    let challengeId: UUID
    let challengeTitle: String
    let challengeEmoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let memberCount: Int
    let inviterId: UUID
    let inviterName: String?
    let inviterUsername: String?
    let inviterPhotoUrl: String?
    let createdAt: Date?
    
    var id: UUID { inviteId }
    
    var displayEmoji: String { challengeEmoji ?? "🔒" }
    
    var inviterDisplayName: String {
        if let name = inviterName, !name.isEmpty { return name }
        if let username = inviterUsername, !username.isEmpty { return "@\(username)" }
        return "Someone"
    }
    
    var inviterFirstName: String {
        inviterName?.components(separatedBy: " ").first ?? inviterUsername ?? "Someone"
    }
    
    var inviterInitial: String {
        String(inviterFirstName.prefix(1)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
        case challengeId = "challenge_id"
        case challengeTitle = "challenge_title"
        case challengeEmoji = "challenge_emoji"
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case memberCount = "member_count"
        case inviterId = "inviter_id"
        case inviterName = "inviter_name"
        case inviterUsername = "inviter_username"
        case inviterPhotoUrl = "inviter_photo_url"
        case createdAt = "created_at"
    }
}

/// A chat message in a private challenge
struct PrivateChallengeMessage: Codable, Identifiable {
    let messageId: UUID
    let senderId: UUID
    let senderName: String?
    let senderUsername: String?
    let senderPhotoUrl: String?
    let messageType: String
    let content: String
    let metadata: [String: AnyCodable]?
    let createdAt: Date?
    let isCurrentUser: Bool
    
    var id: UUID { messageId }
    
    var senderDisplayName: String {
        if let name = senderName, !name.isEmpty { return name }
        if let username = senderUsername, !username.isEmpty { return "@\(username)" }
        return "Anonymous"
    }
    
    var senderFirstName: String {
        senderName?.components(separatedBy: " ").first ?? senderUsername ?? "User"
    }
    
    var isSystemMessage: Bool { messageType == "system" }
    var isMilestoneMessage: Bool { messageType == "milestone" }
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderUsername = "sender_username"
        case senderPhotoUrl = "sender_photo_url"
        case messageType = "message_type"
        case content
        case metadata
        case createdAt = "created_at"
        case isCurrentUser = "is_current_user"
    }
}

/// Codable wrapper for mixed-type JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }
}


// MARK: - Private Challenge Service

@MainActor
class PrivateChallengeService: ObservableObject {
    static let shared = PrivateChallengeService()
    
    @Published var myChallenges: [PrivateChallenge] = []
    @Published var pendingInvites: [PrivateChallengeInvite] = []
    @Published var isLoading = false
    
    /// Realtime channel for live updates
    private var realtimeChannel: RealtimeChannelV2?
    
    /// Throttle
    private var lastRefreshTime: Date?
    private var lastRealtimeRefresh: Date = .distantPast
    
    // Cache keys
    private let myChallengesCacheKey = "private_challenges_cache"
    private let invitesCacheKey = "private_challenge_invites_cache"
    
    private init() {
        loadFromCache()
    }
    
    // MARK: - Cache
    
    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: myChallengesCacheKey) {
            if let cached = try? JSONDecoder().decode([PrivateChallenge].self, from: data) {
                self.myChallenges = cached
                #if DEBUG
                print("✅ [PRIVATE] Loaded \(cached.count) cached private challenges")
                #endif
            }
        }
        if let data = UserDefaults.standard.data(forKey: invitesCacheKey) {
            if let cached = try? JSONDecoder().decode([PrivateChallengeInvite].self, from: data) {
                self.pendingInvites = cached
                #if DEBUG
                print("✅ [PRIVATE] Loaded \(cached.count) cached private invites")
                #endif
            }
        }
    }
    
    private func cacheData() {
        if let data = try? JSONEncoder().encode(myChallenges) {
            UserDefaults.standard.set(data, forKey: myChallengesCacheKey)
        }
        if let data = try? JSONEncoder().encode(pendingInvites) {
            UserDefaults.standard.set(data, forKey: invitesCacheKey)
        }
    }
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: myChallengesCacheKey)
        UserDefaults.standard.removeObject(forKey: invitesCacheKey)
        myChallenges = []
        pendingInvites = []
    }
    
    // MARK: - Refresh All
    
    func refreshAll(force: Bool = false) async {
        let now = Date()
        if !force, let last = lastRefreshTime, now.timeIntervalSince(last) < 10 {
            #if DEBUG
            print("⏭️ [PRIVATE] Skipping refresh — last was \(Int(now.timeIntervalSince(last)))s ago")
            #endif
            return
        }
        lastRefreshTime = now
        
        async let challenges: () = fetchMyChallenges()
        async let invites: () = fetchPendingInvites()
        _ = await (challenges, invites)
        
        cacheData()
        
        #if DEBUG
        print("✅ [PRIVATE] Full refresh completed")
        #endif
    }
    
    // MARK: - Fetch My Private Challenges
    
    func fetchMyChallenges() async {
        do {
            struct Params: Encodable {
                let p_timezone: String
            }
            
            let result: [PrivateChallenge] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_my_private_challenges", params: Params(
                    p_timezone: TimeZone.current.identifier
                ))
                .execute()
                .value
            
            myChallenges = result
            
            // Preload profile photos for all visible members
            var photoData: [(id: String, url: String?)] = []
            for challenge in result {
                if let members = challenge.topMembers {
                    for m in members {
                        photoData.append((id: m.userId.uuidString, url: m.profilePhotoUrl))
                    }
                }
            }
            if !photoData.isEmpty {
                FriendPhotoCache.shared.preloadPhotos(for: photoData)
            }
            
            #if DEBUG
            print("✅ [PRIVATE] Fetched \(result.count) private challenges")
            #endif
        } catch {
            print("❌ [PRIVATE] Error fetching my challenges: \(error)")
        }
    }
    
    // MARK: - Fetch Pending Invites
    
    func fetchPendingInvites() async {
        do {
            struct EmptyParams: Encodable {}
            
            let result: [PrivateChallengeInvite] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_private_challenge_invites_for_me", params: EmptyParams())
                .execute()
                .value
            
            pendingInvites = result
            
            // Preload inviter photos for instant display on dashboard
            let inviterPhotos: [(id: String, url: String?)] = result.map {
                (id: $0.inviterId.uuidString, url: $0.inviterPhotoUrl)
            }
            if !inviterPhotos.isEmpty {
                FriendPhotoCache.shared.preloadPhotos(for: inviterPhotos)
            }
            
            #if DEBUG
            print("✅ [PRIVATE] Fetched \(result.count) pending invites")
            #endif
        } catch {
            print("❌ [PRIVATE] Error fetching invites: \(error)")
        }
    }
    
    // MARK: - Create Private Challenge
    
    func createChallenge(
        challengeType: String,
        title: String,
        description: String? = nil,
        emoji: String = "🔒",
        dailyTarget: Int,
        targetUnit: String,
        isRecurring: Bool = true,
        endDate: String? = nil,
        maxMembers: Int? = 50,
        allowMemberInvites: Bool = false,
        showLeaderboard: Bool = true
    ) async -> UUID? {
        do {
            struct CreateParams: Encodable {
                let p_challenge_type: String
                let p_title: String
                let p_description: String?
                let p_emoji: String
                let p_daily_target: Int
                let p_target_unit: String
                let p_is_recurring: Bool
                let p_end_date: String?
                let p_max_members: Int?
                let p_allow_member_invites: Bool
                let p_show_leaderboard: Bool
            }
            
            let id: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("create_private_challenge", params: CreateParams(
                    p_challenge_type: challengeType,
                    p_title: title,
                    p_description: description,
                    p_emoji: emoji,
                    p_daily_target: dailyTarget,
                    p_target_unit: targetUnit,
                    p_is_recurring: isRecurring,
                    p_end_date: endDate,
                    p_max_members: maxMembers,
                    p_allow_member_invites: allowMemberInvites,
                    p_show_leaderboard: showLeaderboard
                ))
                .execute()
                .value
            
            #if DEBUG
            print("✅ [PRIVATE] Created private challenge: \(id)")
            #endif
            await fetchMyChallenges()
            HapticManager.notification(.success)
            return id
        } catch {
            print("❌ [PRIVATE] Error creating challenge: \(error)")
            HapticManager.notification(.error)
            return nil
        }
    }
    
    // MARK: - Invite User
    
    func inviteUser(challengeId: UUID, userId: UUID) async -> UUID? {
        do {
            struct InviteParams: Encodable {
                let p_challenge_id: String
                let p_invited_user_id: String
            }
            
            let inviteId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("invite_to_private_challenge", params: InviteParams(
                    p_challenge_id: challengeId.uuidString,
                    p_invited_user_id: userId.uuidString
                ))
                .execute()
                .value
            
            #if DEBUG
            print("✅ [PRIVATE] Invited user \(userId) to \(challengeId)")
            #endif
            HapticManager.notification(.success)
            return inviteId
        } catch {
            print("❌ [PRIVATE] Error inviting user: \(error)")
            HapticManager.notification(.error)
            return nil
        }
    }
    
    // MARK: - Accept Invite
    
    func acceptInvite(inviteId: UUID) async -> UUID? {
        do {
            struct AcceptParams: Encodable {
                let p_invite_id: String
            }
            
            let challengeId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("accept_private_challenge_invite", params: AcceptParams(
                    p_invite_id: inviteId.uuidString
                ))
                .execute()
                .value
            
            // Remove from pending invites immediately for instant UI
            pendingInvites.removeAll { $0.inviteId == inviteId }
            
            #if DEBUG
            print("✅ [PRIVATE] Accepted invite \(inviteId) → challenge \(challengeId)")
            #endif
            HapticManager.notification(.success)
            
            // Refresh to get the challenge in myChallenges
            await fetchMyChallenges()
            cacheData()
            return challengeId
        } catch {
            print("❌ [PRIVATE] Error accepting invite: \(error)")
            HapticManager.notification(.error)
            return nil
        }
    }
    
    // MARK: - Decline Invite
    
    func declineInvite(inviteId: UUID) async -> Bool {
        do {
            struct DeclineParams: Encodable {
                let p_invite_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("decline_private_challenge_invite", params: DeclineParams(
                    p_invite_id: inviteId.uuidString
                ))
                .execute()
                .value
            
            pendingInvites.removeAll { $0.inviteId == inviteId }
            cacheData()
            
            #if DEBUG
            print("✅ [PRIVATE] Declined invite \(inviteId)")
            #endif
            return true
        } catch {
            print("❌ [PRIVATE] Error declining invite: \(error)")
            return false
        }
    }
    
    // MARK: - Leave Challenge
    
    func leaveChallenge(challengeId: UUID) async -> Bool {
        do {
            struct LeaveParams: Encodable {
                let p_challenge_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("leave_private_challenge", params: LeaveParams(
                    p_challenge_id: challengeId.uuidString
                ))
                .execute()
                .value
            
            myChallenges.removeAll { $0.challengeId == challengeId }
            cacheData()
            
            #if DEBUG
            print("✅ [PRIVATE] Left private challenge \(challengeId)")
            #endif
            return true
        } catch {
            print("❌ [PRIVATE] Error leaving challenge: \(error)")
            return false
        }
    }
    
    // MARK: - Remove Member (admin)
    
    func removeMember(challengeId: UUID, userId: UUID) async -> Bool {
        do {
            struct RemoveParams: Encodable {
                let p_challenge_id: String
                let p_user_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("remove_from_private_challenge", params: RemoveParams(
                    p_challenge_id: challengeId.uuidString,
                    p_user_id: userId.uuidString
                ))
                .execute()
                .value
            
            #if DEBUG
            print("✅ [PRIVATE] Removed member \(userId) from \(challengeId)")
            #endif
            HapticManager.notification(.success)
            return true
        } catch {
            print("❌ [PRIVATE] Error removing member: \(error)")
            return false
        }
    }
    
    // MARK: - Update Challenge (admin)
    
    func updateChallenge(
        challengeId: UUID,
        title: String? = nil,
        description: String? = nil,
        emoji: String? = nil,
        dailyTarget: Int? = nil,
        allowMemberInvites: Bool? = nil,
        showLeaderboard: Bool? = nil,
        notificationsEnabled: Bool? = nil,
        maxMembers: Int? = nil
    ) async -> Bool {
        do {
            struct UpdateParams: Encodable {
                let p_challenge_id: String
                let p_title: String?
                let p_description: String?
                let p_emoji: String?
                let p_daily_target: Int?
                let p_allow_member_invites: Bool?
                let p_show_leaderboard: Bool?
                let p_notifications_enabled: Bool?
                let p_max_members: Int?
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("update_private_challenge", params: UpdateParams(
                    p_challenge_id: challengeId.uuidString,
                    p_title: title,
                    p_description: description,
                    p_emoji: emoji,
                    p_daily_target: dailyTarget,
                    p_allow_member_invites: allowMemberInvites,
                    p_show_leaderboard: showLeaderboard,
                    p_notifications_enabled: notificationsEnabled,
                    p_max_members: maxMembers
                ))
                .execute()
                .value
            
            #if DEBUG
            print("✅ [PRIVATE] Updated challenge \(challengeId)")
            #endif
            HapticManager.notification(.success)
            await fetchMyChallenges()
            return true
        } catch {
            print("❌ [PRIVATE] Error updating challenge: \(error)")
            return false
        }
    }
    
    // MARK: - Promote / Demote Admin
    
    func promoteToAdmin(challengeId: UUID, userId: UUID) async -> Bool {
        do {
            struct PromoteParams: Encodable {
                let p_challenge_id: String
                let p_user_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("promote_to_admin", params: PromoteParams(
                    p_challenge_id: challengeId.uuidString,
                    p_user_id: userId.uuidString
                ))
                .execute()
                .value
            
            #if DEBUG
            print("✅ [PRIVATE] Promoted \(userId) to admin")
            #endif
            HapticManager.notification(.success)
            return true
        } catch {
            print("❌ [PRIVATE] Error promoting: \(error)")
            return false
        }
    }
    
    func demoteFromAdmin(challengeId: UUID, userId: UUID) async -> Bool {
        do {
            struct DemoteParams: Encodable {
                let p_challenge_id: String
                let p_user_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("demote_from_admin", params: DemoteParams(
                    p_challenge_id: challengeId.uuidString,
                    p_user_id: userId.uuidString
                ))
                .execute()
                .value
            
            #if DEBUG
            print("✅ [PRIVATE] Demoted \(userId) from admin")
            #endif
            return true
        } catch {
            print("❌ [PRIVATE] Error demoting: \(error)")
            return false
        }
    }
    
    // MARK: - End Challenge (admin)
    
    func endChallenge(challengeId: UUID) async -> Bool {
        do {
            struct EndParams: Encodable {
                let p_challenge_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("end_private_challenge", params: EndParams(
                    p_challenge_id: challengeId.uuidString
                ))
                .execute()
                .value
            
            myChallenges.removeAll { $0.challengeId == challengeId }
            cacheData()
            
            #if DEBUG
            print("✅ [PRIVATE] Ended challenge \(challengeId)")
            #endif
            HapticManager.notification(.success)
            return true
        } catch {
            print("❌ [PRIVATE] Error ending challenge: \(error)")
            return false
        }
    }
    
    // MARK: - Log Progress
    
    func logProgress(challengeId: UUID, progressValue: Int) async -> Bool {
        do {
            struct LogParams: Encodable {
                let p_challenge_id: String
                let p_progress: Int
                let p_timezone: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("log_private_challenge_progress", params: LogParams(
                    p_challenge_id: challengeId.uuidString,
                    p_progress: progressValue,
                    p_timezone: TimeZone.current.identifier
                ))
                .execute()
                .value
            
            #if DEBUG
            print("✅ [PRIVATE] Logged progress: \(progressValue) for \(challengeId)")
            #endif
            return true
        } catch {
            print("❌ [PRIVATE] Error logging progress: \(error)")
            return false
        }
    }
    
    // MARK: - Get Challenge Detail
    
    func getChallengeDetail(challengeId: UUID) async -> PrivateChallengeDetail? {
        do {
            struct DetailParams: Encodable {
                let p_challenge_id: String
                let p_timezone: String
            }
            
            let results: [PrivateChallengeDetail] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_private_challenge_detail", params: DetailParams(
                    p_challenge_id: challengeId.uuidString,
                    p_timezone: TimeZone.current.identifier
                ))
                .execute()
                .value
            
            return results.first
        } catch {
            print("❌ [PRIVATE] Error fetching detail: \(error)")
            return nil
        }
    }
    
    // MARK: - Chat: Send Message
    
    func sendMessage(challengeId: UUID, content: String) async -> UUID? {
        do {
            struct MessageParams: Encodable {
                let p_challenge_id: String
                let p_content: String
                let p_message_type: String
            }
            
            let messageId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("send_private_challenge_message", params: MessageParams(
                    p_challenge_id: challengeId.uuidString,
                    p_content: content,
                    p_message_type: "text"
                ))
                .execute()
                .value
            
            return messageId
        } catch {
            print("❌ [PRIVATE] Error sending message: \(error)")
            return nil
        }
    }
    
    // MARK: - Chat: Fetch Messages
    
    func fetchMessages(challengeId: UUID, limit: Int = 50, beforeId: UUID? = nil) async -> [PrivateChallengeMessage] {
        do {
            struct FetchParams: Encodable {
                let p_challenge_id: String
                let p_limit: Int
                let p_before_id: String?
            }
            
            let messages: [PrivateChallengeMessage] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_private_challenge_messages", params: FetchParams(
                    p_challenge_id: challengeId.uuidString,
                    p_limit: limit,
                    p_before_id: beforeId?.uuidString
                ))
                .execute()
                .value
            
            return messages
        } catch {
            print("❌ [PRIVATE] Error fetching messages: \(error)")
            return []
        }
    }
    
    // MARK: - Realtime Subscriptions
    
    func subscribeToRealtimeUpdates() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        let client = SupabaseManager.shared.supabaseClient
        let channel = client.realtimeV2.channel("private-challenges")
        
        // Listen for new members joining (instant photo icon updates)
        let memberInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_members"
        )
        
        // Listen for member updates (progress changes)
        let memberUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "private_challenge_members"
        )
        
        // Listen for daily progress changes
        let progressInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_daily_progress"
        )
        
        let progressUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "private_challenge_daily_progress"
        )
        
        // Listen for new invites
        let inviteInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_invites"
        )
        
        // Listen for chat messages (for live chat + unread badges)
        let chatInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_chat"
        )
        
        // Handle member changes → instant UI refresh
        Task {
            for await _ in memberInserts {
                print("📡 [PRIVATE-RT] New member joined")
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in memberUpdates {
                print("📡 [PRIVATE-RT] Member updated")
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in progressInserts {
                print("📡 [PRIVATE-RT] New progress logged")
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in progressUpdates {
                print("📡 [PRIVATE-RT] Progress updated")
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in inviteInserts {
                print("📡 [PRIVATE-RT] New invite received")
                await fetchPendingInvites()
            }
        }
        
        Task {
            for await _ in chatInserts {
                print("📡 [PRIVATE-RT] New chat message")
                await fetchMyChallenges() // Update last_chat_message preview
            }
        }
        
        await channel.subscribe()
        realtimeChannel = channel
        print("📡 [PRIVATE] Subscribed to real-time updates")
    }
    
    func unsubscribeFromRealtimeUpdates() async {
        if let channel = realtimeChannel {
            await channel.unsubscribe()
            realtimeChannel = nil
            print("📡 [PRIVATE] Unsubscribed from real-time updates")
        }
    }
    
    private func refreshAfterRealtimeUpdate() async {
        let now = Date()
        guard now.timeIntervalSince(lastRealtimeRefresh) > 2 else { return }
        lastRealtimeRefresh = now
        
        await fetchMyChallenges()
        cacheData()
    }
    
    // MARK: - Auto-Sync Progress (from HealthKit)
    
    func syncAllTrackingToPrivateChallenges() async {
        guard !myChallenges.isEmpty else { return }
        
        #if DEBUG
        print("🔄 [PRIVATE] Syncing tracking data to \(myChallenges.count) private challenges...")
        #endif
        
        for challenge in myChallenges {
            let progressValue = await calculateProgress(for: challenge)
            
            if progressValue > 0 {
                let _ = await logProgress(challengeId: challenge.challengeId, progressValue: progressValue)
            }
        }
        
        await fetchMyChallenges()
        cacheData()
        
        #if DEBUG
        print("✅ [PRIVATE] Private challenge sync complete")
        #endif
    }
    
    /// Calculate progress from HealthKit/services for a private challenge
    private func calculateProgress(for challenge: PrivateChallenge) async -> Int {
        let healthKit = HealthKitService.shared
        let healthKitManager = HealthKitManager.shared
        
        switch challenge.challengeType {
        case "steps":
            let steps = healthKitManager.todaySteps > 0 ? healthKitManager.todaySteps : healthKit.todaySteps
            return steps
        case "walk":
            if challenge.targetUnit == "minutes" {
                return healthKit.recentWorkouts
                    .filter { $0.workoutType == .walking && Calendar.current.isDateInToday($0.startDate) }
                    .reduce(0) { $0 + $1.durationMinutes }
            }
            return 0
        case "run":
            if challenge.targetUnit == "minutes" {
                return healthKit.recentWorkouts
                    .filter { $0.workoutType == .running && Calendar.current.isDateInToday($0.startDate) }
                    .reduce(0) { $0 + $1.durationMinutes }
            }
            return 0
        case "lift", "workout_streak":
            return 0
        case "active_minutes":
            return healthKit.todayActiveMinutes
        case "hydrate":
            let totalMl = HydrationService.shared.todayTotal
            if challenge.targetUnit.lowercased() == "oz" {
                return Int(Double(totalMl) / 29.5735)
            }
            return totalMl
        case "protein":
            return MealService.shared.todaysMeals.reduce(0) { $0 + $1.protein }
        case "calories":
            let hkCal = healthKit.todayCalories
            let mealCal = MealService.shared.todaysMeals.reduce(0) { $0 + $1.calories }
            return max(hkCal, mealCal)
        case "sleep":
            let sleepHours = healthKit.lastNightSleep ?? 0
            return Int(sleepHours * 60)
        default:
            return 0
        }
    }
    
    // MARK: - Share Helper
    
    func shareMessage(for challenge: PrivateChallenge) -> String {
        let url = challenge.shareURL?.absoluteString ?? "https://fit33.app"
        return "\(challenge.displayEmoji) Join my private challenge \"\(challenge.title)\" on Fit33! \(challenge.formattedMemberCount) members and counting.\n\n\(url)"
    }
}
