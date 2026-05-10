//
//  DailyQuestViews.swift
//  Fit33
//
//  UI components for the Daily Quest system V2.
//  Each quest card shows clear action, description, difficulty, progress, and reward.
//

import SwiftUI
import CoreData

// MARK: - Daily Quests Widget (Dashboard)

/// Tracks the "← from your brief" focus glow. Phase 3 — Daily Mission
/// Unification (2026-04-27). When the user taps a brief whose CTA is
/// `.focusQuest(key)`, the router writes the quest key into
/// `DailyBriefStore.shared.pendingQuestFocus`. `DailyQuestsWidget`
/// observes that, sets `glowingQuestKey`, applies a brighter ring on
/// the matching card for ~1.2s, then clears.
private let questGlowDuration: TimeInterval = 1.2

struct DailyQuestsWidget: View {
    @ObservedObject var questService: DailyQuestService
    @ObservedObject private var adManager = AdManager.shared
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @ObservedObject private var healthKitService = HealthKitService.shared
    @ObservedObject private var mealService = MealService.shared
    @ObservedObject private var hydrationService = HydrationService.shared
    /// 2026-05-02 — observed so the `complete_workout` daily-goal card's
    /// completion sub-text refreshes the moment a native cardio recap
    /// fanout, a Strava sync, or a HealthKit observer pushes a new
    /// "today" record. Without this, the card would render the stale
    /// "Workout completed ✓" / strength-flavored copy until the next
    /// view re-render. See `RecentCardioCompletionStore`.
    @ObservedObject private var recentCardio = RecentCardioCompletionStore.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Smart Adaptive Daily Goals (20260607) — sheet binding for the
    /// Pro Quest Insights view. Self-contained so the widget can be
    /// embedded on any surface without a NavigationStack contract.
    @State private var showQuestInsights: Bool = false

    /// Free-tier Pro upsell. Tapping the upgrade footer opens the
    /// canonical paywall (`PremiumUpgradeView(.proQuests)`) — replaces
    /// the legacy dev `togglePremiumStatus()` stand-in. Triggering
    /// feature is `.proQuests` so the conversion attribution lands
    /// against the right surface in NewUserJourneyTracker analytics.
    @State private var showProQuestsPaywall: Bool = false

    /// Phase 3 (2026-04-27 — Daily Mission Unification): observed
    /// from `DailyBriefStore.shared` so the brief's `.focusQuest(key)`
    /// CTA can highlight the matching card. Read-only — the wrapper
    /// owns the @ObservedObject lifecycle.
    @ObservedObject private var briefStore = DailyBriefStore.shared
    /// The quest currently glowing as a result of a `.focusQuest`
    /// tap. Cleared via async work-item after `questGlowDuration`.
    @State private var glowingQuestKey: String?

