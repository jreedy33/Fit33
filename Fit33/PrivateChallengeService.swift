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
    let isVerified: Bool?
    let isGoldVerified: Bool?

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
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
    }
}

/// A private challenge summary (returned by get_my_private_challenges)
struct PrivateChallenge: Codable, Identifiable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let coverImageUrl: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let memberCount: Int
    let maxMembers: Int?
    let joinCode: String
    let isRecurring: Bool
    let showLeaderboard: Bool
    let allowMemberInvites: Bool
    var myTodayProgress: Int?
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
        case coverImageUrl = "cover_image_url"
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

/// Preview data for a private challenge (returned by lookup_private_challenge_by_code)
/// Used to show challenge info before the user decides to join
struct PrivateChallengePreview: Codable, Identifiable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let coverImageUrl: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let memberCount: Int
    let maxMembers: Int?
    let joinCode: String
    let isRecurring: Bool
    let creatorName: String?
    let creatorUsername: String?
    let creatorPhotoUrl: String?
    let alreadyJoined: Bool
    let status: String
    
    var id: UUID { challengeId }
    var displayEmoji: String { emoji ?? "🔒" }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case coverImageUrl = "cover_image_url"
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case memberCount = "member_count"
        case maxMembers = "max_members"
        case joinCode = "join_code"
        case isRecurring = "is_recurring"
        case creatorName = "creator_name"
        case creatorUsername = "creator_username"
        case creatorPhotoUrl = "creator_photo_url"
        case alreadyJoined = "already_joined"
        case status
    }
}

