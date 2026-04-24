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
    private var typeGradient: LinearGradient {
        LinearGradient(colors: resolvedType.gradientColors, startPoint: .leading, endPoint: .trailing)
    }
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.md) {
                    headerCard
                    membersSection
                    statsSection
                    
                    if !pendingMembers.isEmpty {
                        pendingSection
                    }
                    
                    actionsSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, 60)
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
            // Subscribe to real-time opponent progress updates for this group challenge
            RealtimeService.shared.onOpponentDailyProgressUpdated = { payload in
                if payload.challengeId == challenge.challengeId {
                    Task {
                        await challengeService.fetchActiveGroupChallenges()
                    }
                }
            }
            
            // Periodic refresh as a safety net (every 2 minutes)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                await challengeService.fetchActiveGroupChallenges()
            }
        }
        .onDisappear {
            RealtimeService.shared.onOpponentDailyProgressUpdated = nil
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
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    Text(resolvedType.emoji)
                        .font(.system(size: 14))
                    Text(resolvedType.displayName)
                        .font(.ds_labelSmall)
                        .fontWeight(.bold)
                }
                .foregroundColor(typeColor)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxxs)
                .background(Capsule().fill(typeColor.opacity(0.12)))
                
                HStack(spacing: Spacing.xxs) {
                    Text(isAccountability ? "🤝" : "⚔️")
                        .font(.system(size: 11))
                    Text(isAccountability ? "Accountability" : "Competition")
                        .font(.ds_labelSmall)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(typeGradient)
                
                Spacer()
                
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    if challenge.daysRemaining > 0 {
                        Text("\(challenge.daysRemaining)d left")
                    } else {
                        Text("Complete")
                    }
                }
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
            }
            
            Text(liveChallenge.displayTitle)
                .font(.ds_heading2)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: -10) {
                ForEach(Array(acceptedMembers.enumerated()), id: \.element.id) { index, member in
                    memberAvatar(member: member, size: 44)
                        .zIndex(Double(acceptedMembers.count - index))
                }
                
                if !pendingMembers.isEmpty {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 44, height: 44)
                        Text("+\(pendingMembers.count)")
                            .font(.ds_labelSmall)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                Text("\(acceptedMembers.count) members")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
            
            if let target = challenge.dailyTarget {
                HStack {
                    Text("Daily Goal")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(target) \(challenge.targetUnit)")
                        .font(.ds_statSmall)
                        .foregroundStyle(typeGradient)
                }
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(typeColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
                        .frame(height: 6)
                    
                    let progress = challenge.durationDays > 0
                        ? CGFloat(challenge.daysElapsed) / CGFloat(challenge.durationDays)
                        : 0
                    
                    Capsule()
                        .fill(typeGradient)
                        .frame(width: max(geo.size.width * min(1, progress), 6), height: 6)
                        .animation(.spring(response: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: 20, accentColor: typeColor)
    }
    
    // MARK: - Members Section
    
    private var membersSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isAccountability ? "person.3.fill" : "trophy.fill")
                    .foregroundStyle(typeGradient)
                    .font(.title3)
                Text(isAccountability ? "Team Check-In" : "Leaderboard")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Day \(challenge.daysElapsed) of \(challenge.durationDays)")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(acceptedMembers.enumerated()), id: \.element.id) { rank, member in
                    memberRow(member: member, rank: rank + 1)
                    
                    if rank < acceptedMembers.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 1)
                            .padding(.horizontal, Spacing.sm)
                    }
                }
            }
            .sleekCardSubtle(cornerRadius: 16)
        }
    }
    
    private func memberRow(member: GroupChallengeMember, rank: Int) -> some View {
        let currentUserId = userManager.currentUser?.id
        let isMe = currentUserId != nil && member.userId == currentUserId
        let target = challenge.dailyTarget ?? 0
        let displayProgress = isMe
            ? ChallengeProgressResolver.shared.liveProgress(for: challenge, serverValue: member.todayProgress)
            : member.todayProgress
        let completedToday = target > 0 && displayProgress >= target
        
        return HStack(spacing: Spacing.sm) {
            if isAccountability {
                Text(completedToday ? "✅" : "⬜")
                    .font(.ds_heading3)
            } else {
                ZStack {
                    Circle()
                        .fill(rank == 1
                            ? LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 28, height: 28)
                    
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.ds_labelSmall)
                            .foregroundColor(.white)
                    } else {
                        Text("\(rank)")
                            .font(.ds_labelSmall)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
            
            memberAvatar(member: member, size: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(isMe ? "You" : member.firstName)
                        .font(.ds_bodySmall)
                        .fontWeight(.semibold)
                    
                    if member.isVerified == true || member.isGoldVerified == true {
                        VerifiedBadge(size: 12, isGold: member.isGoldVerified == true)
                    }
                }
                
                if member.currentStreak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("\(member.currentStreak)-day streak")
                            .font(.ds_caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: Spacing.xxxs) {
                    Text(!isMe && displayProgress == 0 ? "–" : "\(displayProgress)")
                        .font(.ds_statSmall)
                        .foregroundColor(!isMe && displayProgress == 0 ? .secondary.opacity(0.5) : (completedToday ? .green : .primary))
                    
                    if completedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                }
                
                Text("today")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(typeGradient)
                    .font(.title3)
                Text("Group Stats")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            HStack(spacing: 0) {
                groupStatCell(
                    value: formatGroupTotal(acceptedMembers.reduce(0) { $0 + $1.totalProgress }),
                    label: "combined",
                    valueColor: typeColor
                )
                
                groupThinDivider
                
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(acceptedMembers.map(\.currentStreak).max() ?? 0)")
                            .font(.ds_statSmall)
                            .foregroundColor(.primary)
                    }
                    Text("best streak")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                groupThinDivider
                
                groupStatCell(
                    value: "\(challenge.daysRemaining)",
                    label: challenge.daysRemaining == 1 ? "day left" : "days left",
                    valueColor: challenge.daysRemaining <= 1 ? .red : .primary
                )
                
                groupThinDivider
                
                groupStatCell(
                    value: {
                        let target = challenge.dailyTarget ?? 0
                        let done = target > 0 ? acceptedMembers.filter { $0.todayProgress >= target }.count : 0
                        return "\(done)/\(acceptedMembers.count)"
                    }(),
                    label: "done today",
                    valueColor: .green
                )
            }
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(typeColor.opacity(colorScheme == .dark ? 0.06 : 0.04))
            )
        }
        .padding(Spacing.sm)
        .sleekCardSubtle(cornerRadius: 16)
    }
    
    private func groupStatCell(value: String, label: String, valueColor: Color) -> some View {
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
    
    private var groupThinDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 28)
    }
    
    private func formatGroupTotal(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
    
    // MARK: - Pending Section
    
    private var pendingSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "hourglass.circle.fill")
                    .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .font(.title3)
                Text("Waiting to Join")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 0) {
                ForEach(Array(pendingMembers.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: Spacing.sm) {
                        memberAvatar(member: member, size: 36)
                        
                        Text(member.firstName)
                            .font(.ds_bodySmall)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("Pending")
                            .font(.ds_labelSmall)
                            .fontWeight(.semibold)
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
            .sleekCardSubtle(cornerRadius: 16)
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
                        .fontWeight(.medium)
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
                .disabled(isProcessing)
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
    
    // MARK: - Helper
    
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
