//
//  CommunityChallengeService.swift
//  Fit33
//
//  Community Challenge System — open challenges anyone can join,
//  with real-time leaderboards, shareable invite links, and unlimited participants.
//  Think "10K Steps Daily" that thousands of users can opt into.
//

import Foundation
import SwiftUI
import Supabase
import Realtime

// MARK: - Community Challenge Models

/// A leaderboard snippet entry returned inline with community challenge data.
/// Used for rendering mini-leaderboard widgets without a separate RPC call.
struct LeaderboardSnippetEntry: Codable, Identifiable {
    let rank: Int
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let todayProgress: Int
    let daysCompleted: Int
    let currentStreak: Int
    let bestStreak: Int
    let targetHitToday: Bool
    let isCurrentUser: Bool
    
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
    
    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case name, username
        case profilePhotoUrl = "profile_photo_url"
        case todayProgress = "today_progress"
        case daysCompleted = "days_completed"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case targetHitToday = "target_hit_today"
        case isCurrentUser = "is_current_user"
    }
}

/// Lightweight friend info shown as avatar on community widgets
struct CommunityFriendInfo: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    
    var id: UUID { userId }
    
    var displayName: String {
        name ?? username ?? "Friend"
    }
    
    var initial: String {
        String((name ?? username ?? "?").prefix(1)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, username
        case profilePhotoUrl = "profile_photo_url"
    }
}

struct CommunityChallenge: Codable, Identifiable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let participantCount: Int
    let maxParticipants: Int?
    let joinCode: String
    let inviteSlug: String
    let isRecurring: Bool
    let isFeatured: Bool
    let isOfficial: Bool
    let myTodayProgress: Int?
    let myDaysCompleted: Int?
    let myCurrentStreak: Int?
    let myBestStreak: Int?
    let myRank: Int?
    let createdBy: UUID?
    let creatorName: String?
    let creatorUsername: String?
    let topParticipants: [LeaderboardSnippetEntry]?
    let friendsIn: [CommunityFriendInfo]?
    let friendsCount: Int?
    
    var id: UUID { challengeId }
    
    var displayEmoji: String { emoji ?? "🌍" }
    
    var shareURL: URL? {
        URL(string: "https://fit33.app/c/\(inviteSlug)")
    }
    
    /// Deep link URL
    var deepLinkURL: URL? {
        URL(string: "fit33://community-challenge/\(inviteSlug)")
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
    
    /// Formatted participant count (e.g., "1.2K" or "347")
    var formattedParticipantCount: String {
        if participantCount >= 10000 {
            return String(format: "%.1fK", Double(participantCount) / 1000)
        } else if participantCount >= 1000 {
            return String(format: "%.1fK", Double(participantCount) / 1000)
        }
        return "\(participantCount)"
    }
    
    /// How many of the top participants to show based on community size
    var leaderboardDisplayCount: Int {
        if participantCount >= 100 { return 10 }
        if participantCount >= 20 { return 7 }
        return 5
    }
    
    /// Capacity string (e.g. "47/200")
    var capacityString: String {
        if let max = maxParticipants {
            return "\(participantCount)/\(max)"
        }
        return "\(participantCount)"
    }
    
    /// Is the community nearly full?
    var isNearlyFull: Bool {
        guard let max = maxParticipants else { return false }
        return Double(participantCount) / Double(max) >= 0.9
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case participantCount = "participant_count"
        case maxParticipants = "max_participants"
        case joinCode = "join_code"
        case inviteSlug = "invite_slug"
        case isRecurring = "is_recurring"
        case isFeatured = "is_featured"
        case isOfficial = "is_official"
        case myTodayProgress = "my_today_progress"
        case myDaysCompleted = "my_days_completed"
        case myCurrentStreak = "my_current_streak"
        case myBestStreak = "my_best_streak"
        case myRank = "my_rank"
        case createdBy = "created_by"
        case creatorName = "creator_name"
        case creatorUsername = "creator_username"
        case topParticipants = "top_participants"
        case friendsIn = "friends_in"
        case friendsCount = "friends_count"
    }
}

