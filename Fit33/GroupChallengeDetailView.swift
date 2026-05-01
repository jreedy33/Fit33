import SwiftUI

struct GroupChallengeDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var challengeService = ChallengeService.shared

    let challenge: ActiveGroupChallenge

    @State private var showingLeaveConfirm = false
    @State private var showingCancelConfirm = false
    @State private var isProcessing = false

    // Battle Cry overhaul (2026-04-30) — Phase 4 realtime state.
    // Owned by the parent view per PE invariant 9 so the
    // `ReactiveBattleFeed` row never subscribes to RealtimeService
    // itself. Initial snapshot loaded by `loadReactions()`; subsequent
    // INSERTs streamed in via `RealtimeService.subscribeChallengeReactions`.
    @State private var reactions: [ChallengeReaction] = []
    @State private var reactionsLoading: Bool = true
    @State private var reactionsInboundFlash: Int = 0
    @State private var showingBattleCryPicker = false

    /// Live version of the challenge from the service (updates when fetchActiveGroupChallenges runs)
    private var liveChallenge: ActiveGroupChallenge {
        challengeService.activeGroupChallenges.first(where: { $0.challengeId == challenge.challengeId }) ?? challenge
    }

    private var sortedMembers: [GroupChallengeMember] {
        let currentUserId = SupabaseManager.shared.currentUser?.id
        let resolver = ChallengeProgressResolver.shared
        return (liveChallenge.members ?? []).sorted { m1, m2 in
            let p1 = m1.userId == currentUserId
                ? resolver.liveProgress(for: liveChallenge, serverValue: m1.todayProgress)
                : m1.todayProgress
            let p2 = m2.userId == currentUserId
                ? resolver.liveProgress(for: liveChallenge, serverValue: m2.todayProgress)
                : m2.todayProgress
            return p1 > p2
        }
    }

    private var acceptedMembers: [GroupChallengeMember] {
        sortedMembers.filter(\.isAccepted)
    }

    private var pendingMembers: [GroupChallengeMember] {
        sortedMembers.filter(\.isPending)
    }

    private var isAccountability: Bool {
        challenge.challengeMode == .accountability
    }

    private var resolvedType: ChallengeType { challenge.resolvedType }
    private var typeColor: Color { resolvedType.color }
    private var typeGradientColors: [Color] { resolvedType.gradientColors }
    private var typeGradient: LinearGradient {
        LinearGradient(colors: typeGradientColors, startPoint: .leading, endPoint: .trailing)
    }

    private var battleCryMode: BattleCryMode {
        // Group hype lives between competition (1v1 smack) and community
        // (broadcast cheer). Accountability mode borrows the hype/cheer
        // pool so non-competitive groups don't get smack-talk presets.
        isAccountability ? .accountability : .competition
    }

    var body: some View {
        ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.md) {
                    heroCard
                    statChips
                    groupTodayCard
                    membersSection

                    if challenge.status == "active" && acceptedMembers.count > 1 {
                        battleCryStrip

                        ReactiveBattleFeed(
                            mode: battleCryMode,
                            typeColor: typeColor,
                            gradient: typeGradientColors,
                            reactions: reactions,
                            isLoading: reactionsLoading,
                            inboundFlash: reactionsInboundFlash
                        )
                    }

                    if !pendingMembers.isEmpty {
                        pendingSection
                    }

                    actionsSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, 60)
                .trackScrollJank(screen: "GroupChallengeDetail")
            }
        }
        // Phase 12 rage-shake fix (2026-04-24) — see PrivateChallengeDetailView
        // for the invariant. `.trackScreen` reports the current screen to
        // SessionLogManager so a shake surfaces GroupChallengeDetailView.swift
        // as the first file for Claude to review.
        .trackScreen(.groupChallengeDetail, metadata: ["challenge_id": challenge.challengeId])
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: challenge.challengeId) {
            // Sprint 2026-04-24 Phase 4 (N1): pause intelligence phases while
            // user is in this detail view — see UserFocusSentinel doc.
            UserFocusSentinel.shared.beginFocus("GroupChallengeDetail")

            RealtimeService.shared.onOpponentDailyProgressUpdated = { payload in
                if payload.challengeId == challenge.challengeId {
                    Task {
                        await challengeService.fetchActiveGroupChallenges()
                    }
                }
            }

            // Battle Cry overhaul (2026-04-30) — Phase 4 realtime hookup.
            // Owned by the parent view per PE invariant 9. Fly-in animation
            // + confetti is driven by `inboundFlash` ticking up on each
            // remote arrival; local optimistic inserts (in `sendBattleCry`)
            // skip the flash so we don't confetti our own taps.
            await loadReactions()
            await RealtimeService.shared.subscribeChallengeReactions(challengeId: challenge.challengeId)
            RealtimeService.shared.onChallengeReactionReceived = { reaction in
                guard !reaction.isMine else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    reactions.insert(reaction, at: 0)
                }
                reactionsInboundFlash &+= 1
                HapticManager.notification(.warning)
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                await challengeService.fetchActiveGroupChallenges()
            }
        }
        .onDisappear {
            RealtimeService.shared.onOpponentDailyProgressUpdated = nil
            RealtimeService.shared.onChallengeReactionReceived = nil
            Task { await RealtimeService.shared.unsubscribeChallengeReactions() }
            UserFocusSentinel.shared.endFocus("GroupChallengeDetail")
        }
        .sheet(isPresented: $showingBattleCryPicker) {
            BattleCryPickerSheet(
                mode: battleCryMode,
                typeColor: typeColor,
                gradient: typeGradientColors,
                recipientLabel: "the team",
                onSend: { preset in sendBattleCry(preset) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Leave Challenge?", isPresented: $showingLeaveConfirm) {
            Button("Leave", role: .destructive) {
                Task { await leaveChallenge() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let remaining = acceptedMembers.count - 1
            if remaining == 2 {
                Text("The remaining 2 members will continue as a 1v1 challenge.")
            } else if remaining < 2 {
                Text("This will cancel the challenge for everyone since not enough members remain.")
            } else {
                Text("You'll be removed from this group challenge. The others will continue without you.")
            }
        }
        .alert("Cancel Challenge?", isPresented: $showingCancelConfirm) {
            Button("Cancel Challenge", role: .destructive) {
                Task { await cancelChallenge() }
            }
            Button("Never Mind", role: .cancel) { }
        } message: {
            Text("This will end the challenge for everyone. All members will be removed.")
        }
    }

    // MARK: - Hero Card

    /// Top-of-page hero. Shows the challenge title, type emoji, the
    /// (now-visible) description, and a time pill via the shared
    /// `ChallengeHeroCard` kit component. The previous bespoke header
    /// included a duration progress bar that the audit flagged as
    /// confusing (it looked like daily progress) — that bar is gone;
    /// the "Day X of Y" pill on the hero card carries that information
    /// without ambiguity.
    private var heroCard: some View {
        ChallengeHeroCard(
            title: liveChallenge.displayTitle,
            emoji: resolvedType.emoji,
            typeColor: typeColor,
            gradient: typeGradientColors,
            typeLabel: isAccountability ? "Accountability" : "Competition",
            description: liveChallenge.description,
            daysElapsed: liveChallenge.daysElapsed,
            durationDays: liveChallenge.durationDays,
            daysRemaining: liveChallenge.daysRemaining,
            endDate: liveChallenge.endDate,
            memberCountSuffix: "\(acceptedMembers.count) members"
        )
    }

    // MARK: - Stat Chip Row

    private var statChips: some View {
        let target = liveChallenge.dailyTarget ?? 0
        let combined = acceptedMembers.reduce(0) { $0 + $1.totalProgress }
        let bestStreak = acceptedMembers.map(\.currentStreak).max() ?? 0
        let doneToday = target > 0 ? acceptedMembers.filter { $0.todayProgress >= target }.count : 0

        var chips: [StatChip] = []
        chips.append(StatChip(value: formatGroupTotal(combined), label: "Combined", icon: "chart.bar.fill", tint: typeColor))
        if bestStreak > 0 {
            chips.append(StatChip(value: "\(bestStreak)", label: "Best Streak", icon: "flame.fill", tint: .orange))
        }
        if target > 0 {
            chips.append(StatChip(value: "\(doneToday)/\(acceptedMembers.count)", label: "Done Today", icon: "checkmark.seal.fill", tint: doneToday == acceptedMembers.count ? .green : .primary))
            chips.append(StatChip(value: "\(target.formatted())", label: liveChallenge.targetUnit, icon: "target", tint: .primary))
        }
        chips.append(StatChip(
            value: "\(liveChallenge.daysRemaining)",
            label: liveChallenge.daysRemaining == 1 ? "Day Left" : "Days Left",
            icon: "clock",
            tint: liveChallenge.daysRemaining <= 1 ? .red : .primary
        ))

        return StatChipRow(chips: chips)
    }

    /// Shared kit "Today" card — single-row layout (`opponentName` nil)
    /// shows only the current member's live daily progress vs the group
    /// target (plan: Today → group detail). Hidden when the challenge has
    /// no daily target (same as skipping a meaningless progress bar).
    @ViewBuilder
    private var groupTodayCard: some View {
        let daily = liveChallenge.dailyTarget ?? 0
        if daily > 0 {
            let uid = userManager.currentUser?.id
            let myMember = acceptedMembers.first { $0.userId == uid }
            let live = myMember.map {
                ChallengeProgressResolver.shared.liveProgress(for: liveChallenge, serverValue: $0.todayProgress)
            } ?? 0
            let hit = live >= daily

            TodayProgressCard(
                myValue: live,
                myValueText: live.formatted(),
                opponentName: nil,
                opponentValue: 0,
                opponentValueText: "",
                target: daily,
                targetUnit: liveChallenge.targetUnit,
                typeColor: typeColor,
                gradient: typeGradientColors,
                leaderTitle: hit ? "Target hit" : (isAccountability ? "Your check-in" : "Your pace"),
                opponentFreshness: .fresh,
                opponentAgeLabel: nil
            )
        }
    }

    // MARK: - Members / Leaderboard Section

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isAccountability ? "person.3.fill" : "trophy.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(typeGradient)
                Text(isAccountability ? "Team Check-In" : "Leaderboard")
                    .font(.ds_heading3)
                    .foregroundColor(.primary)

                Spacer()
            }

            VStack(spacing: Spacing.xxs) {
                ForEach(Array(acceptedMembers.enumerated()), id: \.element.id) { rank, member in
                    if isAccountability {
                        accountabilityRow(member: member)
                    } else {
                        leaderboardRow(member: member, rank: rank + 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func leaderboardRow(member: GroupChallengeMember, rank: Int) -> some View {
        let currentUserId = userManager.currentUser?.id
        let isMe = currentUserId != nil && member.userId == currentUserId
        let target = liveChallenge.dailyTarget ?? 0
        let displayProgress = isMe
            ? ChallengeProgressResolver.shared.liveProgress(for: liveChallenge, serverValue: member.todayProgress)
            : member.todayProgress
        let valueText = !isMe && displayProgress == 0 ? "—" : "\(displayProgress.formatted())"
        let progressFraction: Double? = target > 0
            ? min(1.0, max(0, Double(displayProgress) / Double(target)))
            : nil
        let streakBadge: String? = member.currentStreak > 0 ? "🔥 \(member.currentStreak)-day streak" : nil

        LeaderboardRow(
            rank: rank,
            userId: member.userId.uuidString,
            displayName: member.firstName,
            photoUrl: member.profilePhotoUrl,
            valueText: valueText,
            progress: progressFraction,
            isMe: isMe,
            typeColor: typeColor,
            gradient: typeGradientColors,
            trailingBadge: streakBadge,
            isVerified: member.isVerified == true,
            isGoldVerified: member.isGoldVerified == true
        )
    }

    @ViewBuilder
    private func accountabilityRow(member: GroupChallengeMember) -> some View {
        let currentUserId = userManager.currentUser?.id
        let isMe = currentUserId != nil && member.userId == currentUserId
        let target = liveChallenge.dailyTarget ?? 0
        let displayProgress = isMe
            ? ChallengeProgressResolver.shared.liveProgress(for: liveChallenge, serverValue: member.todayProgress)
            : member.todayProgress
        let completedToday = target > 0 && displayProgress >= target

        HStack(spacing: Spacing.sm) {
            Text(completedToday ? "✅" : "⬜")
                .font(.ds_heading3)

            CachedFriendPhoto(
                friendId: member.userId.uuidString,
                photoUrl: member.profilePhotoUrl,
                name: member.firstName,
                size: 36,
                showGradientRing: false,
                gradientColors: typeGradientColors
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(isMe ? "You" : member.firstName)
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if member.isVerified == true || member.isGoldVerified == true {
                        VerifiedBadge(size: 10, isGold: member.isGoldVerified == true)
                    }
                }
                if member.currentStreak > 0 {
                    Text("🔥 \(member.currentStreak)-day streak")
                        .font(.ds_caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(!isMe && displayProgress == 0 ? "—" : "\(displayProgress.formatted())")
                    .font(.ds_statSmall)
                    .foregroundColor(completedToday ? .green : .primary)
                Text(completedToday ? "DONE" : "TODAY")
                    .font(.ds_caption)
                    .tracking(0.5)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(isMe ? typeColor.opacity(colorScheme == .dark ? 0.14 : 0.08) : Color.clear)
        )
    }

    // MARK: - Battle Cry Strip

    private var battleCryStrip: some View {
        BattleCryStrip(
            mode: battleCryMode,
            typeColor: typeColor,
            gradient: typeGradientColors,
            onSend: { preset in sendBattleCry(preset) },
            onOpenPicker: {
                HapticManager.impact(.light)
                showingBattleCryPicker = true
            }
        )
    }

    // MARK: - Pending Section

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "hourglass.circle.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Waiting to Join")
                    .font(.ds_heading3)
                    .foregroundColor(.primary)

                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(pendingMembers.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: Spacing.sm) {
                        memberAvatar(member: member, size: 36)

                        Text(member.firstName)
                            .font(.ds_bodySmall)

                        Spacer()

                        Text("Pending")
                            .font(.ds_labelSmall)
                            .foregroundColor(.orange)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxxs)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)

                    if index < pendingMembers.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 1)
                            .padding(.horizontal, Spacing.sm)
                    }
                }
            }
            .sleekCardSubtle(cornerRadius: CornerRadius.lg)
        }
    }

    // MARK: - Actions Section

    private var isCreator: Bool {
        userManager.currentUser?.id == liveChallenge.createdBy
    }

    private var actionsSection: some View {
        VStack(spacing: Spacing.sm) {
            Button(action: { showingLeaveConfirm = true }) {
                HStack(spacing: Spacing.xs) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.ds_bodyMedium)
                    }

                    Text(isProcessing ? "Leaving..." : "Leave Challenge")
                        .font(.ds_bodySmall)
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .fill(Color.orange.opacity(colorScheme == .dark ? 0.08 : 0.04))
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)

            if isCreator {
                Button(action: { showingCancelConfirm = true }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ds_bodyMedium)

                        Text("Cancel Challenge for Everyone")
                            .font(.ds_bodySmall)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                    .fill(Color.red.opacity(colorScheme == .dark ? 0.08 : 0.04))
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isProcessing)
            }
        }
    }

    // MARK: - Reactions

    private func loadReactions() async {
        reactionsLoading = true
        let fetched = await ChallengeService.shared.fetchReactions(challengeId: challenge.challengeId)
        await MainActor.run {
            reactions = fetched
            reactionsLoading = false
        }
    }

    /// Optimistic-insert + group fan-out send. The realtime listener
    /// also receives our own INSERT, but the `isMine` filter in the
    /// `onChallengeReactionReceived` callback prevents a double bubble.
    private func sendBattleCry(_ preset: ReactionPreset) {
        guard let me = SupabaseManager.shared.currentUser?.id else { return }
        let recipients = acceptedMembers.map(\.userId).filter { $0 != me }
        guard !recipients.isEmpty else { return }

        let optimisticId = UUID()
        let optimistic = ChallengeReaction(
            reactionId: optimisticId,
            senderId: me,
            senderName: "You",
            senderPhotoUrl: nil,
            recipientId: recipients.first ?? me,
            reactionKey: preset.id,
            reactionEmoji: preset.emoji,
            reactionText: preset.text,
            reactionCategory: preset.category.rawValue,
            createdAt: Date()
        )
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            reactions.insert(optimistic, at: 0)
        }

        Task {
            let count = await ChallengeService.shared.sendGroupReaction(
                challengeId: challenge.challengeId,
                recipientIds: recipients,
                preset: preset
            )
            if count == 0 {
                await MainActor.run {
                    HapticManager.notification(.error)
                    withAnimation(.easeOut(duration: 0.25)) {
                        reactions.removeAll { $0.id == optimisticId }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func leaveChallenge() async {
        isProcessing = true
        let result = await challengeService.leaveGroupChallenge(challengeId: challenge.challengeId)
        isProcessing = false

        if result != nil {
            HapticManager.notification(.success)
            dismiss()
        } else {
            HapticManager.notification(.error)
        }
    }

    private func cancelChallenge() async {
        isProcessing = true
        let success = await challengeService.cancelGroupChallenge(challengeId: challenge.challengeId)
        isProcessing = false

        if success {
            HapticManager.notification(.success)
            dismiss()
        } else {
            HapticManager.notification(.error)
        }
    }

    // MARK: - Helpers

    private func formatGroupTotal(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }

    private func memberAvatar(member: GroupChallengeMember, size: CGFloat) -> some View {
        Group {
            let currentUserId = SupabaseManager.shared.currentUser?.id
            if member.userId == currentUserId, let cachedImage = ProfilePhotoCache.shared.cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.darkBackground, lineWidth: 2))
            } else {
                CachedFriendPhoto(
                    friendId: member.userId.uuidString,
                    photoUrl: member.profilePhotoUrl,
                    name: member.name ?? member.username ?? "?",
                    size: size,
                    showGradientRing: false,
                    gradientColors: resolvedType.gradientColors
                )
                .overlay(Circle().stroke(Color.darkBackground, lineWidth: 2))
            }
        }
    }
}
