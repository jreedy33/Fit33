//
//  ChallengeDetailKit.swift
//  Fit33
//
//  Shared visual components reused by all four challenge-detail
//  surfaces (1v1 ChallengeDetailView, PrivateChallengeDetailView,
//  GroupChallengeDetailView, CommunityDetailView). Single source of
//  truth for the detail-page brand language so every surface looks
//  like the same product instead of four sibling apps.
//
//  Per DESIGN_AGENT.md: every component uses `.ds_*` typography,
//  `Spacing.*` / `CornerRadius.*` tokens, `.sleekCard()` for primary
//  content, gold-only crowns, and accepts a `typeColor` / `gradient`
//  pair so the surface brand-matches the challenge type (steps green,
//  lift purple, run orange, hydrate cyan, etc.).
//
//  Per PE invariant 9: components NEVER subscribe to services as
//  `@StateObject` from inside a row body — parent detail views own
//  the subscriptions and pass stable values down.
//
//  Components exported:
//    • ChallengeHeroCard       — title, emoji, DESCRIPTION, time pill
//    • ParticipantPodium       — 1v1 head-to-head with crown pulse
//    • LeaderboardRow          — used by group / private / community
//    • LeaderboardPodium       — Olympic top-3 layout for community
//    • TodayProgressCard       — dual-bar today's progress
//    • StatChipRow / StatChip  — horizontally scrollable stat strip
//

import SwiftUI

// MARK: - Hero Card

/// Top-of-page hero. Renders the challenge title, type emoji, optional
/// description, and a time pill ("Day X of Y · ends MMM d") inside a
/// type-color-accented sleek card. Description is the single biggest
/// "on-brand" win — three of four detail surfaces never showed it
/// before this kit.
struct ChallengeHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let emoji: String
    let typeColor: Color
    let gradient: [Color]
    let typeLabel: String?
    let description: String?
    let daysElapsed: Int
    let durationDays: Int
    let daysRemaining: Int
    let endDate: Date?
    let memberCountSuffix: String?

    init(
        title: String,
        emoji: String,
        typeColor: Color,
        gradient: [Color],
        typeLabel: String? = nil,
        description: String? = nil,
        daysElapsed: Int,
        durationDays: Int,
        daysRemaining: Int,
        endDate: Date? = nil,
        memberCountSuffix: String? = nil
    ) {
        self.title = title
        self.emoji = emoji
        self.typeColor = typeColor
        self.gradient = gradient
        self.typeLabel = typeLabel
        self.description = description
        self.daysElapsed = daysElapsed
        self.durationDays = durationDays
        self.daysRemaining = daysRemaining
        self.endDate = endDate
        self.memberCountSuffix = memberCountSuffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                        .opacity(colorScheme == .dark ? 0.22 : 0.16)
                    Text(emoji)
                        .font(.ds_heading2)
                }

                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    if let typeLabel = typeLabel {
                        Text(typeLabel.uppercased())
                            .font(.ds_labelSmall)
                            .tracking(0.6)
                            .foregroundColor(typeColor)
                    }

                    Text(title)
                        .font(.ds_heading3)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let description = description, !description.isEmpty {
                Text(description)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.xs) {
                if durationDays > 0 {
                    pill(icon: "calendar", text: dayProgressText, tint: typeColor)

                    if daysRemaining > 0 {
                        pill(
                            icon: "clock",
                            text: "\(daysRemaining)d left",
                            tint: daysRemaining <= 1 ? .red : .secondary
                        )
                    } else {
                        pill(icon: "checkmark.seal.fill", text: "Complete", tint: .green)
                    }
                }

                if let suffix = memberCountSuffix {
                    pill(icon: "person.2.fill", text: suffix, tint: .secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: typeColor)
    }

    private var dayProgressText: String {
        let bounded = max(0, min(daysElapsed, durationDays))
        return "Day \(bounded) of \(durationDays)"
    }

    @ViewBuilder
    private func pill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.ds_caption)
            Text(text)
                .font(.ds_labelSmall)
        }
        .foregroundColor(tint)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxxs)
        .background(Capsule().fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.10)))
    }
}

// MARK: - Participant Podium (1v1)

