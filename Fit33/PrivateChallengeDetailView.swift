//
//  PrivateChallengeDetailView.swift
//  Fit33
//
//  Detail view for a Private Challenge — shows leaderboard, members, chat,
//  admin settings, and invite management. The central hub for each private challenge.
//

import SwiftUI

struct PrivateChallengeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared
    @ObservedObject private var friendService = FriendService.shared
    
    let challenge: PrivateChallenge
    
    @State private var detail: PrivateChallengeDetail?
    @State private var isLoading = true
    @State private var selectedTab: DetailTab = .leaderboard
    @State private var showAdminSettings = false
    @State private var showInviteSheet = false
    @State private var showShareSheet = false
    @State private var showLeaveConfirmation = false
    @State private var showEndConfirmation = false
    
    enum DetailTab: String, CaseIterable {
        case leaderboard = "Leaderboard"
        case members = "Members"
        case chat = "Chat"
    }
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.home(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header card
                    headerCard
                    
                    // Progress ring
                    progressSection
                    
                    // Tab selector
                    tabSelector
                    
                    // Tab content
                    switch selectedTab {
                    case .leaderboard:
                        leaderboardSection
                    case .members:
                        membersSection
                    case .chat:
                        chatSection
                    }
                    
                    // Action buttons
                    actionButtons
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
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
        .task {
            await loadDetail()
        }
        .refreshable {
            await loadDetail()
        }
        .onChange(of: privateChallengeService.memberChangeToken) { _, _ in
            // A member joined or left — reload detail for live member list
            Task { await loadDetail() }
        }
    }
    
    private func loadDetail() async {
        isLoading = true
        detail = await privateChallengeService.getChallengeDetail(challengeId: challenge.challengeId)
        isLoading = false
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            // Emoji + title
            Text(challenge.displayEmoji)
                .font(.system(size: 48))
            
            Text(challenge.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            if let desc = challenge.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            // Badges row
            HStack(spacing: 10) {
                // Private badge
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.ds_caption)
                    Text("Private")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, Spacing.xxs)
                .background(Capsule().fill(Color.purple.opacity(0.15)))
                
                // Member count
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.ds_caption)
                    Text(challenge.formattedMemberCount)
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, Spacing.xxs)
                .background(Capsule().fill(Color.blue.opacity(0.15)))
                
                // Admin badge
                if challenge.isAdmin {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.ds_caption)
                        Text("Admin")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, Spacing.xxs)
                    .background(Capsule().fill(Color.yellow.opacity(0.15)))
                }
            }
            
            // Member avatars row
            if let topMembers = challenge.topMembers, !topMembers.isEmpty {
                HStack(spacing: -10) {
                    ForEach(Array(topMembers.prefix(8))) { member in
                        CachedFriendPhoto(
                            friendId: member.userId.uuidString,
                            photoUrl: member.profilePhotoUrl,
                            name: member.displayName,
                            size: 36,
                            showGradientRing: member.isAdmin,
                            gradientColors: member.isAdmin ? [.yellow, .orange] : [.purple, .pink]
                        )
                        .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 2))
                    }
                    if challenge.memberCount > 8 {
                        Circle()
                            .fill(Color.purple.opacity(0.3))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text("+\(challenge.memberCount - 8)")
                                    .font(.ds_caption)
                                    .foregroundColor(.white)
                            )
                            .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 2))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.16), Color(white: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        let resolver = ChallengeProgressResolver.shared
        let liveValue = resolver.liveProgress(for: challenge)
        let dailyTarget = detail?.dailyTarget ?? challenge.dailyTarget
        let progress = dailyTarget > 0 ? min(1.0, Double(liveValue) / Double(dailyTarget)) : 0
        let todayProgress = liveValue
        let rank = detail?.myRank ?? challenge.myRank ?? 0
        
        return VStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 10)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5), value: progress)
                
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("today")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Stats row
            HStack(spacing: 24) {
                statItem(value: "\(todayProgress)", label: challenge.targetUnit, icon: "flame.fill", color: .orange)
                statItem(value: "\(dailyTarget)", label: "goal", icon: "target", color: .purple)
                statItem(value: "#\(rank)", label: "rank", icon: "trophy.fill", color: .yellow)
                statItem(value: "\(detail?.myCurrentStreak ?? challenge.myCurrentStreak ?? 0)", label: "streak", icon: "bolt.fill", color: .cyan)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
                .foregroundColor(color)
            Text(value)
                .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                    HapticManager.impact(.light)
                }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .bold : .medium)
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                        
                        Rectangle()
                            .fill(selectedTab == tab
                                ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.clear))
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Spacing.xxs)
    }
    
    // MARK: - Leaderboard Section
    
    private var leaderboardSection: some View {
        VStack(spacing: 12) {
            if let leaderboard = detail?.leaderboard, !leaderboard.isEmpty {
                // Community stats bar
                if let d = detail {
                    HStack(spacing: 16) {
                        miniStat(value: "\(d.avgTodayProgress)", label: "avg")
                        miniStat(value: "\(d.totalActiveToday)", label: "active")
                        miniStat(value: "\(Int(d.completionRateToday * 100))%", label: "done")
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                
                ForEach(leaderboard) { member in
                    leaderboardRow(member: member, dailyTarget: detail?.dailyTarget ?? challenge.dailyTarget)
                }
            } else if isLoading {
                ProgressView()
                    .tint(.purple)
                    .padding(40)
            } else {
                Text("No leaderboard data yet")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(40)
            }
        }
    }
    
    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func leaderboardRow(member: PrivateChallengeMember, dailyTarget: Int) -> some View {
        let isMe = member.isCurrentUser ?? false
        // Use live HealthKit/tracking data for current user, DB data for others
        let displayProgress = isMe
            ? ChallengeProgressResolver.shared.liveProgress(for: challenge)
            : (member.todayProgress ?? 0)
        let progress = dailyTarget > 0 ? min(1.0, Double(displayProgress) / Double(dailyTarget)) : 0
        
        return HStack(spacing: 12) {
            // Rank
            Text("\(member.rank ?? 0)")
                .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                .foregroundColor(rankColor(member.rank ?? 0))
                .frame(width: 24)
            
            // Avatar
            CachedFriendPhoto(
                friendId: member.userId.uuidString,
                photoUrl: member.profilePhotoUrl,
                name: member.displayName,
                size: 36,
                showGradientRing: member.isAdmin,
                gradientColors: member.isAdmin ? [.yellow, .orange] : [.purple, .pink]
            )
            
            // Name + role
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.firstName)
                        .font(.subheadline)
                        .fontWeight(isMe ? .bold : .semibold)
                        .foregroundColor(isMe ? .purple : .white)
                    
                    if member.isVerified == true || member.isGoldVerified == true {
                        VerifiedBadge(size: 13, isGold: member.isGoldVerified == true)
                    }
                    
                    if member.isAdmin {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                    
                    if isMe {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.2)))
                    }
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(
                                LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            Spacer()
            
            // Today's progress (live for current user, DB for others)
            VStack(alignment: .trailing, spacing: 2) {
                Text(!isMe && displayProgress == 0 ? "–" : "\(displayProgress)")
                    .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(!isMe && displayProgress == 0 ? .white.opacity(0.3) : .white)
                
                if (isMe ? (displayProgress >= dailyTarget && dailyTarget > 0) : (member.targetHitToday ?? false)) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_bodySmall)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isMe ? Color.purple.opacity(0.1) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isMe ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
    
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color(white: 0.75)
        case 3: return .orange
        default: return .white.opacity(0.5)
        }
    }
    
    // MARK: - Members Section
    
    private var membersSection: some View {
        VStack(spacing: 12) {
            if let leaderboard = detail?.leaderboard, !leaderboard.isEmpty {
                ForEach(leaderboard) { member in
                    memberRow(member: member)
                }
            } else {
                Text("Loading members...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(40)
            }
        }
    }
    
    private func memberRow(member: PrivateChallengeMember) -> some View {
        let isMe = member.isCurrentUser ?? false
        
        return HStack(spacing: 14) {
            CachedFriendPhoto(
                friendId: member.userId.uuidString,
                photoUrl: member.profilePhotoUrl,
                name: member.displayName,
                size: 44,
                showGradientRing: member.isAdmin,
                gradientColors: member.isAdmin ? [.yellow, .orange] : [.purple, .pink]
            )
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(member.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    if member.isVerified == true || member.isGoldVerified == true {
                        VerifiedBadge(size: 13, isGold: member.isGoldVerified == true)
                    }
                    
                    if member.isAdmin {
                        Text("Admin")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow.opacity(0.15)))
                    }
                }
                
                HStack(spacing: 8) {
                    Label("\(member.daysCompleted ?? 0)d", systemImage: "flame.fill")
                    Label("\(member.currentStreak ?? 0)🔥", systemImage: "bolt.fill")
                }
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Admin actions
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
                        .font(.ds_labelLarge)
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Chat Section (Preview — full chat in future)
    
    @State private var chatMessages: [PrivateChallengeMessage] = []
    @State private var chatText = ""
    @State private var isSendingMessage = false
    
    private var chatSection: some View {
        VStack(spacing: 12) {
            // Messages
            if chatMessages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.ds_heading1)
                        .foregroundColor(.white.opacity(0.3))
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                    Text("Be the first to say something!")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.vertical, 40)
            } else {
                // Show messages in reverse-chronological (newest at bottom)
                ForEach(chatMessages.reversed()) { message in
                    chatBubble(message: message)
                }
            }
            
            // Input bar
            HStack(spacing: 10) {
                TextField("Message...", text: $chatText)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(Spacing.sm)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(20)
                
                Button(action: {
                    guard !chatText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let text = chatText
                    chatText = ""
                    isSendingMessage = true
                    Task {
                        let _ = await privateChallengeService.sendMessage(
                            challengeId: challenge.challengeId,
                            content: text
                        )
                        chatMessages = await privateChallengeService.fetchMessages(
                            challengeId: challenge.challengeId
                        )
                        isSendingMessage = false
                    }
                }) {
                    if isSendingMessage {
                        ProgressView()
                            .tint(.purple)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.ds_labelLarge)
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(Circle())
                    }
                }
                .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty || isSendingMessage)
            }
        }
        .task {
            chatMessages = await privateChallengeService.fetchMessages(challengeId: challenge.challengeId)
        }
    }
    
    private func chatBubble(message: PrivateChallengeMessage) -> some View {
        Group {
            if message.isSystemMessage || message.isMilestoneMessage {
                // System / milestone message (centered)
                HStack {
                    Spacer()
                    Text(message.content)
                        .font(.caption)
                        .foregroundColor(message.isMilestoneMessage ? .yellow : .white.opacity(0.5))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.white.opacity(0.06))
                        )
                    Spacer()
                }
            } else {
                // User message
                HStack(alignment: .top, spacing: 8) {
                    if !message.isCurrentUser {
                        CachedFriendPhoto(
                            friendId: message.senderId.uuidString,
                            photoUrl: message.senderPhotoUrl,
                            name: message.senderDisplayName,
                            size: 28,
                            showGradientRing: false,
                            gradientColors: [.purple, .pink]
                        )
                    }
                    
                    VStack(alignment: message.isCurrentUser ? .trailing : .leading, spacing: 2) {
                        if !message.isCurrentUser {
                            Text(message.senderFirstName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                        }
                        
                        Text(message.content)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(message.isCurrentUser
                                        ? LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                            )
                    }
                    
                    if message.isCurrentUser { Spacer() } else { Spacer() }
                }
                .frame(maxWidth: .infinity, alignment: message.isCurrentUser ? .trailing : .leading)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Invite friends button
            Button(action: { showInviteSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.ds_labelLarge)
                    Text("Invite Friends")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule().stroke(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2
                    )
                )
            }
            
            // Share join code
            Button(action: { showShareSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.ds_bodySmall)
                    Text("Share Code: \(challenge.joinCode)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )
            }
        }
    }
}