/// A community challenge that the user's friends are in but the user hasn't joined yet.
/// Powers the "Your friends are in these communities" discovery widget.
struct DiscoverableCommunityChallenge: Codable, Identifiable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let participantCount: Int
    let maxParticipants: Int?
    let joinCode: String
    let inviteSlug: String
    let isRecurring: Bool
    let isFeatured: Bool
    let isOfficial: Bool
    let createdBy: UUID?
    let friendsInChallenge: [CommunityFriendInfo]?
    let friendsCount: Int
    
    var id: UUID { challengeId }
    var displayEmoji: String { emoji ?? "🌍" }
    
    var formattedParticipantCount: String {
        if participantCount >= 1000 {
            return String(format: "%.1fK", Double(participantCount) / 1000)
        }
        return "\(participantCount)"
    }
    
    var capacityString: String {
        if let max = maxParticipants {
            return "\(participantCount)/\(max)"
        }
        return "\(participantCount)"
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case participantCount = "participant_count"
        case maxParticipants = "max_participants"
        case joinCode = "join_code"
        case inviteSlug = "invite_slug"
        case isRecurring = "is_recurring"
        case isFeatured = "is_featured"
        case isOfficial = "is_official"
        case createdBy = "created_by"
        case friendsInChallenge = "friends_in_challenge"
        case friendsCount = "friends_count"
    }
}

/// Enriched detail response for community challenge detail view
struct CommunityDetailResponse: Codable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let participantCount: Int
    let maxParticipants: Int?
    let joinCode: String
    let inviteSlug: String
    let isRecurring: Bool
    let totalCompletions: Int
    // My stats
    let myTodayProgress: Int
    let myDaysCompleted: Int
    let myCurrentStreak: Int
    let myBestStreak: Int
    let myRank: Int
    let myTotalProgress: Int
    // Community stats
    let avgTodayProgress: Int
    let topTodayProgress: Int
    let avgStreak: Double
    let totalActiveToday: Int
    let completionRateToday: Double
    // Friends
    let friendsIn: [CommunityFriendInfo]?
    let friendsCount: Int
    // Leaderboard + encouragement
    let topLeaderboard: [LeaderboardSnippetEntry]?
    let encouragement: String?
    
    var displayEmoji: String { emoji ?? "🌍" }
    
    /// Shareable URL for this community challenge
    var shareURL: URL? {
        URL(string: "https://fit33.app/c/\(inviteSlug)")
    }
    
    var todayProgressPercentage: Double {
        guard dailyTarget > 0 else { return 0 }
        return min(1.0, Double(myTodayProgress) / Double(dailyTarget))
    }
    
    var targetHitToday: Bool {
        myTodayProgress >= dailyTarget
    }
    
    var capacityString: String {
        if let max = maxParticipants {
            return "\(participantCount)/\(max)"
        }
        return "\(participantCount)"
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case participantCount = "participant_count"
        case maxParticipants = "max_participants"
        case joinCode = "join_code"
        case inviteSlug = "invite_slug"
        case isRecurring = "is_recurring"
        case totalCompletions = "total_completions"
        case myTodayProgress = "my_today_progress"
        case myDaysCompleted = "my_days_completed"
        case myCurrentStreak = "my_current_streak"
        case myBestStreak = "my_best_streak"
        case myRank = "my_rank"
        case myTotalProgress = "my_total_progress"
        case avgTodayProgress = "avg_today_progress"
        case topTodayProgress = "top_today_progress"
        case avgStreak = "avg_streak"
        case totalActiveToday = "total_active_today"
        case completionRateToday = "completion_rate_today"
        case friendsIn = "friends_in"
        case friendsCount = "friends_count"
        case topLeaderboard = "top_leaderboard"
        case encouragement
    }
}

struct FeaturedCommunityChallenge: Codable, Identifiable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let participantCount: Int
    let totalCompletions: Int
    let joinCode: String
    let inviteSlug: String
    let isFeatured: Bool
    let isOfficial: Bool
    let isRecurring: Bool
    let category: String?
    let createdBy: UUID?
    let creatorName: String?
    let creatorUsername: String?
    let alreadyJoined: Bool
    
    var id: UUID { challengeId }
    var displayEmoji: String { emoji ?? "🌍" }
    
    var formattedParticipantCount: String {
        if participantCount >= 1000 {
            return String(format: "%.1fK", Double(participantCount) / 1000)
        }
        return "\(participantCount)"
    }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case participantCount = "participant_count"
        case totalCompletions = "total_completions"
        case joinCode = "join_code"
        case inviteSlug = "invite_slug"
        case isFeatured = "is_featured"
        case isOfficial = "is_official"
        case isRecurring = "is_recurring"
        case category
        case createdBy = "created_by"
        case creatorName = "creator_name"
        case creatorUsername = "creator_username"
        case alreadyJoined = "already_joined"
    }
}

