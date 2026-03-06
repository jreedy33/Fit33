//
//  DailyQuestViews.swift
//  Fit33
//
//  UI components for the Daily Quest system V2.
//  Each quest card shows clear action, description, difficulty, progress, and reward.
//

import SwiftUI

// MARK: - Daily Quests Widget (Dashboard)

struct DailyQuestsWidget: View {
    @ObservedObject var questService: DailyQuestService
    @ObservedObject private var adManager = AdManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private let accentGradient: [Color] = [
        Color(red: 1.0, green: 0.6, blue: 0.2),
        Color(red: 1.0, green: 0.4, blue: 0.4)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            
            if questService.isLoading && questService.quests.isEmpty {
                loadingContent
            } else if questService.quests.isEmpty {
                emptyContent
            } else {
                questsCard
            }
        }
    }
    
    // MARK: - Header
    
    private var headerRow: some View {
        HStack {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: accentGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .font(.title3)
            Text("Daily Quests")
                .font(.title3)
                .fontWeight(.bold)
            
            Spacer()
            
            // Difficulty profile badge
            if !questService.difficultyProfileLabel.isEmpty {
                Text(questService.difficultyProfileLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(difficultyProfileColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(difficultyProfileColor.opacity(0.12))
                    )
            }
            
            // Streak badge
            if questService.questStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("\(questService.questStreak)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                )
            }
        }
    }
    
    private var difficultyProfileColor: Color {
        switch questService.difficultyProfile {
        case "easy_day": return .green
        case "mixed_day": return .blue
        case "hard_day": return .red
        default: return .orange
        }
    }
    
    // MARK: - Quests Card
    
    private var questsCard: some View {
        VStack(spacing: 0) {
            // Overall progress bar
            overallProgressBar
                .padding(.bottom, 16)
            
            // Quest rows — each is a standalone mini-card
            ForEach(Array(questService.quests.enumerated()), id: \.element.id) { index, quest in
                questCard(quest: quest)
                
                if index < questService.quests.count - 1 {
                    Spacer().frame(height: 10)
                }
            }
            
            // Bonus row
            if questService.quests.count > 0 {
                Spacer().frame(height: 12)
                bonusRow
            }
        }
        .padding(16)
        .sleekCard(cornerRadius: 24, accentColor: questService.allComplete ? .green : Color(red: 1.0, green: 0.5, blue: 0.3))
    }
    
    // MARK: - Overall Progress Bar
    
    private var overallProgressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(questService.completedCount)/\(questService.totalCount) Complete")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !questService.allComplete {
                    Text(timeRemainingToday)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            questService.allComplete
                                ? LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * questService.overallProgress, height: 6)
                        .animation(.spring(response: 0.5), value: questService.overallProgress)
                }
            }
            .frame(height: 6)
        }
    }
    
    // MARK: - Quest Card (Redesigned — full info)
    
    private func questCard(quest: DailyQuest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: Icon + Title + Difficulty badge + XP reward
            HStack(spacing: 10) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(
                            quest.isCompleted
                                ? LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [quest.categoryColor.opacity(0.25), quest.categoryColor.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 36, height: 36)
                    
                    if quest.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: quest.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(quest.categoryColor)
                    }
                }
                
                // Title
                Text(quest.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(quest.isCompleted ? .secondary : .primary)
                    .strikethrough(quest.isCompleted, color: .secondary.opacity(0.5))
                    .lineLimit(1)
                
                Spacer()
                
                // Difficulty badge
                Text(quest.difficultyLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(quest.difficultyColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(quest.difficultyColor.opacity(0.12))
                    )
                
                // XP reward
                HStack(spacing: 2) {
                    Text("+\(quest.xpReward)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("XP")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(quest.isCompleted ? .green : .secondary.opacity(0.6))
            }
            
            // Description + verification badge
            if !quest.isCompleted {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    // Show verification badge for app-tracked / social quests
                    if let badge = quest.verificationBadge {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(quest.isAppTracked ? .cyan : .purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((quest.isAppTracked ? Color.cyan : Color.purple).opacity(0.1))
                            )
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 46) // align with title (36 icon + 10 spacing)
            }
            
            // Progress bar + label (not completed)
            if !quest.isCompleted {
                if quest.questKey == QuestKey.watchAds.rawValue {
                    // Special "Watch Video" button for ad quest
                    adQuestActionRow(quest: quest)
                        .padding(.top, 7)
                        .padding(.leading, 46)
                } else {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.12))
                                    .frame(height: 5)
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [quest.categoryColor, quest.categoryColor.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geo.size.width * quest.progress), height: 5)
                                    .animation(.spring(response: 0.4), value: quest.progress)
                            }
                        }
                        .frame(height: 5)
                        
                        // Progress label with units
                        Text(progressLabel(quest: quest))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(quest.categoryColor)
                            .frame(minWidth: 55, alignment: .trailing)
                    }
                    .padding(.top, 7)
                    .padding(.leading, 46)
                }
            }
            
            // Completed state — show reward earned
            if quest.isCompleted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text("Completed — \(quest.xpReward) XP earned")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green.opacity(0.8))
                }
                .padding(.top, 5)
                .padding(.leading, 46)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    quest.isCompleted
                        ? Color.green.opacity(colorScheme == .dark ? 0.06 : 0.04)
                        : Color.gray.opacity(colorScheme == .dark ? 0.08 : 0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    quest.isCompleted
                        ? Color.green.opacity(0.15)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }
    
    /// Formats progress label with smart units — always shows what you're counting
    private func progressLabel(quest: DailyQuest) -> String {
        let unit = quest.targetUnit
        switch unit {
        case "steps":
            if quest.targetValue >= 1000 {
                let currentK = Double(quest.currentValue) / 1000.0
                let targetK = Double(quest.targetValue) / 1000.0
                if quest.currentValue >= 1000 {
                    return String(format: "%.1fk / %.0fk steps", currentK, targetK)
                }
                return String(format: "%d / %.0fk steps", quest.currentValue, targetK)
            }
            return "\(quest.currentValue)/\(quest.targetValue) steps"
        case "glasses":
            return "\(quest.currentValue)/\(quest.targetValue) glasses"
        case "sets":
            return "\(quest.currentValue)/\(quest.targetValue) sets"
        case "meals", "meal":
            return "\(quest.currentValue)/\(quest.targetValue) \(quest.targetValue == 1 ? "meal" : "meals")"
        case "workouts", "workout":
            return "\(quest.currentValue)/\(quest.targetValue) \(quest.targetValue == 1 ? "workout" : "workouts")"
        case "minutes":
            return "\(quest.currentValue)/\(quest.targetValue) min"
        case "goal":
            return quest.currentValue >= quest.targetValue ? "Goal hit!" : "Not yet"
        case "day":
            return "\(quest.currentValue)/\(quest.targetValue) \(quest.targetValue == 1 ? "day" : "days")"
        case "exercise":
            return "\(quest.currentValue)/\(quest.targetValue)"
        case "actions":
            return "\(quest.currentValue)/\(quest.targetValue) done"
        case "videos":
            return "\(quest.currentValue)/\(quest.targetValue) \(quest.targetValue == 1 ? "video" : "videos")"
        default:
            return "\(quest.currentValue)/\(quest.targetValue) \(unit)"
        }
    }
    
    // MARK: - Ad Quest Action Row
    
    /// Special action row for the "Watch 2 Videos" quest — shows a tap-to-watch button
    private func adQuestActionRow(quest: DailyQuest) -> some View {
        HStack(spacing: 10) {
            Button {
                guard let vc = RootViewControllerFinder.find() else { return }
                adManager.showRewardedAd(from: vc) {
                    // Reward callback — user watched the full video
                    Task { @MainActor in
                        await DailyQuestService.shared.onAdWatched()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Watch Video \(quest.currentValue + 1)/\(quest.targetValue)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            adManager.isRewardedAdReady
                                ? LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }
            .disabled(!adManager.isRewardedAdReady)
            
            if !adManager.isRewardedAdReady {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress label
            Text("\(quest.currentValue)/\(quest.targetValue) videos")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(quest.categoryColor)
        }
    }
    
    // MARK: - Bonus Row
    
    private var bonusRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        questService.allComplete
                            ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.yellow.opacity(0.15), Color.orange.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 36, height: 36)
                
                if questService.allComplete {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "gift")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange.opacity(0.5))
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Bonus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(questService.allComplete ? .primary : .secondary)
                
                Text(questService.allComplete ? "All quests completed! 🎉" : "Complete all 3 quests to unlock")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(questService.allComplete ? .green : .secondary.opacity(0.6))
            }
            
            Spacer()
            
            HStack(spacing: 2) {
                Text("+50")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("XP")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(questService.allComplete ? .orange : .secondary.opacity(0.35))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    questService.allComplete
                        ? Color.orange.opacity(colorScheme == .dark ? 0.08 : 0.05)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    questService.allComplete
                        ? Color.orange.opacity(0.2)
                        : Color.gray.opacity(0.08),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Loading / Empty States
    
    private var loadingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading quests...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .sleekCard(cornerRadius: 24, accentColor: .orange)
    }
    
    private var emptyContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.orange.opacity(0.2), .red.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: "star.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(colors: accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 4) {
                Text("Daily Quests")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Complete 3 mini-challenges each day for bonus XP and league points!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .sleekCard(cornerRadius: 24, accentColor: .orange)
    }
    
    // MARK: - Helpers
    
    private var timeRemainingToday: String {
        let calendar = Calendar.current
        let now = Date()
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
            return ""
        }
        let remaining = endOfDay.timeIntervalSince(now)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else {
            return "\(minutes)m left"
        }
    }
}

