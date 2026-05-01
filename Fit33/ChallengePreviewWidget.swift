//
//  ChallengePreviewWidget.swift
//  Fit33
//
//  Shows pending challenge invites on the home screen
//  Similar to FriendRequestPreviewWidget - appears until user accepts or declines
//

import SwiftUI

// MARK: - Challenge Preview Widget

struct ChallengePreviewWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @ObservedObject private var challengeService = ChallengeService.shared
    
    let invite: ChallengeInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var showingDeclineConfirmation = false
    
    private var challengeType: ChallengeType {
        invite.resolvedType
    }
    
    private var themeColor: Color {
        challengeType.color
    }
    
    private var gradientColors: [Color] {
        challengeType.gradientColors
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider().padding(.horizontal, Spacing.md)
            
            challengeDetailsSection
            
            Divider().padding(.horizontal, Spacing.md)
            
            actionButtonsSection
        }
        .background(staticCardBackground(accentColor: themeColor, secondaryColor: gradientColors.last ?? themeColor))
        .shadow(color: themeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: themeColor.opacity(0.08), radius: 25, x: 0, y: 4)
        .confirmationDialog(
            "Decline this challenge?",
            isPresented: $showingDeclineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) { declineChallenge() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll miss out on competing with \(invite.creatorName ?? "your friend")!")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            CachedFriendPhoto(
                friendId: invite.creatorId.uuidString,
                photoUrl: invite.creatorPhotoUrl,
                name: invite.creatorName ?? "Challenger",
                size: 48,
                showGradientRing: true,
                gradientColors: gradientColors
            )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Challenge")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themeColor)
                    
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(themeColor))
                }
                
                Text("\(invite.creatorName ?? "Someone") challenged you!")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(challengeType.emoji)
                .font(.ds_heading1)
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Challenge Details Section
    
    private var challengeDetailsSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let target = invite.dailyTarget {
                    Text("\(target.formatted()) \(invite.targetUnit)/day • \(invite.durationDays) days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                let isAccountability = invite.title.hasPrefix("🤝")
                Text(isAccountability ? "🤝" : "⚔️")
                    .font(.ds_heading3)
                
                Text(isAccountability ? "Buddy" : "Battle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticManager.impact(.light)
                showingDeclineConfirmation = true
            }) {
                HStack(spacing: 4) {
                    if isDeclining {
                        ProgressView().scaleEffect(0.7).tint(.secondary)
                    } else {
                        Image(systemName: "xmark")
                            .font(.ds_labelMedium)
                    }
                    Text("Decline")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(isAccepting || isDeclining)
            
            Button(action: acceptChallenge) {
                HStack(spacing: 4) {
                    if isAccepting {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.ds_labelMedium)
                    }
                    Text("Accept")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(.plain)
            .disabled(isAccepting || isDeclining)
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Actions
    
    private func acceptChallenge() {
        AppLogger.info("✅ [CHALLENGE ACCEPT] Accept button tapped for challenge: \(invite.title)", category: .social)
        HapticManager.impact(.medium)
        isAccepting = true
        
        Task {
            AppLogger.debug("📤 [CHALLENGE ACCEPT] Calling respondToChallenge...", category: .social)
            let success = await challengeService.respondToChallenge(challengeId: invite.challengeId, accept: true)
            if success {
                AppLogger.info("✅ [CHALLENGE ACCEPT] Challenge accepted successfully!", category: .social)
                AppLogger.debug("🔄 [CHALLENGE ACCEPT] Refreshing challenges...", category: .social)
                // Immediately refresh to show active challenge (both 1v1 AND group)
                await challengeService.fetchActiveChallenges()
                await challengeService.fetchActiveGroupChallenges()  // Group challenge may appear here
                await challengeService.fetchPendingInvites()
                HapticManager.notification(.success)
                onAccept()
            } else {
                AppLogger.error("❌ [CHALLENGE ACCEPT] Failed to accept challenge", category: .social)
                HapticManager.notification(.error)
            }
            isAccepting = false
        }
    }
    
    private func declineChallenge() {
        HapticManager.impact(.medium)
        isDeclining = true
        
        Task {
            let success = await challengeService.respondToChallenge(challengeId: invite.challengeId, accept: false)
            if success {
                HapticManager.notification(.success)
                onDecline()
            } else {
                HapticManager.notification(.error)
            }
            isDeclining = false
        }
    }
    
    // MARK: - Helpers
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Challenge Preview Container

/// Container view that shows pending challenge invites on the home screen
struct ChallengePreviewContainer: View {
    @ObservedObject private var challengeService = ChallengeService.shared
    
    var body: some View {
        // Show only the first pending challenge (most recent)
        if let firstInvite = challengeService.pendingInvites.first {
            VStack(spacing: 12) {
                // Show the challenge invite widget
                ChallengePreviewWidget(
                    invite: firstInvite,
                    onAccept: {
                        // Challenge accepted - will appear in active challenges
                    },
                    onDecline: {
                        // Challenge declined - widget disappears
                    }
                )
                
                // If there are more pending invites, show count
                if challengeService.pendingInvites.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                        Text("\(challengeService.pendingInvites.count - 1) more challenge\(challengeService.pendingInvites.count > 2 ? "s" : "") waiting")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Active Challenge Mini Widget (for Friend Profile)

struct ActiveChallengeWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let challenge: ActiveChallenge
    let onTap: () -> Void
    
    @State private var showingReactionPicker = false
    
    private var resolvedType: ChallengeType {
        challenge.resolvedType
    }
    
    private var resolver: ChallengeProgressResolver {
        ChallengeProgressResolver.shared
    }
    
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Header — type-aware
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                            .frame(width: 28, height: 28)
                        Text(resolvedType.emoji)
                            .font(.ds_bodySmall)
                    }
                    
                    Text(challenge.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Status badge
                    if challenge.amWinning {
                        HStack(spacing: 2) {
                            Image(systemName: "crown.fill")
                                .font(.ds_caption)
                            Text("Leading")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.yellow)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(Color.yellow.opacity(0.2))
                        )
                    } else {
                        Text("Behind")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                }
                
                // Progress comparison — live data for "my" side
                HStack(spacing: 0) {
                    // My live progress
                    VStack(spacing: 4) {
                        Text(resolver.formattedProgress(for: challenge))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: resolvedType.gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("You")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Text("vs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Opponent today's progress (from server)
                    VStack(spacing: 4) {
                        Text(resolver.formatValue(challenge.opponentTodayProgress ?? 0, unit: challenge.targetUnit, type: resolvedType))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Them")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Live progress bar + reaction button row
                VStack(spacing: 6) {
                    // Type-colored progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: resolvedType.gradientColors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * resolver.progressPercentage(for: challenge), height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        BattleCryQuickOpenButton(challenge: challenge, showingPicker: $showingReactionPicker)

                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("\(challenge.daysRemaining)d left")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(Spacing.md)
            .sleekCard(cornerRadius: 16, accentColor: resolvedType.color)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingReactionPicker) {
            let mode: BattleCryMode = challenge.mode == .accountability ? .accountability : .competition
            BattleCryPickerSheet(
                mode: mode,
                typeColor: resolvedType.color,
                gradient: resolvedType.gradientColors,
                recipientLabel: challenge.opponentName?.components(separatedBy: " ").first ?? "them",
                onSend: { preset in
                    Task {
                        _ = await ChallengeService.shared.sendReaction(
                            challengeId: challenge.challengeId,
                            recipientId: challenge.opponentId,
                            preset: preset
                        )
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Friend Challenge Row (for Friend Profile challenges list)

struct FriendChallengeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let challenge: FriendChallenge
    let onTap: () -> Void
    
    private var challengeType: ChallengeType {
        challenge.resolvedType
    }
    
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Type emoji - floating
                Text(challengeType.emoji)
                    .font(.ds_heading1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        // Status
                        Text(challenge.status.capitalized)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(challenge.isActive ? .green : .secondary)
                        
                        // Score
                        Text("You: \(challenge.myProgress.formatted()) • Them: \(challenge.friendProgress.formatted())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Win indicator
                if challenge.status == "completed" {
                    Image(systemName: challenge.amWinning ? "trophy.fill" : "medal")
                        .font(.ds_heading3)
                        .foregroundColor(challenge.amWinning ? .yellow : .secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundStyle(
                            LinearGradient(
                                colors: challengeType.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [challengeType.gradientColors[0].opacity(colorScheme == .dark ? 0.3 : 0.2), challengeType.gradientColors.last?.opacity(colorScheme == .dark ? 0.2 : 0.1) ?? challengeType.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Group Challenge Invite Widget

/// Shows a group challenge invite with Accept/Decline buttons
/// Displayed above the challenge cards section for invites the user hasn't responded to yet
struct GroupChallengeInviteWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var challengeService = ChallengeService.shared
    
    let challenge: ActiveGroupChallenge
    
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var showingDeclineConfirmation = false
    @State private var nudgedUserIds: Set<UUID> = []
    @State private var isNudging: UUID? = nil
    
    private let challengeColor = Color(red: 0.0, green: 0.9, blue: 0.7)
    
    private var challengeType: ChallengeType {
        challenge.resolvedType
    }
    
    private var themeColor: Color { challengeColor }
    private var gradientColors: [Color] { [Color(red: 0.0, green: 0.9, blue: 0.7), .teal] }
    
    
    /// Names of all OTHER members (not the current user)
    private var otherMemberNames: [String] {
        let myId = SupabaseManager.shared.currentUser?.id
        return (challenge.members ?? [])
            .filter { $0.userId != myId }
            .map { $0.firstName }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header — who invited you
            HStack(spacing: 12) {
                // Creator avatar
                if let creator = challenge.members?.first(where: { $0.userId == challenge.createdBy }) {
                    CachedFriendPhoto(
                        friendId: creator.userId.uuidString,
                        photoUrl: creator.profilePhotoUrl,
                        name: creator.name ?? "?",
                        size: 48,
                        showGradientRing: true,
                        gradientColors: gradientColors
                    )
                } else {
                    Circle()
                        .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                        .overlay(Text("?").font(.title3).fontWeight(.bold).foregroundColor(.white))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Group Challenge")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(themeColor)
                        
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(themeColor))
                    }
                    
                    Text("\(challenge.creatorName ?? "Someone") invited you!")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(challengeType.emoji)
                    .font(.ds_heading1)
            }
            .padding(Spacing.md)
            
            Divider().padding(.horizontal, Spacing.md)
            
            // Challenge details row
            HStack(spacing: 16) {
                // Challenge title
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let target = challenge.dailyTarget {
                        Text("\(target) \(challenge.targetUnit)/day • \(challenge.durationDays) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Member avatars + names
                VStack(alignment: .trailing, spacing: 2) {
                    // Overlapping avatars
                    HStack(spacing: -8) {
                        let myId = SupabaseManager.shared.currentUser?.id
                        ForEach((challenge.members ?? []).filter({ $0.userId != myId }).prefix(3)) { member in
                            CachedFriendPhoto(
                                friendId: member.userId.uuidString,
                                photoUrl: member.profilePhotoUrl,
                                name: member.name ?? "?",
                                size: 24,
                                showGradientRing: false,
                                gradientColors: gradientColors
                            )
                            .overlay(Circle().stroke(Color.cardBackground, lineWidth: 1.5))
                        }
                    }
                    
                    Text("with \(otherMemberNames.joined(separator: " & "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            Divider().padding(.horizontal, Spacing.md)
            
            // Accept / Decline buttons
            HStack(spacing: 12) {
                // Decline button
                Button {
                    showingDeclineConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        if isDeclining {
                            ProgressView().scaleEffect(0.7).tint(.secondary)
                        } else {
                            Image(systemName: "xmark")
                                .font(.ds_labelMedium)
                        }
                        Text("Decline")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.12))
                    )
                }
                .disabled(isAccepting || isDeclining)
                
                // Accept button
                Button {
                    acceptChallenge()
                } label: {
                    HStack(spacing: 4) {
                        if isAccepting {
                            ProgressView().scaleEffect(0.7).tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.ds_labelMedium)
                        }
                        Text("Join Challenge")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    )
                }
                .disabled(isAccepting || isDeclining)
            }
            .padding(Spacing.md)
        }
        .background(staticCardBackground(accentColor: challengeColor, secondaryColor: .teal))
        .shadow(color: challengeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: challengeColor.opacity(0.08), radius: 25, x: 0, y: 4)
        .onAppear {
            loadNudgedUsers()
        }
        .confirmationDialog(
            "Decline this group challenge?",
            isPresented: $showingDeclineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) { declineChallenge() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If only 2 members remain, it'll become a 1v1 challenge between them.")
        }
    }
    
    // MARK: - Actions
    
    private func acceptChallenge() {
        HapticManager.impact(.medium)
        isAccepting = true
        
        Task {
            let allAccepted = await challengeService.acceptGroupChallenge(challengeId: challenge.challengeId)
            
            // Refresh group challenges so the widget updates
            await challengeService.fetchActiveGroupChallenges()
            
            HapticManager.notification(.success)
            isAccepting = false
        }
    }
    
    private func declineChallenge() {
        HapticManager.impact(.medium)
        isDeclining = true
        
        Task {
            await challengeService.declineGroupChallenge(challengeId: challenge.challengeId)
            
            // Refresh everything — decline may convert to 1v1 for others
            await challengeService.fetchActiveGroupChallenges()
            await challengeService.fetchActiveChallenges()
            
            HapticManager.notification(.success)
            isDeclining = false
        }
    }
    
    private func loadNudgedUsers() {
        // Load which users we've already nudged from UserDefaults
        let myId = SupabaseManager.shared.currentUser?.id
        for member in (challenge.members ?? []) where member.isPending && member.userId != myId {
            let key = "nudge_\(challenge.challengeId.uuidString)_\(member.userId.uuidString)"
            if UserDefaults.standard.bool(forKey: key) {
                nudgedUserIds.insert(member.userId)
            }
        }
    }
}

// MARK: - Private Challenge Invite Widget

/// Shows a private challenge invite with Accept/Decline buttons
/// Displayed on the dashboard for pending private challenge invitations
struct PrivateChallengeInviteWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared
    
    let invite: PrivateChallengeInvite
    
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var showingDeclineConfirmation = false
    @State private var showingDetail = false
    
    private let themeColor = Color.purple
    private var gradientColors: [Color] { [.purple, .pink] }
    
    
    private var challengeType: ChallengeType {
        ChallengeType(rawValue: invite.challengeType) ?? .steps
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header — who invited you
            HStack(spacing: 12) {
                // Inviter avatar
                CachedFriendPhoto(
                    friendId: invite.inviterId.uuidString,
                    photoUrl: invite.inviterPhotoUrl,
                    name: invite.inviterName ?? "?",
                    size: 48,
                    showGradientRing: true,
                    gradientColors: gradientColors
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Private Community")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(themeColor)
                        
                        Text("INVITE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(themeColor))
                    }
                    
                    Text("\(invite.inviterFirstName) invited you to \(invite.challengeTitle)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                
                Spacer()
                
                Text(invite.challengeEmoji ?? challengeType.emoji)
                    .font(.ds_heading1)
            }
            .padding(Spacing.md)
            
            Divider().padding(.horizontal, Spacing.md)
            
            // Challenge details row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.challengeTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(invite.dailyTarget) \(invite.targetUnit)/day • \(invite.memberCount) member\(invite.memberCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Lock icon indicating private
                VStack(spacing: 2) {
                    Image(systemName: "lock.shield.fill")
                        .font(.ds_heading3)
                        .foregroundStyle(
                            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    
                    Text("Private")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            Divider().padding(.horizontal, Spacing.md)
            
            // Accept / Decline buttons
            HStack(spacing: 12) {
                // Decline button
                Button {
                    showingDeclineConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        if isDeclining {
                            ProgressView().scaleEffect(0.7).tint(.secondary)
                        } else {
                            Image(systemName: "xmark")
                                .font(.ds_labelMedium)
                        }
                        Text("Decline")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.12))
                    )
                }
                .disabled(isAccepting || isDeclining)
                
                // Accept button
                Button {
                    acceptInvite()
                } label: {
                    HStack(spacing: 4) {
                        if isAccepting {
                            ProgressView().scaleEffect(0.7).tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.ds_labelMedium)
                        }
                        Text("Join Challenge")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    )
                }
                .disabled(isAccepting || isDeclining)
            }
            .padding(Spacing.md)
        }
        .background(staticCardBackground(accentColor: themeColor, secondaryColor: .pink))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: .purple.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        .confirmationDialog(
            "Decline this private challenge?",
            isPresented: $showingDeclineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) { declineInvite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't be able to join unless invited again.")
        }
    }
    
    // MARK: - Actions
    
    private func acceptInvite() {
        HapticManager.impact(.medium)
        isAccepting = true
        
        Task {
            let challengeId = await privateChallengeService.acceptInvite(inviteId: invite.inviteId)
            
            // Refresh to update the dashboard
            await privateChallengeService.fetchPendingInvites()
            await privateChallengeService.fetchMyChallenges()
            
            HapticManager.notification(.success)
            isAccepting = false
            
            // If accepted successfully, optionally navigate to the challenge
            if let challengeId = challengeId {
                AppLogger.debug("🔒 [PRIVATE] Successfully joined private challenge: \(challengeId)", category: .social)
            }
        }
    }
    
    private func declineInvite() {
        HapticManager.impact(.medium)
        isDeclining = true
        
        Task {
            let success = await privateChallengeService.declineInvite(inviteId: invite.inviteId)
            
            // Refresh to remove from pending
            await privateChallengeService.fetchPendingInvites()
            
            HapticManager.notification(success ? .success : .error)
            isDeclining = false
        }
    }
}

// MARK: - Private Challenge Invite Container

/// Container view that shows pending private challenge invites on the home screen
struct PrivateChallengeInviteContainer: View {
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared
    
    var body: some View {
        if !privateChallengeService.pendingInvites.isEmpty {
            VStack(spacing: 12) {
                // Show each pending private challenge invite
                ForEach(privateChallengeService.pendingInvites) { invite in
                    PrivateChallengeInviteWidget(invite: invite)
                }
                
                // If there are many invites, show summary
                if privateChallengeService.pendingInvites.count > 3 {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.purple)
                        Text("\(privateChallengeService.pendingInvites.count) private challenge invites")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Group Challenge Invites Section (Dashboard Container)

/// Isolated container that shows group challenge invites where the current user
/// hasn't accepted yet. Owns its own @ObservedObject to prevent parent re-renders.
struct GroupChallengeInvitesSection: View {
    @ObservedObject private var challengeService = ChallengeService.shared
    @EnvironmentObject var userManager: UserManager
    
    private var pendingGroupInvites: [ActiveGroupChallenge] {
        challengeService.activeGroupChallenges.filter { !$0.iHaveAccepted }
    }
    
    var body: some View {
        if !pendingGroupInvites.isEmpty {
            VStack(spacing: 12) {
                ForEach(pendingGroupInvites) { challenge in
                    GroupChallengeInviteWidget(challenge: challenge)
                        .environmentObject(userManager)
                }
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ChallengePreviewContainer()
        
        ActiveChallengeWidget(
            challenge: ActiveChallenge(
                challengeId: UUID(),
                challengeType: "steps",
                title: "10K Steps Daily",
                description: nil,
                dailyTarget: 10000,
                totalTarget: nil,
                targetUnit: "steps",
                startDate: Date(),
                endDate: Date().addingTimeInterval(86400 * 7),
                durationDays: 7,
                daysElapsed: 3,
                daysRemaining: 4,
                status: "active",
                myTotalProgress: 28500,
                myDaysCompleted: 2,
                myCurrentStreak: 2,
                opponentId: UUID(),
                opponentName: "Leo Smith",
                opponentUsername: nil,
                opponentPhotoUrl: nil,
                opponentTotalProgress: 25000,
                opponentDaysCompleted: 2,
                amWinning: true
            ),
            onTap: {}
        )
    }
    .padding()
}