    // Today's completed workouts (most recent first). Powers the
    // personalized workout-quest completion summary, e.g.
    // "Evening Arms & Shoulders workout ✓" instead of a generic
    // "Workout completed ✓".
    // Today's completed workouts — used TWICE: (1) personalized completion
    // copy ("Evening Arms & Shoulders workout ✓"), (2) live-tick the
    // `complete_workout` / `complete_program_day` / `early_bird_workout`
    // quest even when the server row is still 0/1 (e.g. after a quest-row
    // reset or on fresh re-install). fetchLimit=5 covers the rare
    // `complete_2_workouts` case + future double-session counts.
    @FetchRequest(fetchRequest: {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            request.predicate = NSPredicate(format: "isCompleted == true")
            request.fetchLimit = 5
            return request
        }
        request.predicate = NSPredicate(
            format: "isCompleted == true AND date >= %@ AND date < %@",
            start as NSDate, end as NSDate
        )
        request.fetchLimit = 5
        return request
    }(), animation: .none)
    private var todaysCompletedWorkouts: FetchedResults<Workout>
    
    private let accentGradient: [Color] = [
        Color(red: 1.0, green: 0.6, blue: 0.2),
        Color(red: 1.0, green: 0.4, blue: 0.4)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if questService.isLoading && questService.quests.isEmpty {
                loadingContent
            } else {
                questsCard
            }
        }
        // The header chevron is the canonical entry point to the
        // Daily Goals Insights sheet (replaces the in-card "Daily Goals
        // Insights" purple banner that used to live above the slate).
        // Free users land on the sheet's `proGate` paywall stub, which
        // double-duties as the upsell surface.
        .sheet(isPresented: $showQuestInsights) {
            NavigationStack {
                QuestInsightsView(questService: questService)
            }
        }
        .fullScreenCover(isPresented: $showProQuestsPaywall) {
            PremiumUpgradeView(triggeringFeature: .proQuests)
        }
        // Phase 3 (2026-04-27 — Daily Mission Unification): when the
        // welcome card's `.focusQuest(key)` CTA fires, briefly glow
        // the matching card so the user sees the connection. Clears
        // after `questGlowDuration` so the card returns to its
        // normal stroke. Re-tapping the brief while still glowing
        // restarts the timer (set fires again, .onChange reacts).
        .onChange(of: briefStore.pendingQuestFocus) { _, key in
            guard let key else {
                glowingQuestKey = nil
                return
            }
            glowingQuestKey = key
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(questGlowDuration))
                if glowingQuestKey == key {
                    glowingQuestKey = nil
                }
                if briefStore.pendingQuestFocus == key {
                    briefStore.pendingQuestFocus = nil
                }
            }
        }
    }

    // MARK: - Header

    /// "Daily Goals" + chevron. Tapping anywhere on the header row
    /// opens the Daily Goals Insights sheet — the same sheet the old
    /// purple banner used to launch. The X/3 counter (or +50 XP star
    /// when all complete) sits on the trailing edge where the streak
    /// badge used to live.
    private var headerRow: some View {
        Button {
            showQuestInsights = true
        } label: {
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
                    .foregroundColor(.primary)

                Spacer()

                bonusIndicator

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Daily Goals")
        // Phase 3 (2026-04-27 — Daily Mission Unification): copy
        // updated to match the new Mission framing — the Insights
        // sheet now answers "Why these goals?" rather than just
        // showing 28-day stats.
        .accessibilityHint("Why these goals?")
    }
    
    // MARK: - Bonus Indicator (X/3 counter in header)

    private var bonusIndicator: some View {
        let quests = questService.quests
        let allDone = questService.allComplete
        // Count a quest as "done" the moment its live progress hits 100%
        // — don't wait for the server to flip `is_completed`. Without
        // this, the visible cards show 2 green "Complete" states while
        // the header still reads 1/3, which the user called out as
        // inconsistent.
        let doneCount = quests.reduce(0) { $0 + (isEffectivelyDone(quest: $1) ? 1 : 0) }

        return Group {
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
                Text("\(doneCount)/3")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(doneCount > 0 ? .primary : .secondary)
            }
        }
    }

    /// Treats a quest as done if the server confirmed it OR live progress
    /// has reached the target. Matches the `progressMet` logic in
    /// `compactQuestRow` so the header dots stay in sync with each card.
    private func isEffectivelyDone(quest: DailyQuest) -> Bool {
        if quest.isCompleted { return true }
        return liveProgress(for: quest) >= 1.0
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

            // Free-user upsell CTA (Pro users get the Insights entry
            // point through the header chevron — no in-slate banner).
            // Renders only once the server has returned a real slate.
            if !questService.quests.isEmpty && !PremiumManager.shared.isPremiumUser {
                freeUpgradeFooter
                    .padding(.top, 4)
            }
        }
    }

    /// Free-user upgrade CTA. Pro users see no in-slate banner — the
    /// header "Daily Goals" chevron is the canonical Insights entry
    /// point (replaces the purple banner that used to live here).
    /// 20260619: slot count is locked at 3 for all tiers per product
    /// decision.
    private var freeUpgradeFooter: some View {
        Button {
            // Real paywall — opens `PremiumUpgradeView(.proQuests)` so
            // analytics attribute the conversion to the correct
            // triggering feature. Replaces the legacy dev
            // `togglePremiumStatus()` shim that previously stood in.
            HapticManager.impact(.light)
            showProQuestsPaywall = true
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.ds_caption)
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pro: 5 rerolls/day · Custom quests · Insights")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Plus 2× XP day · personal Insights")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Upgrade")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                        )
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Live Progress (client-side real-time values from local data sources)
    
    /// Returns the live current value for a quest using local data (HealthKit, meals, hydration)
    /// rather than the server-side currentValue which may lag behind.
    /// Always uses max(localValue, quest.currentValue) so progress never appears lower than
    /// the last server-synced value (e.g. when HealthKit hasn't loaded yet on app open).
    private func liveCurrentValue(for quest: DailyQuest) -> Int {
        guard !quest.isCompleted else { return quest.currentValue }
        guard let key = QuestKey(rawValue: quest.questKey) else { return quest.currentValue }
        
        switch key {
        // Step quests — live HealthKit step count with server fallback
        case .walk3kSteps, .walk5kSteps, .walk7500Steps, .walk10kSteps:
            let liveSteps = max(healthKitManager.todaySteps, healthKitService.todaySteps)
            let best = max(liveSteps, quest.currentValue)
            return min(best, quest.targetValue)
        case .hitStepGoal:
            // Track the live step count against the quest's target so the
            // progress bar grows in real time (9.5k / 10k ≈ 95% full), not
            // just 0% → 100% at the moment the goal is hit. The "goal"
            // target_unit still labels this "Goal hit! / Not yet".
            let liveSteps = max(healthKitManager.todaySteps, healthKitService.todaySteps)
            let best = max(liveSteps, quest.currentValue)
            return min(best, quest.targetValue)
            
        // Water quests — live hydration data
        case .logWater3, .logWater8, .logWater:
            let glasses = hydrationService.todaySummary?.entryCount ?? 0
            return max(glasses, quest.currentValue)
            
        // Hydration before noon
        case .hydrationBeforeNoon:
            let glasses = hydrationService.todaySummary?.entryCount ?? 0
            return max(glasses, quest.currentValue)
            
        // Meal count quests — live meal data
        case .log3Meals:
            let mealCount = mealService.todaysMeals.count
            return max(mealCount, quest.currentValue)
            
        // Individual meal type quests — check todaysMeals for matching type
        case .logBreakfast:
            let has = mealService.todaysMeals.contains { $0.mealType == .breakfast }
            return has ? 1 : quest.currentValue
        case .logLunch:
            let has = mealService.todaysMeals.contains { $0.mealType == .lunch }
            return has ? 1 : quest.currentValue
        case .logDinner:
            let has = mealService.todaysMeals.contains { $0.mealType == .dinner }
            return has ? 1 : quest.currentValue
        case .logSnack:
            let has = mealService.todaysMeals.contains { $0.mealType == .snacks }
            return has ? 1 : quest.currentValue
        case .logMeal:
            let mealCount = mealService.todaysMeals.count
            return max(mealCount, quest.currentValue)
            
        // Protein quests — live binary completion against the user's real
        // protein goal (`DailyQuestService.computeUserProteinGoal`). Returning
        // raw grams against a `target_value=1` binary template pegged the
        // progress bar at 100% on the first meal even though the quest
        // wasn't actually complete. Now the bar shows 0% until the user
        // crosses the gram threshold, then snaps to 100% — matches the
        // mechanic in `MealService → DailyQuestService.onProteinProgress`.
        case .hitProteinGoal:
            let todayProtein = mealService.todaysMeals.reduce(0) { $0 + $1.protein }
            let goal = DailyQuestService.shared.computeUserProteinGoal()
            let live = todayProtein >= goal ? quest.targetValue : 0
            return max(live, quest.currentValue)
        case .logHighProteinMeal:
            let has = mealService.todaysMeals.contains { $0.protein >= 30 }
            return has ? 1 : quest.currentValue
        case .logAllMacros:
            let meals = mealService.todaysMeals
            let hasProtein = meals.contains { $0.protein > 0 }
            let hasCarbs = meals.contains { $0.carbs > 0 }
            let hasFat = meals.contains { $0.fat > 0 }
            let logged = (hasProtein ? 1 : 0) + (hasCarbs ? 1 : 0) + (hasFat ? 1 : 0)
            return max(logged, quest.currentValue)
            
        // Active calories quest
        case .burn300Calories:
            let liveCals = healthKitService.todayCalories
            return max(liveCals, quest.currentValue)
            
        // Active minutes quest
        case .activeMinutes30:
            let liveMinutes = healthKitService.todayActiveMinutes
            return max(liveMinutes, quest.currentValue)
            
        // Sleep quest — live HealthKit sleep data
        case .sleep7Hours:
            if let sleepHours = healthKitService.lastNightSleep {
                return sleepHours >= 7.0 ? 1 : 0
            }
            return quest.currentValue
            
        // Workout quests — live-count today's completed Core Data workouts
        // so the quest ticks immediately after a workout even when the
        // server hasn't synced yet (or the quest row was just re-assigned).
        // `early_bird_workout` uses the same count since any workout today
        // finished before noon satisfies it; the completion summary is
        // time-aware enough to read correctly.
        case .completeWorkout, .completeProgramDay, .earlyBirdWorkout,
             .beginnerFirstWorkout:
            let todays = todaysCompletedWorkouts.count
            return max(todays, quest.currentValue)
        case .complete2Workouts:
            let todays = todaysCompletedWorkouts.count
            return max(todays, quest.currentValue)
        case .logCardio, .stretchSession:
            return quest.currentValue
        case .league3Workouts:
            return quest.currentValue
            
        default:
            return quest.currentValue
        }
    }
    
    /// Computes live progress (0.0–1.0) using client-side data
    private func liveProgress(for quest: DailyQuest) -> Double {
        guard quest.targetValue > 0 else { return 0 }
        let current = liveCurrentValue(for: quest)
        return min(Double(current) / Double(quest.targetValue), 1.0)
    }
    
    /// Formats progress label using live client-side data
    private func liveProgressLabel(for quest: DailyQuest) -> String {
        let current = liveCurrentValue(for: quest)
        let unit = quest.targetUnit
        switch unit {
        case "steps":
            if quest.targetValue >= 1000 {
                let currentK = Double(current) / 1000.0
                let targetK = Double(quest.targetValue) / 1000.0
                if current >= 1000 {
                    return String(format: "%.1fk / %.0fk steps", currentK, targetK)
                }
                return String(format: "%d / %.0fk steps", current, targetK)
            }
            return "\(current)/\(quest.targetValue) steps"
        case "glasses":
            return "\(current)/\(quest.targetValue) glasses"
        case "sets":
            return "\(current)/\(quest.targetValue) sets"
        case "meals", "meal":
            return "\(current)/\(quest.targetValue) \(quest.targetValue == 1 ? "meal" : "meals")"
        case "workouts", "workout":
            return "\(current)/\(quest.targetValue) \(quest.targetValue == 1 ? "workout" : "workouts")"
        case "minutes":
            return "\(current)/\(quest.targetValue) min"
        case "goal":
            return current >= quest.targetValue ? "Goal hit!" : "Not yet"
        default:
            return "\(current)/\(quest.targetValue) \(unit)"
        }
    }
    
    // MARK: - Compact Quest Row (exercise-library-card style with emoji progress ring)
    
    private func compactQuestRow(quest: DailyQuest) -> some View {
        // A completed quest (either server-confirmed OR live progress ≥ 100%)
        // renders identically: green check ring, white title (no strikethrough),
        // green completion summary with trailing ✓, no "Complete" pill. The
        // visual parity was an explicit UX ask — previously progressMet and
        // isCompleted states looked different (emoji + pill vs checkmark +
        // strikethrough), which read as inconsistent.
        let progress = liveProgress(for: quest)
        let progressMet = progress >= 1.0 && !quest.isCompleted
        let isDone = quest.isCompleted || progressMet
        let greenGradient = LinearGradient(
            colors: [.green, .mint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return Button {
            if !isDone {
                navigateToQuest(quest)
            }
        } label: {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                if isDone {
                    Circle()
                        .stroke(greenGradient, lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark")
                        .font(.ds_bodyMedium)
                        .foregroundStyle(greenGradient)
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AnyShapeStyle(quest.categoryColor),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5), value: progress)

                    Text(quest.categoryEmoji)
                        .font(.ds_heading3)
                }
            }

            // Text column — single action line + progress bar, aligned to
            // the right of the emoji ring. 2026-05-10 (Joe Reed shake,
            // build 1.40 "daily goals are too wordy — head + subhead is
            // too much"): the server-side `quest.title` ("Breakfast
            // Check-in" / "Crush a Workout" / "Do a Friend's Workout")
            // is cute-naming that adds no info beyond what
            // `dynamicDescription` already carries ("Log your breakfast"
            // / "Crush a Chest workout" / "Do a friend's workout"). One
            // line per card, action-verb first — same vertical rhythm
            // as the FE invariant 19b "Daily Goals never return empty"
            // contract since `dynamicDescription` always resolves to a
            // non-empty action string. The XP pill in the top-right
            // owns the trailing 56pt — every primary text view in here
            // reserves that padding so long copy never collides.
            VStack(alignment: .leading, spacing: 4) {
                if isDone {
                    Text(completionSummary(for: quest))
                        .font(.ds_labelMedium)
                        .foregroundColor(.green.opacity(0.9))
                        .lineLimit(1)
                        .padding(.trailing, 56)
                } else if quest.questKey == QuestKey.watchAds.rawValue {
                    Text(dynamicDescription(for: quest))
                        .font(.ds_labelMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .padding(.trailing, 56)
                    compactAdRow(quest: quest)
                } else {
                    Text(dynamicDescription(for: quest))
                        .font(.ds_labelMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .padding(.trailing, 56)

                    if hasMetadataRow(for: quest) {
                        questMetadataRow(quest: quest)
                    }
                }

                // Status bar — sits just below the subheader, aligned with
                // the text column (does NOT span under the emoji ring).
                // Completed cards render a full green bar (no trailing
                // label); in-progress cards render categoryColor progress
                // + live label. Ad quests render their own action row
                // above, so suppress the bar there.
                if quest.questKey != QuestKey.watchAds.rawValue {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(Color.gray.opacity(0.12))
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(isDone
                                        ? AnyShapeStyle(greenGradient)
                                        : AnyShapeStyle(quest.categoryColor))
                                    .frame(
                                        width: max(0, geo.size.width * (isDone ? 1.0 : progress)),
                                        height: 4
                                    )
                                    .animation(.spring(response: 0.4), value: progress)
                            }
                        }
                        .frame(height: 4)

                        // Reserve label slot on completed cards too so the
                        // progress row keeps the same vertical rhythm as
                        // active cards (otherwise the completed card looks
                        // ~10pt shorter / "smashed" next to active siblings).
                        if !isDone {
                            Text(liveProgressLabel(for: quest))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 50, alignment: .trailing)
                        } else {
                            Text(" ")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(minWidth: 50, alignment: .trailing)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .adaptiveSleekCardSubtle(cornerRadius: 16)
        .overlay(alignment: .topTrailing) {
            // XP reward pinned to the top-right corner of every card — same
            // position for in-progress and completed states so users can scan
            // rewards uniformly down the list.
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("+\(quest.xpReward)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("XP")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isDone ? .green : .secondary.opacity(0.5))
            .padding(.top, 10)
            .padding(.trailing, Spacing.md)
            .fixedSize()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    cardStroke(quest: quest, isDone: isDone),
                    lineWidth: glowingQuestKey == quest.questKey ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.25), value: glowingQuestKey)
        }
        .buttonStyle(.plain)
        // Smart Adaptive Daily Goals (20260607) — long-press to reroll
        // this slot. Server enforces per-day quotas (free 1, Pro 5)
        // and returns a structured reason on rejection.
        .contextMenu {
            if !isDone {
                Button {
                    Task { await rerollQuest(quest) }
                } label: {
                    Label("Reroll for a new goal", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    /// Phase 3 (2026-04-27): chooses the stroke gradient. Brief-
    /// influenced quests get a blue→cyan accent so they read as
    /// "linked to your mission" without requiring the user to read
    /// the chip. Glow state intensifies the brief-influenced
    /// gradient briefly when the user taps the brief.
    private func cardStroke(quest: DailyQuest, isDone: Bool) -> LinearGradient {
        let isInfluenced = isBriefInfluenced(quest)
        let isGlowing = glowingQuestKey == quest.questKey
        if isDone {
            return LinearGradient(
                colors: [.green.opacity(0.35), .mint.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        if isInfluenced {
            let alpha: Double = isGlowing ? 0.85 : 0.45
            return LinearGradient(
                colors: [.blue.opacity(alpha), .cyan.opacity(alpha * 0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [quest.categoryColor.opacity(0.35), quest.categoryColor.opacity(0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Phase 3 (2026-04-27 — Daily Mission Unification): a quest
    /// is "from your brief" iff (a) the server flagged it on this
    /// fetch (Layer 7 / Layer 8 in the v4 RPC), OR (b) the
    /// client-side engine matched it from the live brief Decision
    /// (covers legacy slates fetched before the v4 migration
    /// shipped). Either path is sufficient.
    private func isBriefInfluenced(_ quest: DailyQuest) -> Bool {
        if quest.isBriefInfluenced == true { return true }
        return briefStore.linkedQuestKeys.contains(quest.questKey)
    }

    /// True when the quest has any metadata badge worth rendering. Used
    /// to gate the metadata row entirely so empty-state cards collapse
    /// to the same vertical rhythm as completed cards.
    private func hasMetadataRow(for quest: DailyQuest) -> Bool {
        quest.doubleXpBadge != nil || quest.wasRerolled
    }

    /// Sub-row beneath a quest's dynamic description showing the
    /// double-XP marker (Pro day) and the "rerolled" tag.
    @ViewBuilder
    private func questMetadataRow(quest: DailyQuest) -> some View {
        HStack(spacing: 6) {
            if let bonus = quest.doubleXpBadge {
                Text(bonus)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            if quest.wasRerolled {
                Text("↻ rerolled")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// Wrapper that calls the reroll RPC and surfaces user-friendly
    /// haptics/toasts via the existing celebration overlay system.
    private func rerollQuest(_ quest: DailyQuest) async {
        let outcome = await questService.reroll(questId: quest.id)
        if outcome.success {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if outcome.reason == "free_limit_reached" {
            // Show a Pro upsell next time the user opens the bonus.
            // The footer below already handles surfacing the upgrade CTA
            // — this is just the haptic so they know the tap registered.
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
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
            
        case .logBreakfast:
            dl.pendingDestination = .addFood(mealType: "breakfast")
        case .logLunch:
            dl.pendingDestination = .addFood(mealType: "lunch")
        case .logDinner:
            dl.pendingDestination = .addFood(mealType: "dinner")
        case .logSnack:
            dl.pendingDestination = .addFood(mealType: "snacks")
        case .log3Meals, .hitProteinGoal, .logHighProteinMeal:
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
            
        // New metric-driven quests
        case .maintainStreak, .beatVolumePR, .league3Workouts:
            dl.pendingDestination = .workout
        case .stretchSession:
            dl.pendingDestination = .workout
        case .activeMinutes30, .burn300Calories:
            dl.pendingDestination = .stepTracker
        case .sleep7Hours:
            dl.pendingDestination = .dashboard
        case .beatFriendSteps:
            dl.pendingDestination = .stepTracker
        case .top3League:
            dl.pendingDestination = .workout
        case .logAllMacros:
            dl.pendingDestination = .mealsTab
        case .hydrationBeforeNoon:
            dl.pendingDestination = .hydration
        case .weeklyWeighIn:
            dl.pendingDestination = .weightTracker
            
        // Legacy keys
        case .logMeal:
            dl.pendingDestination = .mealsTab
        case .logWater:
            dl.pendingDestination = .hydration
        case .exerciseSets10, .exerciseSets20:
            dl.pendingDestination = .workout
            
        // Smart Adaptive Daily Goals (20260604) — new templates
        case .beatYour5kPR, .negativeSplitRun, .runOutside8km,
             .cycleOutside30km, .completeStravaSegment:
            // Strava-driven; deep link into the workout/cardio surface.
            dl.pendingDestination = .workout
        case .matchYesterdayStrain, .walkWhenRed:
            dl.pendingDestination = .stepTracker
        case .doFriendWorkout:
            // Friend's workout deep-link goes through the activity feed
            // — the row carries the workout_id needed to pre-load it.
            dl.pendingDestination = .friends
        case .commentOnFriendsWorkout, .reactTo3Workouts:
            dl.pendingDestination = .friends
        case .start1v1WithTopFriend:
            dl.pendingDestination = .challengeCreation

        // Day 1 beginner quests
        case .beginnerSyncContacts, .beginnerAddFriend:
            dl.pendingDestination = .friendSearch
        case .beginnerSendChallenge:
            dl.pendingDestination = .challengeCreation
        case .beginnerFirstWorkout:
            dl.pendingDestination = .workout
        case .beginnerExploreProgram:
            dl.pendingDestination = .programs
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
            return workoutCompletionSummary()
            
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
            
        case .maintainStreak:
            let streak = UserManager.shared.currentUser?.currentStreak ?? 0
            return "\(streak)-day streak maintained 🔥"
        case .stretchSession:
            return "Stretch session completed 🧘"
        case .beatVolumePR:
            return "New volume PR! 🏆"
        case .activeMinutes30:
            return "30+ active minutes ✓"
        case .burn300Calories:
            return "300+ calories burned 🔥"
        case .sleep7Hours:
            return "7+ hours of sleep 😴"
        case .beatFriendSteps:
            return "Outpaced your friend! 🏃"
        case .league3Workouts:
            return "3 workouts logged for the league ✓"
        case .top3League:
            return "Top 3 in your league! 🥇"
        case .logAllMacros:
            return "All macros logged ✓"
        case .hydrationBeforeNoon:
            return "Hydrated before noon 💧"
        case .weeklyWeighIn:
            return "Weekly weigh-in done ✓"
            
        case .beginnerSyncContacts:
            return "Contacts synced ✓"
        case .beginnerAddFriend:
            return "Friend added ✓"
        case .beginnerSendChallenge:
            return "Challenge sent ✓"
        case .beginnerFirstWorkout:
            return "First workout done! 💪"
        case .beginnerExploreProgram:
            return "Program explored ✓"

        // Smart Adaptive Daily Goals (20260604)
        case .beatYour5kPR:
            return "5K PR beat! 🏆"
        case .negativeSplitRun:
            return "Negative split nailed ✓"
        case .runOutside8km:
            return "8K outdoor run done ✓"
        case .cycleOutside30km:
            return "30K ride logged ✓"
        case .completeStravaSegment:
            return "Segment crushed 🚴"
        case .matchYesterdayStrain:
            return "Strain matched ✓"
        case .walkWhenRed:
            return "Recovery walk done ✓"
        case .doFriendWorkout:
            return "Friend's workout completed 👯"
        case .commentOnFriendsWorkout:
            return "Comment posted ✓"
        case .start1v1WithTopFriend:
            return "1v1 challenge started ⚔️"
        case .reactTo3Workouts:
            return "3 friend reactions sent 🎉"
        }
    }
    
    /// Builds a personalized "completed" caption for workout quests using
    /// the most-recent workout finished today, e.g. "Evening Arms & Shoulders
    /// workout ✓" / "Evening 5K Run ✓" / "Evening 5K with Strava ✓".
    ///
    /// Picks the cardio context (set by `RecentCardioCompletionStore` —
    /// fed by both the native cardio fanout and the Strava sync path) when
    /// it's strictly more recent than the most-recent strength `Workout`
    /// row, otherwise falls back to the strength copy. The cardio-aware
    /// path is what surfaces "Evening 5K with Strava ✓" the moment Strava
    /// imports a finished run (2026-05-02 user request).
    private func workoutCompletionSummary() -> String {
        let cardio = RecentCardioCompletionStore.shared.currentRecordForToday()

        // If a cardio finished today AND it's the most-recent thing, prefer
        // its sub-text. The strength row's `date` and the cardio's
        // `completedAt` use the same wall-clock domain so direct compare
        // is correct.
        if let cardio,
           let cardioText = RecentCardioCompletionStore.shared.completionSummaryText() {
            if let strength = todaysCompletedWorkouts.first,
               let strengthDate = strength.date,
               strengthDate >= cardio.completedAt {
                // Strength finished AFTER the most-recent cardio — keep
                // the strength copy so the card reflects the latest action.
                return strengthCompletionSummary(strength)
            }
            return cardioText
        }

        guard let workout = todaysCompletedWorkouts.first else {
            return "Workout completed ✓"
        }
        return strengthCompletionSummary(workout)
    }

    /// Strength-flavored completion sub-text — pulled into its own helper
    /// so `workoutCompletionSummary()` can share it across the
    /// "cardio more recent" / "strength more recent" / "no cardio today"
    /// branches.
    private func strengthCompletionSummary(_ workout: Workout) -> String {
        guard let finishedAt = workout.date else {
            return "Workout completed ✓"
        }
        let cleanedName = Self.cleanWorkoutName(workout.name)
        let timeOfDay = Self.timeOfDayLabel(for: finishedAt)

        if cleanedName.isEmpty {
            return "\(timeOfDay) workout completed ✓"
        }
        return "\(timeOfDay) \(cleanedName) workout ✓"
    }

    /// Strips trailing " - <date>" suffixes we append when saving workouts
    /// (e.g. "Arms & Shoulders - Apr 21" -> "Arms & Shoulders") so the
    /// completion caption reads naturally.
    private static func cleanWorkoutName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        // Split on the first " - " and keep the part before it only if the
        // suffix looks like a date/month token. Safer than regex-stripping.
        let parts = raw.components(separatedBy: " - ")
        guard parts.count > 1, let base = parts.first, !base.isEmpty else { return raw }
        let suffix = parts.dropFirst().joined(separator: " - ")
        let monthTokens = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        if monthTokens.contains(where: { suffix.hasPrefix($0) }) {
            return base
        }
        return raw
    }

    private static func timeOfDayLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default:      return "Late night"
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
    
    // MARK: - Dynamic Quest Descriptions
    
    /// Heuristic: detects whether the server-sent description for a generic
    /// workout quest is one of the split-personalized strings produced by
    /// `get_daily_quests` (migration 57). Falls back to the legacy engine
    /// text only when the description still looks like a stock template.
    // MARK: - Challenge-aware quest copy
    //
    // When the user has an active challenge whose metric matches a daily
    // quest (steps, active_minutes, calories, hydrate, protein, streak),
    // the quest description is rewritten client-side to surface today's
    // deficit / lead vs. the opponent. Server never sees opponent data —
    // it only knows the challenge TYPE is active via `p_active_challenge_types`.
    // We do the copy here because the numbers are live and the format has
    // to stay ≤35 chars to fit on one line of the compact quest card.

    /// Finds the best active 1v1 challenge matching any of the given types.
    /// "Best" = lowest `amWinningToday` so we prefer `catch up` framing over
    /// `stay ahead`, but falls back to any match.
    private func firstActiveChallenge(matching types: Set<String>) -> ActiveChallenge? {
        let matches = ChallengeService.shared.activeChallenges
            .filter { types.contains($0.challengeType) }
        if matches.isEmpty { return nil }
        return matches.sorted { a, b in
            // False (behind) sorts before True (ahead) → pick the catch-up one first.
            (a.amWinningToday ?? true ? 1 : 0) < (b.amWinningToday ?? true ? 1 : 0)
        }.first
    }

    /// Formats a challenge-deficit / lead string. Kept intentionally short
    /// (≤~35 chars per Data invariant 32 single-line contract) so the quest
    /// row never truncates on iPhone SE / 13 mini.
    ///
    /// All four scenarios share the same "{number} {unit} {direction}
    /// {opponent} - {action prompt}" cadence so the voice stays consistent
    /// regardless of who's ahead. Action prompts ("close it!", "break it!",
    /// "keep it up!", "first move wins") give the user something to do —
    /// neutral descriptions ("Tied with KC", "You vs KC today") tested as
    /// flat in user feedback (2026-04-27 dashboard screenshot).
    ///
    /// Examples (Manuel = 6-char first name, fits comfortably under 35 chars):
    ///   • Winning  → `1.1K ahead of Manuel - keep it up!`         (33)
    ///   • Losing   → `1.1K behind Manuel - close it!`              (30)
    ///   • Tied     → `Tied with Manuel - break it!`                (28)
    ///   • Not yet  → `You vs Manuel - first move wins`             (31)
    /// Long-name guard (`Christopher` = 11-char first name → truncated to 10
    /// at the call site via `shortOpponentName`) keeps every variant ≤ 35
    /// chars even at the edge.
    private func challengeDeficitCopy(
        challenge: ActiveChallenge,
        unitShort: String,
        kFormatted: Bool
    ) -> String? {
        let mine = challenge.myTodayProgress ?? 0
        let theirs = challenge.opponentTodayProgress ?? 0
        let name = Self.shortOpponentName(challenge.opponentDisplayName)
        let diff = abs(theirs - mine)

        func format(_ n: Int) -> String {
            guard kFormatted else { return "\(n)" }
            if n >= 1000 {
                let k = Double(n) / 1000.0
                return k.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(k))K"
                    : String(format: "%.1fK", k)
            }
            return "\(n)"
        }

        if diff == 0 && mine > 0 {
            return "Tied with \(name) - break it!"
        }
        if theirs > mine {
            return "\(format(diff)) \(unitShort) behind \(name) - close it!"
        }
        if mine > theirs && mine > 0 {
            return "\(format(diff)) \(unitShort) ahead of \(name) - keep it up!"
        }
        // Nobody's moved yet — frame the competition + nudge first move.
        return "You vs \(name) - first move wins"
    }

    /// Truncates a display name so it fits: first word only, max 10 chars.
    /// "KC Green" → "KC", "Alexandra Smith" → "Alexandra", "Christopher" → "Christoph…"
    private static func shortOpponentName(_ raw: String) -> String {
        let firstWord = raw.split(separator: " ").first.map(String.init) ?? raw
        if firstWord.count <= 10 { return firstWord }
        return String(firstWord.prefix(9)) + "…"
    }

    // MARK: - Quest copy variations (PE invariant 25-variations, 2026-04-27)
    //
    // Tiered copy picker for quests where the right phrasing depends on
    // user context: connected wearables, fitness goal, time of day, partial
    // progress. Order from most-specific to fallback so the highest tier
    // that passes wins. Within a tier, day-rotate using
    // `Self.dayRotated(...)` so users don't see the same line every day.
    //
    // Factual claim discipline (FE invariant 18b extension): only mention a
    // wearable signal when the wearable is connected AND has surfaced a
    // reading today (`hasWearableRecoverySignal`). NEVER claim "boosts
    // recovery" to a user without a wearable — they have no way to verify.
    // NEVER tie protein to "WHOOP Strain" — Strain is heart-rate-driven,
    // protein affects Recovery (next-day HRV/RHR) instead.

    /// Day-seeded selector that picks one string from a pool. Stable within
    /// a calendar day (no flicker on pull-to-refresh) but evolves across
    /// days. `variant` lets callers stagger pools so two quests don't
    /// always land on the same index.
    private static func dayRotated(_ pool: [String], variant: Int = 0) -> String {
        guard !pool.isEmpty else { return pool.first ?? "" }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return pool[(day + variant) % pool.count]
    }

    /// True when the user's `fitnessGoal` (multi-select comma-separated string
    /// from onboarding) contains the keyword. Case-insensitive.
    private func goalContains(_ keyword: String) -> Bool {
        guard let raw = UserManager.shared.currentUser?.fitnessGoal else { return false }
        return raw.localizedCaseInsensitiveContains(keyword)
    }

    /// True when a wearable is connected AND has surfaced a band reading.
    /// Gates copy that claims a wearable-tied benefit so we never advertise
    /// "boosts tomorrow's recovery" to a user without a wearable to verify.
    /// `todayReadiness` is non-optional (defaults to `.placeholder()` when
    /// no wearable is connected per Data invariant 35), so we read
    /// `hasWearableSignal` directly.
    private var hasWearableRecoverySignal: Bool {
        ReadinessService.shared.todayReadiness.hasWearableSignal
    }

    private static func isPersonalizedWorkoutDescription(_ text: String) -> Bool {
        // Markers from migrations 20260421 + 20260422. Current copy prefixes
        // every personalized description with "Suggested:". Older markers
        // stay in the list for pre-refresh rows still in user_daily_quests.
        let markers = [
            "Suggested:",
            "Your legs are fresh",
            "Legs are fresh",
            "Push feels fresh",
            "Back & biceps are fresh",
            "Back & biceps",
            "Chest, shoulders",
            "Upper body is recovered",
            "Everything is fresh",
            "any workout counts"
        ]
        return markers.contains { text.contains($0) }
    }

    /// 2026-05-10 (shake build 1.40 "make it personalized too"): rewrites the
    /// server-side personalized workout description into the action-verb-
    /// first cadence used everywhere else on the daily-goal surface (PE
    /// invariant 19e). The server's `get_daily_quests` v4 emits
    /// "Suggested: Legs today" / "Your legs are fresh — hit quads & hamstrings
    /// today" / etc. — both formats collapse to "Crush leg day" client-side.
    /// Server copy stays the canonical data contract; iOS owns the
    /// presentation cadence (avoids a 700-line `CREATE OR REPLACE FUNCTION`
    /// migration just to flip 5 strings). Returns `nil` for unrecognized
    /// variants so the caller falls back to the verbatim server description
    /// — future server copy iterations stay legible until a matcher is added
    /// here. Match strings are case-sensitive on the capitalized split name
    /// ("Legs" / "Push" / "Pull" / "Upper body" / "Full body") plus the
    /// 20260421-era "X are fresh" templates that still live in already-
    /// assigned `user_daily_quests` rows. Don't lowercase the input — that
    /// would over-match user-typed copy that happens to contain "legs".
    private static func actionVerbFirstFromPersonalized(_ text: String) -> String? {
        if text.contains("Legs") || text.contains("legs are fresh") {
            return "Crush leg day"
        }
        if text.contains("Push") || text.contains("Chest, shoulders") {
            return "Crush push day"
        }
        if text.contains("Pull") || text.contains("Back & biceps") {
            return "Crush pull day"
        }
        if text.contains("Upper body") || text.contains("Upper Body")
            || text.contains("Upper body is recovered") {
            return "Crush upper body"
        }
        if text.contains("Full body") || text.contains("Everything is fresh") {
            return "Crush full body"
        }
        return nil
    }

    private func dynamicDescription(for quest: DailyQuest) -> String {
        guard let key = QuestKey(rawValue: quest.questKey) else {
            return quest.description
        }
        
        switch key {
        case .completeWorkout:
            let suggestion = WorkoutSuggestionEngine.shared.suggestForToday()
            if suggestion.isFromProgram, let dayName = suggestion.programDayName {
                return "Crush \(dayName)"
            }
            // Server-personalized split-aware description ("Suggested: Legs
            // today" / "Your legs are fresh — …") gets rewritten to the
            // action-verb cadence (PE invariant 19e). Unrecognized variants
            // fall back to the verbatim server copy so future server copy
            // iterations stay legible until the matcher is updated.
            if Self.isPersonalizedWorkoutDescription(quest.description) {
                if let rewritten = Self.actionVerbFirstFromPersonalized(quest.description) {
                    return rewritten
                }
                return quest.description
            }
            // 2026-05-10 (shake build 1.40): action-verb first so the card
            // reads as a complete sentence with the title row dropped.
            // "Suggested: Chest" → "Crush a Chest workout" — matches the
            // user's canonical example ("Crush a chest workout").
            if let first = suggestion.suggestedMuscles.first {
                return "Crush a \(first.rawValue.capitalized) workout"
            }
            return "Crush a workout today"
        case .completeProgramDay:
            if let day = GeneratedProgramService.shared.currentDay {
                let muscle = day.focusMuscles.first ?? "program"
                return "Crush Day \(day.dayNumber) — \(muscle)"
            }
            return "Crush your next program day"
        case .complete2Workouts:
            return "Knock out 2 workouts today"
        case .workout30Min:
            if Self.isPersonalizedWorkoutDescription(quest.description) {
                return quest.description
            }
            return "Complete a 30+ min workout"
        case .exerciseSets15:
            return "Hit 15 sets in a single workout"
        case .exerciseSets25:
            return "Crush 25+ sets in one session"
        case .tryNewExercise:
            return "Try an exercise you haven't done recently"
        case .upperBodyWorkout:
            if Self.isPersonalizedWorkoutDescription(quest.description) {
                return quest.description
            }
            return WorkoutSuggestionEngine.shared.smartQuestDescription(isUpperBody: true)
        case .lowerBodyWorkout:
            if Self.isPersonalizedWorkoutDescription(quest.description) {
                return quest.description
            }
            return WorkoutSuggestionEngine.shared.smartQuestDescription(isUpperBody: false)
            
        case .logBreakfast:
            return "Log your breakfast"
        case .logLunch:
            return "Log your lunch"
        case .logDinner:
            return "Log your dinner"
        case .log3Meals:
            let logged = MealService.shared.todaysMeals.count
            if logged > 0 {
                return "\(logged)/3 meals logged"
            }
            return "Log all 3 meals today"
        case .logSnack:
            return "Log a snack"
        case .logWater3:
            if let ch = firstActiveChallenge(matching: ["hydrate"]),
               let copy = challengeDeficitCopy(challenge: ch, unitShort: "glass", kFormatted: false) {
                return copy
            }
            return "Log 3 glasses of water"
        case .logWater8:
            if let ch = firstActiveChallenge(matching: ["hydrate"]),
               let copy = challengeDeficitCopy(challenge: ch, unitShort: "glass", kFormatted: false) {
                return copy
            }
            // PE invariant 25-variations.
            let glasses = hydrationService.todaySummary?.entryCount ?? 0
            let remaining = max(0, 8 - glasses)

            // Tier 4 — partial progress (1–7 glasses already logged).
            if glasses > 0 && remaining > 0 {
                if remaining <= 2 {
                    return Self.dayRotated([
                        "\(remaining) more glasses - so close",
                        "\(remaining) more to hit 8 - finish it",
                    ], variant: 1)
                }
                return Self.dayRotated([
                    "\(remaining) more glasses today",
                    "\(remaining) glasses left of 8",
                ], variant: 1)
            }

            // Tier 3 — wearable + factual hydration→HRV claim. Dehydration
            // suppresses HRV and elevates RHR; properly-hydrated days
            // measurably improve next-day Recovery scores.
            if hasWearableRecoverySignal {
                return Self.dayRotated([
                    "8 glasses - keep HRV strong",
                    "Drink 8 - dehydration tanks recovery",
                    "8 glasses today - your RHR thanks you",
                ], variant: 2)
            }

            // Tier 2 — fitness-goal-aware.
            if goalContains("lose weight") || goalContains("lean") {
                return Self.dayRotated([
                    "8 glasses - hunger likes to fake thirst",
                    "Drink 8 today - cuts cravings",
                ], variant: 3)
            }

            // Tier 1 — generic fallback.
            return Self.dayRotated([
                "Drink 8 glasses today",
                "Hit 8 glasses - stay topped off",
                "8 glasses of water today",
            ], variant: 4)
        case .hitProteinGoal:
            if let ch = firstActiveChallenge(matching: ["protein"]),
               let copy = challengeDeficitCopy(challenge: ch, unitShort: "g", kFormatted: false) {
                return copy
            }
            // PE invariant 25-variations — tiered copy picker.
            // `computeUserProteinGoal` is the single source of truth for the
            // gram threshold (mirrors DashboardView+Macros + Daily Brief).
            let goal = DailyQuestService.shared.computeUserProteinGoal()
            let consumed = mealService.todaysMeals.reduce(0) { $0 + $1.protein }
            let remaining = max(0, goal - consumed)
            let hour = Calendar.current.component(.hour, from: Date())

            // Tier 4 — partial progress + time-of-day. Mirrors the brief's
            // "<X>g of protein left" cadence, anchors on the meal that
            // closes the gap.
            if consumed > 0 && consumed < goal {
                if hour >= 18 {
                    return Self.dayRotated([
                        "\(remaining)g left - dinner closes it",
                        "\(remaining)g protein - finish strong",
                    ], variant: 1)
                }
                return Self.dayRotated([
                    "\(remaining)g protein left",
                    "\(remaining)g to your protein goal",
                ], variant: 1)
            }

            // Tier 3 — wearable + factually-correct recovery claim. Protein
            // → muscle-protein-synthesis → next-day HRV/RHR (i.e. Recovery,
            // NOT Strain — Strain is HR-driven). Gated on
            // `hasWearableRecoverySignal` so non-wearable users never see a
            // claim they can't verify.
            if hasWearableRecoverySignal && goalContains("muscle") {
                return Self.dayRotated([
                    "Eat \(goal)g - boost tomorrow's recovery",
                    "Hit \(goal)g - lock in today's gains",
                    "\(goal)g protein - fuel muscle repair",
                ], variant: 2)
            }

            // Tier 2 — fitness-goal-aware (no wearable claim).
            if goalContains("muscle") || goalContains("stronger") {
                return Self.dayRotated([
                    "Eat \(goal)g protein - fuel today's gains",
                    "Hit \(goal)g - build the muscle you train for",
                    "\(goal)g protein keeps the gains coming",
                ], variant: 3)
            }
            if goalContains("lose weight") || goalContains("lean") {
                return Self.dayRotated([
                    "\(goal)g protein keeps you on pace",
                    "Eat \(goal)g - protein burns more than carbs",
                    "Hit \(goal)g - protein wins the satiety game",
                ], variant: 3)
            }

            // Tier 1 — generic fallback (rotates daily).
            return Self.dayRotated([
                "Eat \(goal)g protein today",
                "Hit \(goal)g - your daily protein target",
                "\(goal)g protein - get to work",
            ], variant: 4)
        case .logHighProteinMeal:
            return "Log a 30g+ protein meal"
            
        case .walk3kSteps:
            return challengeOrStepsDescription(target: 3000)
        case .walk5kSteps:
            return challengeOrStepsDescription(target: 5000)
        case .walk7500Steps:
            return challengeOrStepsDescription(target: 7500)
        case .walk10kSteps:
            return challengeOrStepsDescription(target: 10000)
        case .hitStepGoal:
            let goal = HealthKitManager.shared.stepGoal
            return challengeOrStepsDescription(target: goal)
            
        case .sendChallenge:
            if let friend = FriendService.shared.friends.first {
                return "Challenge \(Self.shortOpponentName(friend.displayName))"
            }
            return "Challenge any friend"
        case .start1v1Challenge:
            if let friend = FriendService.shared.friends.first {
                return "Start 1v1 with \(Self.shortOpponentName(friend.displayName))"
            }
            return "Start a 1v1 challenge"
        case .reactToWorkout:
            return "React to a friend's workout"
        case .inviteFriend:
            return "Invite someone to join Fit33"
        case .addFriend:
            return "Send a friend request"
        case .startFirstChallenge:
            return "Kick off your first challenge"
            
        case .logWeight:
            return "Log your weight today"
        case .checkProgress:
            return "View your stats & PRs"
        case .beatPersonalRecord:
            return "Beat a personal record"
        case .logCardio:
            return "Log any cardio activity"
            
        case .perfectDay:
            return "Workout + 3 meals + steps"
        case .earlyBirdWorkout:
            return "Workout before noon"
        case .shareWorkout:
            return "Share a workout"
        case .favoriteAWorkout:
            return "Favorite a workout"
            
        case .maintainStreak:
            if let ch = firstActiveChallenge(matching: ["workout_streak"]),
               let copy = challengeDeficitCopy(challenge: ch, unitShort: "day", kFormatted: false) {
                return copy
            }
            // PE invariant 25-variations — streak-milestone-aware. Higher
            // streaks earn higher-stakes language; near-milestone streaks
            // surface the upcoming round number to motivate.
            let streak = Int(UserManager.shared.currentUser?.currentStreak ?? 0)

            // Tier 4 — about to hit a milestone (within 1 day).
            let nextMilestone: Int? = {
                let milestones = [3, 7, 14, 30, 60, 100, 365]
                return milestones.first(where: { $0 == streak + 1 })
            }()
            if let milestone = nextMilestone {
                return Self.dayRotated([
                    "Day \(streak) - hit \(milestone) tomorrow",
                    "1 more day to \(milestone)-day streak",
                ], variant: 1)
            }

            // Tier 3 — long streaks (legendary territory).
            if streak >= 100 {
                return Self.dayRotated([
                    "Day \(streak) - don't break it now",
                    "\(streak) days - you don't miss",
                    "Day \(streak) - keep it untouchable",
                ], variant: 2)
            }
            if streak >= 30 {
                return Self.dayRotated([
                    "Day \(streak) - protect the streak",
                    "\(streak)-day streak - keep it alive",
                    "Day \(streak) - momentum is yours",
                ], variant: 3)
            }
            if streak >= 7 {
                return Self.dayRotated([
                    "Day \(streak) - keep building",
                    "\(streak)-day streak - one more day",
                    "Day \(streak) - habit is forming",
                ], variant: 4)
            }

            // Tier 2 — early streak (1–6 days).
            if streak > 0 {
                return Self.dayRotated([
                    "Keep your \(streak)-day streak",
                    "Day \(streak) - one more rep",
                    "\(streak) days down - keep going",
                ], variant: 5)
            }

            // Tier 1 — no streak yet.
            return Self.dayRotated([
                "Start a workout streak today",
                "Day 1 starts now",
                "Begin your streak today",
            ], variant: 6)
        case .stretchSession:
            return "Complete a guided stretch session"
        case .beatVolumePR:
            return "Beat your best total volume in a workout"
            
        case .activeMinutes30:
            if let ch = firstActiveChallenge(matching: ["active_minutes"]),
               let copy = challengeDeficitCopy(challenge: ch, unitShort: "min", kFormatted: false) {
                return copy
            }
            return "30 active minutes today"
        case .burn300Calories:
            if let ch = firstActiveChallenge(matching: ["calories"]),
               let copy = challengeDeficitCopy(challenge: ch, unitShort: "cal", kFormatted: false) {
                return copy
            }
            return "Burn 300 active cal today"
        case .sleep7Hours:
            return "Get 7+ hours of sleep"
            
        case .beatFriendSteps:
            if let ch = firstActiveChallenge(matching: ["steps", "walk", "run"]),
               let copy = challengeDeficitCopy(challenge: ch, unitShort: "steps", kFormatted: true) {
                return copy
            }
            return "Outpace a friend in steps"
        case .league3Workouts:
            if let standing = WeeklyLeagueService.shared.standing {
                return "Rank #\(standing.myRank) — log 3 workouts"
            }
            return "Log 3 workouts this week"
        case .top3League:
            if let standing = WeeklyLeagueService.shared.standing {
                return "Top 3 — you're #\(standing.myRank)"
            }
            return "Finish top 3 this week"
            
        case .logAllMacros:
            return "Log protein, carbs, and fat"
        case .hydrationBeforeNoon:
            return "4 glasses before noon"
        case .weeklyWeighIn:
            return "Log your weight this week"
            
        case .watchAds:
            return quest.description
        case .logMeal, .logWater, .exerciseSets10, .exerciseSets20:
            return quest.description
            
        case .beginnerSyncContacts, .beginnerAddFriend, .beginnerSendChallenge,
             .beginnerFirstWorkout, .beginnerExploreProgram:
            return quest.description

        // Smart Adaptive Daily Goals (20260604) — server-personalized
        // copy is the source of truth (e.g. "Due for legs — do Paul's").
        // We trust quest.description for these unless it's empty.
        case .beatYour5kPR:
            return quest.description.isEmpty ? "Beat your 5K PR on Strava" : quest.description
        case .negativeSplitRun:
            return quest.description.isEmpty ? "Run with a negative split" : quest.description
        case .runOutside8km:
            return quest.description.isEmpty ? "Run 8K outside" : quest.description
        case .cycleOutside30km:
            return quest.description.isEmpty ? "Cycle 30K outside" : quest.description
        case .completeStravaSegment:
            return quest.description.isEmpty ? "Complete a Strava segment" : quest.description
        case .matchYesterdayStrain:
            return quest.description.isEmpty ? "Match yesterday's strain" : quest.description
        case .walkWhenRed:
            return quest.description.isEmpty ? "Take a 20-min recovery walk" : quest.description
        case .doFriendWorkout:
            // Server already builds split-aware copy; trust it.
            return quest.description.isEmpty ? "Do a friend's workout" : quest.description
        case .commentOnFriendsWorkout:
            return quest.description.isEmpty ? "Comment on a friend's workout" : quest.description
        case .start1v1WithTopFriend:
            return quest.description.isEmpty ? "Start a 1v1 with a top friend" : quest.description
        case .reactTo3Workouts:
            return quest.description.isEmpty ? "React to 3 friend workouts" : quest.description
        }
    }
    
    /// If a step / walk / run challenge is active, surface the opponent gap
    /// ("5K to catch KC"). Otherwise fall back to the generic progress hint.
    /// Every returned string stays ≤35 chars to avoid truncation.
    private func challengeOrStepsDescription(target: Int) -> String {
        if let ch = firstActiveChallenge(matching: ["steps", "walk", "run"]),
           let copy = challengeDeficitCopy(challenge: ch, unitShort: "steps", kFormatted: true) {
            return copy
        }
        return stepsDescription(target: target)
    }

    private func stepsDescription(target: Int) -> String {
        let current = HealthKitService.shared.todaySteps
        let targetK = target >= 1000 ? "\(target / 1000)K" : "\(target)"
        if current > 0 {
            let currentK = current >= 1000
                ? String(format: "%.1fK", Double(current) / 1000.0)
                : "\(current)"
            return "\(currentK) of \(targetK) steps"
        }
        return "Walk \(targetK) steps today"
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
        .adaptiveSleekCardSubtle(cornerRadius: 16)
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
        .adaptiveSleekCard(cornerRadius: 24, accentColor: .orange)
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