struct CommunityLeaderboardEntry: Codable, Identifiable {
    let rank: Int
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let todayProgress: Int
    let daysCompleted: Int
    let currentStreak: Int
    let bestStreak: Int?
    let targetHitToday: Bool
    let totalProgress: Int?
    let isCurrentUser: Bool?
    
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
    
    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case name, username
        case profilePhotoUrl = "profile_photo_url"
        case todayProgress = "today_progress"
        case daysCompleted = "days_completed"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case targetHitToday = "target_hit_today"
        case totalProgress = "total_progress"
        case isCurrentUser = "is_current_user"
    }
}

struct CommunityLeaderboardResponse: Codable, ChallengeTypeResolvable {
    let challengeId: UUID
    let challengeTitle: String
    let challengeEmoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let participantCount: Int
    let joinCode: String
    let inviteSlug: String
    let leaderboard: [CommunityLeaderboardEntry]?
    let myRank: Int
    let myTodayProgress: Int
    let myDaysCompleted: Int
    let myCurrentStreak: Int
    let myBestStreak: Int
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case challengeTitle = "challenge_title"
        case challengeEmoji = "challenge_emoji"
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case participantCount = "participant_count"
        case joinCode = "join_code"
        case inviteSlug = "invite_slug"
        case leaderboard
        case myRank = "my_rank"
        case myTodayProgress = "my_today_progress"
        case myDaysCompleted = "my_days_completed"
        case myCurrentStreak = "my_current_streak"
        case myBestStreak = "my_best_streak"
    }
    
    var title: String { challengeTitle }
}

struct CommunityChallengePreview: Codable, Identifiable, ChallengeTypeResolvable {
    let challengeId: UUID
    let title: String
    let description: String?
    let emoji: String?
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let participantCount: Int
    let joinCode: String
    let inviteSlug: String
    let isRecurring: Bool
    let isFeatured: Bool
    let isOfficial: Bool
    let creatorName: String?
    let creatorUsername: String?
    let creatorPhotoUrl: String?
    let alreadyJoined: Bool
    let status: String
    
    var id: UUID { challengeId }
    var displayEmoji: String { emoji ?? "🌍" }
    
    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case title, description, emoji
        case challengeType = "challenge_type"
        case dailyTarget = "daily_target"
        case targetUnit = "target_unit"
        case participantCount = "participant_count"
        case joinCode = "join_code"
        case inviteSlug = "invite_slug"
        case isRecurring = "is_recurring"
        case isFeatured = "is_featured"
        case isOfficial = "is_official"
        case creatorName = "creator_name"
        case creatorUsername = "creator_username"
        case creatorPhotoUrl = "creator_photo_url"
        case alreadyJoined = "already_joined"
        case status
    }
}


// MARK: - Community Challenge Service

@MainActor
class CommunityChallengeService: ObservableObject {
    static let shared = CommunityChallengeService()
    
    @Published var myChallenges: [CommunityChallenge] = []
    @Published var featuredChallenges: [FeaturedCommunityChallenge] = []
    @Published var discoverableChallenges: [DiscoverableCommunityChallenge] = []
    @Published var isLoading = false
    
    /// Rank change deltas: challengeId → userId → delta (positive = climbed UP, negative = dropped)
    /// e.g. +2 means user moved up 2 spots, -1 means dropped 1 spot
    @Published var rankDeltas: [UUID: [UUID: Int]] = [:]
    
    /// Realtime channel for community updates
    private var communityRealtimeChannel: RealtimeChannelV2?
    
    /// Stores previous ranks for delta computation: challengeId → userId → rank
    private var previousRanks: [UUID: [UUID: Int]] = [:]
    
    /// Whether the community widgets are currently visible on screen.
    /// When true, new deltas replace old ones in real-time.
    /// When false and the view reappears, deltas are cleared.
    var isCommunityViewVisible = false
    
