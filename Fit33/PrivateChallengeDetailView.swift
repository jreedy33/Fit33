//
//  PrivateChallengeDetailView.swift
//  Fit33
//
//  Redesigned detail view for a Private Challenge — single-scroll layout with
//  compact header, league-style stat bar, always-visible leaderboard, chat preview,
//  and members sheet. Matches the Friends tab aesthetic.
//

import SwiftUI
import Realtime

struct PrivateChallengeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared
    @ObservedObject private var friendService = FriendService.shared
    
    let challenge: PrivateChallenge
    
    @State private var detail: PrivateChallengeDetail?
    @State private var isLoading = true
    @State private var showAdminSettings = false
    @State private var showInviteSheet = false
    @State private var showShareSheet = false
    @State private var showMembersSheet = false
    @State private var showFullChat = false
    @State private var showLeaveConfirmation = false
    @State private var showEndConfirmation = false
    @State private var chatMessages: [PrivateChallengeMessage] = []
    @State private var chatText = ""
    @State private var isSendingMessage = false
    @State private var showModerationWarning = false
    // Sprint 2 Q2-7: Report-and-Block sheet (long-press a non-self message)
    @State private var reportTarget: PrivateChallengeMessage?
    // Chat keyboard focus — drives: (a) auto-scrolling the chat widget above
    // the keyboard, (b) dismissing the keyboard when the user taps or scrolls
    // anywhere outside the chat widget.
    @FocusState private var isChatInputFocused: Bool
    
    private var accentGradient: LinearGradient {
        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
    }
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()
                // Tap background to dismiss keyboard.
                .onTapGesture { isChatInputFocused = false }
            
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        headerCard
                            .simultaneousGesture(dismissKeyboardTapGesture)
                        statBar
                            .simultaneousGesture(dismissKeyboardTapGesture)
                        chatPreviewSection
                            .id("chatSection")
                        leaderboardSection
                            .simultaneousGesture(dismissKeyboardTapGesture)
                        actionButtons
                            .simultaneousGesture(dismissKeyboardTapGesture)
                            .padding(.bottom, 60)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                }
                // Any scroll gesture anywhere in this view dismisses the
                // keyboard immediately (covers the "scrolls off the chat
                // widget" case without needing a per-section gesture).
                .scrollDismissesKeyboard(.immediately)
                // When the chat input gains focus, pin the chat widget just
                // above the keyboard so the user can see what they're typing
                // along with the most recent messages.
                .onChange(of: isChatInputFocused) { _, focused in
                    guard focused else { return }
                    // Small delay lets the keyboard begin animating so the
                    // scroll lands at the final resting position.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("chatSection", anchor: .bottom)
                        }
                    }
                }
            }
        }
        // Phase 12 rage-shake fix (2026-04-24) — wire SessionLogManager so
        // BugReportView's `Files Claude will review` shows the correct
        // files when shaking here. Without this, a shake from this
        // screen would point Claude at whatever was tracked last
        // (historically .profile because the Profile tab is the only
        // social-area screen with trackScreen).
        .trackScreen(.privateChallengeDetail, metadata: ["challenge_id": challenge.id])
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showMembersSheet = true }) {
                        Label("Members", systemImage: "person.2.fill")
                    }
                    
                    if challenge.isAdmin {
                        Button(action: { showAdminSettings = true }) {
                            Label("Admin Settings", systemImage: "gearshape.fill")
                        }
                    }
                    
                    Button(action: { showInviteSheet = true }) {
                        Label("Invite Friends", systemImage: "person.badge.plus")
                    }
                    
                    Button(action: { showShareSheet = true }) {
                        Label("Share Join Code", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    if challenge.isAdmin {
                        Button(role: .destructive, action: { showEndConfirmation = true }) {
                            Label("End Challenge", systemImage: "xmark.octagon.fill")
                        }
                    }
                    
                    Button(role: .destructive, action: { showLeaveConfirmation = true }) {
                        Label("Leave Challenge", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.ds_heading3)
                }
            }
        }
        .sheet(isPresented: $showAdminSettings) {
            if let d = detail {
                PrivateChallengeAdminSettingsView(detail: d)
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            PrivateChallengeInviteView(challengeId: challenge.challengeId)
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = challenge.shareURL {
                ShareSheet(items: [
                    privateChallengeService.shareMessage(for: challenge),
                    url
                ])
            }
        }
        .sheet(isPresented: $showMembersSheet) {
            membersSheet
        }
        .fullScreenCover(isPresented: $showFullChat) {
            fullChatSheet
        }
        .confirmationDialog("Leave Challenge?", isPresented: $showLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                Task {
                    let _ = await privateChallengeService.leaveChallenge(challengeId: challenge.challengeId)
                    dismiss()
                }
            }
        } message: {
            Text("You'll lose your progress and rank in this challenge.")
        }
        .confirmationDialog("End Challenge?", isPresented: $showEndConfirmation) {
            Button("End Challenge", role: .destructive) {
                Task {
                    let _ = await privateChallengeService.endChallenge(challengeId: challenge.challengeId)
                    dismiss()
                }
            }
        } message: {
            Text("This will end the challenge for all members. This cannot be undone.")
        }
        .alert("Message Not Sent", isPresented: $showModerationWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your message was not sent because it may violate our community guidelines. Please keep conversations respectful.")
        }
        // Sprint 2 Q2-7 — Report & Block confirmation
        .confirmationDialog(
            "Report this message?",
            isPresented: Binding(
                get: { reportTarget != nil },
                set: { if !$0 { reportTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = reportTarget {
                Button("Report & Block", role: .destructive) {
                    Task { await performReportAndBlock(message: target) }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("We'll hide this message, flag it for review, and block the sender. You can manage blocks in Settings → Privacy & Security → Blocked Users.")
        }
        .task {
            await loadDetail()
            chatMessages = await privateChallengeService.fetchMessages(challengeId: challenge.challengeId)
            privateChallengeService.markChatAsRead(challengeId: challenge.challengeId)
        }
        .task(id: "chat-realtime") {
            // Direct realtime subscription for live chat updates while on this view
            let client = SupabaseManager.shared.supabaseClient
            let channel = client.realtimeV2.channel("private-chat-\(challenge.challengeId.uuidString)")
            
            let inserts = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "private_challenge_chat",
                filter: "challenge_id=eq.\(challenge.challengeId.uuidString)"
            )
            
            Task {
                for await _ in inserts {
                    AppLogger.debug("Live chat: new message in challenge", category: .social)
                    chatMessages = await privateChallengeService.fetchMessages(
                        challengeId: challenge.challengeId
                    )
                    // User is actively viewing the chat — stamp read-time so the
                    // card dot doesn't light up for a message they just saw.
                    privateChallengeService.markChatAsRead(challengeId: challenge.challengeId)
                }
            }
            
            await channel.subscribe()
            
            // Keep alive until view disappears (task cancellation unsubscribes)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
            
            await channel.unsubscribe()
        }
        .refreshable {
            await loadDetail()
            chatMessages = await privateChallengeService.fetchMessages(challengeId: challenge.challengeId)
        }
        .onChange(of: privateChallengeService.memberChangeToken) { _, _ in
            Task { await loadDetail() }
        }
        .onChange(of: showAdminSettings) { _, isShowing in
            if !isShowing {
                Task { await loadDetail() }
            }
        }
    }
    
    private func loadDetail() async {
        isLoading = detail == nil
        if let newDetail = await privateChallengeService.getChallengeDetail(challengeId: challenge.challengeId) {
            detail = newDetail
        }
        isLoading = false
    }
    
    // MARK: - Compact Header Card
    
    private var headerCard: some View {
        VStack(spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                challengeIconView(size: 48, emojiSize: 24)
                
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(challenge.title)
                        .font(.ds_heading3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "target")
                            .font(.ds_caption)
                            .foregroundColor(.purple)
                        Text("\(challenge.dailyTarget) \(challenge.targetUnit)/day")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    }
                    
                    if let desc = challenge.description, !desc.isEmpty {
                        Text(desc)
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer(minLength: 0)
                
                memberAvatarsColumn
            }
            
            badgesRow
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: 20, accentColor: .purple)
    }
    
    @ViewBuilder
    private func challengeIconView(size: CGFloat, emojiSize: CGFloat) -> some View {
        if let coverUrl = challenge.coverImageUrl, let url = URL(string: coverUrl) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1.5))
                } else {
                    emojiCircle(size: size, emojiSize: emojiSize)
                }
            }
        } else {
            emojiCircle(size: size, emojiSize: emojiSize)
        }
    }
    
    private func emojiCircle(size: CGFloat, emojiSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .pink.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            Text(challenge.displayEmoji)
                .font(.system(size: emojiSize))
        }
    }
    
    private var memberAvatarsColumn: some View {
        VStack(alignment: .trailing, spacing: Spacing.xxs) {
            if let topMembers = challenge.topMembers, !topMembers.isEmpty {
                HStack(spacing: -8) {
                    ForEach(Array(topMembers.prefix(4))) { member in
                        CachedFriendPhoto(
                            friendId: member.userId.uuidString,
                            photoUrl: member.profilePhotoUrl,
                            name: member.displayName,
                            size: 28,
                            showGradientRing: member.isAdmin,
                            gradientColors: member.isAdmin ? [.yellow, .orange] : [.purple, .pink]
                        )
                        .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 1.5))
                    }
                }
            }
            
            HStack(spacing: Spacing.xxxs) {
                Image(systemName: "person.2.fill")
                    .font(.ds_caption)
                Text(challenge.formattedMemberCount)
                    .font(.ds_labelSmall)
            }
            .foregroundColor(.secondary)
        }
    }
    
    private var badgesRow: some View {
        HStack(spacing: Spacing.xs) {
            if challenge.isRecurring {
                badgeCapsule(icon: "arrow.triangle.2.circlepath", text: "Recurring", color: .cyan)
            }
            
            if let unread = challenge.unreadCount, unread > 0 {
                HStack(spacing: Spacing.xxxs) {
                    Image(systemName: "bubble.left.fill")
                        .font(.ds_caption)
                    Text("\(unread)")
                        .font(.ds_labelSmall)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxxs)
                .background(Capsule().fill(Color.purple))
            }
            
            Spacer()
            
            if challenge.isAdmin {
                Text("Admin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.yellow)
            }
        }
    }
    
    private func badgeCapsule(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxxs)
        .background(Capsule().fill(color.opacity(0.12)))
    }
    
    // MARK: - League-Style Stat Bar
    
    private var statBar: some View {
        let resolver = ChallengeProgressResolver.shared
        let liveValue = resolver.liveProgress(for: challenge)
        let dailyTarget = detail?.dailyTarget ?? challenge.dailyTarget
        let progress = dailyTarget > 0 ? min(1.0, Double(liveValue) / Double(dailyTarget)) : 0
        let rank = detail?.myRank ?? challenge.myRank ?? 0
        let memberCount = detail?.memberCount ?? challenge.memberCount
        let streak = detail?.myCurrentStreak ?? challenge.myCurrentStreak ?? 0
        
        return VStack(spacing: Spacing.sm) {
            // Progress context line
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    Text(challenge.displayEmoji)
                        .font(.system(size: 14))
                    Text("\(Int(progress * 100))% of daily goal")
                        .font(.ds_labelSmall)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("\(liveValue)/\(dailyTarget) \(challenge.targetUnit)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.purple)
            }
            
            VStack(spacing: Spacing.xxs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.purple.opacity(colorScheme == .dark ? 0.12 : 0.08))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * progress, 6), height: 6)
                    }
                }
                .frame(height: 6)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        HStack {
                            Text("0")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Spacer()
                            
                            Text("\(dailyTarget)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(progress >= 1.0 ? .green : .secondary.opacity(0.5))
                        }
                        
                        if progress > 0 && progress < 1.0 {
                            Text("\(liveValue)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.purple)
                                .position(x: geo.size.width * progress, y: 6)
                        }
                    }
                }
                .frame(height: 12)
            }
            
            // Stats row with dividers (league pattern)
            HStack(spacing: 0) {
                statCell(value: "#\(rank)", label: "of \(memberCount)", valueColor: .purple)
                
                thinDivider
                
                statCell(
                    value: "\(liveValue)",
                    label: challenge.targetUnit,
                    valueColor: .primary
                )
                
                thinDivider
                
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(streak)")
                            .font(.ds_statSmall)
                            .foregroundColor(.primary)
                    }
                    Text("streak")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                thinDivider
                
                if let d = detail {
                    statCell(
                        value: "\(Int(d.completionRateToday * 100))%",
                        label: "completed",
                        valueColor: d.completionRateToday >= 0.5 ? .green : .primary
                    )
                } else {
                    statCell(value: "—", label: "completed", valueColor: .secondary)
                }
            }
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.06 : 0.04))
            )
        }
        .padding(Spacing.sm)
        .sleekCardSubtle(cornerRadius: 16)
    }
    
    private func statCell(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ds_statSmall)
                .foregroundColor(valueColor)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var thinDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 28)
    }
    
    // MARK: - Leaderboard Section
    
    private var leaderboardSection: some View {
        VStack(spacing: Spacing.sm) {
            // Section header
            HStack(spacing: Spacing.xs) {
                Image(systemName: "trophy.circle.fill")
                    .foregroundStyle(accentGradient)
                    .font(.title3)
                Text("Leaderboard")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let d = detail {
                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("\(d.totalActiveToday) active")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let leaderboard = detail?.leaderboard, !leaderboard.isEmpty {
                // Community stats mini bar
                if let d = detail {
                    communityStatsBar(detail: d)
                }
                
                // Leaderboard rows
                ForEach(leaderboard) { member in
                    leaderboardRow(member: member, dailyTarget: detail?.dailyTarget ?? challenge.dailyTarget)
                }
            } else if isLoading {
                ProgressView()
                    .tint(.purple)
                    .padding(Spacing.xl)
            } else {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "trophy")
                        .font(.ds_heading1)
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No leaderboard data yet")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
                .padding(Spacing.xl)
            }
        }
    }
    
    private func communityStatsBar(detail d: PrivateChallengeDetail) -> some View {
        HStack(spacing: 0) {
            miniStatCell(value: "\(d.avgTodayProgress)", label: "avg \(challenge.targetUnit)")
            
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1, height: 20)
            
            miniStatCell(value: "\(d.totalActiveToday)", label: "active today")
            
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1, height: 20)
            
            miniStatCell(value: "\(Int(d.completionRateToday * 100))%", label: "hit goal")
        }
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.purple.opacity(colorScheme == .dark ? 0.06 : 0.04))
        )
    }
    
    private func miniStatCell(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func leaderboardRow(member: PrivateChallengeMember, dailyTarget: Int) -> some View {
        let isMe = member.isCurrentUser ?? false
        let displayProgress = isMe
            ? ChallengeProgressResolver.shared.liveProgress(for: challenge)
            : (member.todayProgress ?? 0)
        let progress = dailyTarget > 0 ? min(1.0, Double(displayProgress) / Double(dailyTarget)) : 0
        let rank = member.rank ?? 0
        
        return HStack(spacing: Spacing.sm) {
            // Rank with medal
            ZStack {
                if rank <= 3 {
                    Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉")
                        .font(.system(size: 16))
                } else {
                    Text("#\(rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(isMe ? .purple : .secondary)
                }
            }
            .frame(width: 26)
            
            CachedFriendPhoto(
                friendId: member.userId.uuidString,
                photoUrl: member.profilePhotoUrl,
                name: member.displayName,
                size: 32,
                showGradientRing: member.isAdmin,
                gradientColors: member.isAdmin ? [.yellow, .orange] : [.purple, .pink]
            )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(isMe ? "You" : member.firstName)
                        .font(.system(size: 13, weight: isMe ? .bold : .medium))
                        .foregroundColor(isMe ? .primary : .secondary)
                        .lineLimit(1)
                    
                    if member.isVerified == true || member.isGoldVerified == true {
                        VerifiedBadge(size: 11, isGold: member.isGoldVerified == true)
                    }
                    
                    if member.isAdmin {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.yellow)
                    }
                }
                
                // Inline progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 3)
                        
                        Capsule()
                            .fill(accentGradient)
                            .frame(width: geometry.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)
            }
            
            Spacer()
            
            // Score
            VStack(alignment: .trailing, spacing: 1) {
                Text(!isMe && displayProgress == 0 ? "–" : "\(displayProgress)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(!isMe && displayProgress == 0 ? .secondary.opacity(0.5) : (isMe ? .purple : .primary))
                
                if (isMe ? (displayProgress >= dailyTarget && dailyTarget > 0) : (member.targetHitToday ?? false)) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isMe
                    ? Color.purple.opacity(colorScheme == .dark ? 0.12 : 0.08)
                    : Color.clear)
        )
    }
    
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color(white: 0.75)
        case 3: return .orange
        default: return .secondary
        }
    }
    
    // MARK: - Chat Preview Section
    
    // Chat preview keeps a fixed maximum height so the widget never grows with
    // message history. Older messages flow off the top (clipped); newest stay
    // pinned to the bottom just above the input bar. Tap the expand button in
    // the top-right to open the full-screen chat sheet.
    // Phase 12c — rage-shake f990840d user feedback:
    //   "when i tap into the private challenge - the chat view is so
    //    bulking and doesn't look right"
    //   "i need this page to flow better feel less bulky with the chat..
    //    integrate the chat so it's more clean and seamless"
    //
    // Conservative pass (not a full redesign — that deserves its own
    // design session):
    //   - Drop the big standalone "Chat" title row (`title3 + bold`)
    //     and inline the expand affordance into the top-right of the
    //     card. Unread badge stays, but as a pill next to the bubble
    //     icon so the card header feels lighter.
    //   - Reduce chat max height 280 → 220 to shorten the widget's
    //     visual footprint so the leaderboard + action buttons sit
    //     closer and the page scans as one page instead of stacked
    //     cards.
    //   - Tighten inner padding (`Spacing.md` → `Spacing.sm`) so the
    //     card edges hug the content.
    //   - Keep `sleekCardSubtle` so the card still has a visual home,
    //     but smaller corner radius (16 → 14) for consistency with
    //     nearby stat cards.
    //
    // If the next shake still says "bulky", the next pass should
    // consider removing the card chrome entirely and letting chat
    // bubbles flow inline with the rest of the page.
    private static let chatPreviewMaxHeight: CGFloat = 220

    private var chatPreviewSection: some View {
        VStack(spacing: Spacing.xs) {
            let visibleChatMessages = chatMessages.filter {
                !friendService.blockedUserIds.contains($0.senderId)
                    && !PrivateChallengeService.shared.hiddenChatMessageIds.contains($0.messageId)
            }

            // Lightweight inline header — no standalone title row.
            HStack(spacing: Spacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(accentGradient)
                    .font(.ds_labelLarge)

                if let unread = challenge.unreadCount, unread > 0 {
                    Text("\(unread) new")
                        .font(.ds_caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                }

                Spacer(minLength: 0)

                Button {
                    showFullChat = true
                    HapticManager.selectionChanged()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(Color.primary.opacity(0.06))
                        )
                }
                .accessibilityLabel("Expand chat")
                .accessibilityHint("Opens the full-screen chat view")
            }

            if visibleChatMessages.isEmpty {
                VStack(spacing: Spacing.xxs) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.ds_heading3)
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No messages yet")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    Text("Start the conversation!")
                        .font(.ds_caption)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.vertical, Spacing.md)
            } else {
                // Chronological (oldest -> newest) so the newest bubble
                // is at the bottom of the bounded scroll view. Older
                // messages flow off the top; the user can scroll up
                // within this area, or tap expand for full history.
                // `.defaultScrollAnchor(.bottom)` keeps the view pinned
                // to the latest message on open and when new messages
                // arrive.
                let chronological = Array(visibleChatMessages.reversed())
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(Array(chronological.enumerated()), id: \.element.id) { index, message in
                            if shouldShowDateHeader(for: message, in: chronological, at: index) {
                                chatDateHeader(for: message.createdAt ?? Date())
                            }
                            chatBubble(message: message)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .defaultScrollAnchor(.bottom)
                .frame(maxWidth: .infinity, maxHeight: Self.chatPreviewMaxHeight)
            }

            chatInputBar
        }
        .padding(Spacing.sm)
        .sleekCardSubtle(cornerRadius: 14)
    }
    
    // Shared tap gesture for every non-chat section in the detail scroll view —
    // tapping anywhere off the chat widget dismisses the keyboard without
    // blocking button presses or scroll gestures inside that section.
    private var dismissKeyboardTapGesture: some Gesture {
        TapGesture().onEnded { isChatInputFocused = false }
    }

    private var chatInputBar: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Message...", text: $chatText)
                .focused($isChatInputFocused)
                .submitLabel(.send)
                .onSubmit { sendMessage() }
                .font(.ds_bodySmall)
                .foregroundColor(.primary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
            
            Button(action: sendMessage) {
                if isSendingMessage {
                    ProgressView()
                        .tint(.purple)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.ds_bodySmall)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(accentGradient)
                        .clipShape(Circle())
                }
            }
            .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty || isSendingMessage)
        }
    }
    
    private func sendMessage() {
        guard !chatText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = chatText
        chatText = ""
        isSendingMessage = true
        Task {
            let result = await privateChallengeService.sendMessage(
                challengeId: challenge.challengeId,
                content: text
            )
            
            if result.isBlocked {
                showModerationWarning = true
                HapticManager.notification(.error)
            } else {
                chatMessages = await privateChallengeService.fetchMessages(
                    challengeId: challenge.challengeId
                )
            }
            isSendingMessage = false
        }
    }

    /// Sprint 2 Q2-7 — report a message + block the sender. Local chat is
    /// purged immediately (optimistic) and the server hides the row for
    /// everyone via content_moderation_log + user_blocks.
    private func performReportAndBlock(message: PrivateChallengeMessage) async {
        let senderId = message.senderId
        let targetId = message.messageId
        async let reported = friendService.reportContent(
            tableName: "private_challenge_chat",
            recordId: targetId.uuidString,
            reportedUserId: senderId,
            contentSnippet: message.content,
            reason: "Reported in private challenge chat"
        )
        async let blocked = friendService.blockUser(userId: senderId)
        _ = await (reported, blocked)

        // Purge this sender from the local chat buffer immediately.
        chatMessages.removeAll { $0.senderId == senderId }
        HapticManager.notification(.success)
        reportTarget = nil
    }
    
    private func chatBubble(message: PrivateChallengeMessage) -> some View {
        Group {
            if message.isSystemMessage || message.isMilestoneMessage {
                HStack {
                    Spacer()
                    Text(message.content)
                        .font(.ds_caption)
                        .foregroundColor(message.isMilestoneMessage ? .yellow : .secondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.04))
                        )
                    Spacer()
                }
            } else if message.isCurrentUser {
                // Current user: bubble on the right, photo on far right
                HStack(alignment: .bottom, spacing: 6) {
                    Spacer(minLength: 40)
                    
                    Text(message.content)
                        .font(.ds_bodySmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(accentGradient)
                        )
                    
                    currentUserPhoto(size: 26)
                }
            } else {
                // Other user: photo on far left, bubble on the left
                HStack(alignment: .bottom, spacing: 6) {
                    CachedFriendPhoto(
                        friendId: message.senderId.uuidString,
                        photoUrl: message.senderPhotoUrl,
                        name: message.senderDisplayName,
                        size: 26,
                        showGradientRing: false,
                        gradientColors: [.purple, .pink]
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.senderFirstName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.purple)
                        
                        Text(message.content)
                            .font(.ds_bodySmall)
                            .foregroundColor(.primary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .contextMenu {
                                // Sprint 2 Q2-7 — long-press "Report & Block"
                                Button(role: .destructive) {
                                    reportTarget = message
                                } label: {
                                    Label("Report & Block", systemImage: "flag.fill")
                                }
                            }
                            .accessibilityHint("Long-press to report or block this user")
                    }
                    
                    Spacer(minLength: 40)
                }
            }
        }
    }
    
    @ViewBuilder
    private func currentUserPhoto(size: CGFloat) -> some View {
        if let cachedImage = ProfilePhotoCache.shared.cachedImage {
            Image(uiImage: cachedImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(accentGradient)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundColor(.white)
                )
        }
    }
    
    // MARK: - Chat Date Helpers
    
    private func shouldShowDateHeader(for message: PrivateChallengeMessage, in messages: [PrivateChallengeMessage], at index: Int) -> Bool {
        guard let messageDate = message.createdAt else { return false }
        if index == 0 { return true }
        guard let previousDate = messages[index - 1].createdAt else { return true }
        return !Calendar.current.isDate(messageDate, inSameDayAs: previousDate)
    }
    
    private func chatDateHeader(for date: Date) -> some View {
        HStack {
            Spacer()
            Text(formatChatDate(date))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxxs)
                .background(
                    Capsule().fill(Color.primary.opacity(0.04))
                )
            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    private func formatChatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: { showInviteSheet = true }) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "person.badge.plus")
                        .font(.ds_bodySmall)
                    Text("Invite")
                        .font(.ds_labelMedium)
                }
                .foregroundStyle(accentGradient)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule().stroke(accentGradient, lineWidth: 1.5)
                )
            }
            
            Button(action: { showShareSheet = true }) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.ds_bodySmall)
                    Text(challenge.joinCode)
                        .font(.ds_labelMedium)
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
            }
        }
    }
    
    // MARK: - Members Sheet
    
    private var membersSheet: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.sm) {
                        if let leaderboard = detail?.leaderboard, !leaderboard.isEmpty {
                            ForEach(leaderboard) { member in
                                memberRow(member: member)
                            }
                        } else {
                            ProgressView()
                                .tint(.purple)
                                .padding(Spacing.xl)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showMembersSheet = false }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
    
    private func memberRow(member: PrivateChallengeMember) -> some View {
        let isMe = member.isCurrentUser ?? false
        
        return HStack(spacing: Spacing.sm) {
            CachedFriendPhoto(
                friendId: member.userId.uuidString,
                photoUrl: member.profilePhotoUrl,
                name: member.displayName,
                size: 40,
                showGradientRing: member.isAdmin,
                gradientColors: member.isAdmin ? [.yellow, .orange] : [.purple, .pink]
            )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxs) {
                    Text(member.displayName)
                        .font(.ds_bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if member.isVerified == true || member.isGoldVerified == true {
                        VerifiedBadge(size: 13, isGold: member.isGoldVerified == true)
                    }
                    
                    if member.isAdmin {
                        Text("Admin")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.yellow.opacity(0.15)))
                    }
                }
                
                HStack(spacing: Spacing.xs) {
                    Label("\(member.daysCompleted ?? 0) days", systemImage: "flame.fill")
                    Label("\(member.currentStreak ?? 0) streak", systemImage: "bolt.fill")
                }
                .font(.ds_caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if challenge.isAdmin && !isMe {
                Menu {
                    if member.isAdmin {
                        Button(action: {
                            Task {
                                let _ = await privateChallengeService.demoteFromAdmin(
                                    challengeId: challenge.challengeId,
                                    userId: member.userId
                                )
                                await loadDetail()
                            }
                        }) {
                            Label("Demote to Member", systemImage: "arrow.down.circle")
                        }
                    } else {
                        Button(action: {
                            Task {
                                let _ = await privateChallengeService.promoteToAdmin(
                                    challengeId: challenge.challengeId,
                                    userId: member.userId
                                )
                                await loadDetail()
                            }
                        }) {
                            Label("Make Admin", systemImage: "crown.fill")
                        }
                    }
                    
                    Button(role: .destructive, action: {
                        Task {
                            let _ = await privateChallengeService.removeMember(
                                challengeId: challenge.challengeId,
                                userId: member.userId
                            )
                            await loadDetail()
                        }
                    }) {
                        Label("Remove from Challenge", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(Spacing.sm)
        .sleekCardSubtle(cornerRadius: 14)
    }
    
    // MARK: - Full Chat Sheet
    
    private var fullChatSheet: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        let allMessages = Array(
                            chatMessages
                                .filter {
                                    !friendService.blockedUserIds.contains($0.senderId)
                                        && !PrivateChallengeService.shared.hiddenChatMessageIds.contains($0.messageId)
                                }
                                .reversed()
                        )
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(Array(allMessages.enumerated()), id: \.element.id) { index, message in
                                if shouldShowDateHeader(for: message, in: allMessages, at: index) {
                                    chatDateHeader(for: message.createdAt ?? Date())
                                }
                                chatBubble(message: message)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xs)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.immediately)
                    
                    // Sticky input bar
                    chatInputBar
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle(challenge.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showFullChat = false
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
    }
}
