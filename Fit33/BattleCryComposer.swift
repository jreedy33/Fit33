//
//  BattleCryComposer.swift
//  Fit33
//
//  Inline one-tap composer + realtime animated reactive feed for the
//  Battle Cry system. Replaces the chevron-row "Send a Battle Cry"
//  CTA and the static `ReactionFeedView` bubble stack on the four
//  challenge-detail surfaces.
//
//  Two components, one design language:
//    • BattleCryStrip   — horizontal row of 5 quick-tap emoji buttons
//                         + trailing "..." for the full picker. Single
//                         tap = haptic + animated pulse + send.
//    • ReactiveBattleFeed — animated bubble feed; new bubbles enter
//                         with a spring scale+move transition and an
//                         optional confetti burst. Real-time insert
//                         driven by RealtimeService.onChallengeReactionReceived.
//
//  Composition is host-driven: the host view passes a `BattleCrySend`
//  closure so the same strip/feed components work for 1v1, group, and
//  community surfaces (each has a different recipient + RPC).
//
//  Per DESIGN_AGENT.md Animation table:
//    • Button press 0.15s easeInOut (UniversalScaleButtonStyle).
//    • Bubble enter spring response 0.45 dampingFraction 0.65.
//    • Confetti ≤700ms one-shot.
//  All decorative motion gated on `accessibilityReduceMotion` +
//  `ProcessInfo.isLowPowerModeEnabled` per DESIGN_SYSTEM_AGENT #4.
//

import SwiftUI

// MARK: - Mode

enum BattleCryMode {
    case competition     // smack-talk presets
    case accountability  // hype presets
    case community       // encouragement presets

    var presets: [ReactionPreset] {
        switch self {
        case .competition:    return ReactionPresets.trashTalk
        case .accountability: return ReactionPresets.cheers
        case .community:      return ReactionPresets.communityEncouragement
        }
    }

    var quickPresets: [ReactionPreset] {
        Array(presets.prefix(5))
    }

    var openCTA: String {
        switch self {
        case .competition:    return "Talk Smack"
        case .accountability: return "Send Hype"
        case .community:      return "Send Hype"
        }
    }

    var icon: String {
        switch self {
        case .competition:    return "flame.fill"
        case .accountability: return "bolt.heart.fill"
        case .community:      return "sparkles"
        }
    }

    var title: String {
        switch self {
        case .competition:    return "Battle Cries"
        case .accountability: return "Hype Feed"
        case .community:      return "Cheer Feed"
        }
    }

    var emptyEmoji: String {
        switch self {
        case .competition:    return "🤐"
        default:              return "💬"
        }
    }

    var emptyTitle: String {
        switch self {
        case .competition:    return "No smack talk yet"
        case .community:      return "No cheers yet"
        case .accountability: return "No messages yet"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .competition:    return "Be the first to fire a shot"
        case .community:      return "Cheer someone on"
        case .accountability: return "Send some hype"
        }
    }
}

// MARK: - Inline Composer