/// Full detail response for a private challenge
struct PrivateChallengeDetail: Codable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let coverImageUrl: String?
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
        case coverImageUrl = "cover_image_url"
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
    
    /// Incremented when a member join/leave realtime event is detected.
    /// Detail views observe this to auto-refresh their member list.
    @Published var memberChangeToken = UUID()
    @Published var chatMessageToken = UUID()
    
    /// Realtime channel for live updates
    private var realtimeChannel: RealtimeChannelV2?
    
    /// Throttle
    private var lastRefreshTime: Date?
    private var lastRealtimeRefresh: Date = .distantPast
    
    // Cache keys
    private let myChallengesCacheKey = "private_challenges_cache"
    private let invitesCacheKey = "private_challenge_invites_cache"
    private let cacheDateKey = "private_challenges_cache_date"
    
    private init() {
        loadFromCache()
    }
    
    // MARK: - Cache
    
    private func loadFromCache() {
        // Check if the cache is from a previous day — if so, today's progress values are stale
        let cacheTimestamp = UserDefaults.standard.double(forKey: cacheDateKey)
        let cacheDate = cacheTimestamp > 0 ? Date(timeIntervalSince1970: cacheTimestamp) : nil
        let isCacheFromToday = cacheDate.map { Calendar.current.isDateInToday($0) } ?? false
        
        if let data = UserDefaults.standard.data(forKey: myChallengesCacheKey) {
            if var cached = try? JSONDecoder().decode([PrivateChallenge].self, from: data) {
                // If cache is from a previous day, zero out today-specific fields
                // so stale yesterday progress doesn't appear as today's progress
                if !isCacheFromToday && !cached.isEmpty {
                    #if DEBUG
                    AppLogger.debug("Private challenge cache is from previous day — zeroing out today's progress", category: .social)
                    #endif
                    for i in cached.indices {
                        cached[i].myTodayProgress = 0
                    }
                }
                self.myChallenges = cached
                #if DEBUG
                AppLogger.info("Successfully loaded \(cached.count) cached private challenges", category: .social)
                #endif
            }
        }
        if let data = UserDefaults.standard.data(forKey: invitesCacheKey) {
            if let cached = try? JSONDecoder().decode([PrivateChallengeInvite].self, from: data) {
                self.pendingInvites = cached
                #if DEBUG
                AppLogger.info("Successfully loaded \(cached.count) cached private invites", category: .social)
                #endif
            }
        }
    }
    
    private func cacheData() {
        if let data = try? JSONEncoder().encode(myChallenges) {
            UserDefaults.standard.set(data, forKey: myChallengesCacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheDateKey)
        }
        if let data = try? JSONEncoder().encode(pendingInvites) {
            UserDefaults.standard.set(data, forKey: invitesCacheKey)
        }
    }
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: myChallengesCacheKey)
        UserDefaults.standard.removeObject(forKey: invitesCacheKey)
        UserDefaults.standard.removeObject(forKey: cacheDateKey)
        myChallenges = []
        pendingInvites = []
    }
    
    // MARK: - Refresh All
    
    func refreshAll(force: Bool = false) async {
        let now = Date()
        if !force, let last = lastRefreshTime, now.timeIntervalSince(last) < 10 {
            #if DEBUG
            AppLogger.debug("Skipping private refresh — last was \(Int(now.timeIntervalSince(last)))s ago", category: .social)
            #endif
            return
        }
        lastRefreshTime = now
        
        async let challenges: () = fetchMyChallenges()
        async let invites: () = fetchPendingInvites()
        _ = await (challenges, invites)
        
        cacheData()
        
        #if DEBUG
        AppLogger.info("Successfully completed private challenge full refresh", category: .social)
        #endif
    }
    
    // MARK: - Fetch My Private Challenges
    
    func fetchMyChallenges() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        struct Params: Encodable {
            let p_timezone: String
        }
        
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                let result: [PrivateChallenge] = try await SupabaseManager.shared.supabaseClient
                    .rpc("get_my_private_challenges", params: Params(
                        p_timezone: TimeZone.current.identifier
                    ))
                    .execute()
                    .value
                
                myChallenges = result
                
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
                AppLogger.info("Successfully fetched \(result.count) private challenges", category: .social)
                #endif
                return
            } catch {
                if error is CancellationError { return }
                guard !Task.isCancelled else { return }
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCancelled)
                if isTimeout && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    AppLogger.warning("fetchMyChallenges timeout (attempt \(attempt)/\(maxRetries)), retrying...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                } else if isTimeout {
                    AppLogger.warning("Error fetching my private challenges: \(error.localizedDescription)", category: .social)
                } else {
                    AppLogger.error("Error fetching my private challenges: \(error.localizedDescription)", category: .social)
                }
            }
        }
    }
    
    // MARK: - Fetch Pending Invites
    
    func fetchPendingInvites() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                struct EmptyParams: Encodable {}
                
                let result: [PrivateChallengeInvite] = try await SupabaseManager.shared.supabaseClient
                    .rpc("get_private_challenge_invites_for_me", params: EmptyParams())
                    .execute()
                    .value
                
                pendingInvites = result
                
                let inviterPhotos: [(id: String, url: String?)] = result.map {
                    (id: $0.inviterId.uuidString, url: $0.inviterPhotoUrl)
                }
                if !inviterPhotos.isEmpty {
                    FriendPhotoCache.shared.preloadPhotos(for: inviterPhotos)
                }
                
                #if DEBUG
                AppLogger.info("Successfully fetched \(result.count) pending invites", category: .social)
                #endif
                return
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCancelled)
                if isTimeout && attempt < maxAttempts {
                    AppLogger.warning("fetchPendingInvites timeout (attempt \(attempt)/\(maxAttempts)), retrying...", category: .social)
                    try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                } else if isTimeout {
                    AppLogger.warning("Error fetching private invites: \(error.localizedDescription)", category: .social)
                } else {
                    AppLogger.error("Error fetching private invites: \(error.localizedDescription)", category: .social)
                }
            }
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
            AppLogger.info("Successfully created private challenge: \(id)", category: .social)
            #endif
            await fetchMyChallenges()
            HapticManager.notification(.success)
            return id
        } catch {
            AppLogger.error("Error creating private challenge: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully invited user \(userId) to \(challengeId)", category: .social)
            #endif
            HapticManager.notification(.success)
            return inviteId
        } catch {
            AppLogger.error("Error inviting user to private challenge: \(error.localizedDescription)", category: .social)
            HapticManager.notification(.error)
            return nil
        }
    }
    
    // MARK: - Join by Code
    
    /// Look up a private challenge by join code WITHOUT joining.
    /// Returns preview data so the user can decide whether to join.
    func lookupByCode(code: String) async -> PrivateChallengePreview? {
        do {
            struct LookupParams: Encodable {
                let p_code: String
            }
            
            let results: [PrivateChallengePreview] = try await SupabaseManager.shared.supabaseClient
                .rpc("lookup_private_challenge_by_code", params: LookupParams(
                    p_code: code
                ))
                .execute()
                .value
            
            #if DEBUG
            AppLogger.debug("Private challenge lookup by code: found \(results.count) result(s)", category: .social)
            #endif
            return results.first
        } catch {
            AppLogger.error("Error looking up private challenge by code: \(error.localizedDescription)", category: .social)
            return nil
        }
    }
    
    func joinByCode(code: String) async -> UUID? {
        do {
            struct JoinByCodeParams: Encodable {
                let p_join_code: String
            }
            
            let challengeId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("join_private_challenge_by_code", params: JoinByCodeParams(
                    p_join_code: code
                ))
                .execute()
                .value
            
            #if DEBUG
            AppLogger.info("Successfully joined private challenge via code: \(challengeId)", category: .social)
            #endif
            HapticManager.notification(.success)
            
            await fetchMyChallenges()
            cacheData()
            return challengeId
        } catch {
            AppLogger.error("Error joining private challenge by code: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully accepted invite \(inviteId) → challenge \(challengeId)", category: .social)
            #endif
            HapticManager.notification(.success)
            
            // Refresh to get the challenge in myChallenges
            await fetchMyChallenges()
            cacheData()
            return challengeId
        } catch {
            AppLogger.error("Error accepting private invite: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully declined invite \(inviteId)", category: .social)
            #endif
            return true
        } catch {
            AppLogger.error("Error declining private invite: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully left private challenge \(challengeId)", category: .social)
            #endif
            return true
        } catch {
            AppLogger.error("Error leaving private challenge: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully removed member \(userId) from \(challengeId)", category: .social)
            #endif
            HapticManager.notification(.success)
            return true
        } catch {
            AppLogger.error("Error removing member from private challenge: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully updated private challenge \(challengeId)", category: .social)
            #endif
            HapticManager.notification(.success)
            await fetchMyChallenges()
            return true
        } catch {
            AppLogger.error("Error updating private challenge: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully promoted \(userId) to admin", category: .social)
            #endif
            HapticManager.notification(.success)
            return true
        } catch {
            AppLogger.error("Error promoting to admin: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully demoted \(userId) from admin", category: .social)
            #endif
            return true
        } catch {
            AppLogger.error("Error demoting from admin: \(error.localizedDescription)", category: .social)
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
            AppLogger.info("Successfully ended private challenge \(challengeId)", category: .social)
            #endif
            HapticManager.notification(.success)
            return true
        } catch {
            AppLogger.error("Error ending private challenge: \(error.localizedDescription)", category: .social)
            return false
        }
    }
    
    // MARK: - Log Progress
    
    func logProgress(challengeId: UUID, progressValue: Int, allowDecrease: Bool = false) async -> Bool {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("[PRIVATE CHALLENGE] Skipping progress log — not authenticated", category: .auth)
            return false
        }
        
        struct LogParams: Encodable {
            let p_challenge_id: String
            let p_progress: Int
            let p_timezone: String
            let p_allow_decrease: Bool
        }

        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                let _: Bool = try await SupabaseManager.shared.supabaseClient
                    .rpc("log_private_challenge_progress", params: LogParams(
                        p_challenge_id: challengeId.uuidString,
                        p_progress: progressValue,
                        p_timezone: TimeZone.current.identifier,
                        p_allow_decrease: allowDecrease
                    ))
                    .execute()
                    .value

                #if DEBUG
                AppLogger.info("Successfully logged private progress: \(progressValue) for \(challengeId) (allowDecrease: \(allowDecrease))", category: .social)
                #endif
                return true
            } catch {
                guard !Task.isCancelled else { return false }
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCancelled)
                if isTimeout && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    AppLogger.warning("log_private_challenge_progress timeout (attempt \(attempt)/\(maxRetries)), retrying...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    AppLogger.error("Error logging private challenge progress: \(error.localizedDescription)", category: .social)
                    return false
                }
            }
        }
        return false
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
            AppLogger.error("Error fetching private challenge detail: \(error.localizedDescription)", category: .social)
            return nil
        }
    }
    
    // MARK: - Chat: Send Message
    
    func sendMessage(challengeId: UUID, content: String) async -> SendMessageResult {
        // Layer 1: Pre-check content via moderation Edge Function
        let moderationResult = await ContentModerationService.shared.checkContent(
            content: content,
            source: "private_challenge_chat"
        )
        
        if moderationResult.flagged {
            AppLogger.info("Message blocked by content moderation: \(moderationResult.categories.joined(separator: ", "))", category: .social)
            return .blocked(categories: moderationResult.categories)
        }
        
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
            
            return .sent(messageId: messageId)
        } catch {
            AppLogger.error("Error sending private challenge message: \(error.localizedDescription)", category: .social)
            return .error(error.localizedDescription)
        }
    }
    
    enum SendMessageResult {
        case sent(messageId: UUID)
        case blocked(categories: [String])
        case error(String)
        
        var messageId: UUID? {
            if case .sent(let id) = self { return id }
            return nil
        }
        
        var isBlocked: Bool {
            if case .blocked = self { return true }
            return false
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
            AppLogger.error("Error fetching private challenge messages: \(error.localizedDescription)", category: .social)
            return []
        }
    }
    
    // MARK: - Realtime Subscriptions
    
    func subscribeToRealtimeUpdates() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        // Prevent duplicate subscriptions — calling postgresChange on an already-subscribed
        // channel triggers "You cannot call postgresChange after joining the channel" warning
        // and silently breaks the subscription.
        if realtimeChannel != nil {
            AppLogger.debug("Already subscribed to private real-time updates — skipping", category: .social)
            return
        }
        
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
                AppLogger.debug("Realtime: new private member joined", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in memberUpdates {
                AppLogger.debug("Realtime: private member updated", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in progressInserts {
                AppLogger.debug("Realtime: new private progress logged", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in progressUpdates {
                AppLogger.debug("Realtime: private progress updated", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in inviteInserts {
                AppLogger.debug("Realtime: new private invite received", category: .social)
                await fetchPendingInvites()
            }
        }
        
        Task {
            for await _ in chatInserts {
                AppLogger.debug("Realtime: new private chat message", category: .social)
                await fetchMyChallenges()
                chatMessageToken = UUID()
            }
        }
        
        await channel.subscribe()
        realtimeChannel = channel
        AppLogger.info("Successfully subscribed to private real-time updates", category: .social)
    }
    
    func unsubscribeFromRealtimeUpdates() async {
        if let channel = realtimeChannel {
            await channel.unsubscribe()
            realtimeChannel = nil
            AppLogger.debug("Unsubscribed from private real-time updates", category: .social)
        }
    }
    
    private func refreshAfterRealtimeUpdate() async {
        let now = Date()
        guard now.timeIntervalSince(lastRealtimeRefresh) > 2 else { return }
        lastRealtimeRefresh = now
        
        await fetchMyChallenges()
        cacheData()
    }
    
    // MARK: - Quick Type-Specific Sync
    
    /// Quick sync for a SPECIFIC challenge type to private challenges.
    /// Called immediately when user logs data (protein, hydration, calories, etc.).
    /// Much faster than full sync — only touches matching challenges.
    /// Pass `allowDecrease: true` when the value may have gone DOWN (e.g. meal removed).
    func syncTrackingForType(_ type: ChallengeType, value: Int, source: String = "auto_sync", allowDecrease: Bool = false) async {
        let matching = myChallenges.filter { $0.resolvedType == type }
        guard !matching.isEmpty else { return }
        
        AppLogger.debug("Quick sync \(type.rawValue): \(value) to \(matching.count) private challenge(s) (allowDecrease: \(allowDecrease))", category: .social)
        
        for challenge in matching {
            var adjustedValue = value
            // Handle unit conversion for hydration (ml → oz if needed)
            if type == .hydrate && challenge.targetUnit.lowercased() == "oz" {
                adjustedValue = Int(Double(value) / 29.5735)
            }
            
            if adjustedValue > 0 || allowDecrease {
                let _ = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: max(adjustedValue, 0),
                    allowDecrease: allowDecrease
                )
            }
        }
        
        // Refresh to show updated progress in widgets
        await fetchMyChallenges()
    }
    
    // MARK: - Auto-Sync Progress (from HealthKit)
    
    func syncAllTrackingToPrivateChallenges() async {
        guard !myChallenges.isEmpty else { return }
        
        let progress = await gatherCurrentProgress()
        
        #if DEBUG
        AppLogger.debug("Syncing tracking data to \(myChallenges.count) private challenges...", category: .social)
        #endif
        
        for (index, challenge) in myChallenges.enumerated() {
            let progressValue = resolveProgress(for: challenge, from: progress)
            
            // For "recalculable" types (protein, hydration, calories) the local value
            // is authoritative — it's freshly computed from today's meals/logs.
            // We MUST log even when the value is 0 so that any stale yesterday row
            // in the DB gets overwritten (e.g. 14g protein from yesterday).
            let isRecalculable = (challenge.challengeType == "protein" ||
                                  challenge.challengeType == "hydrate" ||
                                  challenge.challengeType == "calories")
            
            if progressValue > 0 || isRecalculable {
                // allowDecrease: true ensures the DB value matches the authoritative
                // calculated value. Without this, stale data (e.g. 713g protein from
                // before a meal removal) gets stuck forever due to the GREATEST() clause.
                let _ = await logProgress(
                    challengeId: challenge.challengeId,
                    progressValue: max(progressValue, 0),
                    allowDecrease: isRecalculable
                )
                
                // Small delay between RPCs to avoid overwhelming URLSession connections
                if index < myChallenges.count - 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                }
            }
        }
        
        await fetchMyChallenges()
        cacheData()
        
        #if DEBUG
        AppLogger.info("Successfully completed private challenge sync", category: .social)
        #endif
    }
    
    private func resolveProgress(for challenge: PrivateChallenge, from data: ChallengeProgressData) -> Int {
        switch challenge.challengeType {
        case "steps":       return data.steps
        case "walk":        return challenge.targetUnit == "minutes" ? data.walkMinutesToday : 0
        case "run":         return challenge.targetUnit == "minutes" ? data.runMinutesToday : 0
        case "lift", "workout_streak": return 0
        case "active_minutes": return data.activeMinutes
        case "hydrate":     return data.hydrationInUnit(challenge.targetUnit)
        case "protein":     return data.protein
        case "calories":    return max(data.calories, data.mealCalories)
        case "sleep":       return data.sleepMinutes
        default:            return 0
        }
    }
    
    // MARK: - Challenge Icon Upload
    
    /// Upload a challenge icon image and update the challenge's cover_image_url.
    /// Uses the `avatars` storage bucket with `challenge_icons/` prefix.
    func uploadChallengeIcon(challengeId: UUID, imageData: Data) async throws -> String {
        let fileName = "challenge_icons/\(challengeId.uuidString).jpg"
        let bucket = "avatars"
        
        try await SupabaseManager.shared.supabaseClient.storage
            .from(bucket)
            .upload(
                path: fileName,
                file: imageData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
        
        let publicUrl = try SupabaseManager.shared.supabaseClient.storage
            .from(bucket)
            .getPublicURL(path: fileName)
        
        let urlString = publicUrl.absoluteString
        
        // Update the challenge record with the icon URL
        try await SupabaseManager.shared.supabaseClient
            .from("private_challenges")
            .update(["cover_image_url": urlString])
            .eq("challenge_id", value: challengeId.uuidString)
            .execute()
        
        AppLogger.info("Challenge icon uploaded: \(urlString)", category: .social)
        
        await fetchMyChallenges()
        cacheData()
        return urlString
    }
    
    /// Remove the challenge icon and revert to emoji display.
    func removeChallengeIcon(challengeId: UUID) async -> Bool {
        let fileName = "challenge_icons/\(challengeId.uuidString).jpg"
        let bucket = "avatars"
        
        do {
            try await SupabaseManager.shared.supabaseClient.storage
                .from(bucket)
                .remove(paths: [fileName])
        } catch {
            AppLogger.warning("Could not delete challenge icon from storage: \(error.localizedDescription)", category: .social)
        }
        
        do {
            struct ClearIcon: Encodable {
                let cover_image_url: String? = nil
            }
            
            try await SupabaseManager.shared.supabaseClient
                .from("private_challenges")
                .update(ClearIcon())
                .eq("challenge_id", value: challengeId.uuidString)
                .execute()
            
            AppLogger.info("Challenge icon removed for \(challengeId)", category: .social)
            await fetchMyChallenges()
            cacheData()
            return true
        } catch {
            AppLogger.error("Error removing challenge icon URL: \(error.localizedDescription)", category: .social)
            return false
        }
    }
    
    // MARK: - Share Helper
    
    func shareMessage(for challenge: PrivateChallenge) -> String {
        let url = challenge.shareURL?.absoluteString ?? "https://fit33.app"
        return "\(challenge.displayEmoji) Join my private challenge \"\(challenge.title)\" on Fit33! \(challenge.formattedMemberCount) members and counting.\n\n\(url)"
    }
}
