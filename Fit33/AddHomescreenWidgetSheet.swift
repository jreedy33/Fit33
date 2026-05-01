//
//  AddHomescreenWidgetSheet.swift
//  Fit33
//
//  Step-by-step guide for adding the active-challenge widget to the
//  iOS home screen. iOS does NOT expose any public URL scheme or API
//  for programmatically adding a widget or opening the widget gallery
//  for a specific app, so the best UX we can ship is a clear, visual
//  instructional sheet. (As of iOS 18.) See:
//    • `WidgetCenter` — only `reloadTimelines` / `getCurrentConfigurations`,
//      no install affordance.
//    • Apple's HIG explicitly says widget discovery is system-driven.
//
//  Lifecycle:
//    • Presented from `ChallengeDetailView`'s top-of-screen CTA.
//    • Dismisses via the `Done` button or sheet drag.
//
//  Redesign 2026-04-30 (per user feedback "bulky and generic"):
//    • Replaced the chunky orange/red gradient avatar header with a
//      contextual live preview that mirrors what the user's widget
//      will actually render — challenge name, type emoji, opponent
//      avatar, today's progress vs. opponent, days remaining. The
//      preview makes the purpose self-evident; no marketing-style
//      hero blurb required.
//    • Slimmed numbered-step rows from 32pt accent circles to a
//      single flat "01 ·" prefix in the challenge's type color. Less
//      visual noise per step → easier to scan five steps at once.
//    • Replaced the heavy yellow "Pro tip" card with a single inline
//      tip line at the bottom. Same information, ~70% less ink.
//

import SwiftUI

// MARK: - Instructional Sheet

struct AddHomescreenWidgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// When provided, the preview at the top renders the user's actual
    /// active challenge so they recognize the widget when it appears on
    /// their home screen. Nil falls back to a neutral placeholder so
    /// SwiftUI previews and any future call sites without a challenge
    /// in hand still work.
    let challenge: ActiveChallenge?

    init(challenge: ActiveChallenge? = nil) {
        self.challenge = challenge
    }

    private var accentColor: Color {
        challenge?.resolvedType.color ?? .accentColor
    }

    private var accentGradient: [Color] {
        challenge?.resolvedType.gradientColors ?? [.accentColor, .accentColor]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    previewCard
                    stepsSection
                    inlineTip
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)
            }
            .navigationTitle("Add to Home Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Live preview

    /// Mirrors the widget's actual layout in miniature so the user
    /// pattern-matches the moment they see it on their home screen.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionLabel("Preview")

            VStack(spacing: Spacing.sm) {
                if let challenge = challenge {
                    livePreview(for: challenge)
                } else {
                    placeholderPreview
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(accentColor.opacity(colorScheme == .dark ? 0.25 : 0.18), lineWidth: 1)
            )
            .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 14, x: 0, y: 6)
        }
    }

    @ViewBuilder
    private func livePreview(for challenge: ActiveChallenge) -> some View {
        let resolver = ChallengeProgressResolver.shared
        let myValue = resolver.liveProgress(for: challenge)
        let oppValue = challenge.opponentTodayProgress ?? 0
        let resolvedType = challenge.resolvedType
        let myFormatted = resolver.formatValue(myValue, unit: challenge.targetUnit, type: resolvedType)
        let oppFormatted = resolver.formatValue(oppValue, unit: challenge.targetUnit, type: resolvedType)
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Opponent"
        let percent = resolver.progressPercentage(for: challenge)
        let amWinningToday = challenge.amWinningToday ?? challenge.amWinning

        VStack(spacing: Spacing.sm) {
            // Title row — type emoji + name + days remaining
            HStack(spacing: Spacing.xs) {
                Text(resolvedType.emoji)
                    .font(.system(size: 22))
                Text(challenge.displayTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                if challenge.daysRemaining > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(challenge.daysRemaining)d left")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }

            // Head-to-head row — me vs opponent today
            HStack(spacing: Spacing.sm) {
                participantTile(
                    name: "You",
                    value: myFormatted,
                    photo: nil,
                    fallbackName: "You",
                    isLeading: amWinningToday,
                    gradient: accentGradient
                )

                VStack(spacing: 2) {
                    Text("vs")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(width: 24)

                participantTile(
                    name: opponentFirst,
                    value: oppFormatted,
                    photo: AnyView(
                        CachedFriendPhoto(
                            friendId: challenge.opponentId.uuidString,
                            photoUrl: challenge.opponentPhotoUrl,
                            name: challenge.opponentName ?? opponentFirst,
                            size: 36,
                            showGradientRing: !amWinningToday,
                            gradientColors: accentGradient
                        )
                    ),
                    fallbackName: opponentFirst,
                    isLeading: !amWinningToday && oppValue > 0,
                    gradient: [.orange, .red]
                )
            }

            // Progress bar — your daily target completion
            if challenge.dailyTarget != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * percent, height: 5)
                    }
                }
                .frame(height: 5)
            }

            // Caption — what the widget shows
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Live on your home screen")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholderPreview: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("🏆")
                    .font(.system(size: 22))
                Text("Your active challenge")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
            }
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Live on your home screen")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func participantTile(
        name: String,
        value: String,
        photo: AnyView?,
        fallbackName: String,
        isLeading: Bool,
        gradient: [Color]
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            ZStack {
                if let photo = photo {
                    photo
                } else {
                    Circle()
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(fallbackName.prefix(1)).uppercased())
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                }
                if isLeading {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                        .offset(y: -22)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.heavy)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionLabel("Add it in 4 steps")

            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(number: index + 1, step: step)
                }
            }
        }
    }

    private func stepRow(number: Int, step: Step) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(String(format: "%02d", number))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: accentGradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 26, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(step.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Inline tip

    private var inlineTip: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.yellow)
                .padding(.top, 2)
            Text("Long-press the widget after adding to switch challenges, or stack multiple — one per challenge.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.xxs)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundColor(.secondary)
            .padding(.leading, 2)
    }

    // MARK: - Step content

    private struct Step {
        let title: String
        let body: String
    }

    private static let steps: [Step] = [
        Step(
            title: "Long-press your home screen",
            body: "Touch and hold an empty area until the apps start jiggling."
        ),
        Step(
            title: "Tap the + in the top-left",
            body: "Opens the widget gallery."
        ),
        Step(
            title: "Search \"Fit33\" → Active Challenge",
            body: "Pick a size, then tap Add Widget."
        ),
        Step(
            title: "Tap Done",
            body: "Your live score and any incoming reactions will appear automatically."
        )
    ]
}

#Preview("With challenge") {
    AddHomescreenWidgetSheet(
        challenge: ActiveChallenge(
            challengeId: UUID(),
            challengeType: "steps",
            title: "10K Step Showdown",
            description: nil,
            dailyTarget: 10_000,
            totalTarget: nil,
            targetUnit: "steps",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 5),
            durationDays: 7,
            daysElapsed: 2,
            daysRemaining: 5,
            status: "active",
            myTotalProgress: 28_500,
            myTodayProgress: 7_842,
            myDaysCompleted: 2,
            myCurrentStreak: 2,
            opponentId: UUID(),
            opponentName: "Alex Park",
            opponentUsername: nil,
            opponentPhotoUrl: nil,
            opponentTotalProgress: 25_000,
            opponentTodayProgress: 6_510,
            opponentDaysCompleted: 2,
            amWinning: true,
            amWinningToday: true
        )
    )
}

#Preview("No challenge (fallback)") {
    AddHomescreenWidgetSheet()
}