/// Big head-to-head card for 1v1 challenges. 88pt avatars (was 56),
/// `ds_displayMedium` numbers (was `ds_stat` 24pt), animated crown
/// pulse on the leader (gold-only per DESIGN_SYSTEM #5). Decorative
/// pulse gates on `accessibilityReduceMotion` + `isLowPowerMode`.
struct ParticipantPodium: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let myImage: UIImage?
    let myName: String
    let myValueText: String
    let opponentId: String
    let opponentName: String
    let opponentPhotoUrl: String?
    let opponentValueText: String
    let opponentIsVerified: Bool
    let opponentIsGoldVerified: Bool
    let amWinning: Bool
    let leadDelta: String?
    let typeColor: Color
    let gradient: [Color]
    let opponentFreshness: ProgressFreshness
    let opponentAgeLabel: String?

    @State private var crownPulse = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: 0) {
                participantColumn(
                    image: myImage,
                    name: myName,
                    valueText: myValueText,
                    isLeading: amWinning,
                    fallbackInitial: String(myName.prefix(1)),
                    photoView: nil,
                    isVerified: false,
                    isGoldVerified: false,
                    freshness: .fresh,
                    ageLabel: nil
                )
                .frame(maxWidth: .infinity)

                vsColumn

                participantColumn(
                    image: nil,
                    name: opponentName,
                    valueText: opponentValueText,
                    isLeading: !amWinning && opponentValueText != "—",
                    fallbackInitial: String(opponentName.prefix(1)),
                    photoView: AnyView(
                        CachedFriendPhoto(
                            friendId: opponentId,
                            photoUrl: opponentPhotoUrl,
                            name: opponentName,
                            size: 88,
                            showGradientRing: true,
                            gradientColors: gradient
                        )
                    ),
                    isVerified: opponentIsVerified,
                    isGoldVerified: opponentIsGoldVerified,
                    freshness: opponentFreshness,
                    ageLabel: opponentAgeLabel
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: typeColor)
        .onAppear {
            guard !shouldDisableMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                crownPulse = true
            }
        }
    }

    private var shouldDisableMotion: Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @ViewBuilder
    private func participantColumn(
        image: UIImage?,
        name: String,
        valueText: String,
        isLeading: Bool,
        fallbackInitial: String,
        photoView: AnyView?,
        isVerified: Bool,
        isGoldVerified: Bool,
        freshness: ProgressFreshness,
        ageLabel: String?
    ) -> some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                if let photoView = photoView {
                    photoView
                } else if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 3
                            )
                        )
                } else {
                    Circle()
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                        .overlay(
                            Text(fallbackInitial.uppercased())
                                .font(.ds_heading1)
                                .foregroundColor(.white)
                        )
                }

                if isLeading {
                    Image(systemName: "crown.fill")
                        .font(.ds_heading3)
                        .foregroundColor(.yellow)
                        .scaleEffect(crownPulse ? 1.12 : 1.0)
                        .offset(y: -52)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 3) {
                Text(name)
                    .font(.ds_labelSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if isVerified || isGoldVerified {
                    VerifiedBadge(size: 10, isGold: isGoldVerified)
                }
            }

            Text(valueText)
                .font(.ds_displayMedium)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(
                    isLeading
                        ? AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.primary)
                )

            if let ageLabel = ageLabel, freshness != .fresh {
                Text(ageLabel)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(valueText)\(isLeading ? ", leading" : "")")
    }

    private var vsColumn: some View {
        VStack(spacing: Spacing.xxs) {
            Text("VS")
                .font(.ds_labelLarge)
                .foregroundStyle(LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom))

            if let delta = leadDelta {
                Text(delta)
                    .font(.ds_labelSmall)
                    .foregroundColor(amWinning ? .green : .red)
            }
        }
        .frame(width: 44)
    }
}

// MARK: - Today Progress Card