    /// Tracks friend IDs we've already seen in discoverable challenges (for "friend joined" notifications)
    private var knownDiscoverableFriendIds: Set<UUID> = []
    
    /// Timestamp of last full refresh to avoid redundant calls
    private var lastRefreshTime: Date?
    
    private init() {}
    
    // MARK: - Refresh All Community Data
    
    /// Central refresh method — call from pull-to-refresh, tab switches, and app foreground.
    /// Throttled to avoid redundant network calls within 10 seconds.
    func refreshAll(force: Bool = false) async {
        let now = Date()
        if !force, let last = lastRefreshTime, now.timeIntervalSince(last) < 10 {
            #if DEBUG
            AppLogger.debug("Skipping community refresh — last was \(Int(now.timeIntervalSince(last)))s ago", category: .social)
            #endif
            return
        }
        lastRefreshTime = now
        
        // Fetch in parallel for speed
        async let challenges: () = fetchMyChallenges()
        async let featured: () = fetchFeaturedChallenges()
        async let discoverable: () = fetchDiscoverableChallenges()
        _ = await (challenges, featured, discoverable)
        
        #if DEBUG
        AppLogger.info("Successfully completed community full refresh", category: .social)
        #endif
    }
    
    // MARK: - Fetch My Community Challenges
    
    func fetchMyChallenges() async {
        do {
            struct TimezoneParams: Encodable {
                let p_timezone: String
            }
            
            let result: [CommunityChallenge] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_my_community_challenges", params: TimezoneParams(
                    p_timezone: TimeZone.current.identifier
                ))
                .execute()
                .value
            
            // Compute rank deltas before updating myChallenges
            computeRankDeltas(newChallenges: result)
            
            myChallenges = result
            
            // Preload profile photos for all visible participants
            var photoData: [(id: String, url: String?)] = []
            for challenge in result {
                if let participants = challenge.topParticipants {
                    for p in participants {
                        photoData.append((id: p.userId.uuidString, url: p.profilePhotoUrl))
                    }
                }
                if let friends = challenge.friendsIn {
                    for f in friends {
                        photoData.append((id: f.userId.uuidString, url: f.profilePhotoUrl))
                    }
                }
            }
            if !photoData.isEmpty {
                FriendPhotoCache.shared.preloadPhotos(for: photoData)
            }
            