/// Single-row inline composer. 5 quick-tap emojis, type-color tinted,
/// plus a trailing "more" button that opens the full picker sheet.
/// The host owns the actual send call via the `onSend` closure so the
/// same component works across 1v1, group, and community surfaces.
struct BattleCryStrip: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mode: BattleCryMode
    let typeColor: Color
    let gradient: [Color]
    let onSend: (ReactionPreset) -> Void
    let onOpenPicker: () -> Void

    @State private var pulsedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: mode.icon)
                    .font(.ds_caption)
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))

                Text(mode.openCTA.uppercased())
                    .font(.ds_labelSmall)
                    .tracking(0.6)
                    .foregroundColor(.secondary)

                Spacer()
            }

            HStack(spacing: Spacing.xs) {
                ForEach(mode.quickPresets) { preset in
                    quickButton(preset)
                }

                Spacer(minLength: 0)

                Button {
                    HapticManager.impact(.light)
                    onOpenPicker()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.cardBackground)
                                .overlay(Circle().stroke(typeColor.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More battle cries")
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(typeColor.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func quickButton(_ preset: ReactionPreset) -> some View {
        let isPulsing = pulsedKey == preset.id

        Button {
            HapticManager.notification(.success)
            onSend(preset)
            triggerPulse(preset.id)
        } label: {
            Text(preset.emoji)
                .font(.ds_heading3)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(colorScheme == .dark ? 0.22 : 0.14))
                )
                .overlay(
                    Circle()
                        .stroke(typeColor.opacity(0.25), lineWidth: 1)
                )
                .scaleEffect(isPulsing ? 1.18 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send \(preset.text)")
    }

    private func triggerPulse(_ key: String) {
        guard !shouldDisableMotion else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            pulsedKey = key
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                pulsedKey = nil
            }
        }
    }

    private var shouldDisableMotion: Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

// MARK: - Quick open (compact surfaces)

/// Capsule that teases the latest **incoming** reaction or a default
/// battle-cry affordance. Opens the host's full picker via
/// `showingPicker`. Replaces the deleted `ReactionQuickButton` from
/// `ChallengeReactionsView.swift` so widget / dashboard rows stay on
/// the same kit path as `BattleCryStrip` + `BattleCryPickerSheet`.
struct BattleCryQuickOpenButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let challenge: ActiveChallenge
    @Binding var showingPicker: Bool

    @State private var latestReaction: ChallengeReaction?
    @State private var pulseAnimation = false

    private var mode: ChallengeMode { challenge.mode }
    private var isCompetition: Bool { mode == .competition }

    private var themeGradient: [Color] {
        isCompetition ? [.orange, .red] : [.blue, .cyan]
    }

    private var themeColor: Color {
        isCompetition ? .orange : .cyan
    }

    var body: some View {
        Button {
            HapticManager.impact(.light)
            showingPicker = true
        } label: {
            HStack(spacing: Spacing.xxs) {
                if let reaction = latestReaction, !reaction.isMine {
                    Text(reaction.reactionEmoji)
                        .font(.ds_bodySmall)
                    Text(reaction.reactionText)
                        .font(.ds_caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Image(systemName: isCompetition ? "flame.fill" : "bolt.heart.fill")
                        .font(.ds_bodySmall)
                        .foregroundStyle(
                            LinearGradient(colors: themeGradient, startPoint: .leading, endPoint: .trailing)
                        )
                    Text(isCompetition ? "Talk Smack" : "Send Hype")
                        .font(.ds_caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
            )
            .overlay(
                Capsule()
                    .stroke(themeColor.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(pulseAnimation ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompetition ? "Open battle cry picker" : "Open hype picker")
        .task {
            let reactions = await ChallengeService.shared.fetchReactions(challengeId: challenge.challengeId, limit: 1)
            if let latest = reactions.first {
                latestReaction = latest
                if !latest.isMine {
                    withAnimation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true)) {
                        pulseAnimation = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2.5))
                        guard !Task.isCancelled else { return }
                        pulseAnimation = false
                    }
                }
            }
        }
    }
}

// MARK: - Reactive Feed

/// Animated bubble feed. The host loads the initial `reactions`
/// snapshot and pushes new ones in as they arrive (either via the
/// `RealtimeService.onChallengeReactionReceived` callback or
/// optimistic local inserts on send). Newest at the top; capped at
/// `maxVisible` (12) to keep the surface scannable.
///
/// `inboundFlash` is a counter that the host increments whenever a
/// REMOTE reaction lands; the feed reads it to drive the confetti
/// burst exactly once per arrival without re-firing on Swift's view
/// re-evaluation passes.
struct ReactiveBattleFeed: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mode: BattleCryMode
    let typeColor: Color
    let gradient: [Color]
    let reactions: [ChallengeReaction]
    let isLoading: Bool
    let inboundFlash: Int

    private let maxVisible = 12

    @State private var confettiCount = 0
    @State private var lastFlash = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: mode.icon)
                    .font(.ds_heading3)
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(mode.title)
                    .font(.ds_heading3)
                    .foregroundColor(.primary)

                Spacer()

                if !reactions.isEmpty {
                    Text("\(min(reactions.count, maxVisible))")
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxxs)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }

            ZStack(alignment: .top) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.85)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.lg)
                } else if reactions.isEmpty {
                    emptyState
                } else {
                    bubbleList
                }

                if confettiCount > 0 && !shouldDisableMotion {
                    BattleCryConfetti(burstId: confettiCount, gradient: gradient)
                        .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: inboundFlash) { _, newValue in
            guard newValue != lastFlash else { return }
            lastFlash = newValue
            triggerConfetti()
        }
    }

    private var bubbleList: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(Array(reactions.prefix(maxVisible))) { reaction in
                bubble(reaction)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4)
                            .combined(with: .opacity)
                            .combined(with: .move(edge: reaction.isMine ? .trailing : .leading)),
                        removal: .opacity
                    ))
            }
        }
        .padding(Spacing.sm)
        .sleekCardSubtle(cornerRadius: CornerRadius.lg)
        .animation(shouldDisableMotion ? nil : .spring(response: 0.45, dampingFraction: 0.65), value: reactions.map(\.id))
    }

    @ViewBuilder
    private func bubble(_ reaction: ChallengeReaction) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            if reaction.isMine {
                Spacer(minLength: Spacing.xl)
            } else {
                CachedFriendPhoto(
                    friendId: reaction.senderId.uuidString,
                    photoUrl: reaction.senderPhotoUrl,
                    name: reaction.senderName ?? "?",
                    size: 28,
                    showGradientRing: false,
                    gradientColors: gradient
                )
            }

            VStack(alignment: reaction.isMine ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if !reaction.isMine {
                        Text(reaction.senderFirstName)
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                    Text(reaction.timeAgo)
                        .font(.ds_caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }

                HStack(spacing: 6) {
                    Text(reaction.reactionEmoji)
                        .font(.ds_bodyRegular)
                    Text(reaction.reactionText)
                        .font(.ds_labelSmall)
                        .foregroundColor(reaction.isMine ? .white : .primary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(
                            reaction.isMine
                                ? AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.93))
                        )
                )
            }

            if !reaction.isMine {
                Spacer(minLength: Spacing.xl)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reaction.isMine ? "You" : reaction.senderFirstName) sent \(reaction.reactionText), \(reaction.timeAgo)")
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xs) {
            Text(mode.emptyEmoji)
                .font(.ds_heading1)

            Text(mode.emptyTitle)
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)

            Text(mode.emptySubtitle)
                .font(.ds_caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .sleekCardSubtle(cornerRadius: CornerRadius.lg)
    }

    private func triggerConfetti() {
        guard !shouldDisableMotion else { return }
        confettiCount += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            confettiCount = max(0, confettiCount - 1)
        }
    }

    private var shouldDisableMotion: Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

