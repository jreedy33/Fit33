//
//  FriendRankingService.swift
//  Fit33
//
//  Smart Friend Ranking System
//  Tracks and scores friend relationships based on interactions
//  for better challenge/sharing recommendations
//
//  Created by Fit33 Team - 2026-02-03
//

import Foundation
import SwiftUI

// MARK: - Friend Ranking Service

/// Manages friend relationship scores and rankings for smart recommendations
@MainActor
class FriendRankingService: ObservableObject {
    static let shared = FriendRankingService()
    
    // MARK: - Published Properties
    
    @Published var rankedFriends: [RankedFriend] = []
    @Published var topFriends: [RankedFriend] = []
    @Published var friendsFromContacts: [ContactFriend] = []
    @Published var isLoading = false
    @Published var lastRefreshed: Date?
    
    // Cache duration (refresh every 5 minutes)
    private let cacheDuration: TimeInterval = 300
    
    // MARK: - Cache Keys
    private let rankedFriendsCacheKey = "fit33_cached_ranked_friends"
    
    private init() {
        // Load cached ranked friends immediately for instant Friends tab display
        loadCachedRankedFriends()
    }
    
    // MARK: - Local Caching (instant display on cold start)
    
    private func cacheRankedFriends() {
        guard !rankedFriends.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(rankedFriends)
            UserDefaults.standard.set(data, forKey: rankedFriendsCacheKey)
            AppLogger.debug("💾 [RANKING] Cached \(rankedFriends.count) ranked friends", category: .social)
        } catch {
            AppLogger.warning("⚠️ [RANKING] Failed to cache: \(error)", category: .social)
        }
    }
    
    private func loadCachedRankedFriends() {
        guard let data = UserDefaults.standard.data(forKey: rankedFriendsCacheKey) else { return }
        do {
            let cached = try JSONDecoder().decode([RankedFriend].self, from: data)
            if !cached.isEmpty {
                rankedFriends = cached
                AppLogger.debug("⚡️ [RANKING] Loaded \(cached.count) cached ranked friends (instant)", category: .social)
            }
        } catch {
            AppLogger.warning("⚠️ [RANKING] Failed to load cache: \(error)", category: .social)
            UserDefaults.standard.removeObject(forKey: rankedFriendsCacheKey)
        }
    }
    
    // MARK: - Fetch Ranked Friends
    
    /// Fetches all friends sorted by relationship strength
    func fetchRankedFriends(forceRefresh: Bool = false) async {
        // Use cache if fresh
        if !forceRefresh,
           let lastRefresh = lastRefreshed,
           Date().timeIntervalSince(lastRefresh) < cacheDuration,
           !rankedFriends.isEmpty {
            return
        }
        
        isLoading = true
        
        do {
            let result: [RankedFriend] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_ranked_friends")
                .execute()
                .value
            
            rankedFriends = result
            lastRefreshed = Date()
            cacheRankedFriends() // Persist for instant display on next launch
            AppLogger.info("✅ [RANKING] Fetched \(result.count) ranked friends", category: .social)
            
            // Log top 3 for debugging
            for (index, friend) in result.prefix(3).enumerated() {
                AppLogger.debug("   #\(index + 1): \(friend.friendName ?? friend.friendUsername ?? "Unknown") - Score: \(friend.relationshipScore)", category: .social)
            }
        } catch {
            AppLogger.error("❌ [RANKING] Error fetching ranked friends: \(error)", category: .social)
        }
        
        isLoading = false
    }
    
    // MARK: - Fetch Top Friends (Quick)
    
    /// Fetches just the top N friends for quick suggestions (sharing, challenges)
    func fetchTopFriends(limit: Int = 5) async -> [RankedFriend] {
        do {
            struct TopFriendsParams: Encodable {
                let p_limit: Int
            }
            
            let result: [RankedFriend] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_top_friends", params: TopFriendsParams(p_limit: limit))
                .execute()
                .value
            
            topFriends = result
            AppLogger.info("✅ [RANKING] Fetched top \(result.count) friends", category: .social)
            return result
        } catch {
            AppLogger.error("❌ [RANKING] Error fetching top friends: \(error)", category: .social)
            return []
        }
    }
    
    // MARK: - Fetch Friends From Contacts
    
    /// Fetches friends who are also in the user's synced contacts
    func fetchFriendsFromContacts() async {
        do {
            let result: [ContactFriend] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_friends_from_contacts")
                .execute()
                .value
            
            friendsFromContacts = result
            AppLogger.info("✅ [RANKING] Fetched \(result.count) friends from contacts", category: .social)
        } catch {
            AppLogger.error("❌ [RANKING] Error fetching friends from contacts: \(error)", category: .social)
        }
    }
    
    // MARK: - Log Interaction
    
    /// Logs an interaction between the current user and a friend
    func logInteraction(
        withFriendId friendId: UUID,
        type: InteractionType,
        referenceId: UUID? = nil,
        referenceType: String? = nil
    ) async {
        do {
            struct InteractionParams: Encodable {
                let p_other_user_id: String
                let p_interaction_type: String
                let p_reference_id: String?
                let p_reference_type: String?
                let p_weight: Int
            }
            
            let _: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("log_friend_interaction", params: InteractionParams(
                    p_other_user_id: friendId.uuidString,
                    p_interaction_type: type.rawValue,
                    p_reference_id: referenceId?.uuidString,
                    p_reference_type: referenceType,
                    p_weight: type.defaultWeight
                ))
                .execute()
                .value
            
            AppLogger.info("✅ [RANKING] Logged interaction: \(type.rawValue) with friend \(friendId)", category: .social)
        } catch {
            AppLogger.warning("⚠️ [RANKING] Failed to log interaction: \(error)", category: .social)
            // Non-critical - don't throw
        }
    }
    
    // MARK: - Get Friend Score
    
    /// Gets the relationship score for a specific friend
    func getScore(forFriendId friendId: UUID) -> Double {
        if let friend = rankedFriends.first(where: { $0.friendId == friendId }) {
            return friend.relationshipScore
        }
        return 0
    }
    
    // MARK: - Get Friend Rank
    
    /// Gets the rank position of a specific friend (1 = closest friend)
    func getRank(forFriendId friendId: UUID) -> Int? {
        if let friend = rankedFriends.first(where: { $0.friendId == friendId }) {
            return friend.rank
        }
        return nil
    }
    
    // MARK: - Refresh Scores (Background)
    
    /// Refreshes the friend scores materialized view (call periodically)
    func refreshScores() async {
        do {
            try await SupabaseManager.shared.supabaseClient
                .rpc("refresh_friend_scores")
                .execute()
            
            AppLogger.info("✅ [RANKING] Refreshed friend scores", category: .social)
            
            // Re-fetch ranked friends after refresh
            await fetchRankedFriends(forceRefresh: true)
        } catch {
            AppLogger.warning("⚠️ [RANKING] Failed to refresh scores: \(error)", category: .social)
        }
    }
    
    // MARK: - Helpers
    
    /// Returns friends sorted for the share workout sheet (top friends first)
    func friendsForSharing() -> [RankedFriend] {
        return rankedFriends.isEmpty ? [] : rankedFriends
    }
    
    /// Returns friends sorted for challenge creation (top friends first)
    func friendsForChallenge() -> [RankedFriend] {
        return rankedFriends.isEmpty ? [] : rankedFriends
    }
    
    /// Check if a friend is in the user's contacts
    func isFromContacts(friendId: UUID) -> Bool {
        return friendsFromContacts.contains { $0.friendId == friendId }
    }
    
    /// Get the contact name for a friend (if they're in contacts)
    func contactName(forFriendId friendId: UUID) -> String? {
        return friendsFromContacts.first { $0.friendId == friendId }?.contactName
    }
}

