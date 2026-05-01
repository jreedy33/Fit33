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
    var rank: Int
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    var todayProgress: Int
    let daysCompleted: Int
    let currentStreak: Int
    let bestStreak: Int
    let targetHitToday: Bool
    let isCurrentUser: Bool
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
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
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
    var myTodayProgress: Int?
    let myDaysCompleted: Int?
    let myCurrentStreak: Int?
    let myBestStreak: Int?
    var myRank: Int?
    let createdBy: UUID?
    let creatorName: String?
    let creatorUsername: String?
    var topParticipants: [LeaderboardSnippetEntry]?
    let friendsIn: [CommunityFriendInfo]?
    let friendsCount: Int?
    /// Sprint 20260811 — cadence-aware fields. Optional + nil-safe.
    let targetCadence: String?
    let myPeriodProgress: Int?

    var cadence: ChallengeCadence {
        ChallengeCadence.parse(targetCadence)
    }
    
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
        case targetCadence = "target_cadence"
        case myPeriodProgress = "my_period_progress"
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
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
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
    /// Sprint 20260811 — paired with #177 RPC widening.
    let targetCadence: String?
    let myPeriodProgress: Int?

    var cadence: ChallengeCadence {
        ChallengeCadence.parse(targetCadence)
    }
    
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
        case targetCadence = "target_cadence"
        case myPeriodProgress = "my_period_progress"
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
    
    /// Timer for delayed rank delta clearing after user has "seen" them
    private var rankDeltaClearTask: Task<Void, Never>?
    
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
    /// Throttled to avoid redundant network calls within 5 seconds.
    func refreshAll(force: Bool = false) async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        let now = Date()
        if !force, let last = lastRefreshTime, now.timeIntervalSince(last) < 5 {
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
        guard SupabaseManager.shared.isAuthenticated else { return }
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
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return }
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
    /// Preserves accumulated rank deltas so the user sees changes that happened while away.
    /// Starts a delayed clear — after 10s of continuous visibility, deltas fade out (user has "seen" them).
    func markCommunityViewVisible() {
        isCommunityViewVisible = true
        rankDeltaClearTask?.cancel()
        rankDeltaClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, isCommunityViewVisible else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                rankDeltas = [:]
            }
        }
    }
    
    /// Call when the user navigates AWAY from the community widgets.
    /// Rank deltas are preserved so they're visible when the user returns.
    func markCommunityViewHidden() {
        isCommunityViewVisible = false
        rankDeltaClearTask?.cancel()
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
            if !Task.isCancelled {
                AppLogger.error("Error fetching discoverable challenges: \(error.localizedDescription)", category: .social)
            }
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
            if !Task.isCancelled {
                AppLogger.error("Error fetching featured challenges: \(error.localizedDescription)", category: .social)
            }
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
        category: String = "fitness",
        targetCadence: ChallengeCadence = .daily
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
                let p_target_cadence: String
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
                    p_category: category,
                    p_target_cadence: targetCadence.rawValue
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
            // 2026-04-28 join-time backfill — `community_challenge_daily_progress`
            // is normally populated by the SERVER-SIDE trigger that fans out
            // from `challenge_daily_progress` (1v1) writes (`source =
            // "fanout:challenge_daily_progress"`). The trigger only fires
            // for community challenges the user is a member of AT THE TIME
            // of the 1v1 write — so a user who joins a community AFTER
            // their app has already pushed today's 1v1 progress will show
            // "—" on the leaderboard until their NEXT foreground sync
            // forces a fresh 1v1 write. Canonical incident 2026-04-28:
            // Manuel joined "10K Steps Daily" community at 03:16 UTC; his
            // app had already written 6,254 steps to `challenge_daily_progress`
            // for the 1v1 vs Joe at 02:31 UTC; fanout didn't replay → his
            // app showed in the community leaderboard with "—" today,
            // even though Joe ↔ Manuel 1v1 widget showed 6,254 steps. Fix:
            // immediately push today's HK steps directly via
            // `log_community_challenge_progress` so the row lands without
            // waiting on a 1v1 trigger. Works for users with NO 1v1
            // challenge at all (HK is the source of truth).
            await syncAllTrackingToCommunityChallenges()
            PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "community_challenge_joined")
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
            // 2026-04-28 join-time backfill — see `joinChallenge(code:slug:)` for
            // the canonical rationale. Same fanout-only-fires-for-current-members
            // gap applies to the friend-gated path; without this, leaderboard
            // shows "—" for the joiner until their next foreground 1v1 sync.
            await syncAllTrackingToCommunityChallenges()
            PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "community_challenge_friend_joined")
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
    
    /// No-op — community realtime is handled exclusively by RealtimeService.swift
    /// which subscribes to community_challenge_daily_progress and community_challenge_participants
    /// via dedicated channels. Keeping this method signature so callers don't break.
    func subscribeToRealtimeUpdates() async {
        AppLogger.debug("Community realtime handled by RealtimeService — no-op", category: .social)
    }
    
    /// No-op cleanup — the channel is managed by RealtimeService.disconnect()
    func unsubscribeFromRealtimeUpdates() async {
        AppLogger.debug("Community realtime cleanup handled by RealtimeService — no-op", category: .social)
    }
    
    // MARK: - Optimistic Local Updates
    
    /// Apply an optimistic progress update from a realtime event without waiting for server RPC.
    /// Immediately patches the local myChallenges array so the UI updates within one frame (<16ms).
    /// The next fetchMyChallenges() call reconciles with the server-authoritative data.
    func applyOptimisticProgressUpdate(challengeId: String, userId: String, progressValue: Int) {
        guard let challengeUUID = UUID(uuidString: challengeId),
              let userUUID = UUID(uuidString: userId),
              let idx = myChallenges.firstIndex(where: { $0.challengeId == challengeUUID }),
              var participants = myChallenges[idx].topParticipants else { return }
        
        guard let pIdx = participants.firstIndex(where: { $0.userId == userUUID }) else { return }
        
        participants[pIdx].todayProgress = progressValue
        
        // Re-sort by progress descending and recompute ranks
        participants.sort { $0.todayProgress > $1.todayProgress }
        for i in participants.indices {
            participants[i].rank = i + 1
        }
        
        myChallenges[idx].topParticipants = participants
        
        #if DEBUG
        AppLogger.debug("Optimistic patch: challenge \(challengeId.prefix(8)), user \(userId.prefix(8)) → \(progressValue)", category: .social)
        #endif
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
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("[COMMUNITY CHALLENGE] Skipping progress log — not authenticated", category: .auth)
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
                let isTimeout = nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCancelled)
                if isTimeout && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    AppLogger.warning("log_community_challenge_progress timeout (attempt \(attempt)/\(maxRetries)), retrying...", category: .social)
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    // Bug-intel e03ca9df / d29ff85a (2026-04-27): replace bare
                    // AppLogger.error with NetworkErrorClassifier so 40P01
                    // (deadlock_detected — server-side fix in
                    // 20260628_log_community_challenge_progress_deadlock_retry.sql
                    // adds retry but the residual case still surfaces here)
                    // and other transient classes log as .warning instead of
                    // crash-fingerprinting. QUALITY_PERFORMANCE_AGENT inv 25a.
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error logging community progress",
                        category: .social,
                        transientLevel: .warning,
                        op: "community_challenge.progress_sync",
                        endpoint: "rpc/log_community_challenge_progress"
                    )
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
        // Auto-populate `myChallenges` if empty so a cold HealthKit observer
        // wake still pushes to community challenges — otherwise the sync
        // silently no-ops while private/1v1 go through, producing cross-
        // surface leaderboard inconsistency (the 2026-04-24 Paul bug).
        if myChallenges.isEmpty {
            await fetchMyChallenges()
        }
        guard !myChallenges.isEmpty else { return }

        // Force-refresh HealthKit first so `todaySteps` / `todayActiveMinutes`
        // are fresh before we push. See `PrivateChallengeService` for full
        // rationale (2026-04-24 dawn-ghost bug). Coalescer makes repeat calls
        // free when the BG sync path already triggered a refresh.
        await HealthKitService.shared.syncAllData(force: true)

        let progress = await gatherCurrentProgress()
        
        #if DEBUG
        AppLogger.debug("Syncing tracking data to \(myChallenges.count) community challenges...", category: .social)
        #endif
        
        for (index, challenge) in myChallenges.enumerated() {
            let progressValue = resolveProgress(for: challenge, from: progress)
            
            // Recalculable set: protein/hydrate/calories recompute from today's
            // meals/logs (decreases when a meal is removed). steps/active_minutes
            // added 2026-04-24 (dawn-ghost bug, fingerprint 6be18e3a) — HealthKit
            // cumulative counters can cache yesterday's EoD across midnight;
            // without allowDecrease the server's GREATEST() pins the ghost.
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
        
        // Instantly reflect own progress locally before the server round-trip
        for i in myChallenges.indices {
            let value = resolveProgress(for: myChallenges[i], from: progress)
            if value > 0 || myChallenges[i].myTodayProgress != nil {
                myChallenges[i].myTodayProgress = max(value, 0)
            }
        }
        
        // Server fetch reconciles with authoritative data
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
        case "lift", "workout_streak", "total_volume_lifted": return 0
        case "active_minutes": return data.activeMinutes
        case "hydrate":     return data.hydrationInUnit(challenge.targetUnit)
        case "protein":     return data.protein
        case "calories":    return max(data.calories, data.mealCalories)
        case "sleep", "sleep_hours": return data.sleepMinutes
        case "cycling":
            switch challenge.targetUnit.lowercased() {
            case "minutes":  return data.cyclingMinutes
            case "km":       return Int(data.cyclingMeters / 1000)
            case "miles":    return Int(data.cyclingMeters / 1609.344)
            case "workouts": return data.cyclingSessions
            default: return 0
            }
        case "swim":
            switch challenge.targetUnit.lowercased() {
            case "workouts": return data.swimSessions
            case "minutes":  return data.swimMinutes
            case "km":       return Int(data.swimMeters / 1000)
            default: return 0
            }
        case "stairs_climbed":   return data.stairsClimbed
        case "mind_body_minutes": return data.mindBodyMinutes
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