/// Single-source today's-progress card used by 1v1, group, community.
/// Bigger numbers (`ds_statSmall`), thicker bars (10pt), checkmark badge
/// when target hit, freshness pill on opponent. When `opponentName` is
/// nil, renders a single-row layout (group/community usage).
struct TodayProgressCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let myValue: Int
    let myValueText: String
    let opponentName: String?
    let opponentValue: Int
    let opponentValueText: String
    let target: Int
    let targetUnit: String
    let typeColor: Color
    let gradient: [Color]
    let leaderTitle: String
    let opponentFreshness: ProgressFreshness
    let opponentAgeLabel: String?

    private var myPercent: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(myValue) / Double(target))
    }

    private var oppPercent: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(opponentValue) / Double(target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "bolt.circle.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Today")
                    .font(.ds_heading3)
                    .foregroundColor(.primary)

                Spacer()

                Text(leaderTitle)
                    .font(.ds_caption)
                    .foregroundColor(myPercent >= oppPercent ? .green : .orange)
            }

            progressRow(
                name: "You",
                valueText: myValueText,
                percent: myPercent,
                isMe: true,
                showFreshness: false
            )

            if let opponentName = opponentName {
                progressRow(
                    name: opponentName,
                    valueText: opponentValueText,
                    percent: oppPercent,
                    isMe: false,
                    showFreshness: opponentFreshness != .fresh
                )
            }
        }
        .padding(Spacing.md)
        .sleekCardSubtle(cornerRadius: CornerRadius.lg)
    }

    @ViewBuilder
    private func progressRow(name: String, valueText: String, percent: Double, isMe: Bool, showFreshness: Bool) -> some View {
        VStack(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xxs) {
                Text(name)
                    .font(.ds_labelSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if showFreshness, let age = opponentAgeLabel {
                    Text(age)
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(valueText.isEmpty ? "—" : "\(valueText) / \(target.formatted())")
                    .font(.ds_labelMedium)
                    .foregroundColor(percent >= 1.0 ? .green : (isMe ? typeColor : .primary))

                if percent >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_caption)
                        .foregroundColor(.green)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 10)
                    Capsule()
                        .fill(
                            isMe
                                ? AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                        )
                        .frame(width: geo.size.width * percent, height: 10)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: percent)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(valueText), \(Int(percent * 100)) percent of target")
    }
}

// MARK: - Stat Chip Row

/// Horizontally scrollable chip strip. Each chip shows a `ds_statSmall`
/// value over a `ds_caption` label, optionally with an SF symbol icon.
/// Replaces the cramped 4-cell stat bar that used to sit beneath the
/// head-to-head card.
struct StatChipRow: View {
    let chips: [StatChip]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(chips) { chip in
                    chip.view
                }
            }
            .padding(.horizontal, Spacing.xxs)
        }
    }
}

struct StatChip: View, Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let icon: String?
    let tint: Color

    init(value: String, label: String, icon: String? = nil, tint: Color = .primary) {
        self.value = value
        self.label = label
        self.icon = icon
        self.tint = tint
    }

    var view: AnyView { AnyView(self) }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.ds_caption)
                        .foregroundColor(tint)
                }
                Text(value)
                    .font(.ds_statSmall)
                    .foregroundColor(tint == .primary ? .primary : tint)
            }
            Text(label.uppercased())
                .font(.ds_caption)
                .tracking(0.4)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Leaderboard Row

