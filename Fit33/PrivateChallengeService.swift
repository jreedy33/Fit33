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

    /// Sprint 2 Q2-46 — set of chat message IDs that the moderation webhook
    /// flipped to `is_hidden = true` during this session. Chat UIs must filter
    /// these out regardless of whether the refetched row still contains them.
    @Published var hiddenChatMessageIds: Set<UUID> = []
    
    /// Realtime channel for live updates
    private var realtimeChannel: RealtimeChannelV2?
    
    /// Throttle
    private var lastRefreshTime: Date?
    private var lastRealtimeRefresh: Date = .distantPast
    
    // Cache keys
    private let myChallengesCacheKey = "private_challenges_cache"
    private let invitesCacheKey = "private_challenge_invites_cache"
    private let cacheDateKey = "private_challenges_cache_date"
    private let chatLastReadKey = "private_challenge_chat_last_read_v1"

    // MARK: - Chat Unread Tracking
    // Derived purely from `PrivateChallenge.lastChatAt` (already on the model) vs a
    // per-challenge "last read" timestamp persisted in UserDefaults. No new DB query,
    // no new realtime subscription — the existing `chatInserts` sub already refetches
    // `myChallenges` on every message, which updates `lastChatAt` and triggers SwiftUI
    // to re-evaluate `hasUnreadChat(for:)` on any card observing this service.
    private var chatLastReadAt: [String: Date] = [:]

    /// Incremented when a chat is marked read so cards not bound to `myChallenges`
    /// changes (e.g. ones using stored `let` copies) can still refresh.
    @Published var chatUnreadChangeToken = UUID()

    private init() {
        // ⚡️ Cold-start Phase 4: prefer pre-decoded caches from
        // StartupCachePreloader (decoded on bg before init runs on main).
        let pre = StartupCachePreloader.consumePrivateChallenges()
        if let cachedChallenges = pre.challenges {
            self.myChallenges = cachedChallenges
            #if DEBUG
            AppLogger.info("Successfully loaded \(cachedChallenges.count) cached private challenges (pre-decoded)", category: .social)
            #endif
        }
        if let cachedInvites = pre.invites {
            self.pendingInvites = cachedInvites
            #if DEBUG
            AppLogger.info("Successfully loaded \(cachedInvites.count) cached private invites (pre-decoded)", category: .social)
            #endif
        }
        // Fall back to the legacy synchronous loader only if BOTH slots
        // were unset (preloader hadn't completed in time).
        if pre.challenges == nil && pre.invites == nil {
            loadFromCache()
        }
        loadChatLastReadTimes()
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
        UserDefaults.standard.removeObject(forKey: chatLastReadKey)
        myChallenges = []
        pendingInvites = []
        chatLastReadAt = [:]
    }

    // MARK: - Chat Unread Tracking

    /// Returns true when the challenge has a `lastChatAt` newer than the last time
    /// the user opened its detail view. O(1) dict lookup — safe to call from card
    /// `body` on every redraw.
    func hasUnreadChat(for challenge: PrivateChallenge) -> Bool {
        guard let lastChat = challenge.lastChatAt else { return false }
        let lastRead = chatLastReadAt[challenge.challengeId.uuidString] ?? .distantPast
        return lastChat > lastRead
    }

    /// Called by `PrivateChallengeDetailView` on appear (and after sending a message)
    /// to clear the unread indicator. Persists immediately so the dot doesn't flash
    /// back on the next cold launch.
    func markChatAsRead(challengeId: UUID) {
        let key = challengeId.uuidString
        chatLastReadAt[key] = Date()
        saveChatLastReadTimes()
        chatUnreadChangeToken = UUID()
    }

    private func loadChatLastReadTimes() {
        guard let data = UserDefaults.standard.data(forKey: chatLastReadKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            chatLastReadAt = decoded
        }
    }

    private func saveChatLastReadTimes() {
        if let data = try? JSONEncoder().encode(chatLastReadAt) {
            UserDefaults.standard.set(data, forKey: chatLastReadKey)
        }
    }
    
    // MARK: - Refresh All
    
    func refreshAll(force: Bool = false) async {
        // Cluster D: top-level gate prevents 2 RPCs firing before JWT is
        // fresh, which previously produced paired 401 fingerprints
        // ("fetchMyChallenges failed" + "fetchPendingInvites failed").
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug(
                "Skipping private refreshAll — not authenticated",
                category: .social,
                context: DiagnosticContext(op: "private_challenges.refresh_all", endpoint: "rpc/get_my_private_challenges")
            )
            return
        }
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

    /// Outcome of an `inviteUser` call. The two non-error cases ride the
    /// SAME UI affordance (green "Sent" badge) — `alreadyInvited` is the
    /// idempotent-resend response from `invite_to_private_challenge` when
    /// the invitee already has a `pending` invite for this challenge.
    /// Surfacing it as a real failure ("⚠️ Error" badge) was misleading
    /// (canonical incident: Manuel tapped Invite for Andre twice within 20
    /// min on 2026-04-29 — second tap painted as a hard error even though
    /// the original pending invite was perfectly valid).
    enum InviteOutcome {
        case sent(UUID)
        case alreadyInvited
        case alreadyMember
        case notAllowed(String)
        case failed(String)
    }

    func inviteUser(challengeId: UUID, userId: UUID) async -> InviteOutcome {
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
            return .sent(inviteId)
        } catch {
            // Server's `invite_to_private_challenge` RPC raises typed
            // exceptions (see `supabase/fix_private_challenge_invite.sql`).
            // Translate the canonical messages into structured outcomes so
            // the UI can show the right copy + the right badge instead of
            // a generic "⚠️ Error".
            let desc = error.localizedDescription.lowercased()
            if desc.contains("already has a pending invite") {
                AppLogger.debug("inviteUser idempotent: already pending for \(userId) on \(challengeId)", category: .social)
                return .alreadyInvited
            }
            if desc.contains("already a member") {
                AppLogger.debug("inviteUser: \(userId) is already a member of \(challengeId)", category: .social)
                return .alreadyMember
            }
            if desc.contains("only admins can invite")
                || desc.contains("not a member of this challenge")
                || desc.contains("challenge is full")
            {
                AppLogger.warning("inviteUser blocked by RPC policy: \(error.localizedDescription)", category: .social)
                return .notAllowed(error.localizedDescription)
            }
            AppLogger.error("Error inviting user to private challenge: \(error.localizedDescription)", category: .social)
            HapticManager.notification(.error)
            return .failed(error.localizedDescription)
        }
    }

    /// Returns the set of `invited_user_id`s that currently have a
    /// `pending` invite to this challenge created by the current user.
    /// Used by `PrivateChallengeInviteView` to pre-paint already-invited
    /// friends in the "Sent" state on sheet open, so the user never sees
    /// an "Invite" button for someone who's already been invited (which
    /// would lead to the duplicate-tap error path that produced the
    /// 2026-04-29 Manuel × Andre incident).
    func fetchPendingInviteeIds(challengeId: UUID) async -> Set<UUID> {
        struct InviteRow: Decodable { let invited_user_id: UUID }
        guard let me = SupabaseManager.shared.currentUser?.id else { return [] }
        do {
            let rows: [InviteRow] = try await SupabaseManager.shared.supabaseClient
                .from("private_challenge_invites")
                .select("invited_user_id")
                .eq("challenge_id", value: challengeId.uuidString)
                .eq("invited_by", value: me.uuidString)
                .eq("status", value: "pending")
                .execute()
                .value
            return Set(rows.map { $0.invited_user_id })
        } catch {
            // RLS or schema drift — fall through silently so the user can
            // still tap Invite. Worst case is we re-show the duplicate
            // path and the error message gets translated into the
            // alreadyInvited outcome above.
            AppLogger.warning("fetchPendingInviteeIds failed (will re-prompt): \(error.localizedDescription)", category: .social)
            return []
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
        var didAttemptJwtRefresh = false
        let startedAt = Date()
        let userId = SupabaseManager.shared.currentUser?.id
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
                let isJwtExpired = error.localizedDescription.localizedCaseInsensitiveContains("jwt expired")
                    || error.localizedDescription.localizedCaseInsensitiveContains("invalid jwt")
                // Postgres deadlock (SQLSTATE 40P01) — bug-intel fingerprints
                // 3d7ac331 + 23ac8780. The 2026-05-24 migration adds a
                // server-side retry loop, but keep a client-side safety net
                // in case the server exhausts its retries under load.
                let desc = error.localizedDescription.lowercased()
                let isDeadlock = desc.contains("40p01") || desc.contains("deadlock detected")

                // Cluster G (fingerprint 9a4b5b9e, infra-security HIGH):
                // long-lived sessions that stay open overnight lose the
                // access token while the refresh token is still valid. When
                // the user taps "Mark complete" on a challenge, the RPC
                // returns "JWT expired" and the catch-all `.error` both
                // fingerprinted and dropped the user's progress on the floor.
                // Refresh the session ONCE and retry — mirrors the startup
                // recovery path in `restoreSessionIfAvailable`. If refresh
                // fails, the user genuinely needs to re-auth; surface via
                // NetworkErrorClassifier (classified as `.authExpired`
                // → `.warning` on category `.auth`, so it no longer
                // manufactures a crash fingerprint on normal logout/re-auth).
                if isJwtExpired && !didAttemptJwtRefresh {
                    didAttemptJwtRefresh = true
                    AppLogger.warning("log_private_challenge_progress JWT expired — attempting session refresh before retry", category: .auth)
                    do {
                        _ = try await SupabaseManager.shared.supabaseClient.auth.refreshSession()
                        AppLogger.info("Session refreshed — retrying challenge progress log", category: .auth)
                        continue
                    } catch {
                        AppLogger.warning("Session refresh failed during challenge progress log: \(error.localizedDescription)", category: .auth)
                        _ = NetworkErrorClassifier.log(
                            error,
                            context: "Error logging private challenge progress (session refresh failed)",
                            category: .social,
                            op: "challenges.log_private_progress",
                            endpoint: "rpc/log_private_challenge_progress",
                            startedAt: startedAt,
                            userId: userId
                        )
                        return false
                    }
                }

                if isTimeout && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    AppLogger.warning("log_private_challenge_progress timeout (attempt \(attempt)/\(maxRetries)), retrying...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                } else if isDeadlock && attempt < maxRetries {
                    // Short jittered backoff (150-300ms) so the competing
                    // transaction can commit before we retry.
                    let jitter = UInt64.random(in: 150_000_000...300_000_000)
                    AppLogger.warning("log_private_challenge_progress deadlock (40P01) attempt \(attempt)/\(maxRetries), retrying...", category: .social)
                    try? await Task.sleep(nanoseconds: jitter)
                } else {
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error logging private challenge progress",
                        category: .social,
                        op: "challenges.log_private_progress",
                        endpoint: "rpc/log_private_challenge_progress",
                        startedAt: startedAt,
                        userId: userId,
                        retryAttempt: attempt
                    )
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

            // Sprint 2 Q2-35 — flush queued push notifications so recipients
            // see chat messages pushed in-app while they're backgrounded.
            PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "private_challenge_chat")

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
        } catch is CancellationError {
            // Tab switch / view disappear cancelled the in-flight RPC.
            // Same drain as ContactsService — must NOT classify as a real
            // error or bug-intel will fingerprint every navigation away
            // from a private-challenge chat as a crash-class event.
            AppLogger.debug("[Social] fetchMessages cancelled (tab switch / view disappear)", category: .social)
            return []
        } catch {
            if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
                AppLogger.debug("[Social] Private challenge messages request cancelled (URLSession)", category: .social)
                return []
            }
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

        // Sprint 2 Q2-46 — pick up is_hidden flips from the moderation
        // webhook so a flagged message disappears from the sender's own chat
        // in real time (previously persisted locally until refetch).
        let chatUpdates = channel.postgresChange(
            UpdateAction.self,
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

        Task {
            for await action in chatUpdates {
                let record = action.record
                let isHidden = (record["is_hidden"] as? AnyJSON)?.boolValue ?? false
                guard isHidden else { continue }
                let idStr = (record["id"] as? AnyJSON)?.stringValue
                guard let id = idStr, let messageId = UUID(uuidString: id) else { continue }
                AppLogger.info("Realtime: chat \(messageId.uuidString.prefix(8)) hidden by moderation", category: .social)
                await MainActor.run {
                    self.hiddenChatMessageIds.insert(messageId)
                    self.chatMessageToken = UUID()
                }
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
        // Auto-populate `myChallenges` if the service hasn't fetched this
        // session (e.g. cold HealthKit observer wake). Without this guard the
        // background sync silently no-ops while other challenge services push
        // fresh values, causing cross-surface inconsistency (private shows
        // data, community/1v1 don't — observed 2026-04-24 Paul in private
        // leaderboard vs Paul shown as "—" in community leaderboard same min).
        if myChallenges.isEmpty {
            await fetchMyChallenges()
        }
        guard !myChallenges.isEmpty else { return }

        // Force-refresh HealthKit first so `todaySteps` / `todayActiveMinutes`
        // are pulled fresh for the *current* local day. Without this, a dawn
        // sync can push yesterday's cached `@Published var todaySteps` as
        // today's value (seen 2026-04-24: Paul logged his 15,718 EoD yesterday
        // total against today's progress_date at 00:30 ET). HealthKitService's
        // RequestCoalescer collapses repeat calls so the overhead is ~free
        // when a fresh sync is already in flight (e.g. BG sync path).
        await HealthKitService.shared.syncAllData(force: true)

        let progress = await gatherCurrentProgress()
        
        #if DEBUG
        AppLogger.debug("Syncing tracking data to \(myChallenges.count) private challenges...", category: .social)
        #endif
        
        for (index, challenge) in myChallenges.enumerated() {
            let progressValue = resolveProgress(for: challenge, from: progress)
            
            // "Recalculable" types: the local computation is authoritative, so we
            // MUST log even when 0 (so stale yesterday rows get overwritten) and
            // MUST pass allowDecrease=true (so the server's GREATEST() clause
            // doesn't pin a ghost high value across midnight).
            //
            // • protein / hydrate / calories — recomputed from today's meals/logs;
            //   decreases when a meal is removed.
            // • steps / active_minutes — cumulative HealthKit counters that start
            //   fresh at the user's local midnight. A stale @Published cache at
            //   the midnight boundary can push yesterday's EoD total as today's
            //   value; without allowDecrease the next fresh read can never
            //   correct it.
            let isRecalculable = (challenge.challengeType == "protein" ||
                                  challenge.challengeType == "hydrate" ||
                                  challenge.challengeType == "calories" ||
                                  challenge.challengeType == "steps" ||
                                  challenge.challengeType == "active_minutes")
            
            if progressValue > 0 || isRecalculable {
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
