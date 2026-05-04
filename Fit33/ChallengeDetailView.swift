//
//  ChallengeDetailView.swift
//  Fit33
//
//  Redesigned detail view for active 1v1 challenges — compact head-to-head display,
//  league-style stat bar, day-by-day battle log with actual values, and real-time updates.
//

import SwiftUI

struct ChallengeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    @ObservedObject private var challengeService = ChallengeService.shared
    @ObservedObject private var healthKitService = HealthKitService.shared
    @ObservedObject private var realtimeService = RealtimeService.shared
    
    let challenge: ActiveChallenge
    
    @State private var details: ChallengeDetails?
    /// Bug fix 2026-04-27 — widget→detail latency: split into THREE explicit
    /// states (`idle`/`loading`/`loaded`/`failed`) instead of a single
    /// `isLoading` bool. Lets the battle log render skeleton vs retry CTA
    /// vs real rows, and lets the notification toggle render a placeholder
    /// instead of a stale "ON" default before details arrive. The view body
    /// itself NEVER blocks on this — the head-to-head / stat bar / today /
    /// cancel button paint instantly from the `challenge` argument we
    /// already have on push (per QP §19c "split visible work from
    /// background sync work").
    @State private var detailsLoadState: DetailsLoadState = .idle
    @State private var showingCancelConfirmation = false
    @State private var isCancelling = false
    /// `nil` until details first load — gates the toggle UI so we don't
    /// silently default to "ON" while the real preference is still in
    /// flight (would have been the wrong choice for users who turned it
    /// off on the previous device).
    @State private var notifyOnOpponentComplete: Bool? = nil
    @State private var isTogglingNotification = false
    @State private var lastSyncedSteps = 0
    @State private var showingReactionPicker = false
    @State private var showingAddWidgetSheet = false

    // Battle Cry overhaul (2026-04-30) — Phase 2 realtime state.
    // Owned by the parent detail view per PE invariant 9 so the
    // `ReactiveBattleFeed` row never subscribes to RealtimeService
    // itself. Initial snapshot loaded by `loadReactions()`; subsequent
    // INSERTs streamed in via `RealtimeService.subscribeChallengeReactions`.
    @State private var reactions: [ChallengeReaction] = []
    @State private var reactionsLoading: Bool = true
    @State private var reactionsInboundFlash: Int = 0

    private enum DetailsLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    /// Soft cap before we paint an inline retry CTA on the battle log
    /// section. Mirrors the 5s hard cap that `DashboardView.refreshable`
    /// uses (QP §19c). The `get_challenge_details` RPC keeps running in
    /// the background past this — we just stop blocking the UI on it.
    private static let detailsLoadSoftTimeout: TimeInterval = 5.0
    
    private var challengeType: ChallengeType { challenge.resolvedType }
    private var typeColor: Color { challengeType.color }
    private var typeGradient: LinearGradient {
        LinearGradient(colors: challengeType.gradientColors, startPoint: .leading, endPoint: .trailing)
    }
    private var opponentFirst: String {
        challenge.opponentName?.components(separatedBy: " ").first ?? "Opponent"
    }
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()

            // Bug fix 2026-04-27 — widget→detail latency: paint the entire
            // shell IMMEDIATELY from the `challenge` we already have on
            // push. The previous `if isLoading { ProgressView }` wrapper
            // blocked the user behind a ~5.6s `get_challenge_details` RPC
            // even though we already had myToday / oppToday / opponent
            // name / days remaining / type / target — everything the H2H
            // card and stat bar need. Per QP §19c we now split visible
            // work (renders from `challenge`) from background sync work
            // (battle log + reaction feed → wait for `details`).
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.md) {
                    heroCard
                    podiumCard
                    statChips

                    if challenge.status == "active" {
                        battleCryStrip
                    }

                    todayCard

                    if challenge.status == "active" {
                        ReactiveBattleFeed(
                            mode: battleCryMode,
                            typeColor: typeColor,
                            gradient: challengeType.gradientColors,
                            reactions: reactions,
                            isLoading: reactionsLoading,
                            inboundFlash: reactionsInboundFlash
                        )
                    }

                    battleLogSection

                    notificationToggleCard

                    if challenge.status == "active" || challenge.status == "pending" {
                        cancelChallengeButton
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .trackScrollJank(screen: "ChallengeDetail")
        }
        // Phase 12 rage-shake fix (2026-04-24) — see PrivateChallengeDetailView.
        .trackScreen(.challengeDetail, metadata: ["challenge_id": challenge.id])
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Top-right "+" — opens an instructional sheet that walks
            // the user through pinning the active-challenge widget on
            // their home screen. Active-only; no point pitching the
            // widget for finished challenges. iOS does not allow
            // programmatic widget installation or deep-linking to the
            // widget gallery for a specific app, so this is the best
            // discovery surface we can ship. (See `AddHomescreenWidgetSheet.swift`.)
            if challenge.status == "active" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.impact(.medium)
                        showingAddWidgetSheet = true
                    } label: {
                        Text("Home Screen Widget")
                            .font(.ds_labelMedium)
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add home screen widget")
                    .accessibilityHint("Opens a step-by-step guide for adding the widget")
                }
            }
        }
        .onAppear {
            RealtimeService.shared.dismissIncomingBattleCryBanner(for: challenge.challengeId)
            // Sprint 2026-04-24 Phase 4 (N1): pause intelligence phases while
            // user is in this detail view — see UserFocusSentinel doc.
            UserFocusSentinel.shared.beginFocus("ChallengeDetail")
            loadDetails()
            lastSyncedSteps = healthKitService.todaySteps
        }
        .onDisappear {
            UserFocusSentinel.shared.endFocus("ChallengeDetail")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if oldPhase == .background && newPhase == .active {
                Task { await refreshProgressIfNeeded() }
            }
        }
        .onChange(of: healthKitService.todaySteps) { oldValue, newValue in
            if challenge.challengeType == "steps" && newValue != lastSyncedSteps {
                let dailyTarget = challenge.dailyTarget ?? 1000
                if (lastSyncedSteps < dailyTarget && newValue >= dailyTarget) ||
                   (newValue > lastSyncedSteps + 100) {
                    lastSyncedSteps = newValue
                    Task { await syncMyProgressInBackground() }
                }
            }
        }
        .task(id: challenge.challengeId) {
            RealtimeService.shared.onOpponentDailyProgressUpdated = { payload in
                if payload.challengeId == challenge.challengeId {
                    AppLogger.debug("⚡️ [CHALLENGE] Real-time opponent update received!", category: .social)
                    Task {
                        details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
                        if payload.targetHit {
                            HapticManager.notification(.warning)
                        }
                    }
                }
            }

            // Battle Cry overhaul (2026-04-30) — Phase 2 realtime hookup.
            // Owned by the parent view per PE invariant 9. Fly-in animation
            // + confetti is driven by `inboundFlash` ticking up on each
            // remote arrival; local optimistic inserts (in `sendBattleCry`)
            // skip the flash so we don't confetti our own taps.
            await loadReactions()
            await RealtimeService.shared.subscribeChallengeReactions(challengeId: challenge.challengeId)
            RealtimeService.shared.onChallengeReactionReceived = { reaction in
                // Skip our own sends — they're already inserted
                // optimistically by `sendBattleCry`. Reading `@State`
                // from a long-lived closure returns a stale snapshot
                // (the closure captures the view value at .task time)
                // so id-dedup is unreliable; isMine filtering is the
                // canonical "mine vs theirs" cut.
                guard !reaction.isMine else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    reactions.insert(reaction, at: 0)
                }
                reactionsInboundFlash &+= 1
                HapticManager.notification(.warning)
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                // Only poll-refresh once details have successfully loaded
                // at least once. While we're still in `.loading` / `.failed`
                // the `loadDetails()` flow (or the user's retry tap) owns
                // the next fetch — racing them would clobber state.
                if detailsLoadState == .loaded {
                    details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
                }
            }
        }
        .onDisappear {
            RealtimeService.shared.onOpponentDailyProgressUpdated = nil
            RealtimeService.shared.onChallengeReactionReceived = nil
            Task { await RealtimeService.shared.unsubscribeChallengeReactions() }
        }
        .alert("Cancel Challenge?", isPresented: $showingCancelConfirmation) {
            Button("Keep Challenge", role: .cancel) { }
            Button("Cancel Challenge", role: .destructive) { cancelChallenge() }
        } message: {
            Text("This will end the challenge for both you and \(opponentFirst). They will be notified that you cancelled.")
        }
        .sheet(isPresented: $showingReactionPicker) {
            BattleCryPickerSheet(
                mode: battleCryMode,
                typeColor: typeColor,
                gradient: challengeType.gradientColors,
                recipientLabel: opponentFirst,
                onSend: { preset in sendBattleCry(preset) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddWidgetSheet) {
            // Pass the live challenge so the sheet's preview mirrors the
            // exact widget the user is about to install — name, opponent,
            // today's progress — making the home-screen widget instantly
            // recognizable when it appears.
            AddHomescreenWidgetSheet(challenge: challenge)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Hero Card

    /// Top-of-page hero. Shows the challenge title, type emoji, the
    /// (now-visible) description, and a time pill via the shared
    /// `ChallengeHeroCard` kit component.
    private var heroCard: some View {
        ChallengeHeroCard(
            title: challenge.displayTitle,
            emoji: challengeType.emoji,
            typeColor: typeColor,
            gradient: challengeType.gradientColors,
            typeLabel: challengeType.displayName,
            description: challenge.description,
            daysElapsed: challenge.daysElapsed,
            durationDays: challenge.durationDays,
            daysRemaining: challenge.daysRemaining,
            endDate: challenge.endDate,
            memberCountSuffix: nil
        )
    }

    // MARK: - Participant Podium

    /// Big head-to-head podium with 88pt avatars, animated crown
    /// pulse on the leader, and freshness-aware opponent value via
    /// the shared `ParticipantPodium` kit component.
    private var podiumCard: some View {
        let amLeading = challenge.amWinning && challenge.opponentTotalProgress >= 0
        let leadDelta: String? = {
            guard challenge.myTotalProgress != challenge.opponentTotalProgress else { return nil }
            let diff = abs(challenge.myTotalProgress - challenge.opponentTotalProgress)
            return amLeading ? "+\(formatProgress(diff))" : "-\(formatProgress(diff))"
        }()
        let oppShowsRaw = challenge.opponentLastProgressAt == nil
            || ProgressFreshnessKit.shouldShowRawValue(for: challenge.opponentLastProgressAt)
        let oppValueText = oppShowsRaw
            ? formatProgress(challenge.opponentTotalProgress)
            : "—"

        return ParticipantPodium(
            myImage: ProfilePhotoCache.shared.cachedImage,
            myName: "You",
            myValueText: formatProgress(challenge.myTotalProgress),
            opponentId: challenge.opponentId.uuidString,
            opponentName: opponentFirst,
            opponentPhotoUrl: challenge.opponentPhotoUrl,
            opponentValueText: oppValueText,
            opponentIsVerified: challenge.opponentIsVerified == true,
            opponentIsGoldVerified: challenge.opponentIsGoldVerified == true,
            amWinning: amLeading,
            leadDelta: leadDelta,
            typeColor: typeColor,
            gradient: challengeType.gradientColors,
            opponentFreshness: ProgressFreshnessKit.freshness(for: challenge.opponentLastProgressAt),
            opponentAgeLabel: ProgressFreshnessKit.ageLabel(for: challenge.opponentLastProgressAt)
        )
    }

    // MARK: - Stat Chip Row

    /// Horizontally scrollable stat chip strip — replaces the old
    /// 4-cell `statBar`. Always-visible streak chip with flame.
    private var statChips: some View {
        let liveValue = ChallengeProgressResolver.shared.liveProgress(for: challenge)
        let livePercent = Int(ChallengeProgressResolver.shared.progressPercentage(for: challenge) * 100)
        let target = challenge.dailyTarget ?? 0

        return StatChipRow(chips: [
            StatChip(
                value: "\(challenge.myCurrentStreak)",
                label: "streak",
                icon: "flame.fill",
                tint: .orange
            ),
            StatChip(
                value: "\(liveValue)",
                label: "today \(challenge.targetUnit)",
                tint: typeColor
            ),
            StatChip(
                value: "\(livePercent)%",
                label: "of goal",
                tint: livePercent >= 100 ? .green : .primary
            ),
            StatChip(
                value: formatProgress(target),
                label: "daily target"
            ),
            StatChip(
                value: "\(challenge.myDaysCompleted)/\(max(challenge.daysElapsed, 1))",
                label: "days hit",
                tint: .green
            ),
            StatChip(
                value: "\(challenge.daysRemaining)",
                label: challenge.daysRemaining == 1 ? "day left" : "days left",
                tint: challenge.daysRemaining <= 1 ? .red : .primary
            )
        ])
    }

    // MARK: - Battle Cry Strip (inline composer)

    /// Inline 5-emoji quick-tap composer + "..." trailing button.
    /// One-tap = haptic + animated pulse + send. Replaces the old
    /// chevron-right `reactionSendSection` row.
    private var battleCryStrip: some View {
        BattleCryStrip(
            mode: battleCryMode,
            typeColor: typeColor,
            gradient: challengeType.gradientColors,
            onSend: { preset in sendBattleCry(preset) },
            onOpenPicker: { showingReactionPicker = true }
        )
    }

    // MARK: - Today's Progress Card

    /// Single shared today's-progress card via the kit. Bigger
    /// numbers, freshness-aware opponent label.
    private var todayCard: some View {
        let myLive = ChallengeProgressResolver.shared.liveProgress(for: challenge)
        let oppToday = challenge.opponentTodayProgress ?? 0
        let target = challenge.dailyTarget ?? 1
        let oppShowsRaw = challenge.opponentLastProgressAt == nil
            || ProgressFreshnessKit.shouldShowRawValue(for: challenge.opponentLastProgressAt)
        let oppValueText: String = {
            guard oppShowsRaw else { return "—" }
            return oppToday > 0 ? formatProgress(oppToday) : "—"
        }()
        let leaderTitle: String = {
            if challenge.amWinningToday == true { return "You're ahead" }
            if challenge.amWinningToday == false { return "\(opponentFirst) leads" }
            return ""
        }()

        return TodayProgressCard(
            myValue: myLive,
            myValueText: formatProgress(myLive),
            opponentName: opponentFirst,
            opponentValue: oppShowsRaw ? oppToday : 0,
            opponentValueText: oppValueText,
            target: target,
            targetUnit: challenge.targetUnit,
            typeColor: typeColor,
            gradient: challengeType.gradientColors,
            leaderTitle: leaderTitle,
            opponentFreshness: ProgressFreshnessKit.freshness(for: challenge.opponentLastProgressAt),
            opponentAgeLabel: ProgressFreshnessKit.ageLabel(for: challenge.opponentLastProgressAt)
        )
    }

    // MARK: - Battle Cry Mode

    /// Maps the 1v1 challenge mode to the BattleCryComposer kit's
    /// preset pool: competition → smack-talk, accountability → hype.
    private var battleCryMode: BattleCryMode {
        switch challenge.mode {
        case .competition:    return .competition
        case .accountability: return .accountability
        }
    }
    
    // MARK: - Battle Log (Day-by-Day Timeline)

    private var battleLogSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "calendar.circle.fill")
                    .foregroundStyle(typeGradient)
                    .font(.ds_heading3)
                Text("Battle Log")
                    .font(.ds_heading3)
                    .foregroundColor(.primary)

                Spacer()

                Text("Day \(challenge.daysElapsed) of \(challenge.durationDays)")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }

            battleLogContent
        }
    }

    /// Three explicit states for the day-by-day battle log: skeleton bars
    /// while the `get_challenge_details` RPC is in flight, an inline
    /// retry CTA when the RPC failed (typical when the widget tap
    /// foregrounded the app onto a flaky connection — every parallel
    /// RPC fails with `-1005 connection lost`), and real rows once
    /// details arrive. Pre-fix this branch silently rendered skeleton
    /// boxes forever after a failure with no recovery path.
    @ViewBuilder
    private var battleLogContent: some View {
        if let details = details, let participants = details.participants {
            let myProgress = participants.first { $0.userId.uuidString == SupabaseManager.shared.currentUser?.id.uuidString }
            let opponentProgress = participants.first { $0.userId.uuidString != SupabaseManager.shared.currentUser?.id.uuidString }
            let calendar = createUTCCalendar()
            let allDays = generateDays(from: challenge.startDate, to: challenge.endDate)

            VStack(spacing: 0) {
                ForEach(Array(allDays.enumerated()), id: \.offset) { index, date in
                    let myEntry = myProgress?.dailyProgress?.first { entry in
                        calendar.startOfDay(for: entry.date) == date
                    }
                    let oppEntry = opponentProgress?.dailyProgress?.first { entry in
                        calendar.startOfDay(for: entry.date) == date
                    }

                    BattleLogRow(
                        dayNumber: index + 1,
                        date: date,
                        myValue: myEntry?.value ?? 0,
                        opponentValue: oppEntry?.value ?? 0,
                        target: challenge.dailyTarget ?? 1,
                        targetUnit: challenge.targetUnit,
                        opponentName: opponentFirst,
                        typeColor: typeColor,
                        typeGradientColors: challengeType.gradientColors,
                        colorScheme: colorScheme,
                        leaguePointsAwarded: details.leaguePointsAwarded(on: date),
                        leagueReason: details.primaryLeagueReason(on: date)
                    )

                    if index < allDays.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 1)
                            .padding(.horizontal, Spacing.sm)
                    }
                }
            }
            .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
        } else if detailsLoadState == .failed {
            Button {
                HapticManager.impact(.light)
                loadDetails()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.ds_bodyMedium)
                        .foregroundColor(typeColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couldn't load battle log")
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                        Text("Tap to retry")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading battle log")
            .accessibilityHint("The previous load failed. Tap to try again.")
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(0..<min(challenge.durationDays, 7), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 56)
                }
            }
            .padding(Spacing.sm)
            .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
        }
    }
    
    // MARK: - Notification Toggle
    
    private var notificationToggleCard: some View {
        Group {
            if challenge.status == "active" || challenge.status == "pending" {
                let isOn = notifyOnOpponentComplete ?? true
                HStack(spacing: Spacing.sm) {
                    Image(systemName: notifyOnOpponentComplete == nil
                        ? "bell"
                        : (isOn ? "bell.fill" : "bell.slash"))
                        .font(.ds_bodyMedium)
                        .foregroundColor(notifyOnOpponentComplete == nil
                            ? .secondary
                            : (isOn ? typeColor : .secondary))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Opponent alerts")
                            .font(.ds_bodySmall)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text("Notified when \(opponentFirst) hits their goal")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Bug fix 2026-04-27: until details first land, the
                    // user's actual preference is unknown — show a small
                    // placeholder spinner instead of defaulting to "ON"
                    // (which would silently mis-represent the saved
                    // preference for users who turned it off).
                    if isTogglingNotification || notifyOnOpponentComplete == nil {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Toggle("", isOn: Binding<Bool>(
                            get: { notifyOnOpponentComplete ?? true },
                            set: { newValue in
                                notifyOnOpponentComplete = newValue
                                toggleNotificationPreference(newValue)
                            }
                        ))
                        .labelsHidden()
                        .tint(typeColor)
                    }
                }
                .padding(Spacing.sm)
                .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.md)
            }
        }
    }

    // MARK: - Cancel Button
    
    private var cancelChallengeButton: some View {
        Button(action: { showingCancelConfirmation = true }) {
            HStack(spacing: Spacing.xs) {
                if isCancelling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ds_bodyMedium)
                }
                
                Text(isCancelling ? "Cancelling..." : "Cancel Challenge")
                    .font(.ds_bodySmall)
                    .fontWeight(.medium)
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
        .disabled(isCancelling)
    }
    
    // MARK: - Helpers
    
    /// Bug fix 2026-04-27 — widget→detail latency:
    ///   • `.userInitiated` priority so the deep-link RPC isn't queued
    ///     behind the dashboard's 14-RPC social fanout that fires on
    ///     every app foreground (`get_friends`, `get_pending_*`,
    ///     `get_ranked_friends`, `get_friend_activity_feed`, …).
    ///   • 5s soft timeout race (`detailsLoadSoftTimeout`) so a flaky
    ///     network can't keep the battle log on a skeleton forever — we
    ///     flip to `.failed` and surface the inline retry CTA. The
    ///     underlying RPC keeps running and lands as a late success if
    ///     it eventually returns; the soft timeout just unblocks the UI.
    ///   • Resettable from the retry button (state moves
    ///     `failed` → `loading` → `loaded`/`failed`).
    ///   • Logged via `AppLogger.warning` not `.error` for the timeout
    ///     case — a slow network is not a malfunction (QP §25 + §25a).
    private func loadDetails() {
        // Re-tap on the retry CTA: cycle the state machine without
        // racing two in-flight loads. The previous load's awaited
        // result lands harmlessly into `details` if it eventually
        // returns and we're still mounted.
        detailsLoadState = .loading

        Task(priority: .userInitiated) {
            AppLogger.debug("🔄 [CHALLENGE DETAIL] Fetching details for challenge: \(challenge.challengeId)", category: .social)

            // Race the RPC against the soft timeout. `withTaskGroup`
            // returns whichever finishes first; `.timedOut` lets the
            // UI flip to `.failed` (retry CTA) without cancelling the
            // RPC — if it eventually returns we still capture its
            // result on the late-completion path below.
            enum Outcome { case got(ChallengeDetails?), timedOut }
            let outcome: Outcome = await withTaskGroup(of: Outcome.self, returning: Outcome.self) { group in
                group.addTask { @Sendable [challengeService, challengeId = challenge.challengeId] in
                    let result = await challengeService.getChallengeDetails(challengeId: challengeId)
                    return .got(result)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(Self.detailsLoadSoftTimeout * 1_000_000_000))
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                // Cancel the loser. The soft-timeout sleep accepts
                // cancellation; the RPC is best-effort cancelled by
                // URLSession on its underlying task.
                group.cancelAll()
                return first
            }

            switch outcome {
            case .got(let fetched):
                if let fetched {
                    AppLogger.info("✅ [CHALLENGE DETAIL] Details loaded - \(fetched.participants?.count ?? 0) participants", category: .social)
                    await MainActor.run {
                        details = fetched
                        notifyOnOpponentComplete = fetched.shouldNotifyOnOpponentComplete
                        detailsLoadState = .loaded
                    }
                } else {
                    AppLogger.warning("⚠️ [CHALLENGE DETAIL] Details RPC returned nil — surfacing retry", category: .social)
                    await MainActor.run {
                        detailsLoadState = .failed
                    }
                }
            case .timedOut:
                AppLogger.warning("⚠️ [CHALLENGE DETAIL] Details soft-timeout (\(Int(Self.detailsLoadSoftTimeout))s) — UI unblocked", category: .social)
                await MainActor.run {
                    detailsLoadState = .failed
                }
                // Late-completion path: keep awaiting the RPC in case
                // the network recovers within a reasonable window. If
                // it lands AND the user is still on this view AND the
                // state hasn't been reset by a retry tap, hydrate the
                // UI silently — they get the battle log without an
                // extra round trip.
                Task.detached(priority: .background) { @MainActor [challengeService, challengeId = challenge.challengeId] in
                    let late = await challengeService.getChallengeDetails(challengeId: challengeId)
                    guard let late, detailsLoadState == .failed else { return }
                    AppLogger.info("✅ [CHALLENGE DETAIL] Details landed late — silent hydrate", category: .social)
                    details = late
                    notifyOnOpponentComplete = late.shouldNotifyOnOpponentComplete
                    detailsLoadState = .loaded
                }
            }

            await syncMyProgressInBackground()
        }
    }
    
    private func syncMyProgressInBackground() async {
        guard challenge.status == "active" || challenge.status == "pending" else { return }
        let challengeType = challenge.challengeType
        guard challengeType == "steps" || challengeType == "active_minutes" else { return }
        
        let progressValue: Int
        if challengeType == "steps" {
            progressValue = HealthKitService.shared.todaySteps
        } else {
            progressValue = HealthKitService.shared.todayActiveMinutes
        }
        
        if progressValue > 0 {
            await challengeService.logProgress(
                challengeId: challenge.challengeId,
                progressValue: progressValue,
                source: "healthkit"
            )
            details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
        }
    }
    
    private func refreshProgressIfNeeded() async {
        await syncMyProgressInBackground()
    }

    // MARK: - Battle Cry Helpers

    /// Initial fetch of recent reactions for this challenge. Called
    /// once on `.task(id:)` before the realtime subscription opens
    /// so the feed paints with history instead of an empty bubble
    /// stack while we wait for the next INSERT.
    private func loadReactions() async {
        reactionsLoading = true
        let fetched = await ChallengeService.shared.fetchReactions(challengeId: challenge.challengeId)
        await MainActor.run {
            reactions = fetched
            reactionsLoading = false
        }
    }

    /// Optimistic-insert + send for an inline `BattleCryStrip` tap.
    /// Inserts a placeholder reaction immediately so the bubble
    /// appears in the feed without round-trip latency, then awaits
    /// the RPC; on failure the placeholder fades out + we surface
    /// an error haptic. The realtime listener also receives our
    /// own INSERT, but the dedup-by-id guard in the
    /// `onChallengeReactionReceived` callback prevents a double
    /// bubble (`reactions.first(where: { $0.id == reaction.id })`).
    private func sendBattleCry(_ preset: ReactionPreset) {
        guard let me = SupabaseManager.shared.currentUser?.id else { return }

        let optimisticId = UUID()
        let optimistic = ChallengeReaction(
            reactionId: optimisticId,
            challengeId: challenge.challengeId,
            senderId: me,
            senderName: "You",
            senderPhotoUrl: nil,
            recipientId: challenge.opponentId,
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
            let result = await ChallengeService.shared.sendReaction(
                challengeId: challenge.challengeId,
                recipientId: challenge.opponentId,
                preset: preset
            )
            if !result.success {
                await MainActor.run {
                    HapticManager.notification(.error)
                    withAnimation(.easeOut(duration: 0.25)) {
                        reactions.removeAll { $0.id == optimisticId }
                    }
                }
            }
        }
    }
    
    private func toggleNotificationPreference(_ notify: Bool) {
        isTogglingNotification = true
        HapticManager.impact(.light)
        
        Task {
            let success = await challengeService.toggleChallengeNotificationPreference(
                challengeId: challenge.challengeId,
                notify: notify
            )
            
            await MainActor.run {
                isTogglingNotification = false
                if success {
                    HapticManager.notification(.success)
                } else {
                    notifyOnOpponentComplete = !notify
                    HapticManager.notification(.error)
                }
            }
        }
    }
    
    private func cancelChallenge() {
        isCancelling = true
        HapticManager.impact(.medium)
        
        Task {
            let success = await challengeService.cancelChallenge(challengeId: challenge.challengeId)
            await MainActor.run {
                isCancelling = false
                if success {
                    HapticManager.notification(.success)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.2))
                        dismiss()
                    }
                } else {
                    HapticManager.notification(.error)
                }
            }
        }
    }
    
    private func formatProgress(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
    
    private func createUTCCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    
    private func generateDays(from start: Date, to end: Date) -> [Date] {
        var dates: [Date] = []
        let calendar = createUTCCalendar()
        var current = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        
        while current <= endDay {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return dates
    }
}

// MARK: - Battle Log Row

private struct BattleLogRow: View {
    let dayNumber: Int
    let date: Date
    let myValue: Int
    let opponentValue: Int
    let target: Int
    let targetUnit: String
    let opponentName: String
    let typeColor: Color
    let typeGradientColors: [Color]
    let colorScheme: ColorScheme
    /// 2026-04-30 — Challenge League Points Expansion. Total LP credited to
    /// the caller for this calendar day (sum across hit/winner/intensity/
    /// early-bird awards). Zero = no chip rendered.
    var leaguePointsAwarded: Int = 0
    /// One-line reason string for the chip subtitle (e.g. "Day winner — 2x").
    /// Nil falls back to just the +N LP pill.
    var leagueReason: String? = nil
    
    private var isToday: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.isDateInToday(date)
    }
    
    private var isFuture: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return date > calendar.startOfDay(for: Date())
    }
    
    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var myWon: Bool { myValue >= target && !isFuture }
    private var oppWon: Bool { opponentValue >= target && !isFuture }
    private var iAmAhead: Bool { myValue > opponentValue && !isFuture }
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(spacing: 1) {
                if isToday {
                    Text("TODAY")
                        .font(.ds_caption)
                        .tracking(0.6)
                        .foregroundColor(typeColor)
                } else {
                    Text("Day \(dayNumber)")
                        .font(.ds_caption)
                        .foregroundColor(isFuture ? .secondary.opacity(0.4) : .secondary)
                }

                Text(dayLabel)
                    .font(.ds_caption)
                    .foregroundColor(.secondary.opacity(isFuture ? 0.3 : 0.6))
            }
            .frame(width: 44)

            if isFuture {
                HStack {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.ds_caption)
                        .foregroundColor(.secondary.opacity(0.2))
                    Spacer()
                }
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("You")
                        .font(.ds_caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: Spacing.xxxs) {
                        Text(myValue > 0 ? formatValue(myValue) : "–")
                            .font(.ds_labelMedium)
                            .foregroundColor(myWon ? .green : (myValue > 0 ? .primary : .secondary.opacity(0.4)))

                        if myWon {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.ds_caption)
                                .foregroundColor(.green)
                        } else if myValue > 0 {
                            miniRing(progress: min(1.0, Double(myValue) / Double(target)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                if myValue > 0 || opponentValue > 0 {
                    ZStack {
                        if iAmAhead {
                            Image(systemName: "arrowtriangle.left.fill")
                                .font(.ds_caption)
                                .foregroundColor(.green.opacity(0.6))
                        } else if opponentValue > myValue {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.ds_caption)
                                .foregroundColor(.orange.opacity(0.6))
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(opponentName)
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xxxs) {
                        if oppWon {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.ds_caption)
                                .foregroundColor(.green)
                        } else if opponentValue > 0 {
                            miniRing(progress: min(1.0, Double(opponentValue) / Double(target)))
                        }

                        Text(opponentValue > 0 ? formatValue(opponentValue) : "–")
                            .font(.ds_labelMedium)
                            .foregroundColor(oppWon ? .green : (opponentValue > 0 ? .primary : .secondary.opacity(0.4)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(isToday
                    ? typeColor.opacity(colorScheme == .dark ? 0.1 : 0.06)
                    : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if leaguePointsAwarded > 0 && !isFuture {
                leaguePointsChip
                    .padding(.top, 2)
                    .padding(.trailing, Spacing.xs)
            }
        }
    }

    /// 2026-04-30 — Challenge League Points Expansion.
    /// Small pill that renders "+N LP" with an optional single-line reason
    /// subtitle. Rendered only for past / today rows where the server-side
    /// rollup has actually credited points. Future days, or days with a
    /// zero award sum, render no chip so the row's layout is unchanged.
    private var leaguePointsChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "rosette")
                .font(.system(size: 9, weight: .semibold))
            Text("+\(leaguePointsAwarded) LP")
                .font(.ds_caption)
                .fontWeight(.semibold)
            if let reason = leagueReason, !reason.isEmpty {
                Text("·")
                    .font(.ds_caption)
                    .foregroundColor(.secondary.opacity(0.6))
                Text(reason)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(typeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(typeColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .accessibilityLabel("Earned \(leaguePointsAwarded) league points\(leagueReason.map { " for \($0)" } ?? "")")
    }

    private func miniRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1.5)
                .frame(width: 12, height: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange, lineWidth: 1.5)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(-90))
        }
    }
    
    private func formatValue(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChallengeDetailView(challenge: ActiveChallenge(
            challengeId: UUID(),
            challengeType: "steps",
            title: "10K Steps Daily",
            description: "Hit 10,000 steps every day",
            dailyTarget: 10000,
            totalTarget: nil,
            targetUnit: "steps",
            startDate: Date().addingTimeInterval(-86400 * 3),
            endDate: Date().addingTimeInterval(86400 * 4),
            durationDays: 7,
            daysElapsed: 3,
            daysRemaining: 4,
            status: "active",
            myTotalProgress: 28500,
            myDaysCompleted: 2,
            myCurrentStreak: 2,
            opponentId: UUID(),
            opponentName: "Leo Smith",
            opponentUsername: "leosmith",
            opponentPhotoUrl: nil,
            opponentTotalProgress: 25000,
            opponentDaysCompleted: 2,
            amWinning: true
        ))
    }
}