// MARK: - Interaction Types

enum InteractionType: String, CaseIterable {
    case workoutShared = "workout_shared"
    case workoutCompleted = "workout_completed"
    case challengeCreated = "challenge_created"
    case challengeCompleted = "challenge_completed"
    case challengeWon = "challenge_won"
    case profileViewed = "profile_viewed"
    case workoutLiked = "workout_liked"
    
    var defaultWeight: Int {
        switch self {
        case .workoutShared: return 10
        case .workoutCompleted: return 25
        case .challengeCreated: return 20
        case .challengeCompleted: return 30
        case .challengeWon: return 15
        case .profileViewed: return 2
        case .workoutLiked: return 5
        }
    }
    
    var displayName: String {
        switch self {
        case .workoutShared: return "Workout Shared"
        case .workoutCompleted: return "Workout Completed"
        case .challengeCreated: return "Challenge Started"
        case .challengeCompleted: return "Challenge Completed"
        case .challengeWon: return "Challenge Won"
        case .profileViewed: return "Profile Viewed"
        case .workoutLiked: return "Workout Liked"
        }
    }
}

// MARK: - Ranked Friend Model

struct RankedFriend: Codable, Identifiable {
    let friendId: UUID
    let friendName: String?
    let friendUsername: String?
    let profilePhotoUrl: String?
    let fitnessGoal: String?
    let relationshipScore: Double
    let interactionCount: Int
    let workoutsShared: Int
    let workoutsCompleted: Int
    let challengesTogether: Int
    let lastInteraction: Date?
    let friendshipStarted: Date?
    let rank: Int
    
