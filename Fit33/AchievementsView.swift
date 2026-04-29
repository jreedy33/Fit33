import SwiftUI

struct AchievementsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var achievementService = BadgeService.shared
    @State private var selectedCategory: String? = nil
    
    // 2026-04-29 — League Redesign Plan §B1. "level" category is gone;
    // tier-based achievements live under "tier" with a trophy icon. The
    // "level" key is preserved here ONLY for back-compat with already-saved
    // BadgeService rows (legacy `category="level"` rows still render under
    // the Tier filter). New BadgeService writes use "tier".
    private let categories = ["workout", "streak", "social", "nutrition", "tier", "special"]
    private let categoryLabels = [
        "workout": "Workout",
        "streak": "Streak",
        "social": "Social",
        "nutrition": "Nutrition",
        "tier": "Tier",
        "level": "Tier",       // legacy alias — surfaces old "level"-tagged rows under Tier
        "special": "Special"
    ]
    private let categoryIcons = [
        "workout": "dumbbell.fill",
        "streak": "flame.fill",
        "social": "person.2.fill",
        "nutrition": "fork.knife",
        "tier": "trophy.fill",
        "level": "trophy.fill", // legacy alias
        "special": "sparkles"
    ]
    
    private var filteredAchievements: [AchievementItem] {
        guard let cat = selectedCategory else { return achievementService.achievements }
        return achievementService.achievements.filter { $0.category == cat }
    }
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
            
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Summary header
                    summaryCard
                    
                    // Category filter
                    categoryFilter
                    
                    // Achievement grid
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(filteredAchievements) { achievement in
                            AchievementRow(achievement: achievement)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await achievementService.fetchAchievements()
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        HStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.xxs) {
                Text("\(achievementService.unlockedCount)")
                    .font(.ds_stat)
                    .foregroundColor(.primary)
                Text("Unlocked")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: achievementService.totalCount > 0
                        ? CGFloat(achievementService.unlockedCount) / CGFloat(achievementService.totalCount) : 0)
                    .stroke(
                        LinearGradient.ds_primaryAccent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int((Double(achievementService.unlockedCount) / max(1, Double(achievementService.totalCount))) * 100))%")
                    .font(.ds_labelMedium)
                    .foregroundColor(.primary)
            }
            
            VStack(spacing: Spacing.xxs) {
                Text("\(achievementService.totalCount)")
                    .font(.ds_stat)
                    .foregroundColor(.primary)
                Text("Total")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .purple)
    }
    
    // MARK: - Category Filter
    
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                filterChip(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                
                ForEach(categories, id: \.self) { cat in
                    filterChip(
                        label: categoryLabels[cat] ?? cat.capitalized,
                        icon: categoryIcons[cat],
                        isSelected: selectedCategory == cat
                    ) {
                        selectedCategory = cat
                    }
                }
            }
        }
    }
    
    private func filterChip(label: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                action()
            }
        }) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.ds_caption)
                }
                Text(label)
                    .font(.ds_labelMedium)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.pill)
                    .fill(isSelected
                        ? AnyShapeStyle(LinearGradient.ds_primaryAccent)
                        : AnyShapeStyle(Color.cardBackground)
                    )
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Achievement Row

struct AchievementRow: View {
    let achievement: AchievementItem
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked
                        ? achievement.rarityColor.opacity(0.2)
                        : Color.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: achievement.icon)
                    .font(.ds_heading3)
                    .foregroundColor(achievement.isUnlocked
                        ? achievement.rarityColor
                        : .gray.opacity(0.4))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.xxs) {
                    Text(achievement.title)
                        .font(.ds_heading3)
                        .foregroundColor(achievement.isUnlocked ? .primary : .secondary)
                    
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(achievement.rarityColor)
                    }
                }
                
                Text(achievement.description)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if !achievement.isUnlocked && achievement.threshold > 1 {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(achievement.rarityColor.opacity(0.6))
                                .frame(width: geo.size.width * achievement.progressPercent, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            
            Spacer()
            
            // XP reward / rarity badge
            VStack(spacing: 2) {
                if achievement.xpReward > 0 {
                    Text("+\(achievement.xpReward)")
                        .font(.ds_labelSmall)
                        .foregroundColor(.orange)
                }
                Text(achievement.rarity.capitalized)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(achievement.rarityColor)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .sleekCard(cornerRadius: CornerRadius.lg, accentColor: achievement.isUnlocked ? achievement.rarityColor : .gray)
        .opacity(achievement.isUnlocked ? 1 : 0.7)
    }
}

// MARK: - Achievement Unlock Toast

struct AchievementUnlockToast: View {
    let achievement: AchievementItem
    
    @State private var slideIn = false
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(achievement.rarityColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: achievement.icon)
                    .font(.ds_heading3)
                    .foregroundColor(achievement.rarityColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked!")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                Text(achievement.title)
                    .font(.ds_labelLarge)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            if achievement.xpReward > 0 {
                Text("+\(achievement.xpReward) XP")
                    .font(.ds_labelMedium)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(.ultraThinMaterial)
                .shadow(color: achievement.rarityColor.opacity(0.3), radius: 15, x: 0, y: 5)
        )
        .padding(.horizontal, Spacing.md)
        .offset(y: slideIn ? 0 : -100)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                slideIn = true
            }
        }
    }
}

// MARK: - Achievement Showcase (for Profile)

struct AchievementShowcase: View {
    let achievements: [AchievementItem]
    let maxDisplay: Int
    
    init(achievements: [AchievementItem], maxDisplay: Int = 6) {
        self.achievements = achievements
        self.maxDisplay = maxDisplay
    }
    
    var unlockedAchievements: [AchievementItem] {
        achievements
            .filter(\.isUnlocked)
            .sorted { ($0.rarity == "legendary" ? 0 : $0.rarity == "epic" ? 1 : $0.rarity == "rare" ? 2 : 3)
                < ($1.rarity == "legendary" ? 0 : $1.rarity == "epic" ? 1 : $1.rarity == "rare" ? 2 : 3) }
            .prefix(maxDisplay)
            .map { $0 }
    }
    
    var body: some View {
        if unlockedAchievements.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: min(unlockedAchievements.count, 3)), spacing: Spacing.xs) {
                ForEach(unlockedAchievements) { achievement in
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(achievement.rarityColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: achievement.icon)
                                .font(.ds_heading3)
                                .foregroundColor(achievement.rarityColor)
                        }
                        Text(achievement.title)
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