// MARK: - Battle Cry Picker Sheet

/// Host-driven full picker. Replaces `ReactionPickerSheet` (which was
/// hard-bound to `ActiveChallenge` and the 1v1 RPC) with a generic
/// surface that 1v1, group, and community detail views can all share.
/// The host owns the actual send call via `onSend` so the same sheet
/// works across every challenge type without leaking model details.
struct BattleCryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let mode: BattleCryMode
    let typeColor: Color
    let gradient: [Color]
    let recipientLabel: String
    let onSend: (ReactionPreset) -> Void

    @State private var pulsedKey: String?
    @State private var sentPreset: ReactionPreset?

    private var presets: [ReactionPreset] { mode.presets }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.md) {
                        header
                        grid
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.ds_labelLarge)
                }
            }
            .overlay(alignment: .center) {
                if let sent = sentPreset {
                    sentOverlay(sent)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: mode.icon)
                .font(.ds_displayMedium)
                .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))

            Text(mode.openCTA)
                .font(.ds_heading2)
                .foregroundColor(.primary)

            Text(headerSubtitle)
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.sm)
    }

    private var headerSubtitle: String {
        switch mode {
        case .competition:    return "Let \(recipientLabel) know who's boss"
        case .accountability: return "Hype up \(recipientLabel) to crush today"
        case .community:      return "Send some love to \(recipientLabel)"
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
            ForEach(presets) { preset in
                cell(preset)
            }
        }
    }

    @ViewBuilder
    private func cell(_ preset: ReactionPreset) -> some View {
        let isPulsing = pulsedKey == preset.id
        Button {
            HapticManager.notification(.success)
            sentPreset = preset
            onSend(preset)
            pulse(preset.id)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    sentPreset = nil
                }
                dismiss()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(preset.emoji)
                    .font(.ds_heading2)
                Text(preset.text)
                    .font(.ds_labelMedium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(typeColor.opacity(0.20), lineWidth: 1)
            )
            .scaleEffect(isPulsing ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send \(preset.text)")
    }

    private func pulse(_ key: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            pulsedKey = key
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                pulsedKey = nil
            }
        }
    }

    private func sentOverlay(_ preset: ReactionPreset) -> some View {
        VStack(spacing: Spacing.sm) {
            Text(preset.emoji)
                .font(.system(size: 64))
            Text("Sent")
                .font(.ds_heading3)
                .foregroundColor(.white)
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: typeColor.opacity(0.4), radius: 20)
        )
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Confetti Burst

/// Lightweight one-shot confetti. ≤16 particles, no third-party libs,
/// ≤700ms total animation. Strictly gated on accessibility + low-power
/// settings by the caller — this view itself just renders.
struct BattleCryConfetti: View {
    let burstId: Int
    let gradient: [Color]

    private static let particleCount = 16
    private static let particleSize: CGFloat = 6

    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<Self.particleCount, id: \.self) { i in
                Circle()
                    .fill(gradient[i % gradient.count])
                    .frame(width: Self.particleSize, height: Self.particleSize)
                    .offset(
                        x: animate ? offset(for: i).x : 0,
                        y: animate ? offset(for: i).y : 0
                    )
                    .opacity(animate ? 0 : 1)
                    .scaleEffect(animate ? 0.5 : 1.0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                animate = true
            }
        }
        .id(burstId)
    }

    private func offset(for index: Int) -> CGPoint {
        let angle = (Double(index) / Double(Self.particleCount)) * 2 * .pi
        let radius: CGFloat = 70
        return CGPoint(
            x: CGFloat(cos(angle)) * radius,
            y: CGFloat(sin(angle)) * radius - 20
        )
    }
}