    var id: UUID { friendId }
    
    var displayName: String {
        friendName ?? friendUsername ?? "Friend"
    }
    
    var initials: String {
        guard let name = friendName ?? friendUsername, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    /// Returns a relationship tier based on score
    var relationshipTier: RelationshipTier {
        switch relationshipScore {
        case 100...: return .bestFriend
        case 50..<100: return .closeFriend
        case 20..<50: return .goodFriend
        case 1..<20: return .friend
        default: return .newFriend
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case friendName = "friend_name"
        case friendUsername = "friend_username"
        case profilePhotoUrl = "profile_photo_url"
        case fitnessGoal = "fitness_goal"
        case relationshipScore = "relationship_score"
        case interactionCount = "interaction_count"
        case workoutsShared = "workouts_shared"
        case workoutsCompleted = "workouts_completed"
        case challengesTogether = "challenges_together"
        case lastInteraction = "last_interaction"
        case friendshipStarted = "friendship_started"
        case rank
    }
}

// MARK: - Relationship Tier

enum RelationshipTier: String, CaseIterable {
    case bestFriend = "Best Friend"
    case closeFriend = "Close Friend"
    case goodFriend = "Good Friend"
    case friend = "Friend"
    case newFriend = "New Friend"
    
    var color: Color {
        switch self {
        case .bestFriend: return .orange
        case .closeFriend: return .purple
        case .goodFriend: return .blue
        case .friend: return .green
        case .newFriend: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .bestFriend: return "star.fill"
        case .closeFriend: return "heart.fill"
        case .goodFriend: return "hand.thumbsup.fill"
        case .friend: return "person.fill"
        case .newFriend: return "person.badge.plus"
        }
    }
}

// MARK: - Contact Friend Model

struct ContactFriend: Codable, Identifiable {
    let friendId: UUID
    let friendName: String?
    let friendUsername: String?
    let profilePhotoUrl: String?
    let fitnessGoal: String?
    let relationshipScore: Double
    let contactName: String?
    
    var id: UUID { friendId }
    
    var displayName: String {
        friendName ?? friendUsername ?? contactName ?? "Friend"
    }
    
    var initials: String {
        guard let name = friendName ?? friendUsername ?? contactName, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case friendName = "friend_name"
        case friendUsername = "friend_username"
        case profilePhotoUrl = "profile_photo_url"
        case fitnessGoal = "fitness_goal"
        case relationshipScore = "relationship_score"
        case contactName = "contact_name"
    }
}
