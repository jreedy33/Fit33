//
//  OlympianPathView.swift
//  Fit33
//
//  Detail screen for the "Path to 33" annual Olympian track.
//
//  Layout:
//   - Header: ring + archetype chip + completed-tier dots
//   - 5 tier sections, each a horizontal "constellation" of goal cards
//     (locked / unlocked / in-progress states)
//   - Tap a goal → bottom sheet with full description, progress bar,
//     "How to complete" hint, and a CTA deep-linking to the source surface
//   - Footer: stackable "Olympian YYYY" badges from prior seasons
//
//  Mirrors the visual language of `AchievementsView` (`AchievementRow`
//  locked/unlocked pattern) so the surface feels native — the user is in
//  achievement-land, just on a personalized 33-goal track.
//

import SwiftUI

// MARK: - Detail screen

struct OlympianPathView: View {
    @StateObject private var service = OlympianPathService.shared

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGoal: OlympianGoal?
    @State private var yearEndShareItem: OlympianShareItem?

    private var year: Int { OlympianPathService.currentSeasonYear }

    /// Year as a string with NO grouping separator (`"2026"` not `"2,026"`).
    /// SwiftUI's default `Text("\(intValue)")` runs through Locale-aware
    /// number formatting and inserts thousands separators. Years are
    /// identifiers, not quantities — they should never group. Used in every
    /// "Path to YYYY" / "Olympian YYYY" string in this view.
    private var yearText: String { String(year) }