            #if DEBUG
            AppLogger.info("Successfully fetched \(result.count) community challenges", category: .social)
            #endif
        } catch {
            AppLogger.error("Error fetching my community challenges: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Computes rank change deltas by comparing new leaderboard data against stored previous ranks.
    /// A positive delta means the user climbed (e.g. rank 5 → 3 = +2).
    /// A negative delta means the user dropped (e.g. rank 3 → 5 = -2).
    /// Arrows appear with animation and auto-clear after 6 seconds.
    private func computeRankDeltas(newChallenges: [CommunityChallenge]) {
        var newDeltas: [UUID: [UUID: Int]] = [:]
        var newPreviousRanks: [UUID: [UUID: Int]] = [:]
        
        for challenge in newChallenges {
            let cid = challenge.challengeId
            guard let entries = challenge.topParticipants, !entries.isEmpty else { continue }
            
            // Build current rank map
            var currentRanks: [UUID: Int] = [:]
            for entry in entries {
                currentRanks[entry.userId] = entry.rank
            }
            newPreviousRanks[cid] = currentRanks
            
            // Compare against previous if we have it
            guard let prevRanks = previousRanks[cid] else { continue }
            
            var challengeDeltas: [UUID: Int] = [:]
            for entry in entries {
                if let prevRank = prevRanks[entry.userId] {
                    // Delta: positive = climbed up (lower rank number is better)
                    let delta = prevRank - entry.rank
                    if delta != 0 {
                        challengeDeltas[entry.userId] = delta
                    }
                }
                // New users (not in previous) get no delta — they're new arrivals
            }
            
            if !challengeDeltas.isEmpty {
                newDeltas[cid] = challengeDeltas
            }
        }
        
        // Update stored state
        previousRanks = newPreviousRanks
        
        // Animate the delta arrows in.
        // Arrows persist until the user navigates away from the community view.
        // If the user is already viewing, new deltas replace old ones in real-time.
        if !newDeltas.isEmpty {
            if isCommunityViewVisible {
                // User is watching — merge new deltas into existing (replace per-challenge)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    for (cid, userDeltas) in newDeltas {
                        rankDeltas[cid] = userDeltas
                    }
                }
            } else {
                // User isn't on the screen yet — set fresh deltas for when they arrive
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    rankDeltas = newDeltas
                }
            }
        }
        // If newDeltas is empty, keep existing arrows visible until cleared
    }
    
    // MARK: - Rank Delta Visibility
    
    /// Call when the community widgets appear on screen (Friends tab, Community Hub).
    /// Keeps existing arrows visible and enables real-time delta updates.
    func markCommunityViewVisible() {
        isCommunityViewVisible = true
    }
    
    /// Call when the user navigates AWAY from the community widgets.
    /// Clears all rank delta arrows so they're gone when the user returns.
    func markCommunityViewHidden() {
        isCommunityViewVisible = false
        withAnimation(.easeOut(duration: 0.4)) {
            rankDeltas = [:]
        }
    }
    
    // MARK: - Fetch Discoverable (Friends' Communities)
    
    /// Fetches community challenges that the user's friends are in,
    /// but the user hasn't joined yet. Powers the "friends are in these" widget.
    func fetchDiscoverableChallenges() async {
        do {
            struct DiscoverParams: Encodable {
                let p_timezone: String
                let p_limit: Int
            }
            
            let result: [DiscoverableCommunityChallenge] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_discoverable_community_challenges", params: DiscoverParams(
                    p_timezone: TimeZone.current.identifier,
                    p_limit: 20
                ))
                .execute()
                .value
            
            // Sort by friends count descending so communities with most friends appear first
            let sorted = result.sorted { ($0.friendsCount) > ($1.friendsCount) }
            
            // Detect NEW friends in discoverable challenges for notification
            notifyNewFriendJoins(newChallenges: sorted)
            
            discoverableChallenges = sorted
            #if DEBUG
            AppLogger.info("Successfully fetched \(sorted.count) discoverable friend communities", category: .social)
            #endif
        } catch {
            AppLogger.error("Error fetching discoverable challenges: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Detect when a new friend joins a community we haven't joined,
    /// and send a throttled notification to encourage the user to check it out.
    private func notifyNewFriendJoins(newChallenges: [DiscoverableCommunityChallenge]) {
        // Build current set of friend IDs across all discoverable challenges
        var currentFriendIds = Set<UUID>()
        for challenge in newChallenges {
            for friend in challenge.friendsInChallenge ?? [] {
                currentFriendIds.insert(friend.userId)
            }
        }
        
        // On first load, just seed the known set (don't spam on app launch)
        guard !knownDiscoverableFriendIds.isEmpty else {
            knownDiscoverableFriendIds = currentFriendIds
            return
        }
        
        // Find truly new friend IDs
        let newFriendIds = currentFriendIds.subtracting(knownDiscoverableFriendIds)
        knownDiscoverableFriendIds = currentFriendIds
        
        guard !newFriendIds.isEmpty else { return }
        
        // Find the challenge with the most friends that contains one of these new friend IDs
        // (pick the most compelling one to notify about)
        for challenge in newChallenges {
            guard let friends = challenge.friendsInChallenge else { continue }
            if let newFriend = friends.first(where: { newFriendIds.contains($0.userId) }) {
                let friendName = newFriend.name ?? newFriend.username ?? "A friend"
                NotificationManager.shared.sendCommunityFriendJoinedNotification(
                    friendName: friendName,
                    challengeTitle: challenge.title,
                    challengeEmoji: challenge.displayEmoji,
                    inviteSlug: challenge.inviteSlug
                )
                break // Only send one notification (throttle handles frequency)
            }
        }
    }
    
    // MARK: - Fetch Featured / Discover
    
    func fetchFeaturedChallenges(category: String? = nil) async {
        do {
            struct FeaturedParams: Encodable {
                let p_limit: Int
                let p_category: String?
            }
            
            let result: [FeaturedCommunityChallenge] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_featured_community_challenges", params: FeaturedParams(
                    p_limit: 30,
                    p_category: category
                ))
                .execute()
                .value
            
            featuredChallenges = result
            #if DEBUG
            AppLogger.info("Successfully fetched \(result.count) featured challenges", category: .social)
            #endif
        } catch {
            AppLogger.error("Error fetching featured challenges: \(error.localizedDescription)", category: .social)
        }
    }
    
    // MARK: - Create Community Challenge
    
    func createChallenge(
        challengeType: String,
        title: String,
        description: String? = nil,
        emoji: String = "🌍",
        dailyTarget: Int,
        targetUnit: String,
        isRecurring: Bool = true,
        endDate: String? = nil,
        maxParticipants: Int? = nil,
        visibility: String = "public",
        category: String = "fitness"
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
                let p_max_participants: Int?
                let p_visibility: String
                let p_category: String
            }
            
            let id: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("create_community_challenge", params: CreateParams(
                    p_challenge_type: challengeType,
                    p_title: title,
                    p_description: description,
                    p_emoji: emoji,
                    p_daily_target: dailyTarget,
                    p_target_unit: targetUnit,
                    p_is_recurring: isRecurring,
                    p_end_date: endDate,
                    p_max_participants: maxParticipants,
                    p_visibility: visibility,
                    p_category: category
                ))
                .execute()
                .value
            
            #if DEBUG
            AppLogger.info("Successfully created community challenge: \(id)", category: .social)
            #endif
            await fetchMyChallenges()
            return id
        } catch {
            AppLogger.error("Error creating community challenge: \(error.localizedDescription)", category: .social)
            return nil
        }
    }
    
    // MARK: - Join Challenge
    
    func joinChallenge(code: String? = nil, slug: String? = nil, referredBy: String? = nil) async -> UUID? {
        do {
            struct JoinParams: Encodable {
                let p_join_code: String?
                let p_invite_slug: String?
                let p_referred_by: String?
            }
            
            let id: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("join_community_challenge", params: JoinParams(
                    p_join_code: code,
                    p_invite_slug: slug,
                    p_referred_by: referredBy
                ))
                .execute()
                .value
            
            #if DEBUG
            AppLogger.info("Successfully joined community challenge: \(id)", category: .social)
            #endif
            HapticManager.notification(.success)
            await fetchMyChallenges()
            return id
        } catch {
            AppLogger.error("Error joining community challenge: \(error.localizedDescription)", category: .social)
            HapticManager.notification(.error)
            return nil
        }
    }
    
    // MARK: - Join Challenge (Friend-Gated)
    
    /// Join a community challenge through the friend-chain.
    /// This checks that the user has a friend or FoF in the challenge.
    func joinChallengeFriendGated(challengeId: UUID, referredBy: String? = nil) async -> UUID? {
        do {
            struct JoinFriendsParams: Encodable {
                let p_challenge_id: String
                let p_referred_by: String?
            }
            
            let id: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("join_community_challenge_friends", params: JoinFriendsParams(
                    p_challenge_id: challengeId.uuidString,
                    p_referred_by: referredBy
                ))
                .execute()
                .value
            
            #if DEBUG
            AppLogger.info("Successfully joined friend-gated community: \(id)", category: .social)
            #endif
            HapticManager.notification(.success)
            await fetchMyChallenges()
            await fetchDiscoverableChallenges()
            return id
        } catch {
            AppLogger.error("Error joining friend-gated challenge: \(error.localizedDescription)", category: .social)
            HapticManager.notification(.error)
            return nil
        }
    }
    
    // MARK: - Get Challenge Detail (Enriched)
    
    /// Fetches enriched detail for a community challenge including
    /// community stats, friend highlights, and encouragement.
    func getChallengeDetail(challengeId: UUID) async -> CommunityDetailResponse? {
        do {
            struct DetailParams: Encodable {
                let p_challenge_id: String
                let p_timezone: String
            }
            
            let results: [CommunityDetailResponse] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_community_challenge_detail", params: DetailParams(
                    p_challenge_id: challengeId.uuidString,
                    p_timezone: TimeZone.current.identifier
                ))
                .execute()
                .value
            
            return results.first
        } catch {
            AppLogger.error("Error fetching community challenge detail: \(error.localizedDescription)", category: .social)
            return nil
        }
    }
    
    // MARK: - Realtime Subscriptions
    
    /// Subscribe to real-time updates for community challenge participant changes.
    /// When any participant joins, leaves, or logs progress, the widget updates live.
    func subscribeToRealtimeUpdates() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        // Prevent duplicate subscriptions — calling postgresChange on an already-subscribed
        // channel triggers "You cannot call postgresChange after joining the channel" warning
        // and silently breaks the subscription.
        if communityRealtimeChannel != nil {
            AppLogger.debug("Already subscribed to community real-time updates — skipping", category: .social)
            return
        }
        
        let client = SupabaseManager.shared.supabaseClient
        let channel = client.realtimeV2.channel("community-challenges")
        
        // Listen for new participants joining (someone's friend joins → update widgets)
        let participantInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_challenge_participants"
        )
        
        // Listen for participant updates (progress changes)
        let participantUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "community_challenge_participants"
        )
        
        // Listen for daily progress changes (live leaderboard updates)
        let progressInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_challenge_daily_progress"
        )
        
        let progressUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "community_challenge_daily_progress"
        )
        
        // Handle participant changes → refresh widget data
        Task {
            for await _ in participantInserts {
                AppLogger.debug("Realtime: new participant joined a community", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in participantUpdates {
                AppLogger.debug("Realtime: community participant updated", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        // Handle progress changes → refresh leaderboard data
        Task {
            for await _ in progressInserts {
                AppLogger.debug("Realtime: new community progress logged", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        Task {
            for await _ in progressUpdates {
                AppLogger.debug("Realtime: community progress updated", category: .social)
                await refreshAfterRealtimeUpdate()
            }
        }
        
        await channel.subscribe()
        communityRealtimeChannel = channel
        AppLogger.info("Successfully subscribed to real-time community updates", category: .social)
    }
    
    /// Unsubscribe from real-time updates
    func unsubscribeFromRealtimeUpdates() async {
        if let channel = communityRealtimeChannel {
            await channel.unsubscribe()
            communityRealtimeChannel = nil
            AppLogger.debug("Unsubscribed from community real-time updates", category: .social)
        }
    }
    
    /// Debounced refresh after a realtime event
    private var lastRealtimeRefresh: Date = .distantPast
    
    private func refreshAfterRealtimeUpdate() async {
        // Debounce: don't refresh more than once every 3 seconds
        let now = Date()
        guard now.timeIntervalSince(lastRealtimeRefresh) > 3 else { return }
        lastRealtimeRefresh = now
        
        await fetchMyChallenges()
        await fetchDiscoverableChallenges()
    }
    
    // MARK: - Leave Challenge
    
    func leaveChallenge(challengeId: UUID) async -> Bool {
        do {
            struct LeaveParams: Encodable {
                let p_challenge_id: String
            }
            
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("leave_community_challenge", params: LeaveParams(
                    p_challenge_id: challengeId.uuidString
                ))
                .execute()
                .value
            
            myChallenges.removeAll { $0.challengeId == challengeId }
            #if DEBUG
            AppLogger.info("Successfully left community challenge: \(challengeId)", category: .social)
            #endif
            return true
        } catch {
            AppLogger.error("Error leaving community challenge: \(error.localizedDescription)", category: .social)
            return false
        }
    }
    
    // MARK: - Log Progress
    
    func logProgress(challengeId: UUID, progressValue: Int, allowDecrease: Bool = false) async -> Bool {
        struct LogParams: Encodable {
            let p_challenge_id: String
            let p_progress: Int
            let p_timezone: String
            let p_allow_decrease: Bool
        }
        
        let maxRetries = 5
        for attempt in 1...maxRetries {
            do {
                let _: Bool = try await SupabaseManager.shared.supabaseClient
                    .rpc("log_community_challenge_progress", params: LogParams(
                        p_challenge_id: challengeId.uuidString,
                        p_progress: progressValue,
                        p_timezone: TimeZone.current.identifier,
                        p_allow_decrease: allowDecrease
                    ))
                    .execute()
                    .value
                
                #if DEBUG
                AppLogger.info("Successfully logged community progress: \(progressValue) for \(challengeId) (allowDecrease: \(allowDecrease))", category: .social)
                #endif
                return true
            } catch {
                guard !Task.isCancelled else { return false }
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    AppLogger.warning("log_community_challenge_progress cancelled (attempt \(attempt)/\(maxRetries)), retrying in \(Double(delay) / 1_000_000_000)s...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    AppLogger.error("Error logging community progress: \(error.localizedDescription)", category: .social)
                    return false
                }
            }
        }
        return false
    }
    
    // MARK: - Get Leaderboard
    
    func getLeaderboard(challengeId: UUID, limit: Int = 20) async -> CommunityLeaderboardResponse? {
        do {
            struct LeaderboardParams: Encodable {
                let p_challenge_id: String
                let p_limit: Int
                let p_timezone: String
            }
            
            let results: [CommunityLeaderboardResponse] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_community_challenge_leaderboard", params: LeaderboardParams(
                    p_challenge_id: challengeId.uuidString,
                    p_limit: limit,
                    p_timezone: TimeZone.current.identifier
                ))
                .execute()
                .value
            
            return results.first
        } catch {
            AppLogger.error("Error fetching community leaderboard: \(error.localizedDescription)", category: .social)
            return nil
        }
    }
    
    // MARK: - Lookup Challenge by Code/Slug
    
    func lookupChallenge(code: String) async -> CommunityChallengePreview? {
        do {
            struct LookupParams: Encodable {
                let p_code: String
            }
            
            let results: [CommunityChallengePreview] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_community_challenge_by_code", params: LookupParams(
                    p_code: code
                ))
                .execute()
                .value
            
            return results.first
        } catch {
            AppLogger.error("Error looking up community challenge: \(error.localizedDescription)", category: .social)
            return nil
        }
    }
    
    // MARK: - Quick Type-Specific Sync
    
    /// Quick sync for a SPECIFIC challenge type to community challenges.
    /// Called immediately when user logs data (protein, hydration, calories, etc.).
    /// Much faster than full sync — only touches matching challenges.
    /// Pass `allowDecrease: true` when the value may have gone DOWN (e.g. meal removed).
    func syncTrackingForType(_ type: ChallengeType, value: Int, source: String = "auto_sync", allowDecrease: Bool = false) async {
        let matching = myChallenges.filter { $0.resolvedType == type }
        guard !matching.isEmpty else { return }
        
        AppLogger.debug("Quick sync \(type.rawValue): \(value) to \(matching.count) community challenge(s) (allowDecrease: \(allowDecrease))", category: .social)
        
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
    
    // MARK: - Auto-Sync Progress to Community Challenges
    
    /// Syncs HealthKit/tracking data to all active community challenges
    /// Called alongside the existing challenge sync
    func syncAllTrackingToCommunityChallenges() async {
        guard !myChallenges.isEmpty else { return }
        
        let progress = await gatherCurrentProgress()
        
        #if DEBUG
        AppLogger.debug("Syncing tracking data to \(myChallenges.count) community challenges...", category: .social)
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
        
        // Refresh to show updated progress
        await fetchMyChallenges()
        #if DEBUG
        AppLogger.info("Successfully completed community challenge sync", category: .social)
        #endif
    }
    
    private func resolveProgress(for challenge: CommunityChallenge, from data: ChallengeProgressData) -> Int {
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
    
    // MARK: - Share Helper
    
    /// Generate a share message for a community challenge
    func shareMessage(for challenge: CommunityChallenge) -> String {
        let url = challenge.shareURL?.absoluteString ?? "https://fit33.app"
        return "\(challenge.displayEmoji) Join me on the \"\(challenge.title)\" challenge on Fit33! \(challenge.formattedParticipantCount) people are already in. Can you hit \(challenge.dailyTarget) \(challenge.targetUnit) daily?\n\n\(url)"
    }
    
    /// Generate a share message for a community challenge detail (used from CommunityDetailView)
    func shareMessage(for detail: CommunityDetailResponse) -> String {
        let url = detail.shareURL?.absoluteString ?? "https://fit33.app"
        return "\(detail.displayEmoji) Join me on the \"\(detail.title)\" challenge on Fit33! \(detail.participantCount) people are already in. Can you hit \(detail.dailyTarget) \(detail.targetUnit) daily?\n\n\(url)"
    }
    
    /// Generate a share message when you hit your target
    func celebrationShareMessage(for challenge: CommunityChallenge) -> String {
        let url = challenge.shareURL?.absoluteString ?? "https://fit33.app"
        let rank = challenge.myRank ?? 0
        return "🎉 I just crushed my \(challenge.title) goal! Ranked #\(rank) out of \(challenge.formattedParticipantCount) people on Fit33.\n\nThink you can beat me? \(url)"
    }
}