/// Used by group, private, and community detail views. Top-3 get medal
/// emojis; "me" row gets a soft accent wash; thin progress bar under
/// the row when a daily target exists; gradient ring on rank-1 avatar.
struct LeaderboardRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let rank: Int
    let userId: String
    let displayName: String
    let photoUrl: String?
    let valueText: String
    let progress: Double?
    let isMe: Bool
    let typeColor: Color
    let gradient: [Color]
    let trailingBadge: String?
    let isVerified: Bool
    let isGoldVerified: Bool

    init(
        rank: Int,
        userId: String,
        displayName: String,
        photoUrl: String?,
        valueText: String,
        progress: Double? = nil,
        isMe: Bool,
        typeColor: Color,
        gradient: [Color],
        trailingBadge: String? = nil,
        isVerified: Bool = false,
        isGoldVerified: Bool = false
    ) {
        self.rank = rank
        self.userId = userId
        self.displayName = displayName
        self.photoUrl = photoUrl
        self.valueText = valueText
        self.progress = progress
        self.isMe = isMe
        self.typeColor = typeColor
        self.gradient = gradient
        self.trailingBadge = trailingBadge
        self.isVerified = isVerified
        self.isGoldVerified = isGoldVerified
    }

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.sm) {
                rankBadge

                CachedFriendPhoto(
                    friendId: userId,
                    photoUrl: photoUrl,
                    name: displayName,
                    size: 36,
                    showGradientRing: rank == 1,
                    gradientColors: gradient
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(isMe ? "You" : displayName)
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if isVerified || isGoldVerified {
                            VerifiedBadge(size: 10, isGold: isGoldVerified)
                        }

                        if isMe {
                            Text("YOU")
                                .font(.ds_caption)
                                .tracking(0.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, Spacing.xxs)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(typeColor))
                        }
                    }

                    if let badge = trailingBadge {
                        Text(badge)
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Text(valueText.isEmpty ? "—" : valueText)
                    .font(.ds_statSmall)
                    .foregroundStyle(
                        rank == 1
                            ? AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.primary)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let progress = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(1.0, max(0, progress)), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(isMe ? typeColor.opacity(colorScheme == .dark ? 0.14 : 0.08) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(isMe ? "you" : displayName), \(valueText)")
    }

    @ViewBuilder
    private var rankBadge: some View {
        ZStack {
            switch rank {
            case 1:
                Text("🥇")
                    .font(.ds_heading3)
            case 2:
                Text("🥈")
                    .font(.ds_heading3)
            case 3:
                Text("🥉")
                    .font(.ds_heading3)
            default:
                Text("#\(rank)")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 32)
    }
}

// MARK: - Leaderboard Podium (Olympic top-3)

/// Olympic-style podium for community leaderboards. 1st in the center
/// (biggest), 2nd on the left, 3rd on the right. Each gets a gold /
/// silver / bronze gradient ring. Used in CommunityDetailView above
/// the leaderboard list.
struct LeaderboardPodium: View {
    let entries: [LeaderboardPodiumEntry]
    let typeColor: Color
    let gradient: [Color]

    private static let goldRing: [Color] = [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.65, blue: 0.1)]
    private static let silverRing: [Color] = [Color(white: 0.85), Color(white: 0.65)]
    private static let bronzeRing: [Color] = [Color(red: 0.85, green: 0.55, blue: 0.30), Color(red: 0.55, green: 0.30, blue: 0.15)]

    var body: some View {
        let first = entries.first(where: { $0.rank == 1 })
        let second = entries.first(where: { $0.rank == 2 })
        let third = entries.first(where: { $0.rank == 3 })

        HStack(alignment: .bottom, spacing: Spacing.sm) {
            podiumColumn(entry: second, height: 56, ring: Self.silverRing, medal: "🥈")
            podiumColumn(entry: first, height: 80, ring: Self.goldRing, medal: "🥇")
            podiumColumn(entry: third, height: 44, ring: Self.bronzeRing, medal: "🥉")
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: typeColor)
    }

    @ViewBuilder
    private func podiumColumn(entry: LeaderboardPodiumEntry?, height: CGFloat, ring: [Color], medal: String) -> some View {
        VStack(spacing: Spacing.xs) {
            if let entry = entry {
                Text(medal)
                    .font(.ds_heading2)

                CachedFriendPhoto(
                    friendId: entry.userId,
                    photoUrl: entry.photoUrl,
                    name: entry.displayName,
                    size: entry.rank == 1 ? 64 : 52,
                    showGradientRing: true,
                    gradientColors: ring
                )

                Text(entry.displayName)
                    .font(.ds_labelSmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(entry.valueText)
                    .font(.ds_labelMedium)
                    .foregroundStyle(
                        entry.rank == 1
                            ? AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.primary)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 52, height: 52)
            }

            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(LinearGradient(colors: ring, startPoint: .top, endPoint: .bottom).opacity(0.55))
                .frame(height: height)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.map { "\($0.rank == 1 ? "First place" : ($0.rank == 2 ? "Second place" : "Third place")), \($0.displayName), \($0.valueText)" }
                ?? "Empty podium spot"
        )
    }
}

struct LeaderboardPodiumEntry: Identifiable {
    let id = UUID()
    let rank: Int
    let userId: String
    let displayName: String
    let photoUrl: String?
    let valueText: String
}