    /// True between Dec 27 and Jan 7 (inclusive) — the window the year-end
    /// recap card surfaces in the detail screen. The window straddles the
    /// year boundary deliberately so the user can share their *previous*
    /// year's run for the first week of the new season.
    private var isInYearEndRecapWindow: Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: Date())
        guard let month = components.month, let day = components.day else { return false }
        return (month == 12 && day >= 27) || (month == 1 && day <= 7)
    }

    var body: some View {
        ZStack {
            AnimatedOrbBackground.stats(colorScheme: colorScheme)

            ScrollView {
                LazyVStack(spacing: Spacing.lg) {
                    headerCard

                    // 2026-05-04 — Year-end recap: surfaces between
                    // Dec 27 and Jan 7 so users see it on either side
                    // of the year boundary. Tap → OS share sheet
                    // (uses the same `OlympianShareItem` as the
                    // celebration overlay's Share button).
                    if isInYearEndRecapWindow {
                        yearEndRecapCard
                    }

                    if service.goals.isEmpty {
                        // Empty-state cases (in priority order):
                        //   • Loading on first open — show skeleton
                        //   • Migration not yet deployed to this Supabase
                        //     project (assignments table empty / RPC
                        //     missing) — show "setting up" copy + retry
                        //   • Network failure — same UI, retry restores
                        // We never let the screen go blank below the
                        // header card; the user paid $0 for these 33
                        // goals but they paid attention to find them.
                        emptyStateCard
                    } else {
                        ForEach(1...5, id: \.self) { tier in
                            tierSection(tier: tier)
                        }
                    }

                    if !service.seasonBadges.isEmpty {
                        priorSeasonsFooter
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .padding(.bottom, 60)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Path to \(yearText)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_heading3)
                        .foregroundColor(.primary)
                }
            }
        }
        .task {
            await service.loadCurrentSeason()
        }
        .refreshable {
            await service.loadCurrentSeason(force: true)
        }
        .sheet(item: $selectedGoal) { goal in
            GoalDetailSheet(goal: goal, onClose: { selectedGoal = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $yearEndShareItem) { item in
            ShareSheet(items: [item.shareText])
        }
    }

    // MARK: - Empty state (no goals loaded yet)

    /// Shown when the path returns 0 goals — covers three real cases:
    ///   1. First-open loading (the 200-300ms before the RPC resolves)
    ///   2. Migration not yet deployed (`assign_olympian_path` 404s OR
    ///      `achievements` table has no `olympian_path` rows so
    ///      `rebuildGoals` filter-misses every assignment)
    ///   3. Transient network failure
    /// Same card for all three so the user is never staring at a blank
    /// page below the header. Pull-to-refresh and the "Try again" tap
    /// both call `loadCurrentSeason(force: true)`.
    private var emptyStateCard: some View {
        let goldAccent = Color(red: 1.00, green: 0.84, blue: 0.00)

        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(goldAccent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: service.isLoading ? "hourglass" : "crown.fill")
                    .font(.title)
                    .foregroundStyle(LinearGradient(
                        colors: [goldAccent, service.archetype.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .symbolEffect(.bounce, value: service.isLoading)
            }

            Text(service.isLoading
                 ? "Setting up your 33 goals…"
                 : "Your 33 goals aren't loaded yet")
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(service.isLoading
                 ? "Picking goals tailored to your path. This only happens once a year."
                 : "Pull down to refresh, or tap below to try again. If this keeps happening, the Olympian Path migration may not be live yet for your account.")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.sm)

            // Surface the actual server error if there is one. This is the
            // single most useful debug signal during the rollout — a
            // PGRST202 means "migration not deployed", a "Olympian
            // assignment short" means "seed pool incomplete", an auth
            // error means "session expired". Without this, every failure
            // looks identical to the user.
            if !service.isLoading, let err = service.lastLoadError {
                Text(err)
                    .font(.ds_caption)
                    .foregroundColor(.orange.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.08))
                    )
                    .accessibilityLabel("Server error: \(err)")
            }

            if !service.isLoading {
                Button(action: {
                    HapticManager.tap()
                    Task { await service.loadCurrentSeason(force: true) }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try again")
                            .fontWeight(.bold)
                    }
                    .font(.ds_labelLarge)
                    .foregroundColor(.black)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(LinearGradient(
                            colors: [goldAccent, service.archetype.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    )
                }
                .accessibilityHint("Refreshes the Olympian Path from the server.")
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .adaptiveSleekCard(cornerRadius: 20, accentColor: goldAccent)
    }

    // MARK: - Year-end recap card

    private var yearEndRecapCard: some View {
        let goldAccent = Color(red: 1.00, green: 0.84, blue: 0.00)
        let coralAccent = Color(red: 0.95, green: 0.50, blue: 0.30)

        // Recap reflects whichever season the user actually engaged with
        // in this window — early-Jan opens reflect last year, late-Dec
        // opens reflect the current year. We pick the most recent
        // completed season if any, else the active path.
        let recapBadge = service.seasonBadges.first
        let recapYear = recapBadge?.seasonYear ?? year
        let completed = service.progress.completed
        let isFromBadge = recapBadge != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(LinearGradient(
                        colors: [goldAccent, coralAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("Year-End Recap")
                    .font(.ds_labelLarge)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
            }

            Text(isFromBadge
                 ? "You hit Olympian \(String(recapYear)). Share the moment."
                 : "Your \(String(recapYear)) run: \(completed) of 33. Share the milestone you're proudest of.")
                .font(.ds_bodyMedium)
                .foregroundColor(.primary)
                .lineLimit(3)

            Button(action: {
                HapticManager.tap()
                let badge = recapBadge ?? OlympianSeasonBadge(
                    seasonYear: recapYear,
                    archetype: service.archetype.rawValue,
                    completedAt: ISO8601DateFormatter().string(from: Date())
                )
                yearEndShareItem = OlympianShareItem(badge: badge)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Recap")
                        .fontWeight(.bold)
                }
                .font(.ds_labelLarge)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [goldAccent, coralAccent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                )
            }
            .accessibilityHint("Opens the system share sheet with your Olympian recap.")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveSleekCard(cornerRadius: 20, accentColor: goldAccent)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.18), lineWidth: 10)
                        .frame(width: 110, height: 110)

                    let progress = service.progress
                    Circle()
                        .trim(from: 0, to: min(1.0, Double(progress.completed) / Double(max(progress.total, 33))))
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.75, blue: 0.95),
                                    Color(red: 0.40, green: 0.85, blue: 0.65),
                                    Color(red: 0.95, green: 0.75, blue: 0.30),
                                    Color(red: 0.95, green: 0.50, blue: 0.30),
                                    Color(red: 1.00, green: 0.84, blue: 0.00)
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 110, height: 110)
                        .animation(.easeInOut(duration: 0.6), value: progress.completed)

                    VStack(spacing: 0) {
                        Text("\(progress.completed)")
                            .font(.ds_displayMedium)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("/ 33")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Path to Olympian \(yearText)")
                        .font(.ds_heading3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Image(systemName: service.archetype.icon)
                            .font(.caption)
                            .foregroundColor(service.archetype.accent)
                        Text(service.archetype.displayName)
                            .font(.ds_labelMedium)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(service.archetype.accent.opacity(0.15))
                    .clipShape(Capsule())

                    tierProgressDots
                }

                Spacer()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveSleekCard(cornerRadius: 24, accentColor: service.archetype.accent)
    }

    private var tierProgressDots: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { tier in
                Circle()
                    .fill(service.highestClearedTier >= tier ? colorForTier(tier) : Color.gray.opacity(0.25))
                    .frame(width: 9, height: 9)
            }

            Text("\(service.highestClearedTier) of 5 tiers")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Tier section

    @ViewBuilder
    private func tierSection(tier: Int) -> some View {
        let goalsInTier = service.goals.filter { $0.tier == tier }
        if !goalsInTier.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                tierSectionHeader(tier: tier, goals: goalsInTier)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(goalsInTier) { goal in
                            ConstellationCard(goal: goal) {
                                HapticManager.tap()
                                selectedGoal = goal
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func tierSectionHeader(tier: Int, goals: [OlympianGoal]) -> some View {
        let unlocked = goals.filter(\.unlocked).count
        let isComplete = unlocked == goals.count

        return HStack(spacing: 10) {
            Circle()
                .fill(colorForTier(tier))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.6), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Tier \(tier)")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text(tierName(tier))
                        .font(.ds_labelMedium)
                        .foregroundColor(colorForTier(tier))
                    if isComplete {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(colorForTier(tier))
                    }
                }
                Text("\(unlocked) / \(goals.count) unlocked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Prior seasons footer

    private var priorSeasonsFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Olympian History")
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(service.seasonBadges) { badge in
                        olympianBadgeChip(badge)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .adaptiveSleekCard(cornerRadius: 20, accentColor: Color(red: 1.00, green: 0.84, blue: 0.00))
    }

    private func olympianBadgeChip(_ badge: OlympianSeasonBadge) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.00, green: 0.84, blue: 0.00), badge.resolvedArchetype.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String(badge.seasonYear))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .frame(width: 60, height: 60)
        .background(
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.84, blue: 0.00).opacity(0.15),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 30
                    )
                )
        )
        .overlay(
            Circle().stroke(Color(red: 1.00, green: 0.84, blue: 0.00).opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func colorForTier(_ tier: Int) -> Color {
        switch tier {
        case 1: return Color(red: 0.55, green: 0.75, blue: 0.95)
        case 2: return Color(red: 0.40, green: 0.85, blue: 0.65)
        case 3: return Color(red: 0.95, green: 0.75, blue: 0.30)
        case 4: return Color(red: 0.95, green: 0.50, blue: 0.30)
        case 5: return Color(red: 1.00, green: 0.84, blue: 0.00)
        default: return .gray
        }
    }

    private func tierName(_ tier: Int) -> String {
        switch tier {
        case 1: return "Foundation"
        case 2: return "Habits"
        case 3: return "Strength"
        case 4: return "Mastery"
        case 5: return "Olympian"
        default: return ""
        }
    }
}

// MARK: - Constellation card (one goal)

private struct ConstellationCard: View {
    let goal: OlympianGoal
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    Text("#\(goal.goalNumber)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if goal.unlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(goal.tierColor)
                    }
                }

                ZStack {
                    Circle()
                        .fill(goal.unlocked
                              ? goal.tierColor.opacity(0.20)
                              : Color.gray.opacity(0.10))
                        .frame(width: 44, height: 44)

                    Image(systemName: goal.icon)
                        .font(.title3)
                        .foregroundColor(goal.unlocked ? goal.tierColor : .gray.opacity(0.5))
                }

                Text(goal.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(goal.unlocked ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)

                if !goal.unlocked && goal.threshold > 1 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(goal.tierColor.opacity(0.7))
                                .frame(width: geo.size.width * goal.progressPercent, height: 4)
                        }
                    }
                    .frame(height: 4)
                } else {
                    Color.clear.frame(height: 4)
                }

                if goal.threshold > 1 {
                    Text("\(goal.progress) / \(goal.threshold)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                } else {
                    Text(goal.unlocked ? "Done" : "Locked")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(goal.unlocked ? goal.tierColor : .secondary)
                }
            }
            .padding(10)
            .frame(width: 130, height: 170)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        goal.unlocked
                            ? LinearGradient(colors: [goal.tierColor, goal.tierColor.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.gray.opacity(0.2)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
            )
            .opacity(goal.unlocked ? 1.0 : 0.85)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Goal detail sheet

private struct GoalDetailSheet: View {
    let goal: OlympianGoal
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Hero
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(goal.tierColor.opacity(0.18))
                            .frame(width: 80, height: 80)
                        Image(systemName: goal.icon)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(goal.tierColor)
                    }

                    Text("Goal #\(goal.goalNumber) — Tier \(goal.tier)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(goal.title)
                        .font(.ds_heading2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    Text(goal.description)
                        .font(.ds_bodyMedium)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                // Progress bar
                if goal.threshold > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Progress")
                                .font(.ds_labelMedium)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(goal.progress) / \(goal.threshold)")
                                .font(.ds_labelMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .monospacedDigit()
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.18))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(goal.tierColor)
                                    .frame(width: geo.size.width * goal.progressPercent, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }

                // How to complete
                hintSection

                // CTA
                if !goal.unlocked, let cta = ctaForGoal {
                    Button(action: cta.action) {
                        HStack {
                            Image(systemName: cta.icon)
                            Text(cta.label)
                                .fontWeight(.bold)
                        }
                        .font(.ds_labelLarge)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            LinearGradient(
                                colors: [goal.tierColor, goal.tierColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(CornerRadius.lg)
                    }
                }

                if goal.unlocked, goal.xpReward > 0 {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Earned +\(goal.xpReward) XP")
                            .fontWeight(.semibold)
                    }
                    .font(.ds_labelMedium)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.lg)
            .padding(.top, Spacing.md)
        }
        .background(colorScheme == .dark ? Color.black : Color(white: 0.98))
    }

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to Complete")
                .font(.ds_labelMedium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(hintText)
                .font(.ds_bodyMedium)
                .foregroundColor(.primary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(goal.tierColor.opacity(colorScheme == .dark ? 0.10 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(goal.tierColor.opacity(0.3), lineWidth: 1)
        )
    }

    /// Personalized one-liner hint sourced from the goal key. Mirrors the
    /// `DailyBriefEngine` style — short, action-first, friendly.
    private var hintText: String {
        let key = goal.achievementKey
        let remaining = max(0, goal.threshold - goal.progress)

        if key.contains("streak_") {
            return remaining > 0
                ? "You're at \(goal.progress) days. Train today to keep the streak alive — \(remaining) to go."
                : "Maintain your streak to keep this unlocked — every day counts."
        }
        if key.contains("workouts_") {
            return remaining > 0
                ? "Log \(remaining) more workout\(remaining == 1 ? "" : "s") to unlock this. Any workout type counts."
                : "Each workout you log moves this forward."
        }
        if key.contains("first_") {
            return goal.unlocked
                ? "Done — nice work."
                : "One quick action unlocks this. Tap the button below to jump there."
        }
        if key.contains("react_") {
            return remaining > 0
                ? "React to friends' workouts — \(remaining) more reactions to go."
                : "Send reactions on the friends feed to progress this."
        }
        if key.contains("meals_") {
            return remaining > 0
                ? "Log \(remaining) more meal\(remaining == 1 ? "" : "s") to hit this milestone."
                : "Log meals consistently to keep this moving."
        }
        if key.contains("tier_gold") || key.contains("tier_diamond") || key.contains("tier_platinum") {
            return "Climb the Weekly League to reach this tier. Win League Points by logging workouts and hitting daily quests."
        }
        if key.contains("complete_path") {
            return "The grand finale — complete the other 32 goals first."
        }
        if key.contains("calorie_") || key.contains("protein_") {
            return remaining > 0
                ? "Hit your daily target \(remaining) more day\(remaining == 1 ? "" : "s")."
                : "Stay on target every day to keep this moving."
        }
        if key.contains("hydration_") {
            return remaining > 0
                ? "Hit your hydration goal \(remaining) more day\(remaining == 1 ? "" : "s")."
                : "Hit your daily hydration goal to progress this."
        }
        if key.contains("cardio_") || key.contains("distance_") || key.contains("5k") {
            return remaining > 0
                ? "Get out there — \(remaining) to go."
                : "Each cardio session moves this forward."
        }
        if key.contains("pr_") {
            return remaining > 0
                ? "Set \(remaining) more personal record\(remaining == 1 ? "" : "s") to unlock this."
                : "Beat a previous best to log a new PR."
        }
        if key.contains("won_challenge") {
            return "Start a 1:1 challenge with a friend and finish on top to unlock this."
        }
        if key.contains("send_challenge") {
            return "Tap Challenges → Start a Challenge to send your first."
        }
        if key.contains("first_friend") || key.contains("friends_") {
            return "Add friends from the Friends tab — invite via contacts or shared link."
        }
        if key.contains("program_") || key.contains("complete_prog") {
            return "Open the Programs tab and finish a program. Multiple programs count toward higher milestones."
        }
        if key.contains("quest_") {
            return remaining > 0
                ? "Complete a daily quest \(remaining) more day\(remaining == 1 ? "" : "s") to keep this streak alive."
                : "Tap into Daily Quests to keep building your streak."
        }
        if key.contains("connect") {
            return "Connect Strava or Apple Health Running in Settings → Integrations to unlock outdoor cardio goals."
        }
        // Generic fallback
        return goal.description
    }

    /// Optional CTA per goal — opens the relevant source surface so the user
    /// can take action immediately. Returns nil when no surface exists for
    /// the goal (e.g., the meta goal #33 has no useful CTA).
    ///
    /// Tab navigation goes through the canonical `WorkoutManager` triggers
    /// (`shouldNavigateToWorkoutTab` etc.) which are observed by
    /// `MainTabView.applyNavigationTriggers`. For tabs without an existing
    /// flag (Friends, Nutrition), the CTA is omitted — the user closes the
    /// sheet and navigates manually. Adding new triggers is out of scope.
    private var ctaForGoal: (label: String, icon: String, action: () -> Void)? {
        let key = goal.achievementKey

        if key.contains("complete_path") {
            return nil // meta — no CTA
        }

        if key.contains("workouts_") || key.contains("first_workout") || key.contains("first_lift")
            || key.contains("all_muscles") || key.contains("first_pr") || key.contains("str_") {
            return ("Start a Workout", "dumbbell.fill", {
                onClose()
                WorkoutManager.shared.shouldNavigateToWorkoutTab = true
            })
        }
        if key.contains("cardio_") || key.contains("distance_") || key.contains("5k")
            || key.contains("first_cardio") || key.contains("end_") {
            return ("Open Workout Tab", "figure.run", {
                onClose()
                WorkoutManager.shared.shouldNavigateToWorkoutTab = true
            })
        }
        if key.contains("program_") || key.contains("complete_prog") {
            return ("Browse Programs", "list.bullet.clipboard.fill", {
                onClose()
                WorkoutManager.shared.shouldNavigateToPrograms = true
            })
        }
        if key.contains("meals_") || key.contains("first_meal") || key.contains("calorie_")
            || key.contains("protein_") || key.contains("macros_") || key.contains("hydration_")
            || key.contains("wl_") {
            return ("Open Meals", "fork.knife", {
                onClose()
                WorkoutManager.shared.shouldNavigateToMealsTab = true
            })
        }
        return nil
    }
}
