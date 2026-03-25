//
//  WeeklyLeagueService.swift
//  Fit33
//
//  Weekly League System — Duolingo-style competitive leagues
//  Users are grouped into pools of ~30 and compete weekly for points.
//  Top performers get promoted; bottom performers get relegated.
//  Resets every Monday morning.
//

import Foundation
import SwiftUI

// MARK: - League Models

struct LeagueStanding: Codable {
    let groupId: UUID
    let tierRank: Int
    let tierName: String
    let tierEmoji: String
    let tierColor: String
    let promotionCount: Int
    let relegationCount: Int
    let weekStart: String
    let daysRemaining: Int
    let myPoints: Int
    let myRank: Int
    let groupSize: Int
    let leaderboard: [LeagueEntry]
    
    var friendsInLeague: Int {
        leaderboard.filter { $0.isFriend == true && !$0.isCurrentUser }.count
    }
    
    var connectionsInLeague: Int {
        leaderboard.filter {
            !$0.isCurrentUser && ($0.isFriend == true || ($0.mutualFriendCount ?? 0) > 0)
        }.count
    }
    
    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case tierRank = "tier_rank"
        case tierName = "tier_name"
        case tierEmoji = "tier_emoji"
        case tierColor = "tier_color"
        case promotionCount = "promotion_count"
        case relegationCount = "relegation_count"
        case weekStart = "week_start"
        case daysRemaining = "days_remaining"
        case myPoints = "my_points"
        case myRank = "my_rank"
        case groupSize = "group_size"
        case leaderboard
    }
    
    /// SwiftUI color for the current tier
    var tierSwiftUIColor: Color {
        switch tierRank {
        case 1: return .orange           // Bronze
        case 2: return .gray             // Silver
        case 3: return .yellow           // Gold
        case 4: return Color(red: 0.66, green: 0.66, blue: 0.78) // Platinum
        case 5: return .cyan             // Diamond
        case 6: return Color(red: 1.0, green: 0.42, blue: 0.21)  // Elite
        default: return .blue
        }
    }
    
    /// Gradient colors for the current tier
    var tierGradient: [Color] {
        switch tierRank {
        case 1: return [.orange, Color(red: 0.8, green: 0.5, blue: 0.2)]     // Bronze
        case 2: return [.gray, Color(white: 0.85)]                             // Silver
        case 3: return [.yellow, .orange]                                       // Gold
        case 4: return [Color(red: 0.66, green: 0.66, blue: 0.78), .purple]   // Platinum
        case 5: return [.cyan, .blue]                                           // Diamond
        case 6: return [Color(red: 1.0, green: 0.42, blue: 0.21), .red]       // Elite
        default: return [.blue, .cyan]
        }
    }
    
    /// Whether the user is in the promotion zone
    var isInPromotionZone: Bool {
        promotionCount > 0 && myRank <= promotionCount
    }
    
    /// Whether the user is in the relegation zone
    var isInRelegationZone: Bool {
        relegationCount > 0 && myRank > (groupSize - relegationCount)
    }
    
    /// Next tier name (for promotion display)
    var nextTierName: String? {
        switch tierRank {
        case 1: return "Silver"
        case 2: return "Gold"
        case 3: return "Platinum"
        case 4: return "Diamond"
        case 5: return "Elite"
        default: return nil
        }
    }
    
    /// Previous tier name (for relegation display)
    var prevTierName: String? {
        switch tierRank {
        case 2: return "Bronze"
        case 3: return "Silver"
        case 4: return "Gold"
        case 5: return "Platinum"
        case 6: return "Diamond"
        default: return nil
        }
    }
}

struct LeagueEntry: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let points: Int
    let workoutsCompleted: Int?
    let rank: Int
    let isCurrentUser: Bool
    let isFriend: Bool?
    let mutualFriendCount: Int?
    
    var id: UUID { userId }
    
    var displayName: String {
        if let name = name, !name.isEmpty { return name }
        if let username = username, !username.isEmpty { return "@\(username)" }
        return "Athlete"
    }
    
    var firstName: String {
        displayName.components(separatedBy: " ").first ?? displayName
    }
    
    var initials: String {
        let parts = displayName.components(separatedBy: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
    
    /// Whether this person is a social connection (friend or friend-of-friend)
    var isConnection: Bool {
        isFriend == true || (mutualFriendCount ?? 0) > 0
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case username
        case profilePhotoUrl = "profile_photo_url"
        case points
        case workoutsCompleted = "workouts_completed"
        case rank
        case isCurrentUser = "is_current_user"
        case isFriend = "is_friend"
        case mutualFriendCount = "mutual_friend_count"
    }
}

struct LeagueHistoryEntry: Codable, Identifiable {
    let weekStart: String
    let tierName: String
    let tierRank: Int
    let finalRank: Int
    let finalPoints: Int
    let groupSize: Int
    let wasPromoted: Bool
    let wasRelegated: Bool
    
    var id: String { weekStart }
    
    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case tierName = "tier_name"
        case tierRank = "tier_rank"
        case finalRank = "final_rank"
        case finalPoints = "final_points"
        case groupSize = "group_size"
        case wasPromoted = "was_promoted"
        case wasRelegated = "was_relegated"
    }
}

