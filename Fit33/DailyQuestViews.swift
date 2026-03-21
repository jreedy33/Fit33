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
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .font(.title3)
            Text("Daily Goals")
                .font(.title3)
                .fontWeight(.bold)
            
            Spacer()
            
            // Bonus progress dots
            bonusIndicator
            
            // Streak badge
            if questService.questStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.ds_bodySmall)
                        .foregroundColor(.orange)
                    Text("\(questService.questStreak)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                )
            }
        }
    }
    
    // MARK: - Bonus Indicator (3 dots in header)
    
    private var bonusIndicator: some View {
        let quests = questService.quests
        let allDone = questService.allComplete
        
        return HStack(spacing: 5) {
            if allDone {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.ds_caption)
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                        )
                    Text("+50 XP")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                        )
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule()
                        .fill(Color.yellow.opacity(0.15))
                )
            } else {
                ForEach(0..<3, id: \.self) { index in
                    let isComplete = index < quests.count && quests[index].isCompleted
                    let questColor = index < quests.count ? quests[index].categoryColor : Color.gray
                    
                    Circle()
                        .fill(isComplete ? questColor : Color.clear)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(
                                    isComplete ? questColor : Color.gray.opacity(0.3),
                                    lineWidth: 1.5
                                )
                        )
                        .animation(.spring(response: 0.4), value: isComplete)
                }
                
                if questService.completedCount > 0 {
                    Text("\(questService.completedCount)/3")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
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
        VStack(spacing: 8) {
            ForEach(Array(questService.quests.enumerated()), id: \.element.id) { _, quest in
                compactQuestRow(quest: quest)
            }
        }
    }
    
    // Overall progress is now shown via individual quest rings + bonus row
    
    // MARK: - Compact Quest Row (exercise-library-card style with emoji progress ring)
    
    private func compactQuestRow(quest: DailyQuest) -> some View {
        Button {
            if !quest.isCompleted {
                navigateToQuest(quest)
            }
        } label: {
        HStack(spacing: 12) {
            ZStack {
                if quest.isCompleted {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "checkmark")
                        .font(.ds_bodyMedium)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                        .frame(width: 40, height: 40)
                    
                    Circle()
                        .trim(from: 0, to: quest.progress)
                        .stroke(
                            quest.categoryColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5), value: quest.progress)
                    
                    Text(quest.categoryEmoji)
                        .font(.ds_heading3)
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(quest.title)
                        .font(.ds_labelMedium)
                        .foregroundColor(quest.isCompleted ? .secondary : .primary)
                        .strikethrough(quest.isCompleted, color: .secondary.opacity(0.5))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 2) {
                        Text("+\(quest.xpReward)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text("XP")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(quest.isCompleted ? .green : .secondary.opacity(0.5))
                }
                
                if quest.isCompleted {
                    Text(completionSummary(for: quest))
                        .font(.ds_caption)
                        .foregroundColor(.green.opacity(0.8))
                        .lineLimit(1)
                } else if quest.questKey == QuestKey.watchAds.rawValue {
                    compactAdRow(quest: quest)
                } else {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(Color.gray.opacity(0.12))
                                    .frame(height: 4)
                                
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(quest.categoryColor)
                                    .frame(width: max(0, geo.size.width * quest.progress), height: 4)
                                    .animation(.spring(response: 0.4), value: quest.progress)
                            }
                        }
                        .frame(height: 4)
                        
                        Text(progressLabel(quest: quest))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .sleekCardSubtle(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    quest.isCompleted
                        ? LinearGradient(colors: [.green.opacity(0.35), .mint.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [quest.categoryColor.opacity(0.35), quest.categoryColor.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Quest Deep Link Navigation
    
    private func navigateToQuest(_ quest: DailyQuest) {
        guard let key = QuestKey(rawValue: quest.questKey) else { return }
        let dl = DeepLinkManager.shared
        
        switch key {
        // Workout quests → auto-gen workout flow
        case .completeWorkout, .completeProgramDay, .complete2Workouts,
             .workout30Min, .exerciseSets15, .exerciseSets25,
             .upperBodyWorkout, .lowerBodyWorkout, .earlyBirdWorkout:
            dl.pendingDestination = .workout
            
        // Nutrition quests → meals tab
        case .logBreakfast, .logLunch, .logDinner, .log3Meals,
             .logSnack, .hitProteinGoal, .logHighProteinMeal:
            dl.pendingDestination = .mealsTab
            
        // Water quests → hydration widget
        case .logWater3, .logWater8:
            dl.pendingDestination = .hydration
            
        // Steps quests → step tracker
        case .walk3kSteps, .walk5kSteps, .walk7500Steps,
             .hitStepGoal, .walk10kSteps:
            dl.pendingDestination = .stepTracker
            
        // Social / challenge quests
        case .sendChallenge, .start1v1Challenge, .startFirstChallenge:
            dl.pendingDestination = .challengeCreation
            
        case .reactToWorkout, .addFriend, .inviteFriend:
            dl.pendingDestination = .friends
            
        // Tracking quests → weight / stats
        case .logWeight:
            dl.pendingDestination = .weightTracker
            
        case .checkProgress, .beatPersonalRecord:
            dl.pendingDestination = .personalRecord
            
        case .logCardio:
            dl.pendingDestination = .workout
            
        // Exercise discovery → exercises tab
        case .tryNewExercise:
            dl.pendingDestination = .dashboard
            
        // Wildcard
        case .shareWorkout, .favoriteAWorkout:
            dl.pendingDestination = .workoutHistory
            
        case .perfectDay:
            break
            
        // Ad quest handled by its own button
        case .watchAds:
            break
            
        // Legacy keys
        case .logMeal:
            dl.pendingDestination = .mealsTab
        case .logWater:
            dl.pendingDestination = .hydration
        case .exerciseSets10, .exerciseSets20:
            dl.pendingDestination = .workout
        }
    }
    
    // MARK: - Completion Summary (contextual detail for completed quests)
    
    private func completionSummary(for quest: DailyQuest) -> String {
        guard let key = QuestKey(rawValue: quest.questKey) else {
            return "Done ✓"
        }
        
        switch key {
        case .completeWorkout, .completeProgramDay, .complete2Workouts,
             .workout30Min, .exerciseSets15, .exerciseSets25,
             .exerciseSets10, .exerciseSets20,
             .upperBodyWorkout, .lowerBodyWorkout, .earlyBirdWorkout:
            return "Workout completed ✓"
            
        case .logBreakfast:
            return mealSummary(for: .breakfast)
        case .logLunch:
            return mealSummary(for: .lunch)
        case .logDinner:
            return mealSummary(for: .dinner)
        case .logSnack:
            return mealSummary(for: .snacks)
        case .log3Meals, .logMeal:
            let count = MealService.shared.todaysMeals.count
            return "\(count) meals logged ✓"
        case .hitProteinGoal, .logHighProteinMeal:
            return "Protein goal hit ✓"
            
        case .logWater3:
            return "3+ glasses logged 💧"
        case .logWater8, .logWater:
            return "8 glasses logged 💧"
            
        case .walk3kSteps, .walk5kSteps, .walk7500Steps:
            return "\(formattedSteps) steps walked"
        case .walk10kSteps, .hitStepGoal:
            return "\(formattedSteps) steps — goal hit!"
            
        case .sendChallenge, .start1v1Challenge, .startFirstChallenge:
            if let recent = ChallengeService.shared.activeChallenges.last {
                let opponent = recent.opponentName ?? "a friend"
                return "\(recent.title ?? "Challenge") with \(opponent)"
            }
            return "Challenge started ✓"
            
        case .reactToWorkout:
            return "Reacted to a friend's workout ✓"
        case .addFriend, .inviteFriend:
            return "Friend added ✓"
            
        case .logWeight:
            return "Weight logged ✓"
        case .logCardio:
            return "Cardio session logged ✓"
        case .checkProgress:
            return "Progress checked ✓"
        case .beatPersonalRecord:
            return "New personal record! 🏆"
            
        case .tryNewExercise:
            return "New exercise tried ✓"
        case .shareWorkout:
            return "Workout shared ✓"
        case .favoriteAWorkout:
            return "Workout favorited ⭐"
        case .perfectDay:
            return "Perfect day achieved 🌟"
            
        case .watchAds:
            return "Videos watched — thank you!"
        }
    }
    
    private func mealSummary(for mealType: MealType) -> String {
        let meals = MealService.shared.todaysMeals.filter { $0.mealType == mealType }
        if !meals.isEmpty {
            let names = meals.prefix(3).map { $0.foodName }
            return "Logged — \(names.joined(separator: ", "))"
        }
        return "\(mealType.displayName) logged ✓"
    }
    
    private var formattedSteps: String {
        let steps = HealthKitService.shared.todaySteps
        if steps >= 1000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        return "\(steps)"
    }
    
    private func compactAdRow(quest: DailyQuest) -> some View {
        HStack(spacing: 8) {
            Button {
                guard let vc = RootViewControllerFinder.find() else { return }
                adManager.showRewardedAd(from: vc) {
                    Task { @MainActor in
                        await DailyQuestService.shared.onAdWatched()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Watch \(quest.currentValue + 1)/\(quest.targetValue)")
                        .font(.ds_caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule().fill(
                        adManager.isRewardedAdReady
                            ? LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                    )
                )
            }
            .disabled(!adManager.isRewardedAdReady)
            
            Spacer()
            
            Text("\(quest.currentValue)/\(quest.targetValue) videos")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
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
                        .font(.ds_caption)
                    Text("Watch Video \(quest.currentValue + 1)/\(quest.targetValue)")
                        .font(.ds_bodySmall).fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.xs)
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
                        .font(.ds_caption)
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
    
    // MARK: - Compact Bonus Row
    
    private var compactBonusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                    .frame(width: 40, height: 40)
                
                Circle()
                    .trim(from: 0, to: questService.overallProgress)
                    .stroke(
                        questService.allComplete ? Color.orange : Color.orange.opacity(0.4),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5), value: questService.overallProgress)
                
                Text(questService.allComplete ? "🎁" : "🎯")
                    .font(.ds_heading3)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Daily Bonus")
                        .font(.ds_labelMedium)
                        .foregroundColor(questService.allComplete ? .primary : .secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 2) {
                        Text("+50")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text("XP")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(questService.allComplete ? .orange : .secondary.opacity(0.35))
                }
                
                Text(questService.allComplete
                    ? "All quests done! 🎉"
                    : "\(questService.completedCount)/\(questService.totalCount) complete")
                    .font(.ds_caption)
                    .foregroundColor(questService.allComplete ? .green.opacity(0.8) : .secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .sleekCardSubtle(cornerRadius: 16)
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
        .padding(Spacing.lg)
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
                    .font(.ds_heading2)
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
                            .font(.ds_bodySmall).fontWeight(.bold)
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
                            .font(.ds_heading3)
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
                .padding(Spacing.md)
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
                            .font(.ds_bodySmall)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: quest.icon)
                            .font(.ds_labelMedium)
                            .foregroundColor(quest.categoryColor)
                    }
                }
                
                Text(quest.title)
                    .font(.ds_labelMedium)
                    .foregroundColor(quest.isCompleted ? .secondary : .primary)
                    .strikethrough(quest.isCompleted, color: .secondary.opacity(0.5))
                
                Spacer()
                
                Text(quest.difficulty.capitalized)
                    .font(.ds_caption)
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
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    
                    if quest.isAppTracked {
                        Text("📱 App Tracked")
                            .font(.ds_caption).fontWeight(.semibold)
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
                                    .font(.ds_caption)
                                Text("Watch Video \(quest.currentValue + 1)/\(quest.targetValue)")
                                    .font(.ds_bodySmall).fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, Spacing.xs)
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
                    Image(systemName: "checkmark.circle.fill").font(.ds_labelSmall).foregroundColor(.green)
                    Text("Completed — \(quest.xpReward) XP earned")
                        .font(.ds_labelSmall).foregroundColor(.green.opacity(0.8))
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