// MARK: - Quest Completion Celebration Overlay

struct QuestCompletionCelebration: View {
    let quest: DailyQuest
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quest Complete!")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("\(quest.title) — +\(quest.xpReward) XP")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .green.opacity(0.3), radius: 20, x: 0, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isShowing)
            .onTapGesture {
                withAnimation { isShowing = false }
            }
        }
    }
}

// MARK: - Bonus Unlocked Celebration

struct QuestBonusCelebration: View {
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "gift.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🎉 Daily Bonus Unlocked!")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("+50 XP • +30 League Points")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .orange.opacity(0.4), radius: 25, x: 0, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 2
                        )
                )
            }
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isShowing)
            .onTapGesture {
                withAnimation { isShowing = false }
            }
        }
    }
}

// MARK: - Preview

#Preview("Live Quests") {
    ScrollView {
        DailyQuestsWidget(questService: DailyQuestService.shared)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Ad Quest Card") {
    let adQuest = DailyQuest(
        id: UUID(),
        questKey: "watch_ads",
        title: "Support Fit33",
        description: "Watch 2 short videos to support the app — thank you!",
        icon: "play.rectangle.fill",
        category: "reward",
        targetValue: 2,
        currentValue: 1,
        targetUnit: "videos",
        xpReward: 25,
        leaguePoints: 15,
        difficulty: "easy",
        isCompleted: false,
        completedAt: nil,
        funLabel: "📺 Quick & easy",
        verificationType: "auto"
    )
    
    let completedAdQuest = DailyQuest(
        id: UUID(),
        questKey: "watch_ads",
        title: "Support Fit33",
        description: "Watch 2 short videos to support the app — thank you!",
        icon: "play.rectangle.fill",
        category: "reward",
        targetValue: 2,
        currentValue: 2,
        targetUnit: "videos",
        xpReward: 25,
        leaguePoints: 15,
        difficulty: "easy",
        isCompleted: true,
        completedAt: "2026-03-05T12:00:00Z",
        funLabel: "📺 Quick & easy",
        verificationType: "auto"
    )
    
    let workoutQuest = DailyQuest(
        id: UUID(),
        questKey: "complete_workout",
        title: "Crush a Workout",
        description: "Complete any workout today — no excuses!",
        icon: "dumbbell.fill",
        category: "workout",
        targetValue: 1,
        currentValue: 0,
        targetUnit: "workout",
        xpReward: 30,
        leaguePoints: 20,
        difficulty: "easy",
        isCompleted: false,
        completedAt: nil,
        funLabel: "💪 Just show up",
        verificationType: "auto"
    )
    
    ScrollView {
        VStack(spacing: 20) {
            Text("Ad Quest — 1/2 watched")
                .font(.caption).foregroundColor(.secondary)
            AdQuestPreviewCard(quest: adQuest)
            
            Text("Ad Quest — Completed")
                .font(.caption).foregroundColor(.secondary)
            AdQuestPreviewCard(quest: completedAdQuest)
            
            Text("Normal Quest — for comparison")
                .font(.caption).foregroundColor(.secondary)
            AdQuestPreviewCard(quest: workoutQuest)
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

/// Standalone preview wrapper to render a single quest card
private struct AdQuestPreviewCard: View {
    let quest: DailyQuest
    @ObservedObject private var adManager = AdManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            quest.isCompleted
                                ? LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [quest.categoryColor.opacity(0.25), quest.categoryColor.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 36, height: 36)
                    
                    if quest.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: quest.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(quest.categoryColor)
                    }
                }
                
                Text(quest.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(quest.isCompleted ? .secondary : .primary)
                    .strikethrough(quest.isCompleted, color: .secondary.opacity(0.5))
                
                Spacer()
                
                Text(quest.difficulty.capitalized)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(quest.difficultyColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(quest.difficultyColor.opacity(0.12)))
                
                HStack(spacing: 2) {
                    Text("+\(quest.xpReward)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("XP")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(quest.isCompleted ? .green : .secondary.opacity(0.6))
            }
            
            // Description
            if !quest.isCompleted {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if quest.isAppTracked {
                        Text("📱 App Tracked")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.cyan.opacity(0.1)))
                    }
                }
                .padding(.top, 6).padding(.leading, 46)
            }
            
            // Action row
            if !quest.isCompleted {
                if quest.questKey == "watch_ads" {
                    // Ad quest button
                    HStack(spacing: 10) {
                        Button {} label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Watch Video \(quest.currentValue + 1)/\(quest.targetValue)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                                )
                            )
                        }
                        Spacer()
                        Text("\(quest.currentValue)/\(quest.targetValue) videos")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(quest.categoryColor)
                    }
                    .padding(.top, 7).padding(.leading, 46)
                } else {
                    // Normal progress bar
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.12)).frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(LinearGradient(colors: [quest.categoryColor, quest.categoryColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(0, geo.size.width * quest.progress), height: 5)
                            }
                        }.frame(height: 5)
                        Text("\(quest.currentValue)/\(quest.targetValue) \(quest.targetUnit)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(quest.categoryColor)
                            .frame(minWidth: 55, alignment: .trailing)
                    }
                    .padding(.top, 7).padding(.leading, 46)
                }
            }
            
            // Completed
            if quest.isCompleted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(.green)
                    Text("Completed — \(quest.xpReward) XP earned")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.green.opacity(0.8))
                }
                .padding(.top, 5).padding(.leading, 46)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(quest.isCompleted ? Color.green.opacity(colorScheme == .dark ? 0.06 : 0.04) : Color.gray.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(quest.isCompleted ? Color.green.opacity(0.15) : Color.clear, lineWidth: 1)
        )
    }
}
