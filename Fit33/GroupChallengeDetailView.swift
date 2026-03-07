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
    
    private var accentGradient: [Color] {
        isAccountability ? [.blue, .cyan] : [.orange, .red]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header card
                headerCard
                
                // Members leaderboard / check-in
                membersSection
                
                // Stats overview
                statsSection
                
                // Pending members
                if !pendingMembers.isEmpty {
                    pendingSection
                }
                
                // Actions section (Leave / Cancel)
                actionsSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(
            AnimatedOrbBackground.home(colorScheme: colorScheme)
                .ignoresSafeArea()
        )
        .navigationTitle(liveChallenge.displayTitle)
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
        VStack(spacing: 16) {
            // Challenge type + mode
            HStack(spacing: 8) {
                Text(challenge.type?.emoji ?? "🏆")
                    .font(.system(size: 36))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.displayTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 6) {
                        Text(isAccountability ? "🤝 Accountability" : "⚔️ Competition")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing))
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(challenge.daysRemaining) days left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Member avatars overlapping
            HStack(spacing: -12) {
                ForEach(Array(acceptedMembers.enumerated()), id: \.element.id) { index, member in
                    memberAvatar(member: member, size: 46)
                        .zIndex(Double(acceptedMembers.count - index))
                }
                
                if !pendingMembers.isEmpty {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 46, height: 46)
                        Text("+\(pendingMembers.count)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
            }
            
            // Daily target
            if let target = challenge.dailyTarget {
                HStack {
                    Text("Daily Goal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(target) \(challenge.targetUnit)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing))
                }
            }
            
            // Progress bar (days elapsed)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    
                    let progress = challenge.durationDays > 0
                        ? CGFloat(challenge.daysElapsed) / CGFloat(challenge.durationDays)
                        : 0
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * min(1, progress), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(colors: accentGradient.map { $0.opacity(0.3) }, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Members Section
    
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isAccountability ? "Team Check-In" : "Leaderboard")
                .font(.headline)
                .fontWeight(.bold)
            
            ForEach(Array(acceptedMembers.enumerated()), id: \.element.id) { rank, member in
                memberRow(member: member, rank: rank + 1)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.97))
        )
    }
    
    private func memberRow(member: GroupChallengeMember, rank: Int) -> some View {
        let currentUserId = userManager.currentUser?.id
        let isMe = currentUserId != nil && member.userId == currentUserId
        let target = challenge.dailyTarget ?? 0
        // Use live HealthKit data for current user, DB data for others
        let displayProgress = isMe
            ? ChallengeProgressResolver.shared.liveProgress(for: challenge, serverValue: member.todayProgress)
            : member.todayProgress
        let completedToday = target > 0 && displayProgress >= target
        
        return HStack(spacing: 12) {
            // Rank or check
            if isAccountability {
                Text(completedToday ? "✅" : "⬜")
                    .font(.system(size: 18))
            } else {
                ZStack {
                    Circle()
                        .fill(rank == 1 ? LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 28, height: 28)
                    
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.ds_labelSmall)
                            .foregroundColor(.white)
                    } else {
                        Text("\(rank)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
            
            memberAvatar(member: member, size: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(isMe ? "You" : member.firstName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if isMe {
                        Text("(me)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if member.currentStreak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("\(member.currentStreak)-day streak")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Progress
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(displayProgress)")
                    .font(.ds_statSmall)
                    .foregroundColor(completedToday ? .green : .primary)
                
                Text("today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group Stats")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(
                    title: "Total Combined",
                    value: "\(acceptedMembers.reduce(0) { $0 + $1.totalProgress })",
                    icon: "chart.bar.fill",
                    color: accentGradient[0]
                )
                
                statCard(
                    title: "Days Left",
                    value: "\(challenge.daysRemaining)",
                    icon: "calendar",
                    color: .purple
                )
                
                statCard(
                    title: "Best Streak",
                    value: "\(acceptedMembers.map(\.currentStreak).max() ?? 0)",
                    icon: "flame.fill",
                    color: .orange
                )
                
                statCard(
                    title: "Completed Today",
                    value: {
                        let target = challenge.dailyTarget ?? 0
                        let done = target > 0 ? acceptedMembers.filter { $0.todayProgress >= target }.count : 0
                        return "\(done)/\(acceptedMembers.count)"
                    }(),
                    icon: "checkmark.circle.fill",
                    color: .green
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.97))
        )
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.16) : Color.white)
        )
    }
    
    // MARK: - Pending Section
    
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Waiting to Join")
                .font(.headline)
                .fontWeight(.bold)
            
            ForEach(pendingMembers) { member in
                HStack(spacing: 12) {
                    memberAvatar(member: member, size: 36)
                    
                    Text(member.firstName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("Pending")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.97))
        )
    }
    
    // MARK: - Actions Section
    
    private var isCreator: Bool {
        userManager.currentUser?.id == liveChallenge.createdBy
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Leave Challenge button (any member)
            Button {
                showingLeaveConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Leave Challenge")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.orange)
                )
            }
            .disabled(isProcessing)
            
            // Cancel Challenge button — only the creator can cancel for everyone
            if isCreator {
                Button {
                    showingCancelConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Cancel Challenge for Everyone")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red.opacity(0.12))
                    )
                }
                .disabled(isProcessing)
            }
        }
        .padding(.top, 8)
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
                    gradientColors: accentGradient
                )
                .overlay(Circle().stroke(Color.darkBackground, lineWidth: 2))
            }
        }
    }
}