// MARK: - League Points Configuration

enum LeaguePointSource: String {
    case workout = "workout"
    case challengeTarget = "challenge_target"
    case personalRecord = "personal_record"
    case mealLogged = "meal_logged"
    case dailyLogin = "daily_login"
    
    var points: Int {
        switch self {
        case .workout: return 50
        case .challengeTarget: return 25
        case .personalRecord: return 30
        case .mealLogged: return 10
        case .dailyLogin: return 5
        }
    }
    
    var displayName: String {
        switch self {
        case .workout: return "Workout"
        case .challengeTarget: return "Challenge"
        case .personalRecord: return "PR"
        case .mealLogged: return "Meal"
        case .dailyLogin: return "Login"
        }
    }
}

// MARK: - Weekly League Service

@MainActor
class WeeklyLeagueService: ObservableObject {
    static let shared = WeeklyLeagueService()
    
    // MARK: - Published State
    @Published var standing: LeagueStanding?
    @Published var history: [LeagueHistoryEntry] = []
    @Published var isLoading = false
    @Published var hasJoined = false
    @Published var error: String?
    
    // MARK: - Cache
    private let standingCacheKey = "fit33_league_standing"
    private let standingCacheDateKey = "fit33_league_cache_date"
    private let dailyLoginKey = "fit33_league_daily_login"
    private let cacheDuration: TimeInterval = 120 // 2 minutes
    
    private init() {
        loadCachedStanding()
    }
    
    // MARK: - Fetch / Join League
    
    /// Main entry point: get or create the user's league membership for this week.
    /// Lazily processes past weeks (promotions/relegations) on the server.
    func fetchOrJoinLeague(force: Bool = false) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Throttle: skip if we fetched recently (unless forced)
        if !force, let cacheDate = UserDefaults.standard.object(forKey: standingCacheDateKey) as? Date,
           Date().timeIntervalSince(cacheDate) < cacheDuration,
           standing != nil {
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let result: LeagueStanding = try await SupabaseManager.shared.supabaseClient
                .rpc("get_or_join_weekly_league", params: ["p_user_id": userId.uuidString])
                .execute()
                .value
            
            self.standing = result
            self.hasJoined = true
            cacheStanding(result)
            
            #if DEBUG
            AppLogger.debug("🏆 [LEAGUE] Joined/fetched league: \(result.tierName) league, rank #\(result.myRank)/\(result.groupSize), \(result.myPoints) pts", category: .social)
            #endif
            
            // Award daily login points (once per day)
            await awardDailyLoginPoints()
            
        } catch is CancellationError {
            AppLogger.debug("🔕 [LEAGUE] League fetch cancelled (tab switch)", category: .social)
        } catch let urlError as URLError where urlError.code == .cancelled {
            AppLogger.debug("🔕 [LEAGUE] League fetch cancelled (tab switch)", category: .social)
        } catch {
            self.error = error.localizedDescription
            #if DEBUG
            AppLogger.error("❌ [LEAGUE] Failed to fetch league: \(error)", category: .social)
            #endif
        }
        
