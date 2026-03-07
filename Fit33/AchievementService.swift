import SwiftUI
import Combine

// MARK: - Achievement Model

struct AchievementItem: Codable, Identifiable {
    let achievementKey: String
    let title: String
    let description: String
    let icon: String
    let category: String
    let threshold: Int
    let xpReward: Int
    let rarity: String
    let progress: Int
    let unlockedAt: String?
    let sortOrder: Int
    
    var id: String { achievementKey }
    var isUnlocked: Bool { unlockedAt != nil }
    var progressPercent: Double {
        guard threshold > 0 else { return 0 }
        return min(1.0, Double(progress) / Double(threshold))
    }
    
    var rarityColor: Color {
        switch rarity {
        case "common": return .gray
        case "uncommon": return .green
        case "rare": return .blue
        case "epic": return .purple
        case "legendary": return .orange
        default: return .gray
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case achievementKey = "achievement_key"
        case title, description, icon, category, threshold
        case xpReward = "xp_reward"
        case rarity, progress
        case unlockedAt = "unlocked_at"
        case sortOrder = "sort_order"
    }
}

struct UnlockResult: Codable {
    let unlocked: Bool
    let achievementTitle: String?
    let achievementIcon: String?
    let achievementRarity: String?
    let xpReward: Int?
    
    enum CodingKeys: String, CodingKey {
        case unlocked
        case achievementTitle = "achievement_title"
        case achievementIcon = "achievement_icon"
        case achievementRarity = "achievement_rarity"
        case xpReward = "xp_reward"
    }
}

// MARK: - Badge Service (Supabase-backed achievements)

class BadgeService: ObservableObject {
    static let shared = BadgeService()
    
    @Published var achievements: [AchievementItem] = []
    @Published var showUnlockToast = false
    @Published var lastUnlockedAchievement: AchievementItem?
    
    var unlockedCount: Int { achievements.filter(\.isUnlocked).count }
    var totalCount: Int { achievements.count }
    
    private init() {}
    
    // MARK: - Fetch
    
    func fetchAchievements(forUserId userId: UUID? = nil) async {
        do {
            var params: [String: String] = [:]
            if let userId = userId {
                params["p_user_id"] = userId.uuidString
            }
            
            let result: [AchievementItem] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_user_achievements", params: params)
                .execute()
                .value
            
            await MainActor.run {
                self.achievements = result
            }
        } catch {
            print("❌ Failed to fetch achievements: \(error)")
        }
    }
    
    // MARK: - Unlock Check
    
    @discardableResult
    func checkAndUnlock(key: String, progress: Int = 1) async -> Bool {
        do {
            struct UnlockParams: Encodable {
                let p_achievement_key: String
                let p_progress: Int
            }
            
            let results: [UnlockResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("unlock_achievement", params: UnlockParams(
                    p_achievement_key: key,
                    p_progress: progress
                ))
                .execute()
                .value
            
            guard let result = results.first, result.unlocked else { return false }
            
            // Award XP locally
            if let xp = result.xpReward, xp > 0 {
                await MainActor.run {
                    UserManager.shared.addXP(Int32(xp))
                }
            }
            
            // Show toast
            await MainActor.run {
                if let match = self.achievements.first(where: { $0.achievementKey == key }) {
                    self.lastUnlockedAchievement = match
                } else if let title = result.achievementTitle {
                    self.lastUnlockedAchievement = AchievementItem(
                        achievementKey: key,
                        title: title,
                        description: "",
                        icon: result.achievementIcon ?? "star.fill",
                        category: "special",
                        threshold: 1,
                        xpReward: result.xpReward ?? 0,
                        rarity: result.achievementRarity ?? "common",
                        progress: 1,
                        unlockedAt: ISO8601DateFormatter().string(from: Date()),
                        sortOrder: 0
                    )
                }
                self.showUnlockToast = true
            }
            
            // Refresh achievements list
            await fetchAchievements()
            
            // Auto-hide toast
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                self.showUnlockToast = false
            }
            
            return true
        } catch {
            print("❌ Failed to check achievement \(key): \(error)")
            return false
        }
    }
    
    // MARK: - Convenience Checkers
    
    func onWorkoutCompleted(totalWorkouts: Int) async {
        await checkAndUnlock(key: "first_workout", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_10", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_50", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_100", progress: totalWorkouts)
        await checkAndUnlock(key: "workouts_500", progress: totalWorkouts)
        
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 {
            await checkAndUnlock(key: "early_bird")
        }
        if hour >= 22 {
            await checkAndUnlock(key: "night_owl")
        }
    }
    
    func onStreakUpdated(streak: Int) async {
        await checkAndUnlock(key: "streak_7", progress: streak)
        await checkAndUnlock(key: "streak_14", progress: streak)
        await checkAndUnlock(key: "streak_30", progress: streak)
        await checkAndUnlock(key: "streak_60", progress: streak)
        await checkAndUnlock(key: "streak_100", progress: streak)
    }
    
    func onFriendAdded(totalFriends: Int) async {
        await checkAndUnlock(key: "first_friend", progress: totalFriends)
        await checkAndUnlock(key: "friends_10", progress: totalFriends)
    }
    
    func onChallengeWon(totalWins: Int) async {
        await checkAndUnlock(key: "first_challenge_won", progress: totalWins)
        await checkAndUnlock(key: "challenges_won_10", progress: totalWins)
    }
    
    func onMealLogged(totalMeals: Int) async {
        await checkAndUnlock(key: "first_meal_logged", progress: totalMeals)
        await checkAndUnlock(key: "meals_logged_100", progress: totalMeals)
    }
    
    func onWorkoutShared() async {
        await checkAndUnlock(key: "first_workout_shared")
    }
    
    func onReactionSent(totalReactions: Int) async {
        await checkAndUnlock(key: "reactions_sent_50", progress: totalReactions)
    }
    
    func onPersonalRecord() async {
        await checkAndUnlock(key: "first_pr")
    }
}