        isLoading = false
    }
    
    // MARK: - Add Points
    
    /// Add points for a specific activity. Call from workout completion, PR detection, etc.
    func addPoints(source: LeaguePointSource) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        guard hasJoined else { return } // Don't add points if user hasn't joined league yet
        
        do {
            struct PointsResult: Decodable {
                let success: Bool
                let new_points: Int?
                let points_added: Int?
            }
            
            let result: PointsResult = try await SupabaseManager.shared.supabaseClient
                .rpc("add_league_points", params: [
                    "p_user_id": userId.uuidString,
                    "p_points": "\(source.points)",
                    "p_source": source.rawValue
                ])
                .execute()
                .value
            
            if result.success, let newPoints = result.new_points {
                // Update local state immediately
                if var current = standing {
                    // Re-sort leaderboard with new points
                    var updatedLeaderboard = current.leaderboard
                    if let idx = updatedLeaderboard.firstIndex(where: { $0.isCurrentUser }) {
                        let old = updatedLeaderboard[idx]
                        updatedLeaderboard[idx] = LeagueEntry(
                            userId: old.userId,
                            name: old.name,
                            username: old.username,
                            profilePhotoUrl: old.profilePhotoUrl,
                            points: newPoints,
                            workoutsCompleted: (old.workoutsCompleted ?? 0) + (source == .workout ? 1 : 0),
                            rank: old.rank,
                            isCurrentUser: true,
                            isFriend: old.isFriend,
                            mutualFriendCount: old.mutualFriendCount
                        )
                    }
                    // Note: rank may change — do a full refresh next time
                    self.standing = LeagueStanding(
                        groupId: current.groupId,
                        tierRank: current.tierRank,
                        tierName: current.tierName,
                        tierEmoji: current.tierEmoji,
                        tierColor: current.tierColor,
                        promotionCount: current.promotionCount,
                        relegationCount: current.relegationCount,
                        weekStart: current.weekStart,
                        daysRemaining: current.daysRemaining,
                        myPoints: newPoints,
                        myRank: current.myRank,
                        groupSize: current.groupSize,
                        leaderboard: updatedLeaderboard
                    )
                }
                
                #if DEBUG
                AppLogger.debug("🏆 [LEAGUE] +\(source.points) pts (\(source.displayName)) → \(newPoints) total", category: .social)
                #endif
            }
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [LEAGUE] Failed to add points: \(error)", category: .social)
            #endif
        }
    }
    
    // MARK: - Fetch Full Leaderboard
    
    /// Get the full leaderboard for the current group (used in detail view)
    func fetchFullLeaderboard() async {
        guard let userId = SupabaseManager.shared.currentUser?.id,
              let groupId = standing?.groupId else { return }
        
        isLoading = true
        
        do {
            let result: LeagueStanding = try await SupabaseManager.shared.supabaseClient
                .rpc("get_league_leaderboard", params: [
                    "p_user_id": userId.uuidString,
                    "p_group_id": groupId.uuidString
                ])
                .execute()
                .value
            
            self.standing = result
            cacheStanding(result)
            
        } catch is CancellationError {
            AppLogger.debug("🔕 [LEAGUE] Leaderboard fetch cancelled (tab switch)", category: .social)
        } catch let urlError as URLError where urlError.code == .cancelled {
            AppLogger.debug("🔕 [LEAGUE] Leaderboard fetch cancelled (tab switch)", category: .social)
        } catch {
            #if DEBUG
            AppLogger.error("❌ [LEAGUE] Failed to fetch leaderboard: \(error)", category: .social)
            #endif
        }
        
        isLoading = false
    }
    
    // MARK: - Fetch History
    
    func fetchHistory() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            let result: [LeagueHistoryEntry] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_league_history", params: ["p_user_id": userId.uuidString])
                .execute()
                .value
            
            self.history = result
            
        } catch {
            #if DEBUG
            AppLogger.error("❌ [LEAGUE] Failed to fetch history: \(error)", category: .social)
            #endif
        }
    }
    
    // MARK: - Daily Login Points
    
    private func awardDailyLoginPoints() async {
        let today = Calendar.current.startOfDay(for: Date())
        let lastLogin = UserDefaults.standard.object(forKey: dailyLoginKey) as? Date
        
        if let lastLogin = lastLogin, Calendar.current.isDate(lastLogin, inSameDayAs: today) {
            return // Already awarded today
        }
        
        // Award login points
        await addPoints(source: .dailyLogin)
        UserDefaults.standard.set(today, forKey: dailyLoginKey)
        
        #if DEBUG
        AppLogger.debug("🏆 [LEAGUE] Daily login bonus awarded (+5 pts)", category: .social)
        #endif
    }
    
    // MARK: - Hide / Unhide League Users
    
    @Published var hiddenUserIds: Set<UUID> = []
    
    func hideUser(_ userId: UUID) async {
        hiddenUserIds.insert(userId)
        
        if let current = standing {
            let filtered = current.leaderboard.filter { $0.userId != userId }
            self.standing = LeagueStanding(
                groupId: current.groupId,
                tierRank: current.tierRank,
                tierName: current.tierName,
                tierEmoji: current.tierEmoji,
                tierColor: current.tierColor,
                promotionCount: current.promotionCount,
                relegationCount: current.relegationCount,
                weekStart: current.weekStart,
                daysRemaining: current.daysRemaining,
                myPoints: current.myPoints,
                myRank: current.myRank,
                groupSize: current.groupSize,
                leaderboard: filtered
            )
        }
        
        do {
            struct HideResult: Decodable { let success: Bool }
            let _: HideResult = try await SupabaseManager.shared.supabaseClient
                .rpc("hide_league_user", params: ["p_hidden_user_id": userId.uuidString])
                .execute()
                .value
        } catch {
            AppLogger.warning("Failed to hide league user: \(error)", category: .social)
        }
    }
    
    func unhideUser(_ userId: UUID) async {
        hiddenUserIds.remove(userId)
        
        do {
            struct UnhideResult: Decodable { let success: Bool }
            let _: UnhideResult = try await SupabaseManager.shared.supabaseClient
                .rpc("unhide_league_user", params: ["p_hidden_user_id": userId.uuidString])
                .execute()
                .value
            
            await fetchFullLeaderboard()
        } catch {
            AppLogger.warning("Failed to unhide league user: \(error)", category: .social)
        }
    }
    
    // MARK: - Cache
    
    private func cacheStanding(_ standing: LeagueStanding) {
        if let data = try? JSONEncoder().encode(standing) {
            UserDefaults.standard.set(data, forKey: standingCacheKey)
            UserDefaults.standard.set(Date(), forKey: standingCacheDateKey)
        }
    }
    
    private func loadCachedStanding() {
        guard let data = UserDefaults.standard.data(forKey: standingCacheKey),
              let cached = try? JSONDecoder().decode(LeagueStanding.self, from: data) else {
            return
        }
        self.standing = cached
        self.hasJoined = true
    }
}
